import 'dart:convert';

import 'package:driver/domain/driver_coverage.dart';
import 'package:driver/domain/driver_ride_status.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/relay.dart';
import 'package:driver/domain/service_state.dart';
import 'package:driver/services/background/relay_host_core.dart';
import 'package:driver/services/background/service_messages.dart';
import 'package:driver/services/background/service_state_store.dart';
import 'package:driver/services/consumed_kinds.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:driver/services/relay_repository.dart';
import 'package:driver/services/relay_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_message_channel.dart';
import '../../support/fake_relay_gateway.dart';
import '../../support/fake_ride_request_notifier.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/signed_payload.dart';

const _relayA = 'wss://a.test';
const _relayB = 'wss://b.test';

void main() {
  late FakeRelayGateway gateway;
  late FakeChannelPair canais;
  late FakeRideRequestNotifier notifier;
  late InMemoryKeyValueStore store;
  late DateTime agora;
  late RelayHostCore core;

  Future<void> iniciar({
    ServiceState? estado,
    List<String> relays = const [_relayA, _relayB],
  }) async {
    gateway = FakeRelayGateway();
    canais = FakeChannelPair();
    notifier = FakeRideRequestNotifier();
    store = InMemoryKeyValueStore();
    agora = DateTime.utc(2026, 10, 11, 12);
    await RelayRepository(store).save([for (final u in relays) Relay(url: u)]);
    if (estado != null) await ServiceStateStore(store).save(estado);
    core =
        RelayHostCore(
            relays: RelayService(
              gateway,
              subscriptionKinds: driverConsumedKinds.toList(),
              retryInterval: const Duration(days: 1),
              livenessInterval: const Duration(days: 1),
            ),
            channel: canais.service,
            stateStore: ServiceStateStore(store),
            relayRepository: RelayRepository(store),
            notifier: notifier,
            acceptedKinds: driverConsumedKinds,
            now: () => agora,
          )
          ..coverage = DriverCoverage.around(
            lat: origemDeTesteLat,
            lon: origemDeTesteLon,
            radiusKm: 10,
          );
    await core.start();
  }

  tearDown(() async => core.dispose());

  /// Mensagens do tipo [T] que o serviço enviou à interface.
  List<T> enviadas<T extends ServiceMessage>() =>
      canais.service.sent.whereType<T>().toList();

  void chega(Map<String, dynamic> payload, {String relay = _relayA}) {
    gateway.emitPayload(relay, payload);
  }

  void daInterface(ServiceMessage mensagem) => canais.ui.send(mensagem);

  const online = ServiceState(
    online: true,
    acceptedPayments: {'pix', 'cartao'},
  );

  Map<String, dynamic> solicitacao({String payment = 'pix'}) => signedPayload(
    kind: NostrEvent.kindRideRequest,
    content: rideRequestContent(payment: payment),
    tags: tagsDeSolicitacao(),
  );

  group('RelayHostCore — verificação antes de tudo (Princípios II e IV)', () {
    setUp(() => iniciar(estado: online));

    test('repassa à interface o evento válido', () async {
      final payload = solicitacao();

      chega(payload);
      await pumpEventQueue();

      final recebidos = enviadas<ServiceIncoming>();
      expect(recebidos, hasLength(1));
      expect(recebidos.single.payload['id'], payload['id']);
      expect(recebidos.single.relayUrl, _relayA);
    });

    test('descarta assinatura adulterada', () async {
      chega(solicitacao()..['sig'] = 'f' * 128);
      await pumpEventQueue();

      expect(enviadas<ServiceIncoming>(), isEmpty);
      expect(core.discardedInvalidCount, 1);
      expect(notifier.notified, isEmpty);
    });

    test('descarta conteúdo adulterado com id e sig originais', () async {
      chega(solicitacao()..['content'] = rideRequestContent(payment: 'cartao'));
      await pumpEventQueue();

      expect(enviadas<ServiceIncoming>(), isEmpty);
      expect(core.discardedInvalidCount, 1);
      expect(notifier.notified, isEmpty);
    });

    test('descarta evento sem o marcador do protótipo', () async {
      chega(
        signedPayload(
          kind: NostrEvent.kindRideRequest,
          content: rideRequestContent(),
          tags: const [],
        ),
      );
      await pumpEventQueue();

      expect(enviadas<ServiceIncoming>(), isEmpty);
      expect(core.discardedUnmarkedCount, 1);
    });

    test('ignora, sem erro, kind que o app não consome', () async {
      chega(signedPayload(kind: 20099));
      await pumpEventQueue();

      expect(enviadas<ServiceIncoming>(), isEmpty);
      expect(core.discardedInvalidCount, 0);
    });

    test('deduplica o mesmo id vindo de dois relays', () async {
      final payload = solicitacao();

      chega(payload, relay: _relayA);
      chega(payload, relay: _relayB);
      await pumpEventQueue();

      expect(enviadas<ServiceIncoming>(), hasLength(1));
      expect(core.discardedDuplicateCount, 1);
    });

    test('esquece os ids mais antigos além da janela', () async {
      gateway = FakeRelayGateway();
      await core.dispose();
      canais = FakeChannelPair();
      core = RelayHostCore(
        relays: RelayService(gateway),
        channel: canais.service,
        stateStore: ServiceStateStore(store),
        relayRepository: RelayRepository(store),
        notifier: notifier,
        acceptedKinds: driverConsumedKinds,
        maxSeenIds: 2,
      );
      await core.start();
      final primeiro = solicitacao();

      chega(primeiro);
      chega(solicitacao());
      chega(solicitacao());
      chega(primeiro);
      await pumpEventQueue();

      expect(enviadas<ServiceIncoming>(), hasLength(4));
    });
  });

  group('RelayHostCore — conexão hospedada no serviço', () {
    test(
      'conecta sozinho à lista persistida e avisa que está pronto',
      () async {
        await iniciar();

        expect(gateway.connected, [_relayA, _relayB]);
        expect(enviadas<ServiceReady>(), hasLength(1));
      },
    );

    test(
      'iniciado pelo app, ignora o estado de uma execução anterior',
      () async {
        await iniciar(estado: online);
        await core.dispose();
        final outroCanal = FakeChannelPair();
        core = RelayHostCore(
          relays: RelayService(gateway),
          channel: outroCanal.service,
          stateStore: ServiceStateStore(store),
          relayRepository: RelayRepository(store),
          notifier: notifier,
          acceptedKinds: driverConsumedKinds,
        );

        await core.start(restoreState: false);

        expect(core.state, const ServiceState());
        final salvo = await ServiceStateStore(store).load();
        expect(
          salvo.online,
          isFalse,
          reason: 'o online antigo não pode voltar',
        );
        outroCanal.ui.send(const ServiceHello(foreground: true));
        await pumpEventQueue();
        expect(
          outroCanal.service.sent.whereType<ServiceHelloAck>().single.online,
          isFalse,
        );
      },
    );

    test('lê o estado persistido ao iniciar', () async {
      await iniciar(estado: online);

      expect(core.state.online, isTrue);
      expect(core.state.acceptedPayments, {'pix', 'cartao'});
    });

    test('mudança de estado de um relay chega à interface', () async {
      await iniciar();

      gateway.drop(_relayA);
      await pumpEventQueue();

      final mudancas = enviadas<ServiceRelaysChanged>();
      expect(mudancas, isNotEmpty);
      expect(
        mudancas.last.relays.firstWhere((r) => r.url == _relayA).status,
        RelayStatus.unavailable,
      );
    });

    test(
      'relay que cai é reconectado sozinho e a interface é avisada (US3)',
      () async {
        await iniciar();
        await core.dispose();
        gateway = FakeRelayGateway();
        canais = FakeChannelPair();
        core = RelayHostCore(
          relays: RelayService(
            gateway,
            retryInterval: const Duration(milliseconds: 20),
            livenessInterval: const Duration(days: 1),
          ),
          channel: canais.service,
          stateStore: ServiceStateStore(store),
          relayRepository: RelayRepository(store),
          notifier: notifier,
          acceptedKinds: driverConsumedKinds,
        );
        await core.start();
        expect(gateway.connected, [_relayA, _relayB]);

        gateway.drop(_relayA);
        await pumpEventQueue();
        expect(
          enviadas<ServiceRelaysChanged>().last.relays
              .firstWhere((r) => r.url == _relayA)
              .status,
          RelayStatus.unavailable,
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));
        await pumpEventQueue();

        expect(gateway.connected.where((u) => u == _relayA), hasLength(2));
        expect(
          enviadas<ServiceRelaysChanged>().last.relays
              .firstWhere((r) => r.url == _relayA)
              .status,
          RelayStatus.connected,
        );
      },
    );

    test('executa addRelay, removeRelay e reconnectNow da interface', () async {
      await iniciar();

      daInterface(const ServiceAddRelay('wss://c.test'));
      await pumpEventQueue();
      expect(gateway.connected, contains('wss://c.test'));

      daInterface(const ServiceRemoveRelay('wss://c.test'));
      await pumpEventQueue();
      expect(gateway.disconnected, contains('wss://c.test'));

      final antes = enviadas<ServiceRelaysChanged>().length;
      daInterface(const ServiceReconnectNow());
      await pumpEventQueue();
      expect(gateway.probes[_relayA], 1);
      expect(
        enviadas<ServiceRelaysChanged>().length,
        greaterThan(antes),
        reason: 'a interface espera uma resposta mesmo sem mudança de estado',
      );
    });

    test('connectAll da interface substitui a lista', () async {
      await iniciar();

      daInterface(const ServiceConnectAll([Relay(url: 'wss://d.test')]));
      await pumpEventQueue();

      expect(gateway.connected, contains('wss://d.test'));
    });

    test('ServiceStop encerra e pede a parada do serviço', () async {
      var parou = false;
      await iniciar();
      await core.dispose();
      canais = FakeChannelPair();
      core = RelayHostCore(
        relays: RelayService(gateway),
        channel: canais.service,
        stateStore: ServiceStateStore(store),
        relayRepository: RelayRepository(store),
        notifier: notifier,
        acceptedKinds: driverConsumedKinds,
        onStopRequested: () async => parou = true,
      );
      await core.start();

      daInterface(const ServiceStop());
      await pumpEventQueue();

      expect(parou, isTrue);
    });
  });

  group('RelayHostCore — publicar o que a interface já assinou', () {
    setUp(iniciar);

    test('publica o payload e devolve um resultado por relay', () async {
      gateway.publishOutcomes = const [
        PublishOutcome(relayUrl: _relayA, accepted: true),
        PublishOutcome(relayUrl: _relayB, accepted: false, message: 'blocked'),
      ];
      final payload = signedPayload(kind: NostrEvent.kindRideQuote);

      daInterface(
        ServicePublish(reqId: 3, id: payload['id'] as String, payload: payload),
      );
      await pumpEventQueue();

      expect(gateway.published.single['id'], payload['id']);
      final resultados = enviadas<ServicePublishResult>();
      expect(
        resultados.where((r) => !r.done).map((r) => r.outcomes.single.accepted),
        [true, false],
      );
      expect(resultados.last.done, isTrue);
      expect(resultados.last.reqId, 3);
      expect(resultados.last.error, isNull);
    });

    test('sem relay conectado devolve no_relay e não publica', () async {
      await core.dispose();
      await iniciar(relays: const []);
      final payload = signedPayload(kind: NostrEvent.kindRideQuote);

      daInterface(
        ServicePublish(reqId: 4, id: payload['id'] as String, payload: payload),
      );
      await pumpEventQueue();

      expect(gateway.published, isEmpty);
      final fim = enviadas<ServicePublishResult>().single;
      expect(fim.done, isTrue);
      expect(fim.error, 'no_relay');
    });
  });

  group(
    'RelayHostCore — notificação de solicitação (FR-005, FR-006, FR-007)',
    () {
      test(
        'notifica com o app fora de primeiro plano e a regra satisfeita',
        () async {
          await iniciar(estado: online);
          final payload = solicitacao();

          chega(payload);
          await pumpEventQueue();

          expect(notifier.notified, [payload['id']]);
        },
      );

      test('uma única notificação por id mesmo vindo de três relays', () async {
        await iniciar(estado: online);
        final payload = solicitacao();

        chega(payload, relay: _relayA);
        chega(payload, relay: _relayB);
        chega(payload, relay: 'wss://c.test');
        await pumpEventQueue();

        expect(notifier.notified, hasLength(1));
      });

      test('com o app em primeiro plano só repassa, sem notificar', () async {
        await iniciar(estado: online.copyWith(appInForeground: true));
        daInterface(const ServiceHello(foreground: true));
        final payload = solicitacao();

        chega(payload);
        await pumpEventQueue();

        expect(enviadas<ServiceIncoming>(), hasLength(1));
        expect(notifier.notified, isEmpty);
      });

      for (final caso in <(String, ServiceState, String)>[
        ('offline', online.copyWith(online: false), 'pix'),
        (
          'em corrida',
          online.copyWith(rideStatus: DriverRideStatus.emCorrida),
          'pix',
        ),
        (
          'deslocando-se',
          online.copyWith(rideStatus: DriverRideStatus.deslocandoAtePassageiro),
          'pix',
        ),
        (
          'pagamento não aceito',
          online.copyWith(acceptedPayments: const {'dinheiro'}),
          'pix',
        ),
        ('pagamento fora do contrato', online, 'bitcoin'),
      ]) {
        test('não notifica: ${caso.$1}', () async {
          await iniciar(estado: caso.$2);

          chega(solicitacao(payment: caso.$3));
          await pumpEventQueue();

          expect(notifier.notified, isEmpty);
        });
      }

      test('não notifica content malformado', () async {
        await iniciar(estado: online);

        chega(signedPayload(kind: NostrEvent.kindRideRequest, content: 'lixo'));
        await pumpEventQueue();

        expect(notifier.notified, isEmpty);
      });

      test(
        'recibo (20014) e confirmação (20015) válidos são só repassados, sem '
        'notificar nem decifrar (feature 026)',
        () async {
          await iniciar(estado: online);
          // O conteúdo é opaco para o serviço: aqui, texto cifrado qualquer.
          final recibo = signedPayload(
            kind: NostrEvent.kindReceipt,
            content: 'AuaCIAwsLvpa',
          );
          final confirmacao = signedPayload(
            kind: NostrEvent.kindReceiptAck,
            content: 'AuaCIAwsLvpb',
          );

          chega(recibo);
          chega(confirmacao);
          await pumpEventQueue();

          expect(enviadas<ServiceIncoming>().map((m) => m.payload['id']), [
            recibo['id'],
            confirmacao['id'],
          ]);
          expect(notifier.notified, isEmpty);
        },
      );

      test('20014 e 20015 com assinatura adulterada ou sem marcador são '
          'descartados, e nada é notificado', () async {
        await iniciar(estado: online);

        chega(
          signedPayload(kind: NostrEvent.kindReceipt, content: 'x')
            ..['sig'] = 'f' * 128,
        );
        chega(
          signedPayload(
            kind: NostrEvent.kindReceiptAck,
            content: 'x',
            tags: const [],
          ),
        );
        await pumpEventQueue();

        expect(enviadas<ServiceIncoming>(), isEmpty);
        expect(core.discardedInvalidCount, 1);
        expect(core.discardedUnmarkedCount, 1);
        expect(notifier.notified, isEmpty);
      });

      test('só a solicitação notifica, não os outros kinds', () async {
        await iniciar(estado: online);

        chega(signedPayload(kind: NostrEvent.kindQuoteAccepted, content: 'x'));
        await pumpEventQueue();

        expect(notifier.notified, isEmpty);
      });

      test(
        'state da interface muda a decisão e é persistido sem o primeiro plano',
        () async {
          await iniciar();

          daInterface(
            const ServiceStateUpdate(
              ServiceState(online: true, acceptedPayments: {'pix'}),
            ),
          );
          await pumpEventQueue();
          chega(solicitacao());
          await pumpEventQueue();

          expect(notifier.notified, hasLength(1));
          final salvo =
              jsonDecode(store.values[ServiceStateStore.storageKey]!) as Map;
          expect(salvo['online'], isTrue);
          expect(salvo.containsKey('appInForeground'), isFalse);
        },
      );

      test('hello devolve as solicitações guardadas uma única vez', () async {
        await iniciar(estado: online);
        final payload = solicitacao();
        chega(payload);
        await pumpEventQueue();

        daInterface(const ServiceHello(foreground: true));
        await pumpEventQueue();
        daInterface(const ServiceHello(foreground: true));
        await pumpEventQueue();

        final acks = enviadas<ServiceHelloAck>();
        expect(acks, hasLength(2));
        expect(acks[0].online, isTrue);
        expect(acks[0].pending.single['id'], payload['id']);
        expect(acks[1].pending, isEmpty);
      });

      test(
        'descarta da reentrega a solicitação com mais de 5 minutos',
        () async {
          await iniciar(estado: online);
          chega(solicitacao());
          await pumpEventQueue();

          agora = agora.add(const Duration(minutes: 5, seconds: 1));
          daInterface(const ServiceHello(foreground: true));
          await pumpEventQueue();

          expect(enviadas<ServiceHelloAck>().single.pending, isEmpty);
        },
      );

      test('mantém na reentrega a de menos de 5 minutos', () async {
        await iniciar(estado: online);
        chega(solicitacao());
        await pumpEventQueue();

        agora = agora.add(const Duration(minutes: 4, seconds: 59));
        daInterface(const ServiceHello(foreground: true));
        await pumpEventQueue();

        expect(enviadas<ServiceHelloAck>().single.pending, hasLength(1));
      });

      test('app voltando à tela remove as notificações da bandeja', () async {
        await iniciar(estado: online);

        daInterface(const ServiceHello(foreground: true));
        await pumpEventQueue();

        expect(notifier.cancelAllCalls, 1);
      });
    },
  );
}
