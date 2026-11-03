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
    String? erro,
    String? endereco,
    double? lat,
    double? lon,
    double? lat2,
    double? lon2,
    int? ms,
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
    String? erro,
    String? endereco,
    double? lat,
    double? lon,
    double? lat2,
    double? lon2,
    int? ms,
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
    String? erro,
    String? endereco,
    double? lat,
    double? lon,
    double? lat2,
    double? lon2,
    int? ms,
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
      if (erro != null && erro.trim().isNotEmpty) 'erro': _texto(erro),
      if (endereco != null && endereco.trim().isNotEmpty)
        'endereco': _texto(endereco),
      if (_lat(lat) && _lon(lon)) ...{'lat': lat, 'lon': lon},
      if (_lat(lat2) && _lon(lon2)) ...{'lat2': lat2, 'lon2': lon2},
      if (ms != null && ms >= 0) 'ms': ms,
    };
  }

  /// Valores que nunca podem aparecer em texto livre do log (por exemplo, a
  /// chave da ORS). Registrados na inicialização do app.
  static final Set<String> segredos = {};

  static final RegExp _credencial = RegExp(
    r'((?:api[_-]?key|authorization|token|secret|nsec)\S*?[=:\s]+)\S+',
    caseSensitive: false,
  );
  static final RegExp _hex64Solto = RegExp(r'\b[0-9a-fA-F]{64}\b');

  /// Texto livre (erro, endereço): uma linha, no máximo 300 caracteres, sem
  /// credenciais, chaves privadas (64 hex / nsec) nem os [segredos].
  static String _texto(String bruto) {
    var t = bruto.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    for (final s in segredos) {
      if (s.length >= 8) t = t.replaceAll(s, '[oculto]');
    }
    t = t.replaceAllMapped(_credencial, (m) => '${m[1]}[oculto]');
    t = t.replaceAll(_hex64Solto, '[oculto]');
    t = t.replaceAll(RegExp(r'nsec1[0-9a-z]+'), '[oculto]');
    return t.length > 300 ? '${t.substring(0, 300)}…' : t;
  }

  static bool _lat(double? v) => v != null && v >= -90 && v <= 90;
  static bool _lon(double? v) => v != null && v >= -180 && v <= 180;

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
/// relatório usa para atribuir a falha ao serviço (FR-021a). Leva o texto do
/// erro e o que foi consultado (endereço, coordenadas), para auditoria manual.
extension FlowLogExterno on FlowLog {
  void externoFalhou(
    String servico,
    Object erro, {
    String? endereco,
    double? lat,
    double? lon,
    double? lat2,
    double? lon2,
    int? ms,
  }) => registrar(
    comp: 'externo',
    op: 'externo.falha',
    res: FlowLog.falha,
    ext: servico,
    motivo: motivoExterno(erro),
    erro: erro.toString(),
    endereco: endereco,
    lat: lat,
    lon: lon,
    lat2: lat2,
    lon2: lon2,
  );
}

/// Toda chamada a um serviço externo (Photon, OpenFreeMap, ORS), com sucesso ou
/// não: `externo.chamada` com a duração em `ms`, o componente que chamou em
/// `comp` (`rota`, `geocodificacao`, `estilo`, `tile`, `sprite`) e o que foi
/// consultado. Em falha acrescenta `externo.falha` e relança.
extension FlowLogChamada on FlowLog {
  /// [falhaDoServico] diz se o erro é falha do serviço; falso = resposta
  /// válida do serviço (por exemplo, "nenhum endereço"), registrada como ok.
  Future<T> chamadaExterna<T>(
    String servico,
    String componente,
    Future<T> Function() chamada, {
    String? endereco,
    double? lat,
    double? lon,
    double? lat2,
    double? lon2,
    int Function(T resultado)? tamanho,
    bool Function(Object erro)? falhaDoServico,
  }) async {
    final cronometro = Stopwatch()..start();
    try {
      final resultado = await chamada();
      registrar(
        comp: componente,
        op: 'externo.chamada',
        res: FlowLog.ok,
        ext: servico,
        ms: cronometro.elapsedMilliseconds,
        n: tamanho?.call(resultado),
        endereco: endereco,
        lat: lat,
        lon: lon,
        lat2: lat2,
        lon2: lon2,
      );
      return resultado;
    } on Object catch (erro) {
      final falhou = falhaDoServico?.call(erro) ?? true;
      registrar(
        comp: componente,
        op: 'externo.chamada',
        res: falhou ? FlowLog.falha : FlowLog.ok,
        ext: servico,
        ms: cronometro.elapsedMilliseconds,
        motivo: falhou ? motivoExterno(erro) : 'sem_resultado',
        erro: erro.toString(),
        endereco: endereco,
        lat: lat,
        lon: lon,
        lat2: lat2,
        lon2: lon2,
      );
      if (falhou) {
        externoFalhou(
          servico,
          erro,
          endereco: endereco,
          lat: lat,
          lon: lon,
          lat2: lat2,
          lon2: lon2,
        );
      }
      rethrow;
    }
  }
}
