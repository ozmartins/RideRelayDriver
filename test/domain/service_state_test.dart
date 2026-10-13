import 'package:driver/domain/driver_ride_status.dart';
import 'package:driver/domain/service_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceState (data-model.md da feature 025)', () {
    test(
      'o padrão é offline, aguardando, sem cadastro e sem primeiro plano',
      () {
        const estado = ServiceState();

        expect(estado.online, isFalse);
        expect(estado.acceptedPayments, isNull);
        expect(estado.rideStatus, DriverRideStatus.aguardandoSolicitacao);
        expect(estado.appInForeground, isFalse);
      },
    );

    test('toJson e fromJson preservam os quatro campos', () {
      const estado = ServiceState(
        online: true,
        acceptedPayments: {'pix', 'dinheiro'},
        rideStatus: DriverRideStatus.emCorrida,
        appInForeground: true,
      );

      expect(ServiceState.fromJson(estado.toJson()), estado);
    });

    test('toStorageJson não persiste o primeiro plano', () {
      const estado = ServiceState(online: true, appInForeground: true);

      expect(estado.toStorageJson().containsKey('appInForeground'), isFalse);
      expect(
        ServiceState.fromJson(estado.toStorageJson()).appInForeground,
        isFalse,
      );
    });

    test('fromJson tolera campos ausentes e valores inesperados', () {
      expect(ServiceState.fromJson(const {}), const ServiceState());
      expect(
        ServiceState.fromJson(const {
          'online': 'sim',
          'acceptedPayments': 3,
          'rideStatus': 'inexistente',
        }),
        const ServiceState(),
      );
    });

    test('acceptedPayments ausente (null) difere de lista vazia', () {
      expect(
        ServiceState.fromJson(const {'acceptedPayments': <String>[]}),
        const ServiceState(acceptedPayments: <String>{}),
      );
      expect(ServiceState.fromJson(const {}).acceptedPayments, isNull);
    });

    test('copyWith troca só o que foi informado', () {
      const base = ServiceState(online: true, acceptedPayments: {'pix'});
      final copia = base.copyWith(appInForeground: true);

      expect(copia.online, isTrue);
      expect(copia.acceptedPayments, {'pix'});
      expect(copia.appInForeground, isTrue);
    });
  });
}
