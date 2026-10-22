import 'dart:async';

import 'package:driver/domain/driver_coverage.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/relay.dart';
import 'package:driver/services/background/service_messages.dart';
import 'package:driver/services/relay_connection.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:driver/services/remote_relay_connection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_message_channel.dart';
import '../support/signed_payload.dart';

const _a = Relay(url: 'wss://a.test', status: RelayStatus.connected);
const _b = Relay(url: 'wss://b.test', status: RelayStatus.unavailable);

void main() {
  late FakeChannelPair canais;
  late RemoteRelayConnection remota;

  setUp(() {
    canais = FakeChannelPair();
    remota = RemoteRelayConnection(
      canais.ui,
      helloRetry: const Duration(milliseconds: 20),
      reconnectTimeout: const Duration(milliseconds: 100),
    );
  });

  tearDown(() => remota.dispose());

  List<T> daInterface<T extends ServiceMessage>() =>
      canais.ui.sent.whereType<T>().toList();

  /// O serviço responde ao hello.
  void servicoResponde({
    List<Relay> relays = const [_a, _b],
    List<Map<String, dynamic>> pending = const [],
  }) => canais.service.send(
    ServiceHelloAck(online: true, relays: relays, pending: pending),
  );

  NostrEvent eventoDe(Map<String, dynamic> payload) =>
      NostrEvent.fromVerifiedPayload(payload);

  group('RemoteRelayConnection — ligação com o serviço', () {
    test('attach envia o hello e o repete até o serviço responder', () async {
      remota.attach(foreground: true);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(daInterface<ServiceHello>().length, greaterThanOrEqualTo(3));
      expect(daInterface<ServiceHello>().first.foreground, isTrue);

      servicoResponde();
      final enviados = daInterface<ServiceHello>().length;
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(daInterface<ServiceHello>().length, enviados);
      expect(remota.isAttached, isTrue);
    });

    test('o helloAck traz o estado dos relays e avisa a interface', () async {
      var avisos = 0;
      remota.statusChanges.listen((_) => avisos++);
      remota.attach(foreground: true);

      servicoResponde();
      await pumpEventQueue();

      expect(remota.relays.map((r) => r.url), ['wss://a.test', 'wss://b.test']);
      expect(remota.hasConnectedRelay, isTrue);
      expect(avisos, 1);
    });

    test(
      'as solicitações guardadas chegam pelo mesmo incoming dos eventos',
      () async {
        final recebidos = <IncomingEvent>[];
        remota.incoming.listen(recebidos.add);
        final payload = signedPayload(content: rideRequestContent());
        remota.attach(foreground: true);

        servicoResponde(pending: [payload]);
        await pumpEventQueue();

        expect(recebidos.single.payload['id'], payload['id']);
      },
    );

    test('comandos antes da resposta esperam e saem na ordem', () async {
      remota.attach(foreground: true);
      await remota.addRelay('wss://c.test');
      await remota.removeRelay('wss://b.test');

      expect(daInterface<ServiceAddRelay>(), isEmpty);

      servicoResponde();
      await pumpEventQueue();

      final comandos = canais.ui.sent
          .where((m) => m is ServiceAddRelay || m is ServiceRemoveRelay)
          .map((m) => m.type)
          .toList();
      expect(comandos, ['addRelay', 'removeRelay']);
    });

    test('depois de ligado os comandos saem na hora', () async {
      remota.attach(foreground: true);
      servicoResponde();
      await pumpEventQueue();

      await remota.addRelay('wss://c.test');

      expect(daInterface<ServiceAddRelay>().single.url, 'wss://c.test');
    });

    test('um novo ready (serviço reiniciado) refaz o handshake', () async {
      remota.attach(foreground: true);
      servicoResponde();
      await pumpEventQueue();
      final antes = daInterface<ServiceHello>().length;

      canais.service.send(const ServiceReady());
      await pumpEventQueue();

      expect(daInterface<ServiceHello>().length, greaterThan(antes));
      expect(remota.isAttached, isFalse);
    });

    test('attached emite a cada resposta do serviço', () async {
      var respostas = 0;
      remota.attached.listen((_) => respostas++);
      remota.attach(foreground: true);

      servicoResponde();
      await pumpEventQueue();

      expect(respostas, 1);
    });
  });

  group('RemoteRelayConnection — estado e eventos', () {
    setUp(() async {
      remota.attach(foreground: true);
      servicoResponde();
      await pumpEventQueue();
    });

    test('relaysChanged atualiza a lista e avisa', () async {
      var avisos = 0;
      remota.statusChanges.listen((_) => avisos++);

      canais.service.send(
        const ServiceRelaysChanged([
          Relay(url: 'wss://a.test', status: RelayStatus.unavailable),
        ]),
      );
      await pumpEventQueue();

      expect(remota.hasConnectedRelay, isFalse);
      expect(remota.relays.single.status, RelayStatus.unavailable);
      expect(avisos, 1);
    });

    test('incoming vira IncomingEvent com o relay de origem', () async {
      final recebidos = <IncomingEvent>[];
      remota.incoming.listen(recebidos.add);
      final payload = signedPayload();

      canais.service.send(
        ServiceIncoming(relayUrl: 'wss://a.test', payload: payload),
      );
      await pumpEventQueue();

      expect(recebidos.single.relayUrl, 'wss://a.test');
      expect(recebidos.single.id, payload['id']);
    });

    test(
      'connectAll com a mesma lista que o serviço já tem não faz nada',
      () async {
        await remota.connectAll(const [_b, _a]);

        expect(daInterface<ServiceConnectAll>(), isEmpty);
      },
    );

    test('connectAll com outra lista é enviado', () async {
      await remota.connectAll(const [Relay(url: 'wss://z.test')]);

      expect(
        daInterface<ServiceConnectAll>().single.relays.single.url,
        'wss://z.test',
      );
    });

    test('reconnectNow espera a resposta do serviço', () async {
      var terminou = false;
      final espera = remota.reconnectNow().then((_) => terminou = true);
      await pumpEventQueue();

      expect(daInterface<ServiceReconnectNow>(), hasLength(1));
      expect(terminou, isFalse);

      canais.service.send(const ServiceRelaysChanged([_a]));
      await espera;

      expect(terminou, isTrue);
    });

    test('reconnectNow não trava se o serviço não responder', () async {
      await remota.reconnectNow();
    });
  });

  group('RemoteRelayConnection — publicar', () {
    setUp(() async {
      remota.attach(foreground: true);
      servicoResponde();
      await pumpEventQueue();
    });

    test(
      'envia o payload já assinado e devolve um resultado por relay',
      () async {
        final payload = signedPayload(kind: NostrEvent.kindRideQuote);
        final resultados = <PublishOutcome>[];
        final fim = Completer<void>();

        remota
            .publish(eventoDe(payload), payload: payload)
            .listen(resultados.add, onDone: fim.complete);
        await pumpEventQueue();

        final enviado = daInterface<ServicePublish>().single;
        expect(enviado.id, payload['id']);
        expect(enviado.payload, payload);

        canais.service
          ..send(
            ServicePublishResult(
              reqId: enviado.reqId,
              outcomes: const [
                PublishOutcome(relayUrl: 'wss://a.test', accepted: true),
              ],
              done: false,
            ),
          )
          ..send(
            ServicePublishResult(
              reqId: enviado.reqId,
              outcomes: const [
                PublishOutcome(
                  relayUrl: 'wss://b.test',
                  accepted: false,
                  message: 'x',
                ),
              ],
              done: false,
            ),
          )
          ..send(
            ServicePublishResult(
              reqId: enviado.reqId,
              outcomes: const [],
              done: true,
            ),
          );
        await fim.future;

        expect(resultados.map((r) => r.accepted), [true, false]);
      },
    );

    test(
      'lança NoConnectedRelay na hora se nenhum relay está conectado',
      () async {
        canais.service.send(const ServiceRelaysChanged([_b]));
        await pumpEventQueue();
        final payload = signedPayload();

        expect(
          () => remota.publish(eventoDe(payload), payload: payload),
          throwsA(isA<NoConnectedRelay>()),
        );
        expect(daInterface<ServicePublish>(), isEmpty);
      },
    );

    test('no_relay do serviço vira NoConnectedRelay no fluxo', () async {
      final payload = signedPayload();
      final erros = <Object>[];
      final fim = Completer<void>();
      remota
          .publish(eventoDe(payload), payload: payload)
          .listen((_) {}, onError: erros.add, onDone: fim.complete);
      await pumpEventQueue();

      canais.service.send(
        ServicePublishResult(
          reqId: daInterface<ServicePublish>().single.reqId,
          outcomes: const [],
          done: true,
          error: 'no_relay',
        ),
      );
      await fim.future;

      expect(erros.single, isA<NoConnectedRelay>());
    });

    test('duas publicações simultâneas não misturam resultados', () async {
      final p1 = signedPayload(kind: NostrEvent.kindRideQuote);
      final p2 = signedPayload(kind: NostrEvent.kindRideQuote);
      final r1 = <PublishOutcome>[];
      final r2 = <PublishOutcome>[];
      remota.publish(eventoDe(p1), payload: p1).listen(r1.add);
      remota.publish(eventoDe(p2), payload: p2).listen(r2.add);
      await pumpEventQueue();
      final ids = daInterface<ServicePublish>();

      canais.service.send(
        ServicePublishResult(
          reqId: ids[1].reqId,
          outcomes: const [
            PublishOutcome(relayUrl: 'wss://b.test', accepted: true),
          ],
          done: false,
        ),
      );
      await pumpEventQueue();

      expect(r1, isEmpty);
      expect(r2.single.relayUrl, 'wss://b.test');
    });
  });

  test('dispose é idempotente e fecha os fluxos', () async {
    var fechou = false;
    remota.incoming.listen((_) {}, onDone: () => fechou = true);

    await remota.dispose();
    await remota.dispose();
    await pumpEventQueue();

    expect(fechou, isTrue);
  });
  group('RemoteRelayConnection — cobertura geográfica (feature 027)', () {
    final cobertura = DriverCoverage.around(
      lat: -28.9298,
      lon: -49.4753,
      radiusKm: 10,
    );

    test(
      'applyCoverage guarda a cobertura e envia ServiceSetCoverage',
      () async {
        remota.attach(foreground: true);
        servicoResponde();
        await pumpEventQueue();

        await remota.applyCoverage(cobertura);

        expect(remota.coverage, cobertura);
        final enviadas = daInterface<ServiceSetCoverage>();
        expect(enviadas, hasLength(1));
        expect(enviadas.single.coverage, cobertura);
      },
    );

    test('applyCoverage(null) envia null e zera a cobertura', () async {
      remota.attach(foreground: true);
      servicoResponde();
      await pumpEventQueue();
      await remota.applyCoverage(cobertura);

      await remota.applyCoverage(null);

      expect(remota.coverage, isNull);
      expect(daInterface<ServiceSetCoverage>().last.coverage, isNull);
    });

    test('antes de o serviço responder, a mensagem espera na fila', () async {
      remota.attach(foreground: true);
      await remota.applyCoverage(cobertura);
      expect(daInterface<ServiceSetCoverage>(), isEmpty);

      servicoResponde();
      await pumpEventQueue();

      expect(daInterface<ServiceSetCoverage>().last.coverage, cobertura);
    });

    test(
      'serviço reiniciado (novo helloAck) recebe a cobertura vigente',
      () async {
        remota.attach(foreground: true);
        servicoResponde();
        await pumpEventQueue();
        await remota.applyCoverage(cobertura);
        final antes = daInterface<ServiceSetCoverage>().length;

        remota.attach(foreground: true);
        servicoResponde();
        await pumpEventQueue();

        expect(daInterface<ServiceSetCoverage>().length, antes + 1);
        expect(daInterface<ServiceSetCoverage>().last.coverage, cobertura);
      },
    );

    test('sem cobertura, o helloAck não manda mensagem de cobertura', () async {
      remota.attach(foreground: true);
      servicoResponde();
      await pumpEventQueue();

      expect(daInterface<ServiceSetCoverage>(), isEmpty);
    });
  });
}
