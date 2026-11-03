import 'relay_gateway.dart';

/// Log estruturado do fluxo (feature 029, emenda de 2026-11-03).
///
/// Contrato em `specs/029-teste-e2e-fluxo-corrida/contracts/logs.md`. A
/// interface só aceita os campos da tabela do contrato e [FlowLine.format]
/// descarta o que não tem a forma esperada: não há como passar `content`,
/// chave, posição ou raio por aqui (FR-052).
abstract class FlowLog {
  /// Registra uma operação. Nunca lança: falha de log não afeta o fluxo.
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
  });

  static const String ok = 'ok';
  static const String falha = 'falha';
  static const String descartado = 'descartado';
  static const String info = 'info';
}

/// Não registra nada (padrão quando nenhum log é injetado).
class NoFlowLog implements FlowLog {
  const NoFlowLog();

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
  }) {}
}

/// Monta uma linha do log. Função pura, testada com valores plantados.
class FlowLine {
  const FlowLine._();

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _nome = RegExp(r'^[a-z0-9_.:-]{1,40}$');
  static const Set<String> _resultados = {
    FlowLog.ok,
    FlowLog.falha,
    FlowLog.descartado,
    FlowLog.info,
  };
  static const Set<String> _externos = {'photon', 'openfreemap', 'ors'};

  /// Campos fora do formato esperado são omitidos; `comp`, `op` e `res`
  /// inválidos viram `invalido`, para o erro aparecer sem vazar o valor.
  static Map<String, Object?> build({
    required int t,
    required String papel,
    required String exec,
    required String iso,
    required String comp,
    required String op,
    required String res,
    int? kind,
    String? id,
    String? relay,
    String? guid,
    String? motivo,
    String? ext,
    int? n,
  }) {
    String nome(String v) => _nome.hasMatch(v) ? v : 'invalido';
    return {
      't': t,
      'papel': nome(papel),
      'exec': nome(exec),
      'iso': nome(iso),
      'comp': nome(comp),
      'op': nome(op),
      'res': _resultados.contains(res) ? res : 'info',
      if (kind != null && kind >= 0 && kind <= 65535) 'kind': kind,
      if (id != null && _hex64.hasMatch(id)) 'id': id,
      if (relay != null) ...?_relay(relay),
      if (guid != null && _hex64.hasMatch(guid)) 'guid': guid,
      if (motivo != null && _nome.hasMatch(motivo)) 'motivo': motivo,
      if (ext != null && _externos.contains(ext)) 'ext': ext,
      if (n != null && n >= 0) 'n': n,
    };
  }

  /// Só `ws://` ou `wss://` com host, sem usuário, consulta ou fragmento.
  static Map<String, Object?>? _relay(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'ws' || uri.scheme == 'wss')) {
      return null;
    }
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    final limpo =
        '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
    return limpo.length <= 120 ? {'relay': limpo} : null;
  }
}

/// Registro de eventos recebidos: só `kind`, `id` e relay; o `content` e as
/// tags nunca são lidos.
extension FlowLogEventos on FlowLog {
  void eventoRecebido(
    IncomingEvent incoming, {
    required String comp,
    required String op,
    required String res,
    String? motivo,
  }) {
    final payload = incoming.payload;
    final kind = payload['kind'];
    final id = payload['id'];
    registrar(
      comp: comp,
      op: op,
      res: res,
      kind: kind is int ? kind : null,
      id: id is String ? id : null,
      relay: incoming.relayUrl,
      motivo: motivo,
    );
  }
}

/// Classifica a falha de um serviço externo num código curto. O texto do erro
/// é só lido, nunca copiado para o log.
String motivoExterno(Object erro) {
  final texto = erro.toString().toLowerCase();
  if (texto.contains('429')) return 'http429';
  final http = RegExp(r'(?:http|status)\s*(\d{3})').firstMatch(texto);
  if (http != null) return 'http${http.group(1)}';
  if (texto.contains('timeout') || texto.contains('timed out')) {
    return 'timeout';
  }
  if (texto.contains('socket') ||
      texto.contains('host lookup') ||
      texto.contains('connection') ||
      texto.contains('clientexception')) {
    return 'rede';
  }
  return 'erro';
}

/// Falha de um serviço externo (Photon, OpenFreeMap, ORS): é o sinal que o
/// relatório usa para atribuir a falha ao serviço (FR-021a).
extension FlowLogExterno on FlowLog {
  void externoFalhou(String servico, Object erro) => registrar(
    comp: 'externo',
    op: 'externo.falha',
    res: FlowLog.falha,
    ext: servico,
    motivo: motivoExterno(erro),
  );
}
