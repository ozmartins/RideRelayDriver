import 'dart:convert';

import 'driver_profile.dart';
import 'geo_distance.dart';
import 'geohash.dart';

/// Por que uma solicitação (`kind: 20001`) fica fora da cobertura do motorista.
enum CoverageRefusal { semTagG, foraDasCelulas, origemIlegivel, alemDoRaio }

/// Resultado de [DriverCoverage.evaluateRideRequest]: aceita, ou o motivo.
class CoverageDecision {
  const CoverageDecision.accepted() : refusal = null;
  const CoverageDecision.refused(CoverageRefusal this.refusal);

  final CoverageRefusal? refusal;

  bool get accepted => refusal == null;

  @override
  String toString() => accepted ? 'aceita' : 'recusada($refusal)';
}

/// A cobertura do motorista online (feature 027): a posição em que ele ficou
/// online, o raio de atendimento daquele momento e as 9 células de geohash que
/// cobrem o círculo (emenda 27 do contrato).
///
/// Só existe em memória, de "ficar online" a "ficar offline": nunca é
/// persistida nem publicada em evento (FR-004, FR-005). [evaluateRideRequest]
/// é a **única** implementação da regra de recepção 8; a interface, o
/// `EventFeed` e o serviço em segundo plano a chamam.
class DriverCoverage {
  const DriverCoverage._({
    required this.referenceLat,
    required this.referenceLon,
    required this.radiusKm,
    required this.precision,
    required this.cells,
  });

  /// Cobertura em torno de ([lat], [lon]) com [radiusKm] de raio. Lança
  /// [ArgumentError] para posição fora da faixa ou raio fora de
  /// [kRaioMinKm]–[kRaioMaxKm] (quem chama já validou o cadastro).
  factory DriverCoverage.around({
    required double lat,
    required double lon,
    required int radiusKm,
  }) {
    if (!DriverProfile.isRaioValido(radiusKm)) {
      throw ArgumentError.value(
        radiusKm,
        'radiusKm',
        'fora de $kRaioMinKm–$kRaioMaxKm',
      );
    }
    final precision = precisionFor(radiusKm, lat);
    // `encode` valida lat/lon.
    final centro = Geohash.encode(lat, lon, precision);
    return DriverCoverage._(
      referenceLat: lat,
      referenceLon: lon,
      radiusKm: radiusKm,
      precision: precision,
      cells: List.unmodifiable(Geohash.cellWithNeighbors(centro)),
    );
  }

  /// Corpo da mensagem `ServiceSetCoverage`. Estrito: lança [FormatException]
  /// para campo faltando, tipo errado, posição fora da faixa ou raio fora de
  /// [kRaioMinKm]–[kRaioMaxKm]. `precision` e `cells` são recalculados.
  factory DriverCoverage.fromJson(Object? json) {
    try {
      final mapa = json as Map;
      final lat = mapa['lat'];
      final lon = mapa['lon'];
      final raio = mapa['raio_km'];
      if (lat is! num || lon is! num || raio is! int) {
        throw const FormatException('campo ausente ou de tipo errado');
      }
      return DriverCoverage.around(
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        radiusKm: raio,
      );
    } on FormatException {
      rethrow;
    } on Object catch (erro) {
      throw FormatException('Cobertura malformada: $erro');
    }
  }

  /// Posição em que o motorista ficou online. Dado pessoal: nunca em log,
  /// armazenamento, evento nem notificação.
  final double referenceLat;
  final double referenceLon;

  /// Raio vigente quando ficou online, em km. Mudar o raio no cadastro depois
  /// não altera uma cobertura já criada (FR-006).
  final int radiusKm;

  /// Caracteres do geohash das [cells]: 5, 4 ou 3.
  final int precision;

  /// A célula da referência e as 8 vizinhas (menos perto dos polos), todas de
  /// [precision] caracteres: o `#g` da inscrição.
  final List<String> cells;

  /// A maior precisão de [kPrecisoesDaTag] em que as 9 células cobrem o
  /// círculo de [radiusKm] em torno de um ponto de latitude [lat]; 3 se
  /// nenhuma cobre (latitudes acima de ~49°, fora da região de uso).
  ///
  /// No pior caso a referência encosta numa borda da célula central, e a borda
  /// do bloco 3×3 fica a uma célula de distância; a cobertura garantida é a
  /// menor dimensão da célula, com a largura medida na latitude mais afastada
  /// do equador que o círculo alcança (R3 do research).
  static int precisionFor(int radiusKm, double lat) {
    final longe = (lat.abs() + radiusKm / 111.195).clamp(0.0, 89.0);
    for (final p in kPrecisoesDaTag) {
      final altura = Geohash.cellHeightKm(p);
      final largura = Geohash.cellWidthKm(p, longe);
      final cobertura = altura < largura ? altura : largura;
      if (radiusKm <= cobertura) return p;
    }
    return kPrecisoesDaTag.last;
  }

  /// Se alguma tag `g` bem formada de [tags] é uma das [cells]. Tags `g` mal
  /// formadas, ou de outra precisão, são ignoradas.
  bool matchesCells(List<List<String>> tags) {
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == 'g' && cells.contains(tag[1])) {
        return true;
      }
    }
    return false;
  }

  /// Se o ponto está a até [radiusKm] da referência (Haversine, inclusivo).
  bool withinRadius(double lat, double lon) =>
      metersBetween(referenceLat, referenceLon, lat, lon) <= radiusKm * 1000;

  /// A regra de recepção 8 do contrato: o `20001` só vale se alguma tag `g`
  /// coincide com as [cells] **e** a `origin` do [content] está dentro do
  /// raio. A tag é só pré-filtro; a origem exata vem do [content]. Não lança.
  CoverageDecision evaluateRideRequest({
    required List<List<String>> tags,
    required String content,
  }) {
    final temTagG = tags.any(
      (t) => t.length >= 2 && t[0] == 'g' && Geohash.isValid(t[1]),
    );
    if (!temTagG) {
      return const CoverageDecision.refused(CoverageRefusal.semTagG);
    }
    if (!matchesCells(tags)) {
      return const CoverageDecision.refused(CoverageRefusal.foraDasCelulas);
    }

    final double lat, lon;
    try {
      final origem = (jsonDecode(content) as Map)['origin'] as Map;
      final a = origem['lat'], o = origem['lon'];
      if (a is! num || o is! num) throw const FormatException('origin');
      lat = a.toDouble();
      lon = o.toDouble();
      if (!(lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180)) {
        throw const FormatException('origin fora da faixa');
      }
    } on Object {
      // content é dado, nunca instrução (regra 3 de recepção).
      return const CoverageDecision.refused(CoverageRefusal.origemIlegivel);
    }
    if (!withinRadius(lat, lon)) {
      return const CoverageDecision.refused(CoverageRefusal.alemDoRaio);
    }
    return const CoverageDecision.accepted();
  }

  Map<String, Object> toJson() => {
    'lat': referenceLat,
    'lon': referenceLon,
    'raio_km': radiusKm,
  };

  @override
  bool operator ==(Object other) =>
      other is DriverCoverage &&
      other.referenceLat == referenceLat &&
      other.referenceLon == referenceLon &&
      other.radiusKm == radiusKm;

  @override
  int get hashCode => Object.hash(referenceLat, referenceLon, radiusKm);

  /// Sem a posição: nunca vai para log (dado pessoal).
  @override
  String toString() => 'DriverCoverage(raio: $radiusKm km, p$precision)';
}
