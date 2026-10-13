import 'dart:async';

import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/relay.dart';
import 'package:driver/services/relay_connection.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:driver/services/relay_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Transporte dublê: nenhum teste toca a rede (decisão D5).
class FakeGateway implements RelayGateway {
  FakeGateway({
    this.failingUrls = const {},
    this.hangingUrls = const {},
    Set<String>? silentUrls,
  }) : silentUrls = silentUrls ?? {};

  final Set<String> failingUrls;
  final Set<String> hangingUrls;

  /// Relays que conectam mas não respondem à sonda de vivacidade — conexão
  /// meio aberta, cujo TCP morreu sem avisar.
  final Set<String> silentUrls;
  final Map<String, int> probes = {};
  final List<String> connected = [];
  final List<String> disconnected = [];
  final _events = StreamController<IncomingEvent>.broadcast();
  final _lost = StreamController<String>.broadcast();
  List<PublishOutcome> publishOutcomes = const [];

  /// Tentativas de conexão por url, bem-sucedidas ou não.
  final Map<String, int> attempts = {};

  @override
  Stream<String> get connectionLost => _lost.stream;

  /// Simula a conexão com [relayUrl] caindo depois de estabelecida.
  void drop(String relayUrl) => _lost.add(relayUrl);

  @override
  Future<void> connect(String relayUrl) async {
    attempts.update(relayUrl, (n) => n + 1, ifAbsent: () => 1);
    if (hangingUrls.contains(relayUrl)) {
      await Future<void>.delayed(const Duration(minutes: 5));
      return;
    }
    if (failingUrls.contains(relayUrl)) {
      throw StateError('SocketException: Connection refused (errno = 111)');
    }
    connected.add(relayUrl);
  }

  @override
  Future<void> disconnect(String relayUrl) async => disconnected.add(relayUrl);

  @override
  Future<void> probe(String relayUrl) async {
    probes.update(relayUrl, (n) => n + 1, ifAbsent: () => 1);
    if (silentUrls.contains(relayUrl)) await Completer<void>().future;
  }

  @override
  Stream<IncomingEvent> subscribe({required List<int> kinds}) => _events.stream;

  @override
  Stream<PublishOutcome> publish(
    NostrEvent event, {
    required Map<String, dynamic> payload,
  }) => Stream.fromIterable(publishOutcomes);

  void emit(IncomingEvent event) => _events.add(event);

  void emitPayload(String relayUrl, Map<String, dynamic> payload) =>
      _events.add(IncomingEvent(relayUrl: relayUrl, payload: payload));
}

