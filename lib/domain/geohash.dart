import 'dart:math' as math;

/// Precisões (em caracteres) em que o passageiro publica a tag `g` do `20001`
/// (emenda 27 do contrato). O relay compara o valor da tag por igualdade
/// exata, então o motorista só consegue pedir, via `#g`, uma precisão que o
/// evento carrega.
const List<int> kPrecisoesDaTag = [5, 4, 3];

/// Geohash padrão (Niemeyer), em Dart puro: sem dependência de terceiros
/// (R1 de `specs/027-filtro-geografico-solicitacoes/research.md`).
abstract final class Geohash {
  static const String _alfabeto = '0123456789bcdefghjkmnpqrstuvwxyz';
  static const double _kmPorGrau = 111.195;

  static final RegExp _valido = RegExp(r'^[0-9b-hjkmnp-z]{3,5}$');

  /// Geohash de [precisao] caracteres para o ponto. Os bits alternam entre
  /// longitude e latitude, começando pela longitude.
  ///
  /// Lança [ArgumentError] para latitude fora de −90..90, longitude fora de
  /// −180..180 (ou não numéricas) e precisão fora de 1–12.
  static String encode(double lat, double lon, int precisao) {
    if (!(lat >= -90 && lat <= 90)) {
      throw ArgumentError.value(lat, 'lat', 'fora de −90..90');
    }
    if (!(lon >= -180 && lon <= 180)) {
      throw ArgumentError.value(lon, 'lon', 'fora de −180..180');
    }
    if (precisao < 1 || precisao > 12) {
      throw ArgumentError.value(precisao, 'precisao', 'fora de 1–12');
    }

    var minLat = -90.0, maxLat = 90.0, minLon = -180.0, maxLon = 180.0;
    final buffer = StringBuffer();
    var bits = 0, valor = 0;
    var par = true;
    while (buffer.length < precisao) {
      if (par) {
        final meio = (minLon + maxLon) / 2;
        if (lon >= meio) {
          valor = (valor << 1) | 1;
          minLon = meio;
        } else {
          valor <<= 1;
          maxLon = meio;
        }
      } else {
        final meio = (minLat + maxLat) / 2;
        if (lat >= meio) {
          valor = (valor << 1) | 1;
          minLat = meio;
        } else {
          valor <<= 1;
          maxLat = meio;
        }
      }
      par = !par;
      if (++bits == 5) {
        buffer.write(_alfabeto[valor]);
        bits = 0;
        valor = 0;
      }
    }
    return buffer.toString();
  }

  /// Limites geográficos da célula [celula]. Lança [ArgumentError] se ela
  /// tiver caractere fora do alfabeto.
  static ({double minLat, double maxLat, double minLon, double maxLon}) bounds(
    String celula,
  ) {
    var minLat = -90.0, maxLat = 90.0, minLon = -180.0, maxLon = 180.0;
    var par = true;
    for (final c in celula.split('')) {
      final indice = _alfabeto.indexOf(c);
      if (indice < 0) throw ArgumentError.value(celula, 'celula', 'inválida');
      for (var bit = 4; bit >= 0; bit--) {
        final um = (indice >> bit) & 1 == 1;
        if (par) {
          final meio = (minLon + maxLon) / 2;
          um ? minLon = meio : maxLon = meio;
        } else {
          final meio = (minLat + maxLat) / 2;
          um ? minLat = meio : maxLat = meio;
        }
        par = !par;
      }
    }
    return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon);
  }

  /// As vizinhas de [celula], sem ela e sem repetição. A longitude dá a volta
  /// no antimeridiano; não existe vizinha além dos polos (há menos de 8 ali).
  static List<String> neighbors(String celula) {
    final b = bounds(celula);
    final altura = b.maxLat - b.minLat;
    final largura = b.maxLon - b.minLon;
    final centroLat = (b.minLat + b.maxLat) / 2;
    final centroLon = (b.minLon + b.maxLon) / 2;

    final resultado = <String>{};
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final lat = centroLat + dy * altura;
        if (lat < -90 || lat > 90) continue;
        var lon = centroLon + dx * largura;
        if (lon > 180) lon -= 360;
        if (lon < -180) lon += 360;
        final vizinha = encode(lat, lon, celula.length);
        if (vizinha != celula) resultado.add(vizinha);
      }
    }
    return resultado.toList();
  }

  /// [celula] seguida das suas vizinhas: o bloco 3×3 da inscrição.
  static List<String> cellWithNeighbors(String celula) => [
    celula,
    ...neighbors(celula),
  ];

  /// Comprimento 3–5 e só caracteres do alfabeto (minúsculos): o que a tag
  /// `g` do contrato aceita.
  static bool isValid(String valor) => _valido.hasMatch(valor);

  /// Altura da célula de [precisao] caracteres, em km (cálculo, não medição).
  static double cellHeightKm(int precisao) =>
      180 / math.pow(2, (5 * precisao) ~/ 2) * _kmPorGrau;

  /// Largura da célula de [precisao] caracteres na latitude [lat], em km: a
  /// largura no equador, encolhida por `cos(lat)`.
  static double cellWidthKm(int precisao, double lat) =>
      360 /
      math.pow(2, (5 * precisao + 1) ~/ 2) *
      _kmPorGrau *
      math.cos(lat * math.pi / 180);
}
