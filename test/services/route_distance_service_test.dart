import 'dart:convert';

import 'package:driver/domain/geo_distance.dart';
import 'package:driver/domain/route_trace.dart';
import 'package:driver/services/route_distance_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:open_route_service/open_route_service.dart';

/// Dublê de `http.Client`: nenhum teste toca rede real (Princípio II
/// aplicado por analogia).
class _ClienteHttpDeTeste extends http.BaseClient {
  _ClienteHttpDeTeste(this._respostas);

  final Future<http.StreamedResponse> Function(http.BaseRequest) _respostas;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _respostas(request);
}

http.StreamedResponse _respostaJson(String corpo, {int status = 200}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(corpo)),
    status,
    headers: {'content-type': 'application/json'},
  );
}

const _origem = LatLng(-28.9298, -49.4753);
const _destino = LatLng(-28.9350, -49.4800);

const _corpoComRota = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {"summary": {"distance": 812.5, "duration": 120.0}},
      "geometry": {
        "type": "LineString",
        "coordinates": [[-49.4753, -28.9298], [-49.4800, -28.9350]]
      }
    }
  ]
}
''';

void main() {
  fallbackTests();
  test(
    'devolve a distância e a duração do trajeto, da mesma resposta',
    () async {
      final servico = OrsRouteDistanceService(
        client: OpenRouteService(
          apiKey: 'chave-de-teste',
          client: _ClienteHttpDeTeste(
            (_) async => _respostaJson(_corpoComRota),
          ),
        ),
      );

      final estimativa = await servico.estimate(
        origin: _origem,
        destination: _destino,
      );

      expect(estimativa.distanceMeters, 812.5);
      expect(estimativa.durationSeconds, 120.0);
    },
  );

  group('trace (feature 016)', () {
    test('devolve os pontos e a distância do trajeto', () async {
      final servico = OrsRouteDistanceService(
        client: OpenRouteService(
          apiKey: 'chave-de-teste',
          client: _ClienteHttpDeTeste(
            (_) async => _respostaJson(_corpoComRota),
          ),
        ),
      );

      final trajeto = await servico.trace(
        origin: _origem,
        destination: _destino,
      );

      expect(trajeto.points, const [
        LatLng(-28.9298, -49.4753),
        LatLng(-28.9350, -49.4800),
      ]);
      expect(trajeto.distanceMeters, 812.5);
      expect(trajeto.originUsed, _origem);
      expect(trajeto.target, _destino);
    });

    test(
      'a requisição leva só as duas coordenadas, por HTTPS (FR-008)',
      () async {
        http.BaseRequest? enviada;
        final servico = OrsRouteDistanceService(
          client: OpenRouteService(
            apiKey: 'chave-de-teste',
            client: _ClienteHttpDeTeste((requisicao) async {
              enviada = requisicao;
              return _respostaJson(_corpoComRota);
            }),
          ),
        );

        await servico.trace(origin: _origem, destination: _destino);

        final url = enviada!.url;
        expect(url.scheme, 'https');
        expect(url.path, endsWith('/driving-car'));
        // Só a credencial do app (`api_key`, não um identificador do usuário)
        // e as duas coordenadas (longitude,latitude): nenhum outro parâmetro.
        expect(url.queryParameters.keys.toSet(), {'api_key', 'start', 'end'});
        expect(url.queryParameters['start'], '-49.4753,-28.9298');
        expect(url.queryParameters['end'], '-49.48,-28.935');
        expect(enviada, isA<http.Request>());
        expect((enviada! as http.Request).body, isEmpty);
      },
    );

    test('lança RouteDistanceFailure em erro HTTP', () async {
      final servico = OrsRouteDistanceService(
        client: OpenRouteService(
          apiKey: 'chave-de-teste',
          client: _ClienteHttpDeTeste(
            (_) async =>
                _respostaJson('{"error": "limite excedido"}', status: 429),
          ),
        ),
      );

      expect(
        () => servico.trace(origin: _origem, destination: _destino),
        throwsA(isA<RouteDistanceFailure>()),
      );
    });

    test('lança RouteDistanceFailure em resposta malformada', () async {
      final servico = OrsRouteDistanceService(
        client: OpenRouteService(
          apiKey: 'chave-de-teste',
          client: _ClienteHttpDeTeste(
            (_) async => _respostaJson('{"features": []}'),
          ),
        ),
      );

      expect(
        () => servico.trace(origin: _origem, destination: _destino),
        throwsA(isA<RouteDistanceFailure>()),
      );
    });

    test('o decorador repassa o resultado e propaga a falha sem nova tentativa '
        'nem linha reta', () async {
      final trajeto = RouteTrace(
        points: const [_origem, _destino],
        distanceMeters: 500,
        originUsed: _origem,
        target: _destino,
      );
      final ok = _ServicoDeTeste(const [])..resultadoTrace = trajeto;
      final decorado = FallbackRouteDistanceService(
        ok,
        retryDelay: Duration.zero,
      );
      expect(
        await decorado.trace(origin: _origem, destination: _destino),
        same(trajeto),
      );

      final falha = _ServicoDeTeste(const [])
        ..resultadoTrace = Exception('rede');
      final decoradoFalha = FallbackRouteDistanceService(
        falha,
        retryDelay: Duration.zero,
      );
      await expectLater(
        decoradoFalha.trace(origin: _origem, destination: _destino),
        throwsException,
      );
      expect(falha.tracesChamados, 1);
    });
  });

  test('lança RouteDistanceFailure em resposta de erro HTTP', () async {
    final servico = OrsRouteDistanceService(
      client: OpenRouteService(
        apiKey: 'chave-de-teste',
        client: _ClienteHttpDeTeste(
          (_) async =>
              _respostaJson('{"error": "limite excedido"}', status: 429),
        ),
      ),
    );

    expect(
      () => servico.estimate(origin: _origem, destination: _destino),
      throwsA(isA<RouteDistanceFailure>()),
    );
  });

  test('lança RouteDistanceFailure em resposta malformada', () async {
    final servico = OrsRouteDistanceService(
      client: OpenRouteService(
        apiKey: 'chave-de-teste',
        client: _ClienteHttpDeTeste(
          (_) async => _respostaJson('{"features": []}'),
        ),
      ),
    );

    expect(
      () => servico.estimate(origin: _origem, destination: _destino),
      throwsA(isA<RouteDistanceFailure>()),
    );
  });
}

class _ServicoDeTeste implements RouteDistanceService {
  _ServicoDeTeste(this._respostas);

  final List<Object> _respostas; // RouteEstimate ou Exception, em ordem
  var chamadas = 0;

  @override
  Future<RouteEstimate> estimate({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final resposta = _respostas[chamadas++];
    if (resposta is Exception) throw resposta;
    return resposta as RouteEstimate;
  }

  var tracesChamados = 0;
  Object? resultadoTrace;

  @override
  Future<RouteTrace> trace({
    required LatLng origin,
    required LatLng destination,
  }) async {
    tracesChamados++;
    final resultado = resultadoTrace;
    if (resultado is Exception) throw resultado;
    return resultado as RouteTrace;
  }
}

void fallbackTests() {
  const real = RouteEstimate(distanceMeters: 900, durationSeconds: 100);

  group('FallbackRouteDistanceService', () {
    test(
      'devolve o cálculo real, sem retry, quando funciona de primeira',
      () async {
        final interno = _ServicoDeTeste([real]);
        final servico = FallbackRouteDistanceService(
          interno,
          retryDelay: Duration.zero,
        );

        final r = await servico.estimate(
          origin: _origem,
          destination: _destino,
        );

        expect(r.approximate, isFalse);
        expect(r.distanceMeters, 900);
        expect(interno.chamadas, 1);
      },
    );

    test(
      'tenta de novo e usa o cálculo real se uma nova tentativa funciona',
      () async {
        final interno = _ServicoDeTeste([Exception('x'), Exception('y'), real]);
        final servico = FallbackRouteDistanceService(
          interno,
          retryDelay: Duration.zero,
        );

        final r = await servico.estimate(
          origin: _origem,
          destination: _destino,
        );

        expect(r.approximate, isFalse);
        expect(r.durationSeconds, 100);
        expect(interno.chamadas, 3);
      },
    );

    test(
      'só após esgotar as tentativas usa a linha reta, marcada aproximada',
      () async {
        final interno = _ServicoDeTeste([
          Exception('a'),
          Exception('b'),
          Exception('c'),
        ]);
        final servico = FallbackRouteDistanceService(
          interno,
          retryDelay: Duration.zero,
        );

        final r = await servico.estimate(
          origin: _origem,
          destination: _destino,
        );

        expect(interno.chamadas, 3);
        expect(r.approximate, isTrue);
        expect(r.durationSeconds, isNull);
        expect(
          r.distanceMeters,
          closeTo(
            metersBetween(
              _origem.latitude,
              _origem.longitude,
              _destino.latitude,
              _destino.longitude,
            ),
            0.001,
          ),
        );
      },
    );
  });
}
