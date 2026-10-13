import 'package:latlong2/latlong.dart';

/// Trajeto rodoviário calculado entre a posição do motorista e o ponto-alvo
/// do trecho vigente da corrida (`data-model.md` da feature 016).
///
/// Tipo próprio do projeto — não expõe nenhum tipo de `open_route_service`
/// (Princípio III). Existe só em memória, nunca persistido nem publicado.
class RouteTrace {
  const RouteTrace({
    required this.points,
    required this.distanceMeters,
    required this.originUsed,
    required this.target,
    this.durationSeconds,
  });

  /// Pontos do trajeto, da origem ao alvo — alimenta a polilinha do mapa.
  final List<LatLng> points;

  /// Distância rodoviária total, em metros.
  final double distanceMeters;

  /// Posição do motorista no momento do cálculo — base do limiar de 50 m
  /// para recalcular (FR-004).
  final LatLng originUsed;

  /// Alvo usado neste cálculo — permite descartar uma resposta tardia que
  /// já não corresponde ao trecho vigente.
  final LatLng target;

  /// Duração estimada do trajeto, em segundos, quando o serviço a informa.
  final double? durationSeconds;

  @override
  String toString() =>
      'RouteTrace(${points.length} pontos, ${distanceMeters}m, '
      'origem=$originUsed, alvo=$target)';
}
