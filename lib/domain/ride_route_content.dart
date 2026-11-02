import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// `content` do `kind: 20011` ("Rota da corrida", emenda 13 do contrato):
/// reduz o trajeto a no máximo [maxPoints] pontos e o codifica como
/// `{"points": [[lat, lon], ...]}` (feature 017, `data-model.md`).
///
/// Lógica pura, sem Flutter nem `dart_nostr`.
abstract final class RideRouteContent {
  /// Teto de pontos por evento (D3 de `specs/017-publicar-rota-ao-passageiro/
  /// research.md`): ~23 KB, uma fração do menor `max_message_length` medido
  /// nos relays padrão (131 072 B).
  static const int maxPoints = 1000;

  /// Casas decimais de latitude e longitude no `content` (~1 m).
  static const int decimalPlaces = 5;

  /// Devolve [points] intacto se couber em [maxPoints]; senão, exatamente
  /// [maxPoints] pontos nos índices `round(i · (n − 1) / (maxPoints − 1))` —
  /// o primeiro e o último originais por construção, ordem preservada.
  static List<LatLng> reduce(List<LatLng> points) {
    final n = points.length;
    if (n <= maxPoints) return points;
    return [
      for (var i = 0; i < maxPoints; i++)
        points[(i * (n - 1) / (maxPoints - 1)).round()],
    ];
  }

  /// Codifica o trajeto (depois de [reduce]) com lat/lon arredondados a
  /// [decimalPlaces] casas.
  ///
  /// Lança [ArgumentError] com menos de 2 pontos: sem trajeto não há o que
  /// publicar, e quem chama trata como falha de rota.
  static String encode(List<LatLng> points) {
    if (points.length < 2) {
      throw ArgumentError.value(
        points.length,
        'points',
        'uma rota precisa de ao menos 2 pontos',
      );
    }
    return jsonEncode({
      'points': [
        for (final ponto in reduce(points))
          [_arredondar(ponto.latitude), _arredondar(ponto.longitude)],
      ],
    });
  }

  static double _arredondar(double valor) =>
      double.parse(valor.toStringAsFixed(decimalPlaces));
}
