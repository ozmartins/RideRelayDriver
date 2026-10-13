import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:open_route_service/open_route_service.dart';

import '../domain/geo_distance.dart';
import '../domain/route_trace.dart';
import 'ors_api_key.dart';

/// Resultado de um cálculo de rota real (rodoviária, não linha reta) entre
/// dois pontos — distância e duração, do mesmo `summary` da resposta do
/// serviço de rota (D1 de `specs/009-detalhes-do-orcamento/research.md`).
class RouteEstimate {
  const RouteEstimate({
    required this.distanceMeters,
    this.durationSeconds,
    this.approximate = false,
  });

  final double distanceMeters;

  /// `null` quando [approximate]: a linha reta não tem duração estimável.
  final double? durationSeconds;

  /// `true` quando o cálculo real de rota falhou e [distanceMeters] é a
  /// distância em linha reta (Haversine), que subestima a rota real.
  final bool approximate;
}

/// Cálculo da distância e duração reais de rota entre dois pontos.
///
/// Abstração do projeto (Princípio III): a implementação real consulta a API
/// openrouteservice via `open_route_service` (D1 de
/// `specs/007-receber-solicitacao-corrida/research.md`); os testes usam um
/// dublê. Mais leve que o `RouteService` da feature 007 do passageiro — sem
/// `points`/traçado, que esta modal não usa.
abstract class RouteDistanceService {
  /// Calcula a distância e a duração do trajeto rodoviário entre [origin] e
  /// [destination].
  ///
  /// Lança em qualquer falha — rede, timeout, chave de API ausente/inválida,
  /// limite de requisições excedido, resposta malformada. Quem chama trata
  /// qualquer exceção como "indisponível" (FR-016 da feature 007), sem
  /// distinguir motivos.
  Future<RouteEstimate> estimate({
    required LatLng origin,
    required LatLng destination,
  });

  /// Calcula o trajeto rodoviário — geometria e distância — entre [origin] e
  /// [destination], para traçá-lo no mapa durante a corrida (feature 016).
  ///
  /// Lança [RouteDistanceFailure] em qualquer falha; quem chama a trata como
  /// "rota indisponível" (FR-005 da feature 016).
  Future<RouteTrace> trace({
    required LatLng origin,
    required LatLng destination,
  });
}

/// Implementação real: consulta a API openrouteservice
/// (`https://api.openrouteservice.org`) pelo perfil `driving-car`.
///
/// Único tipo do aplicativo, além do teste deste arquivo, que conhece
/// `package:open_route_service` (Princípio III). A chave de API vem do arquivo de
/// configuração `assets/ors_api_key.txt` (`OrsApiKey`).
class OrsRouteDistanceService implements RouteDistanceService {
  OrsRouteDistanceService({String? apiKey, OpenRouteService? client})
    : _client = client ?? _buildClient(apiKey ?? OrsApiKey.value);

  final OpenRouteService _client;

  // O pacote `open_route_service` 1.2.9 envia a chave só como query param
  // `api_key=`, formato que a API atual do openrouteservice.org rejeita com
  // 401 "Authorization field missing" — exige o header `Authorization` (D7
  // de `specs/007-receber-solicitacao-corrida/research.md`).
  static OpenRouteService _buildClient(String apiKey) => OpenRouteService(
    apiKey: apiKey,
    defaultProfile: ORSProfile.drivingCar,
    client: _AuthorizingHttpClient(apiKey),
  );

  @override
  Future<RouteTrace> trace({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final resposta = await _directions(origin, destination);
      final feature = resposta.features.first;
      final resumo = feature.properties['summary'] as Map<String, dynamic>;
      return RouteTrace(
        points: [
          for (final coordenada in feature.geometry.coordinates.first)
            LatLng(coordenada.latitude, coordenada.longitude),
        ],
        distanceMeters: (resumo['distance'] as num).toDouble(),
        originUsed: origin,
        target: destination,
        durationSeconds: (resumo['duration'] as num?)?.toDouble(),
      );
    } on Object catch (erro) {
      throw RouteDistanceFailure(erro);
    }
  }

  /// Sempre pelo perfil `driving-car`, mesmo quando o `OpenRouteService`
  /// injetado foi montado sem `defaultProfile` (o pacote assume
  /// `foot-walking` nesse caso).
  Future<GeoJsonFeatureCollection> _directions(
    LatLng origin,
    LatLng destination,
  ) => _client.directionsRouteGeoJsonGet(
    profileOverride: ORSProfile.drivingCar,
    startCoordinate: ORSCoordinate(
      latitude: origin.latitude,
      longitude: origin.longitude,
    ),
    endCoordinate: ORSCoordinate(
      latitude: destination.latitude,
      longitude: destination.longitude,
    ),
  );

  @override
  Future<RouteEstimate> estimate({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final resposta = await _directions(origin, destination);
      final resumo =
          resposta.features.first.properties['summary'] as Map<String, dynamic>;
      return RouteEstimate(
        distanceMeters: (resumo['distance'] as num).toDouble(),
        durationSeconds: (resumo['duration'] as num).toDouble(),
      );
    } on Object catch (erro) {
      throw RouteDistanceFailure(erro);
    }
  }
}

/// O cálculo de rota falhou — rede indisponível, timeout, chave de API
/// ausente/inválida, limite de requisições excedido ou resposta malformada
/// do serviço (FR-016 da feature 007).
class RouteDistanceFailure implements Exception {
  const RouteDistanceFailure(this.cause);
  final Object? cause;

  @override
  String toString() => 'Falha no cálculo de distância: $cause';
}

/// Acrescenta o header `Authorization` a toda requisição — workaround do bug
/// de D7 de `specs/007-receber-solicitacao-corrida/research.md`.
class _AuthorizingHttpClient extends http.BaseClient {
  _AuthorizingHttpClient(this._apiKey) : _inner = http.Client();

  final String _apiKey;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = _apiKey;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Decorador que torna o cálculo de rota resiliente: tenta o serviço real
/// até [attempts] vezes (esperando [retryDelay] entre as tentativas) e, só se
/// todas falharem, devolve a distância em linha reta marcada como
/// [RouteEstimate.approximate] — nunca substitui um cálculo real que funcionou.
class FallbackRouteDistanceService implements RouteDistanceService {
  FallbackRouteDistanceService(
    this._inner, {
    this.attempts = 3,
    this.retryDelay = const Duration(milliseconds: 800),
  }) : assert(attempts >= 1);

  final RouteDistanceService _inner;
  final int attempts;
  final Duration retryDelay;

  @override
  Future<RouteEstimate> estimate({
    required LatLng origin,
    required LatLng destination,
  }) async {
    for (var tentativa = 1; tentativa <= attempts; tentativa++) {
      try {
        return await _inner.estimate(origin: origin, destination: destination);
      } on Object {
        if (tentativa < attempts) await Future<void>.delayed(retryDelay);
      }
    }
    return RouteEstimate(
      distanceMeters: metersBetween(
        origin.latitude,
        origin.longitude,
        destination.latitude,
        destination.longitude,
      ),
      approximate: true,
    );
  }

  /// Repasse puro, sem nova tentativa e sem linha reta como substituto
  /// (D1 de `specs/016-rota-no-mapa/research.md`): uma reta não diz ao
  /// motorista por qual via seguir, e tentativas extras consumiriam o
  /// limite gratuito do serviço.
  @override
  Future<RouteTrace> trace({
    required LatLng origin,
    required LatLng destination,
  }) => _inner.trace(origin: origin, destination: destination);
}
