import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Converte uma coordenada em endereço legível (feature 015).
abstract class ReverseGeocodingService {
  /// Devolve o endereço de [point], ou lança [ReverseGeocodingFailure].
  Future<String> addressOf(LatLng point);
}

/// A geocodificação reversa falhou — rede, timeout, status diferente de 200,
/// resposta malformada ou nenhum endereço para a coordenada.
class ReverseGeocodingFailure implements Exception {
  const ReverseGeocodingFailure(this.cause, {this.transient = false});
  final Object? cause;

  /// Vale tentar de novo: rede, timeout, HTTP 429 ou 5xx.
  final bool transient;

  @override
  String toString() => 'Falha na geocodificação reversa: $cause';
}

/// Implementação sobre a Photon pública (`https://photon.komoot.io/reverse`).
///
/// Ao contrário do passageiro (`GeocodingService.search`), aqui a coordenada
/// enviada é de origem/destino de uma solicitação de terceiro — coberta pela
/// exceção de geocodificação reversa da constituição 2.9.0: HTTPS, só a
/// coordenada na requisição, resposta guardada apenas em memória (cache da
/// sessão, nunca persistido).
class PhotonReverseGeocodingService implements ReverseGeocodingService {
  PhotonReverseGeocodingService({
    http.Client? client,
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 2)],
  }) : _client = client ?? http.Client();

  /// Espera antes de cada retentativa de falha transitória (a Photon pública
  /// limita a taxa; origem e destino são consultados quase juntos).
  final List<Duration> retryDelays;

  static final _baseUri = Uri.parse('https://photon.komoot.io/reverse');
  static const _timeout = Duration(seconds: 5);

  /// A Photon bloqueia com HTTP 403 o `User-Agent` padrão do `package:http`
  /// (mesma descoberta do passageiro, D4 da feature 005 dele).
  static const _userAgent =
      'CorridasMotorista/1.0 (br.ufsc.tcc.caronas.driver; academic '
      'prototype, UFSC)';

  final http.Client _client;
  final _cache = <String, String>{};

  @override
  Future<String> addressOf(LatLng point) async {
    final chave =
        '${point.latitude.toStringAsFixed(5)},'
        '${point.longitude.toStringAsFixed(5)}';
    final emCache = _cache[chave];
    if (emCache != null) return emCache;

    for (var tentativa = 0; ; tentativa++) {
      try {
        return _cache[chave] = await _consultar(point);
      } on ReverseGeocodingFailure catch (falha) {
        if (!falha.transient || tentativa >= retryDelays.length) rethrow;
        await Future<void>.delayed(retryDelays[tentativa]);
      }
    }
  }

  Future<String> _consultar(LatLng point) async {
    try {
      final uri = _baseUri.replace(
        queryParameters: {
          'lat': point.latitude.toString(),
          'lon': point.longitude.toString(),
          'lang': 'default',
          'limit': '1',
        },
      );
      final resposta = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(_timeout);
      final status = resposta.statusCode;
      if (status != 200) {
        throw ReverseGeocodingFailure(
          'HTTP $status',
          transient: status == 429 || status >= 500,
        );
      }
      final json = jsonDecode(utf8.decode(resposta.bodyBytes));
      final features = (json as Map<String, dynamic>)['features'] as List;
      if (features.isEmpty) {
        throw const ReverseGeocodingFailure('nenhum endereço encontrado');
      }
      final endereco = formatar(
        (features.first as Map<String, dynamic>)['properties']
            as Map<String, dynamic>,
      );
      if (endereco.isEmpty) {
        throw const ReverseGeocodingFailure('endereço vazio');
      }
      return endereco;
    } on ReverseGeocodingFailure {
      rethrow;
    } on http.ClientException catch (erro) {
      throw ReverseGeocodingFailure(erro, transient: true);
    } on TimeoutException catch (erro) {
      throw ReverseGeocodingFailure(erro, transient: true);
    } on Object catch (erro) {
      throw ReverseGeocodingFailure(erro);
    }
  }

  /// Mesma composição de `_paraSugestao` do passageiro, sem o país (curto
  /// para caber na modal) e tolerando a ausência de `name` — um ponto sem
  /// nome (casa numa rua) é comum na resposta reversa.
  static String formatar(Map<String, dynamic> propriedades) {
    final partes = <String>[];

    final nome = propriedades['name'] as String?;
    final rua = propriedades['street'] as String?;
    final numero = propriedades['housenumber'] as String?;
    if (nome != null && nome != rua) partes.add(nome);
    if (rua != null) partes.add(numero != null ? '$rua, $numero' : rua);

    final bairro = propriedades['district'] as String?;
    if (bairro != null) partes.add(bairro);

    final cidade = (propriedades['city'] ?? propriedades['county']) as String?;
    if (cidade != null) partes.add(cidade);

    final estado = propriedades['state'] as String?;
    if (estado != null) partes.add(estado);

    return partes.join(', ');
  }
}
