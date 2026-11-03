import 'dart:convert';

import 'package:driver/services/flow_log.dart';

/// [FlowLog] em memória: guarda as linhas já montadas pelo [FlowLine], como o
/// arquivo as gravaria.
class MemoryFlowLog implements FlowLog {
  final List<Map<String, Object?>> linhas = [];

  @override
  void registrar({
    required String comp,
    required String op,
    String res = FlowLog.info,
    int? kind,
    String? id,
    String? relay,
    String? guid,
    String? motivo,
    String? ext,
    int? n,
  }) {
    linhas.add(
      FlowLine.build(
        t: 0,
        papel: 'motorista',
        exec: 'teste',
        iso: 'ui',
        comp: comp,
        op: op,
        res: res,
        kind: kind,
        id: id,
        relay: relay,
        guid: guid,
        motivo: motivo,
        ext: ext,
        n: n,
      ),
    );
  }

  String get texto => linhas.map(jsonEncode).join('\n');

  List<String> get ops => [for (final l in linhas) l['op'] as String];
}
