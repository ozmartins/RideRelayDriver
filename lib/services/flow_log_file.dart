import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'flow_log.dart';

/// Identificador da execução manual: `--dart-define=EXEC_ID=...` (FR-056).
const String kExecId = String.fromEnvironment(
  'EXEC_ID',
  defaultValue: 'manual',
);

/// Diretório privado do app para os logs (`<databases>/logs`), sem plugin novo.
Future<String> diretorioDeLogs() async =>
    p.join(await sqflite.getDatabasesPath(), 'logs');

/// [FlowLog] em arquivo JSON Lines, um arquivo por isolate
/// (`fluxo-<iso>.jsonl`), sem escrita concorrente. Ao passar de [maxBytes] o
/// arquivo vira `.1` (o `.1` anterior é perdido e a perda é registrada).
///
/// Toda falha de E/S é absorvida (FR-054).
class FileFlowLog implements FlowLog {
  FileFlowLog({
    required this.papel,
    required this.iso,
    this.exec = kExecId,
    Future<String> Function()? diretorio,
    this.maxBytes = 32 * 1024 * 1024,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _diretorio = diretorio ?? diretorioDeLogs {
    _pronto = _abrir();
  }

  final String papel;
  final String iso;
  final String exec;
  final int maxBytes;
  final DateTime Function() _now;
  final Future<String> Function() _diretorio;

  late final Future<void> _pronto;
  File? _arquivo;
  var _tamanho = 0;
  final List<String> _espera = [];

  /// Termina quando tudo o que foi registrado até agora está no disco.
  Future<void> get gravado => _pronto;

  Future<void> _abrir() async {
    try {
      final dir = Directory(await _diretorio());
      await dir.create(recursive: true);
      final arquivo = File(p.join(dir.path, 'fluxo-$iso.jsonl'));
      _tamanho = await arquivo.exists() ? await arquivo.length() : 0;
      _arquivo = arquivo;
      final pendentes = List<String>.of(_espera);
      _espera.clear();
      pendentes.forEach(_gravar);
    } on Object {
      _espera.clear();
    }
  }

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
    String? erro,
    String? endereco,
    double? lat,
    double? lon,
    double? lat2,
    double? lon2,
    int? ms,
  }) {
    try {
      final linha = jsonEncode(
        FlowLine.build(
          t: _now().toUtc().millisecondsSinceEpoch,
          papel: papel,
          exec: exec,
          iso: iso,
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
          erro: erro,
          endereco: endereco,
          lat: lat,
          lon: lon,
          lat2: lat2,
          lon2: lon2,
          ms: ms,
        ),
      );
      if (_arquivo == null) {
        if (_espera.length < 2000) _espera.add(linha);
        return;
      }
      _gravar(linha);
    } on Object {
      // Absorvida: o log nunca afeta o fluxo.
    }
  }

  void _gravar(String linha) {
    try {
      final arquivo = _arquivo!;
      if (_tamanho > maxBytes) _rotacionar(arquivo);
      final bytes = '$linha\n';
      arquivo.writeAsStringSync(bytes, mode: FileMode.append, flush: true);
      _tamanho += utf8.encode(bytes).length;
    } on Object {
      // Absorvida.
    }
  }

  void _rotacionar(File arquivo) {
    var perdidas = 0;
    final antigo = File('${arquivo.path}.1');
    if (antigo.existsSync()) {
      perdidas = antigo.readAsLinesSync().length;
    }
    arquivo.renameSync(antigo.path);
    _tamanho = 0;
    final linha = jsonEncode(
      FlowLine.build(
        t: _now().toUtc().millisecondsSinceEpoch,
        papel: papel,
        exec: exec,
        iso: iso,
        comp: 'log',
        op: 'log.rotacao',
        res: FlowLog.info,
        n: perdidas,
      ),
    );
    arquivo.writeAsStringSync('$linha\n', mode: FileMode.append, flush: true);
    _tamanho = utf8.encode(linha).length + 1;
  }
}
