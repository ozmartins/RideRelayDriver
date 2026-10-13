import 'package:driver/domain/driver_ride_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriverRideRules.canStartRide (FR-002)', () {
    test('permite iniciar corrida a partir de aguardandoSolicitacao', () {
      expect(
        DriverRideRules.canStartRide(DriverRideStatus.aguardandoSolicitacao),
        isTrue,
      );
    });

    test('impede iniciar corrida a partir de deslocandoAtePassageiro', () {
      expect(
        DriverRideRules.canStartRide(DriverRideStatus.deslocandoAtePassageiro),
        isFalse,
      );
    });

    test('impede iniciar corrida a partir de emCorrida', () {
      expect(DriverRideRules.canStartRide(DriverRideStatus.emCorrida), isFalse);
    });
  });

  group('DriverRideRules.canConfirmMeeting (FR-001/FR-002 da feature 012)', () {
    test('permite confirmar encontro a partir de deslocandoAtePassageiro', () {
      expect(
        DriverRideRules.canConfirmMeeting(
          DriverRideStatus.deslocandoAtePassageiro,
        ),
        isTrue,
      );
    });

    test('impede confirmar encontro a partir de aguardandoSolicitacao', () {
      expect(
        DriverRideRules.canConfirmMeeting(
          DriverRideStatus.aguardandoSolicitacao,
        ),
        isFalse,
      );
    });

    test('impede confirmar encontro a partir de emCorrida (idempotência)', () {
      expect(
        DriverRideRules.canConfirmMeeting(DriverRideStatus.emCorrida),
        isFalse,
      );
    });
  });

  group(
    'DriverRideRules.canConfirmDestinationArrival (FR-007/FR-008 da feature '
    '012)',
    () {
      test('permite confirmar destino a partir de emCorrida', () {
        expect(
          DriverRideRules.canConfirmDestinationArrival(
            DriverRideStatus.emCorrida,
          ),
          isTrue,
        );
      });

      test('impede confirmar destino a partir de deslocandoAtePassageiro', () {
        expect(
          DriverRideRules.canConfirmDestinationArrival(
            DriverRideStatus.deslocandoAtePassageiro,
          ),
          isFalse,
        );
      });

      test('impede confirmar destino a partir de aguardandoSolicitacao', () {
        expect(
          DriverRideRules.canConfirmDestinationArrival(
            DriverRideStatus.aguardandoSolicitacao,
          ),
          isFalse,
        );
      });
    },
  );

  group('DriverRideRules.canCancelRide (feature 018)', () {
    test('impede cancelar em aguardandoSolicitacao', () {
      expect(
        DriverRideRules.canCancelRide(DriverRideStatus.aguardandoSolicitacao),
        isFalse,
      );
    });

    test('permite cancelar em deslocandoAtePassageiro', () {
      expect(
        DriverRideRules.canCancelRide(DriverRideStatus.deslocandoAtePassageiro),
        isTrue,
      );
    });

    test('permite cancelar em emCorrida', () {
      expect(DriverRideRules.canCancelRide(DriverRideStatus.emCorrida), isTrue);
    });
  });

  group('DriverRideRules.canBeCancelledByPassenger (feature 020)', () {
    test('ignora o aviso em aguardandoSolicitacao', () {
      expect(
        DriverRideRules.canBeCancelledByPassenger(
          DriverRideStatus.aguardandoSolicitacao,
        ),
        isFalse,
      );
    });

    test('vale em deslocandoAtePassageiro', () {
      expect(
        DriverRideRules.canBeCancelledByPassenger(
          DriverRideStatus.deslocandoAtePassageiro,
        ),
        isTrue,
      );
    });

    test('vale em emCorrida', () {
      expect(
        DriverRideRules.canBeCancelledByPassenger(DriverRideStatus.emCorrida),
        isTrue,
      );
    });
  });
}