void main() {
  const damus = 'wss://relay.damus.io';
  const nos = 'wss://nos.lol';

  group('RelayService — estados de conexão', () {
    test('relay conectado passa de connecting para connected', () async {
      final service = RelayService(FakeGateway());

      await service.connectAll([const Relay(url: damus)]);

      expect(service.relays.single.status, RelayStatus.connected);
      expect(service.relays.single.lastError, isNull);
    });

    test('relay que falha fica unavailable com motivo preenchido', () async {
      final service = RelayService(FakeGateway(failingUrls: {damus}));

      await service.connectAll([const Relay(url: damus)]);

      final relay = service.relays.single;
      expect(relay.status, RelayStatus.unavailable);
      expect(relay.lastError, isNotNull);
      expect(relay.lastError, 'conexão recusada pelo relay');
      expect(
        relay.lastError,
        isNot(contains('SocketException')),
        reason: 'FR-015: nada de erro técnico cru na interface',
      );
    });

    test(
      'falha de um relay não altera o estado dos demais (FR-003/SC-003)',
      () async {
        final service = RelayService(FakeGateway(failingUrls: {damus}));

        await service.connectAll([
          const Relay(url: damus),
          const Relay(url: nos),
        ]);

        final porUrl = {for (final r in service.relays) r.url: r.status};
        expect(porUrl[damus], RelayStatus.unavailable);
        expect(porUrl[nos], RelayStatus.connected);
        expect(service.hasConnectedRelay, isTrue);
      },
    );

    test(
      'relay que aceita e nunca responde expira e fica unavailable',
      () async {
        final service = RelayService(
          FakeGateway(hangingUrls: {damus}),
          connectTimeout: const Duration(milliseconds: 50),
        );

        await service.connectAll([const Relay(url: damus)]);

        expect(service.relays.single.status, RelayStatus.unavailable);
        expect(service.relays.single.lastError, contains('tempo limite'));
      },
    );
  });

  group('RelayService — reconexão', () {
    test(
      'retentar manualmente reconecta os indisponíveis quando a rede volta',
      () async {
        final gateway = FakeGateway(failingUrls: {damus});
        final service = RelayService(gateway);
        await service.connectAll([const Relay(url: damus)]);
        expect(service.relays.single.status, RelayStatus.unavailable);

        gateway.failingUrls.remove(damus);
        await service.reconnectUnavailable();

        expect(service.relays.single.status, RelayStatus.connected);
        expect(service.relays.single.lastError, isNull);
      },
    );

    test(
      'repassa os eventos brutos recebidos, sem verificar nem deduplicar',
      () async {
        final gateway = FakeGateway();
        final service = RelayService(gateway);
        await service.connectAll([
          const Relay(url: damus),
          const Relay(url: nos),
        ]);

        final recebidos = <IncomingEvent>[];
        final sub = service.incoming.listen(recebidos.add);

        gateway.emitPayload(damus, {'id': 'e' * 64, 'kind': 1});
        gateway.emitPayload(nos, {'id': 'e' * 64, 'kind': 1});
        await pumpEventQueue();

        expect(
          recebidos.length,
          2,
          reason:
              'verificação e deduplicação são responsabilidade do EventFeed',
        );
        await sub.cancel();
      },
    );
  });

  group('RelayService — reconexão automática (FR-014)', () {
    RelayService comRetentativa(FakeGateway gateway) => RelayService(
      gateway,
      connectTimeout: const Duration(milliseconds: 50),
      retryInterval: const Duration(milliseconds: 30),
    );

    test('queda de conexão depois de conectado marca o relay como '
        'indisponível', () async {
      final gateway = FakeGateway();
      final service = RelayService(gateway);
      await service.connectAll([
        const Relay(url: damus),
        const Relay(url: nos),
      ]);

      gateway.drop(damus);
      await pumpEventQueue();

      final porUrl = {for (final r in service.relays) r: r};
      final caido = porUrl[const Relay(url: damus)]!;
      expect(
        caido.status,
        RelayStatus.unavailable,
        reason: 'relay caído não pode continuar aparecendo como conectado',
      );
      expect(caido.lastError, 'conexão encerrada pelo relay');
      expect(porUrl[const Relay(url: nos)]!.status, RelayStatus.connected);
      await service.dispose();
    });

    test(
      'reconecta sozinho quando a rede volta, sem intervenção manual',
      () async {
        final gateway = FakeGateway(failingUrls: {damus});
        final service = comRetentativa(gateway);
        await service.connectAll([const Relay(url: damus)]);
        service.enableAutoRetry();
        expect(service.relays.single.status, RelayStatus.unavailable);

        // A rede volta. Ninguém toca em nada.
        gateway.failingUrls.remove(damus);
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(service.relays.single.status, RelayStatus.connected);
        await service.dispose();
      },
    );

    test('relay que cai depois de conectado reconecta sozinho', () async {
      final gateway = FakeGateway();
      final service = comRetentativa(gateway);
      await service.connectAll([const Relay(url: damus)]);
      service.enableAutoRetry();

      gateway.drop(damus);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(service.relays.single.status, RelayStatus.connected);
      expect(gateway.attempts[damus], 2);
      await service.dispose();
    });

    test(
      'não abre segunda tentativa para relay que ainda está conectando',
      () async {
        final gateway = FakeGateway(hangingUrls: {damus});
        final service = RelayService(
          gateway,
          connectTimeout: const Duration(seconds: 1),
          retryInterval: const Duration(milliseconds: 30),
        );
        unawaited(service.connectAll([const Relay(url: damus)]));
        service.enableAutoRetry();

        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(service.relays.single.status, RelayStatus.connecting);
        expect(gateway.attempts[damus], 1);
        await service.dispose();
      },
    );

    test('queda de relay já removido não o recoloca na lista', () async {
      final gateway = FakeGateway();
      final service = comRetentativa(gateway);
      await service.connectAll([const Relay(url: damus)]);
      service.enableAutoRetry();
      await service.removeRelay(damus);

      gateway.drop(damus);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(service.relays, isEmpty);
      expect(gateway.attempts[damus], 1);
      await service.dispose();
    });

    test('o ciclo de retentativas para ao descartar o serviço', () async {
      final gateway = FakeGateway(failingUrls: {damus});
      final service = comRetentativa(gateway);
      await service.connectAll([const Relay(url: damus)]);
      service.enableAutoRetry();
      await service.dispose();
      final tentativasAoDescartar = gateway.attempts[damus];

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        gateway.attempts[damus],
        tentativasAoDescartar,
        reason: 'timer vazado continuaria tentando conectar após o dispose',
      );
    });
  });

  group('RelayService — reconexão a pedido (reconnectNow)', () {
    RelayService criar(FakeGateway gateway) => RelayService(
      gateway,
      retryInterval: const Duration(hours: 1),
      livenessInterval: const Duration(hours: 1),
      livenessTimeout: const Duration(milliseconds: 30),
    );

    test('reconecta os indisponíveis sem esperar o ciclo automático', () async {
      final gateway = FakeGateway(failingUrls: {damus});
      final service = criar(gateway);
      await service.connectAll([
        const Relay(url: damus),
        const Relay(url: nos),
      ]);
      expect(service.hasConnectedRelay, isTrue);
      expect(
        service.relays.firstWhere((r) => r.url == damus).status,
        RelayStatus.unavailable,
      );

      gateway.failingUrls.remove(damus);
      await service.reconnectNow();

      expect(
        service.relays.every((r) => r.status == RelayStatus.connected),
        isTrue,
      );
      expect(gateway.attempts[nos], 1, reason: 'o conectado não é reaberto');
      await service.dispose();
    });

    test('detecta conexão meio aberta pela sonda e a reconecta', () async {
      final gateway = FakeGateway();
      final service = criar(gateway);
      await service.connectAll([const Relay(url: damus)]);

      // O TCP morre sem avisar: o relay segue "conectado" para a interface.
      gateway.silentUrls.add(damus);
      expect(service.relays.single.status, RelayStatus.connected);

      final reconexao = service.reconnectNow();
      // Passada a sonda sem resposta, o relay volta a responder.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      gateway.silentUrls.remove(damus);
      await reconexao;

      expect(service.relays.single.status, RelayStatus.connected);
      expect(gateway.disconnected, contains(damus));
      expect(gateway.attempts[damus], 2);
      await service.dispose();
    });

    test('relay que responde à sonda não é reconectado', () async {
      final gateway = FakeGateway();
      final service = criar(gateway);
      await service.connectAll([const Relay(url: damus)]);

      await service.reconnectNow();

      expect(gateway.attempts[damus], 1);
      expect(gateway.disconnected, isEmpty);
      await service.dispose();
    });

    test('sem relays na lista, não faz nada nem lança', () async {
      final service = criar(FakeGateway());
      await service.connectAll(const []);

      await service.reconnectNow();

      expect(service.relays, isEmpty);
      await service.dispose();
    });

    test('depois de descartado o serviço, não faz nada', () async {
      final gateway = FakeGateway(failingUrls: {damus});
      final service = criar(gateway);
      await service.connectAll([const Relay(url: damus)]);
      await service.dispose();

      await service.reconnectNow();

      expect(gateway.attempts[damus], 1);
    });
  });

  group('RelayService — vivacidade de conexão estabelecida', () {
    RelayService comSonda(FakeGateway gateway) => RelayService(
      gateway,
      retryInterval: const Duration(hours: 1),
      livenessInterval: const Duration(milliseconds: 30),
      livenessTimeout: const Duration(milliseconds: 30),
    );

    test('relay conectado que para de responder vira indisponível', () async {
      final gateway = FakeGateway();
      final service = comSonda(gateway);
      await service.connectAll([
        const Relay(url: damus),
        const Relay(url: nos),
      ]);
      service.enableAutoRetry();

      // O TCP morre sem avisar: nenhum erro, nenhum fechamento, só silêncio.
      gateway.silentUrls.add(damus);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final porUrl = {for (final r in service.relays) r: r};
      expect(porUrl[const Relay(url: damus)]!.status, RelayStatus.unavailable);
      expect(
        porUrl[const Relay(url: damus)]!.lastError,
        'sem resposta do relay',
      );
      expect(gateway.disconnected, contains(damus));
      expect(porUrl[const Relay(url: nos)]!.status, RelayStatus.connected);
      await service.dispose();
    });

    test('relay que responde à sonda continua conectado', () async {
      final gateway = FakeGateway();
      final service = comSonda(gateway);
      await service.connectAll([const Relay(url: damus)]);
      service.enableAutoRetry();

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(service.relays.single.status, RelayStatus.connected);
      expect(gateway.probes[damus], greaterThan(1));
      await service.dispose();
    });

    test('não sonda de novo um relay cuja sonda ainda está pendente', () async {
      final gateway = FakeGateway(silentUrls: {damus});
      final service = RelayService(
        gateway,
        retryInterval: const Duration(hours: 1),
        livenessInterval: const Duration(milliseconds: 20),
        livenessTimeout: const Duration(seconds: 1),
      );
      await service.connectAll([const Relay(url: damus)]);
      service.enableAutoRetry();

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(gateway.probes[damus], 1);
      await service.dispose();
    });

    test('a sonda para ao descartar o serviço', () async {
      final gateway = FakeGateway();
      final service = comSonda(gateway);
      await service.connectAll([const Relay(url: damus)]);
      service.enableAutoRetry();
      await service.dispose();
      final sondasAoDescartar = gateway.probes[damus];

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(gateway.probes[damus], sondasAoDescartar);
    });
  });

  group('RelayService — gestão da lista', () {
    test('adicionar relay dispara conexão', () async {
      final gateway = FakeGateway();
      final service = RelayService(gateway);
      await service.connectAll([const Relay(url: damus)]);

      await service.addRelay(nos);

      expect(gateway.connected, contains(nos));
      expect(service.relays.length, 2);
    });

    test('remover relay encerra a conexão', () async {
      final gateway = FakeGateway();
      final service = RelayService(gateway);
      await service.connectAll([
        const Relay(url: damus),
        const Relay(url: nos),
      ]);

      await service.removeRelay(nos);

      expect(gateway.disconnected, contains(nos));
      expect(service.relays.single.url, damus);
    });
  });

  group('RelayService — publicação', () {
    test('reporta o resultado por relay, incluindo recusa', () async {
      final gateway = FakeGateway()
        ..publishOutcomes = const [
          PublishOutcome(relayUrl: damus, accepted: true),
          PublishOutcome(
            relayUrl: nos,
            accepted: false,
            message: 'payment required',
          ),
        ];
      final service = RelayService(gateway);
      await service.connectAll([
        const Relay(url: damus),
        const Relay(url: nos),
      ]);

      final resultados = await service
          .publish(
            NostrEvent(
              id: 'f',
              authorPublicKey: 'a',
              createdAt: _fixedDate,
              kind: 20001,
              content: 'oi',
              isSignatureValid: true,
            ),
            payload: const {},
          )
          .toList();

      expect(resultados.length, 2);
      expect(resultados.firstWhere((r) => r.relayUrl == nos).accepted, isFalse);
      expect(
        resultados.firstWhere((r) => r.relayUrl == nos).message,
        contains('payment'),
      );
    });

    test('publicar sem relay conectado é impedido', () async {
      final service = RelayService(FakeGateway(failingUrls: {damus}));
      await service.connectAll([const Relay(url: damus)]);

      expect(service.hasConnectedRelay, isFalse);
      expect(
        () => service.publish(
          NostrEvent(
            id: 'f',
            authorPublicKey: 'a',
            createdAt: _fixedDate,
            kind: 20001,
            content: 'oi',
            isSignatureValid: true,
          ),
          payload: const {},
        ),
        throwsA(isA<NoConnectedRelay>()),
      );
    });
  });
  group('RelayService — mensagens de falha (FR-015)', () {
    // Descoberto em teste no aparelho: um relay com host inexistente exibia
    // "WebSocketChannelException: SocketException: Failed host lookup: ...",
    // erro técnico cru que FR-015 proíbe.
    test('traduz falhas técnicas em texto compreensível', () {
      final casos = {
        'WebSocketChannelException: SocketException: Failed host lookup: '
                "'relay.inexistente.bg'":
            'endereço não encontrado',
        'SocketException: Connection refused (errno = 111)':
            'conexão recusada pelo relay',
        'TimeoutException after 0:00:10.000000':
            'sem resposta dentro do tempo limite',
        'HandshakeException: Handshake error in client':
            'falha na conexão segura',
        'SocketException: Network is unreachable': 'sem acesso à rede',
        'WebSocketChannelException: connection closed':
            'conexão encerrada pelo relay',
        'algo completamente inesperado': 'não foi possível conectar',
      };

      casos.forEach((bruto, esperado) {
        expect(
          RelayService.describeFailure(StateError(bruto)),
          esperado,
          reason: 'entrada: $bruto',
        );
      });
    });

    test('nenhuma mensagem exibida contém nome de classe de exceção', () {
      final mensagens = [
        RelayService.describeFailure(
          StateError(
            'WebSocketChannelException: SocketException: '
            'Failed host lookup',
          ),
        ),
        RelayService.describeFailure(Exception('boom')),
      ];

      for (final mensagem in mensagens) {
        expect(mensagem.toLowerCase(), isNot(contains('exception')));
        expect(mensagem.toLowerCase(), isNot(contains('errno')));
      }
    });
  });
}

final _fixedDate = DateTime.utc(2026, 9, 15);
