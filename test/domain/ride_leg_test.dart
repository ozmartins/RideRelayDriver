import 'package:driver/domain/active_ride.dart';
import 'package:driver/domain/driver_ride_status.dart';
import 'package:driver/domain/ride_leg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

ActiveRide corrida({
  double originLat = -28.9298,
  double originLon = -49.4753,
  double destinationLat = -28.6721,
  double destinationLon = -49.3671,
}) => ActiveRide(
  quoteId: 'quote-1',
  passengerPubkey: 'pub-1',
  originLat: originLat,
  originLon: originLon,
  destinationLat: destinationLat,
  destinationLon: destinationLon,
);

void main() {
  group('RideLeg.of', () {
    test('Deslocando-se até o passageiro orienta até a origem', () {
      final leg = RideLeg.of(
        DriverRideStatus.deslocandoAtePassageiro,
        corrida(),
      );

      expect(leg, isNotNull);
      expect(leg!.kind, RideLegKind.pickup);
      expect(leg.target, const LatLng(-28.9298, -49.4753));
    });

    test('Em corrida orienta até o destino', () {
      final leg = RideLeg.of(DriverRideStatus.emCorrida, corrida());

      expect(leg!.kind, RideLegKind.dropoff);
      expect(leg.target, const LatLng(-28.6721, -49.3671));
    });

    test('Aguardando solicitação não tem trecho (FR-003)', () {
      expect(
        RideLeg.of(DriverRideStatus.aguardandoSolicitacao, corrida()),
        isNull,
      );
    });

    test('sem corrida ativa não tem trecho', () {
      expect(
        RideLeg.of(DriverRideStatus.deslocandoAtePassageiro, null),
        isNull,
      );
      expect(RideLeg.of(DriverRideStatus.emCorrida, null), isNull);
    });

    test(
      'alvo em (0, 0) — corrida sem coordenada gravada — não tem trecho',
      () {
        expect(
          RideLeg.of(
            DriverRideStatus.deslocandoAtePassageiro,
            corrida(originLat: 0, originLon: 0),
          ),
          isNull,
        );
        expect(
          RideLeg.of(
            DriverRideStatus.emCorrida,
            corrida(destinationLat: 0, destinationLon: 0),
          ),
          isNull,
        );
      },
    );

    test('origem em (0, 0) não impede o trecho de destino', () {
      final leg = RideLeg.of(
        DriverRideStatus.emCorrida,
        corrida(originLat: 0, originLon: 0),
      );

      expect(leg, isNotNull);
      expect(leg!.kind, RideLegKind.dropoff);
    });
  });

  group('RideLeg.shouldRefresh', () {
    const leg = RideLeg(
      kind: RideLegKind.pickup,
      target: LatLng(-28.9298, -49.4753),
    );
    const origem = LatLng(-28.9350, -49.4800);

    test('sem tentativa anterior, consulta', () {
      expect(RideLeg.shouldRefresh(leg: leg, current: origem), isTrue);
    });

    test('mesmo trecho e deslocamento menor que 50 m, não consulta', () {
      // ~11 m ao norte.
      const atual = LatLng(-28.9349, -49.4800);

      expect(
        RideLeg.shouldRefresh(
          leg: leg,
          current: atual,
          lastAttempt: (leg: leg, origin: origem),
        ),
        isFalse,
      );
    });

    test('mesmo trecho e deslocamento de 50 m ou mais, consulta', () {
      // ~111 m ao norte.
      const atual = LatLng(-28.9340, -49.4800);

      expect(
        RideLeg.shouldRefresh(
          leg: leg,
          current: atual,
          lastAttempt: (leg: leg, origin: origem),
        ),
        isTrue,
      );
    });

    test('trecho diferente consulta mesmo sem o motorista ter se movido', () {
      const outro = RideLeg(
        kind: RideLegKind.dropoff,
        target: LatLng(-28.6721, -49.3671),
      );

      expect(
        RideLeg.shouldRefresh(
          leg: outro,
          current: origem,
          lastAttempt: (leg: leg, origin: origem),
        ),
        isTrue,
      );
    });

    group('com trajeto já traçado', () {
      // Rota reta de ~1,1 km ao norte da origem.
      const rota = [LatLng(-28.9350, -49.4800), LatLng(-28.9250, -49.4800)];

      bool consulta(LatLng atual, {List<LatLng>? route = rota}) =>
          RideLeg.shouldRefresh(
            leg: leg,
            current: atual,
            lastAttempt: (leg: leg, origin: origem),
            route: route,
          );

      test('andar centenas de metros sobre a rota não consulta', () {
        // ~555 m ao norte, em cima da rota.
        expect(consulta(const LatLng(-28.9300, -49.4800)), isFalse);
      });

      test('a menos de 50 m da rota não consulta', () {
        // ~555 m ao norte e ~20 m para o lado.
        expect(consulta(const LatLng(-28.9300, -49.47982)), isFalse);
      });

      test('a 50 m ou mais da rota consulta', () {
        // ~555 m ao norte e ~100 m para o lado.
        expect(consulta(const LatLng(-28.9300, -49.4791)), isTrue);
      });

      test('passar do fim da rota conta pela distância ao último ponto', () {
        // ~280 m depois do fim.
        expect(consulta(const LatLng(-28.9225, -49.4800)), isTrue);
      });

      test('sem trajeto (tentativa falhou), vale a regra de 50 m andados', () {
        expect(consulta(const LatLng(-28.9340, -49.4800), route: null), isTrue);
        expect(
          consulta(const LatLng(-28.9349, -49.4800), route: null),
          isFalse,
        );
      });
    });
  });
}
