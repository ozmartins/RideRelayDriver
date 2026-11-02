import 'package:driver/domain/driver_ride_status.dart';
import 'package:driver/domain/service_state.dart';
import 'package:driver/services/background/service_controller.dart';
import 'package:driver/services/background/service_messages.dart';
import 'package:driver/services/remote_relay_connection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_background_service.dart';
import '../../support/fake_message_channel.dart';

void main() {
  late FakeChannelPair canais;
  late FakeBackgroundService servico;
  late RemoteRelayConnection conexao;
  late ServiceController controlador;

  setUp(() {
    canais = FakeChannelPair();
    servico = FakeBackgroundService(canais.ui);
    conexao = RemoteRelayConnection(
      canais.ui,
      helloRetry: const Duration(milliseconds: 20),
    );
    controlador = ServiceController(
      service: servico,
      connection: conexao,
      resumeTimeout: const Duration(milliseconds: 80),
    );
  });

  tearDown(() async {
    await controlador.dispose();
    await conexao.dispose();
  });

  List<T> daInterface<T extends ServiceMessage>() =>
      canais.ui.sent.whereType<T>().toList();

  void servicoResponde({bool online = false}) => canais.service.send(
    ServiceHelloAck(online: online, relays: const [], pending: const []),
  );

  const online = ServiceState(online: true, acceptedPayments: {'pix'});

  group('ServiceController.shouldRun (FR-001)', () {
    test('roda em primeiro plano, online ou não', () {
      for (final on in [true, false]) {
        for (final notifica in [true, false]) {
          expect(
            ServiceController.shouldRun(
              foreground: true,
              online: on,
              canNotify: notifica,
            ),
            isTrue,
          );
        }
      }
    });

    test('em segundo plano só roda online e com permissão de notificar', () {
      bool roda({required bool online, required bool notifica}) =>
          ServiceController.shouldRun(
            foreground: false,
            online: online,
            canNotify: notifica,
          );

      expect(roda(online: true, notifica: true), isTrue);
      expect(roda(online: true, notifica: false), isFalse);
      expect(roda(online: false, notifica: true), isFalse);
      expect(roda(online: false, notifica: false), isFalse);
    });
  });

  group('ServiceController — início e estado', () {
    test(
      'start liga o serviço com a notificação discreta e se apresenta',
      () async {
        await controlador.start();

        expect(servico.started, [ServiceController.textConnected]);
        expect(daInterface<ServiceHello>().first.foreground, isTrue);
      },
    );

    test(
      'não manda estado antes de a tela informar o primeiro (FR-012)',
      () async {
        await controlador.start();
        servicoResponde(online: true);
        await pumpEventQueue();

        expect(daInterface<ServiceStateUpdate>(), isEmpty);
      },
    );

    test('update manda o estado e troca o texto ao ficar online', () async {
      await controlador.start();
      servicoResponde();
      await pumpEventQueue();

      controlador.update(online);
      await pumpEventQueue();

      final estado = daInterface<ServiceStateUpdate>().single.state;
      expect(estado.online, isTrue);
      expect(estado.acceptedPayments, {'pix'});
      expect(estado.appInForeground, isTrue);
      expect(servico.texts.last, ServiceController.textOnline);
      expect(servico.running, isTrue);
    });

    test('update sem mudança não reenvia', () async {
      await controlador.start();
      servicoResponde();
      await pumpEventQueue();
      controlador.update(online);
      controlador.update(online);
      controlador.update(online.copyWith());
      await pumpEventQueue();

      expect(daInterface<ServiceStateUpdate>(), hasLength(1));
    });

    test('o estado da corrida chega ao serviço', () async {
      await controlador.start();
      servicoResponde();
      controlador.update(online);
      controlador.update(
        online.copyWith(rideStatus: DriverRideStatus.deslocandoAtePassageiro),
      );
      await pumpEventQueue();

      expect(
        daInterface<ServiceStateUpdate>().last.state.rideStatus,
        DriverRideStatus.deslocandoAtePassageiro,
      );
    });

    test('quando o serviço reaparece, o estado é reenviado', () async {
      await controlador.start();
      servicoResponde();
      controlador.update(online);
      await pumpEventQueue();
      final antes = daInterface<ServiceStateUpdate>().length;

      canais.service.send(const ServiceReady());
      await pumpEventQueue();
      servicoResponde();
      await pumpEventQueue();

      expect(daInterface<ServiceStateUpdate>().length, greaterThan(antes));
    });
  });

  group('ServiceController — retomar online (FR-012)', () {
    test('resumeOnline traz o que o serviço guardou', () async {
      await controlador.start();

      servicoResponde(online: true);

      expect(await controlador.resumeOnline, isTrue);
    });

    test('resumeOnline é falso se o serviço estava offline', () async {
      await controlador.start();

      servicoResponde(online: false);

      expect(await controlador.resumeOnline, isFalse);
    });

    test(
      'resumeOnline desiste e devolve falso se o serviço não responde',
      () async {
        await controlador.start();

        expect(await controlador.resumeOnline, isFalse);
      },
    );
  });

  group('ServiceController — ciclo de vida (FR-001)', () {
    setUp(() async {
      await controlador.start();
      servicoResponde();
      await pumpEventQueue();
    });

    test('sair do app offline encerra o serviço', () async {
      controlador.update(const ServiceState(acceptedPayments: {'pix'}));
      await controlador.onForeground(false);

      expect(servico.running, isFalse);
      expect(servico.stops, 1);
    });

    test(
      'sair do app online mantém o serviço e avisa que não há tela',
      () async {
        controlador.update(online);
        await controlador.onForeground(false);
        servicoResponde();
        await pumpEventQueue();

        expect(servico.running, isTrue);
        expect(
          daInterface<ServiceStateUpdate>().last.state.appInForeground,
          isFalse,
        );
      },
    );

    test(
      'sair do app online sem permissão de notificar encerra o serviço',
      () async {
        servico.permission = false;
        servico.grantsWhenAsked = false;
        controlador.update(online);
        await controlador.ensureNotificationPermission();
        await controlador.onForeground(false);

        expect(servico.running, isFalse);
      },
    );

    test(
      'voltar à tela religa o serviço parado e se apresenta de novo',
      () async {
        controlador.update(const ServiceState(acceptedPayments: {'pix'}));
        await controlador.onForeground(false);
        final hellos = daInterface<ServiceHello>().length;

        await controlador.onForeground(true);

        expect(servico.running, isTrue);
        expect(servico.started, hasLength(2));
        expect(daInterface<ServiceHello>().length, greaterThan(hellos));
        expect(daInterface<ServiceHello>().last.foreground, isTrue);
      },
    );

    test(
      'ficar offline com o app em segundo plano encerra o serviço',
      () async {
        controlador.update(online);
        await controlador.onForeground(false);
        expect(servico.running, isTrue);

        controlador.update(online.copyWith(online: false));

        expect(servico.running, isFalse);
      },
    );

    test('o mesmo estado de primeiro plano repetido não faz nada', () async {
      final hellos = daInterface<ServiceHello>().length;

      await controlador.onForeground(true);

      expect(daInterface<ServiceHello>().length, hellos);
      expect(servico.stops, 0);
    });
  });

  group('ServiceController — permissão de notificação (FR-009)', () {
    setUp(() async {
      await controlador.start();
      servicoResponde();
      await pumpEventQueue();
    });

    test('não pede de novo se já foi concedida', () async {
      expect(await controlador.ensureNotificationPermission(), isTrue);
      expect(servico.permissionRequests, 0);
    });

    test('pede se ainda não foi concedida e devolve a resposta', () async {
      servico.permission = false;

      expect(await controlador.ensureNotificationPermission(), isTrue);
      expect(servico.permissionRequests, 1);
    });

    test('negada: devolve falso', () async {
      servico.permission = false;
      servico.grantsWhenAsked = false;

      expect(await controlador.ensureNotificationPermission(), isFalse);
    });
  });
}
