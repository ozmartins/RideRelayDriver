import 'dart:math' as math;

/// Distância aproximada, em metros, entre dois pontos geográficos (fórmula
/// de Haversine).
///
/// Sem dependência de terceiros — o único uso desta feature é comparar contra
/// o deslocamento mínimo de publicação (FR-008), para o qual a aproximação
/// esférica da Terra é suficiente (mesma ordem de grandeza de precisão já
/// aceita pelos serviços de roteamento usados nas features anteriores).
double metersBetween(double lat1, double lon1, double lat2, double lon2) {
  const raioTerraMetros = 6371000.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return raioTerraMetros * c;
}

/// Menor distância, em metros, de ([lat], [lon]) à polilinha [pontos]
/// (pares `[lat, lon]`); `double.infinity` se a polilinha tem menos de 2
/// pontos.
///
/// Projeção equiretangular local sobre cada segmento: para trajetos urbanos
/// (centenas de metros por segmento) o erro é desprezível frente ao do GPS.
double distanceToPolylineMeters(
  double lat,
  double lon,
  List<({double lat, double lon})> pontos,
) {
  if (pontos.length < 2) return double.infinity;
  const raioTerraMetros = 6371000.0;
  final metrosPorGrauLat = raioTerraMetros * math.pi / 180;
  final metrosPorGrauLon = metrosPorGrauLat * math.cos(_toRadians(lat));

  var menor = double.infinity;
  for (var i = 0; i < pontos.length - 1; i++) {
    final ax = (pontos[i].lon - lon) * metrosPorGrauLon;
    final ay = (pontos[i].lat - lat) * metrosPorGrauLat;
    final bx = (pontos[i + 1].lon - lon) * metrosPorGrauLon;
    final by = (pontos[i + 1].lat - lat) * metrosPorGrauLat;
    final dx = bx - ax;
    final dy = by - ay;
    final comprimento2 = dx * dx + dy * dy;
    // Ponto de P (origem local) mais próximo do segmento AB.
    final t = comprimento2 == 0
        ? 0.0
        : (-(ax * dx + ay * dy) / comprimento2).clamp(0.0, 1.0);
    final px = ax + t * dx;
    final py = ay + t * dy;
    final distancia = math.sqrt(px * px + py * py);
    if (distancia < menor) menor = distancia;
  }
  return menor;
}

double _toRadians(double graus) => graus * math.pi / 180;
