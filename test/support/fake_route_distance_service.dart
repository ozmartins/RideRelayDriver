import 'dart:async';

import 'package:driver/domain/route_trace.dart';
import 'package:driver/services/route_distance_service.dart';
import 'package:latlong2/latlong.dart';

/// Dublê em memória de `RouteDistanceService`: nenhum teste toca o serviço de
/// rota real (Princípio II aplicado por analogia).
///
/// `estimate()` consome a próxima entrada de [resultados] (padrão 1000 m) —
/// usado pela modal de solicitação (feature 007). `trace()` (feature 016)
/// devolve uma rota de dois pontos (origem → alvo), registra cada chamada em
/// [traceChamadas], falha com [traceErro] quando definido e, quando
/// [traceBloqueio] está definido, só responde depois que ele for completado
/// — para simular uma resposta em voo.
class FakeRouteDistanceService implements RouteDistanceService {
  FakeRouteDistanceService({List<double>? resultados})
    : _resultados = [...?resultados];

  final List<double> _resultados;

  final traceChamadas = <({LatLng origin, LatLng destination})>[];
  Object? traceErro;

  /// Pontos devolvidos por `trace()`; padrão: origem → alvo (2 pontos).
  List<LatLng>? tracePontos;
  Completer<void>? traceBloqueio;

  @override
  Future<RouteEstimate> estimate({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final distancia = _resultados.isEmpty ? 1000.0 : _resultados.removeAt(0);
    return RouteEstimate(distanceMeters: distancia, durationSeconds: 300);
  }

  @override
  Future<RouteTrace> trace({
    required LatLng origin,
    required LatLng destination,
  }) async {
    traceChamadas.add((origin: origin, destination: destination));
    final bloqueio = traceBloqueio;
    if (bloqueio != null) await bloqueio.future;
    final erro = traceErro;
    if (erro != null) throw erro;
    return RouteTrace(
      points: tracePontos ?? [origin, destination],
      distanceMeters: 1000,
      originUsed: origin,
      target: destination,
    );
  }
}
