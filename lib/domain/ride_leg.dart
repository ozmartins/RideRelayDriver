import 'package:latlong2/latlong.dart';

import 'active_ride.dart';
import 'driver_ride_status.dart';
import 'geo_distance.dart';

/// Qual trecho da corrida o mapa deve orientar.
enum RideLegKind {
  /// "Deslocando-se até o passageiro": do motorista ao ponto de embarque.
  pickup,

  /// "Em corrida": do motorista ao destino.
  dropoff,
}

/// Trecho vigente da corrida, derivado de [DriverRideStatus] e [ActiveRide]
/// (D4 de `specs/016-rota-no-mapa/research.md`). Nunca persistido: o que
/// sobrevive a um reinício do app é o `ActiveRide`, do qual este valor sai
/// de novo.
class RideLeg {
  const RideLeg({required this.kind, required this.target});

  final RideLegKind kind;
  final LatLng target;

  /// Limiar, em metros, de deslocamento para recalcular o trajeto (FR-004;
  /// mesmo valor da feature 007 do passageiro).
  static const refreshThresholdMeters = 50.0;

  /// Trecho a orientar, ou `null` quando não há nenhum (FR-003): fora de
  /// "Deslocando-se"/"Em corrida", sem corrida ativa, ou com o alvo em
  /// `(0, 0)` — corrida anterior às features 011/012, sem coordenada
  /// gravada.
  static RideLeg? of(DriverRideStatus status, ActiveRide? ride) {
    if (ride == null) return null;
    final RideLeg leg;
    switch (status) {
      case DriverRideStatus.deslocandoAtePassageiro:
        leg = RideLeg(
          kind: RideLegKind.pickup,
          target: LatLng(ride.originLat, ride.originLon),
        );
      case DriverRideStatus.emCorrida:
        leg = RideLeg(
          kind: RideLegKind.dropoff,
          target: LatLng(ride.destinationLat, ride.destinationLon),
        );
      case DriverRideStatus.aguardandoSolicitacao:
        return null;
    }
    if (leg.target.latitude == 0 && leg.target.longitude == 0) return null;
    return leg;
  }

  /// Decide se uma nova consulta de rota é necessária (D3 de `research.md`):
  /// não há tentativa anterior, ou o trecho (tipo ou alvo) mudou.
  ///
  /// Com um trajeto [route] já calculado com sucesso para este trecho, só
  /// consulta de novo se o motorista saiu da rota: a distância de [current]
  /// à polilinha, medida localmente (sem requisição), é de ao menos
  /// [thresholdMeters]. Seguindo a rota, o trecho inteiro custa uma
  /// consulta só. Sem trajeto (a última tentativa falhou ou ainda não
  /// respondeu), vale a regra antiga: ao menos [thresholdMeters] desde a
  /// última tentativa, bem-sucedida ou não.
  static bool shouldRefresh({
    required RideLeg leg,
    required LatLng current,
    ({RideLeg leg, LatLng origin})? lastAttempt,
    List<LatLng>? route,
    double thresholdMeters = refreshThresholdMeters,
  }) {
    if (lastAttempt == null) return true;
    if (lastAttempt.leg != leg) return true;
    if (route != null && route.length >= 2) {
      return distanceToPolylineMeters(current.latitude, current.longitude, [
            for (final ponto in route)
              (lat: ponto.latitude, lon: ponto.longitude),
          ]) >=
          thresholdMeters;
    }
    return metersBetween(
          lastAttempt.origin.latitude,
          lastAttempt.origin.longitude,
          current.latitude,
          current.longitude,
        ) >=
        thresholdMeters;
  }

  @override
  bool operator ==(Object other) =>
      other is RideLeg && other.kind == kind && other.target == target;

  @override
  int get hashCode => Object.hash(kind, target);

  @override
  String toString() => 'RideLeg($kind, $target)';
}
