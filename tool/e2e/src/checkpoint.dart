import 'dart:convert';
import 'dart:io';

/// Registros do roteiro e sua persistência (data-model.md). Nada aqui guarda
/// chave privada nem `content` de evento.

String _iso(DateTime d) => d.toUtc().toIso8601String();

class Acao {
  Acao({
    required this.id,
    required this.tipo,
    required this.inicioUtc,
    required this.fimUtc,
  });

  /// Identificador da ação na tabela de latência (ver `latencia.dart`).
  final String id;

  /// `toque` ou `posicionamento`.
  final String tipo;

  /// Instante em que o comando foi disparado.
  final DateTime inicioUtc;

  /// Instante em que o comando retornou (referência da latência).
  final DateTime fimUtc;

  Map<String, Object?> toJson() => {
    'id': id,
    'tipo': tipo,
    'acao_inicio_utc': _iso(inicioUtc),
    'acao_utc': _iso(fimUtc),
  };

  factory Acao.fromJson(Map<String, dynamic> j) => Acao(
    id: j['id'] as String,
    tipo: j['tipo'] as String,
    inicioUtc: DateTime.parse(j['acao_inicio_utc'] as String),
    fimUtc: DateTime.parse(j['acao_utc'] as String),
  );
}

class Etapa {
  Etapa({
    required this.id,
    required this.resultado,
    required this.inicioUtc,
    required this.fimUtc,
    required this.limiteMs,
    this.acoes = const [],
  });

  /// `E01`…`E12` ou `R`.
  final String id;

  /// `ok`, `falha` ou `timeout`.
  final String resultado;
  final DateTime inicioUtc;
  final DateTime fimUtc;
  final int limiteMs;
  final List<Acao> acoes;

  Map<String, Object?> toJson() => {
    'id': id,
    'resultado': resultado,
    'inicio_utc': _iso(inicioUtc),
    'fim_utc': _iso(fimUtc),
    'limite_ms': limiteMs,
    'acoes': [for (final a in acoes) a.toJson()],
  };

  factory Etapa.fromJson(Map<String, dynamic> j) => Etapa(
    id: j['id'] as String,
    resultado: j['resultado'] as String,
    inicioUtc: DateTime.parse(j['inicio_utc'] as String),
    fimUtc: DateTime.parse(j['fim_utc'] as String),
    limiteMs: j['limite_ms'] as int,
    acoes: [
      for (final a in (j['acoes'] as List<dynamic>? ?? const []))
        Acao.fromJson(Map<String, dynamic>.from(a as Map)),
    ],
  );
}

class Ciclo {
  Ciclo({
    required this.ciclo,
    required this.periodo,
    required this.inicioUtc,
    required this.fimUtc,
    required this.etapas,
    required this.resultado,
    required this.valido,
    this.repostoPor,
    this.etapaFalha,
    this.origem,
    this.servicoExterno,
    this.origemBruta,
    this.sinalExterno,
    this.capturas = const [],
    this.anomalias = const [],
    this.desvios = const [],
    this.eventos = const [],
  });

  final int ciclo;

  /// `1`, `2` ou `ensaio`.
  final String periodo;
  final DateTime inicioUtc;
  final DateTime fimUtc;
  final List<Etapa> etapas;

  /// `sucesso`, `falha` ou `interrompido`.
  final String resultado;

  /// Falso para falha externa (reposta) e para ciclo interrompido.
  final bool valido;
  final int? repostoPor;
  final String? etapaFalha;

  /// `aplicativo`, `relays`, `servico_externo` ou `ambiente_teste`.
  final String? origem;

  /// `Photon`, `OpenFreeMap` ou `OpenRouteService`.
  final String? servicoExterno;

  /// `indeterminada` ou igual a [origem] (FR-026).
  final String? origemBruta;

  /// Só a classificação do sinal (`fonte`, `servico`, `http`), nunca a linha.
  final Map<String, Object?>? sinalExterno;
  final List<String> capturas;
  final List<int> anomalias;
  final List<String> desvios;

  /// Ids (hex) dos eventos associados ao ciclo.
  final List<String> eventos;

  bool get falhou => resultado == 'falha';
  bool get externo => origem == 'servico_externo';

  Ciclo copyWith({int? repostoPor}) => Ciclo(
    ciclo: ciclo,
    periodo: periodo,
    inicioUtc: inicioUtc,
    fimUtc: fimUtc,
    etapas: etapas,
    resultado: resultado,
    valido: valido,
    repostoPor: repostoPor ?? this.repostoPor,
    etapaFalha: etapaFalha,
    origem: origem,
    servicoExterno: servicoExterno,
    origemBruta: origemBruta,
    sinalExterno: sinalExterno,
    capturas: capturas,
    anomalias: anomalias,
    desvios: desvios,
    eventos: eventos,
  );

  Map<String, Object?> toJson() => {
    'ciclo': ciclo,
    'periodo': periodo,
    'inicio_utc': _iso(inicioUtc),
    'fim_utc': _iso(fimUtc),
    'etapas': [for (final e in etapas) e.toJson()],
    'resultado': resultado,
    'valido': valido,
    'reposto_por': repostoPor,
    'etapa_falha': etapaFalha,
    'origem': origem,
    'servico_externo': servicoExterno,
    'origem_bruta': origemBruta,
    'sinal_externo': sinalExterno,
    'capturas': capturas,
    'anomalias': anomalias,
    'desvios': desvios,
    'eventos': eventos,
  };

  factory Ciclo.fromJson(Map<String, dynamic> j) => Ciclo(
    ciclo: j['ciclo'] as int,
    periodo: j['periodo'].toString(),
    inicioUtc: DateTime.parse(j['inicio_utc'] as String),
    fimUtc: DateTime.parse(j['fim_utc'] as String),
    etapas: [
      for (final e in (j['etapas'] as List<dynamic>))
        Etapa.fromJson(Map<String, dynamic>.from(e as Map)),
    ],
    resultado: j['resultado'] as String,
    valido: j['valido'] as bool,
    repostoPor: j['reposto_por'] as int?,
    etapaFalha: j['etapa_falha'] as String?,
    origem: j['origem'] as String?,
    servicoExterno: j['servico_externo'] as String?,
    origemBruta: j['origem_bruta'] as String?,
    sinalExterno: j['sinal_externo'] == null
        ? null
        : Map<String, Object?>.from(j['sinal_externo'] as Map),
    capturas: List<String>.from(j['capturas'] as List<dynamic>? ?? const []),
    anomalias: List<int>.from(j['anomalias'] as List<dynamic>? ?? const []),
    desvios: List<String>.from(j['desvios'] as List<dynamic>? ?? const []),
    eventos: List<String>.from(j['eventos'] as List<dynamic>? ?? const []),
  );
}

/// Contadores recalculáveis a partir dos ciclos registrados.
class Contadores {
  const Contadores({
    required this.executados,
    required this.validos,
    required this.falhasValidas,
    required this.falhasTotais,
    required this.externosRepostos,
    required this.interrompidos,
  });

  factory Contadores.de(Iterable<Ciclo> ciclos) {
    var executados = 0, validos = 0, falhasValidas = 0, falhasTotais = 0;
    var externos = 0, interrompidos = 0;
    for (final c in ciclos) {
      executados++;
      if (c.valido) validos++;
      if (c.falhou) {
        falhasTotais++;
        if (c.valido) falhasValidas++;
      }
      if (!c.valido && c.externo) externos++;
      if (c.resultado == 'interrompido') interrompidos++;
    }
    return Contadores(
      executados: executados,
      validos: validos,
      falhasValidas: falhasValidas,
      falhasTotais: falhasTotais,
      externosRepostos: externos,
      interrompidos: interrompidos,
    );
  }

  final int executados;
  final int validos;

  /// Falhas de ciclos válidos (sem as externas): base do critério (FR-031).
  final int falhasValidas;

  /// Falhas incluindo as externas (informativo, FR-032).
  final int falhasTotais;
  final int externosRepostos;
  final int interrompidos;
}

enum EstadoPeriodo { emAndamento, concluido, parcial }

class Periodo {
  Periodo({
    required this.periodo,
    required this.metaValidos,
    required this.tetoExecutados,
    required this.orcamentoMs,
    this.tempoAtivoMs = 0,
    this.execucoes = const [],
    this.motoristaPub = '',
    this.passageiroPub = '',
    this.estado = EstadoPeriodo.emAndamento,
    this.motivoParcial,
    this.versoes = const {},
    this.ambiente = const {},
    this.telasCapturadas = const [],
  });

  /// `1`, `2` ou `ensaio`.
  final String periodo;
  final int metaValidos;
  final int tetoExecutados;
  final int orcamentoMs;
  int tempoAtivoMs;
  List<Map<String, Object?>> execucoes;
  String motoristaPub;
  String passageiroPub;
  EstadoPeriodo estado;

  /// `orcamento`, `teto_executados`, `limite_diario_ors`, `ambiente`,
  /// `interrompido`.
  String? motivoParcial;
  Map<String, Object?> versoes;
  Map<String, Object?> ambiente;

  /// Rótulos das telas fixas já capturadas (FR-027).
  List<String> telasCapturadas;

  Duration get orcamento => Duration(milliseconds: orcamentoMs);
  Duration get tempoAtivo => Duration(milliseconds: tempoAtivoMs);
  Duration get saldoDoOrcamento {
    final saldo = orcamentoMs - tempoAtivoMs;
    return Duration(milliseconds: saldo < 0 ? 0 : saldo);
  }

  Map<String, Object?> toJson() => {
    'periodo': periodo,
    'meta_validos': metaValidos,
    'teto_executados': tetoExecutados,
    'orcamento_ms': orcamentoMs,
    'tempo_ativo_ms': tempoAtivoMs,
    'execucoes': execucoes,
    'identidades': {
      'motorista_pub': motoristaPub,
      'passageiro_pub': passageiroPub,
    },
    'estado': estado.name,
    'motivo_parcial': motivoParcial,
    'versoes': versoes,
    'ambiente': ambiente,
    'telas_capturadas': telasCapturadas,
  };

  factory Periodo.fromJson(Map<String, dynamic> j) {
    final ids = Map<String, dynamic>.from(j['identidades'] as Map);
    return Periodo(
      periodo: j['periodo'].toString(),
      metaValidos: j['meta_validos'] as int,
      tetoExecutados: j['teto_executados'] as int,
      orcamentoMs: j['orcamento_ms'] as int,
      tempoAtivoMs: j['tempo_ativo_ms'] as int? ?? 0,
      execucoes: [
        for (final e in (j['execucoes'] as List<dynamic>? ?? const []))
          Map<String, Object?>.from(e as Map),
      ],
      motoristaPub: ids['motorista_pub'] as String? ?? '',
      passageiroPub: ids['passageiro_pub'] as String? ?? '',
      estado: EstadoPeriodo.values.byName(j['estado'] as String),
      motivoParcial: j['motivo_parcial'] as String?,
      versoes: Map<String, Object?>.from(j['versoes'] as Map? ?? const {}),
      ambiente: Map<String, Object?>.from(j['ambiente'] as Map? ?? const {}),
      telasCapturadas: List<String>.from(
        j['telas_capturadas'] as List<dynamic>? ?? const [],
      ),
    );
  }
}

/// Persistência de um período: `ciclos.jsonl` só-acréscimo e `checkpoint.json`
/// reescrito de forma atômica (arquivo temporário + rename).
class RepositorioPeriodo {
  RepositorioPeriodo(this.pasta);

  final Directory pasta;

  File get _ciclos => File('${pasta.path}/ciclos.jsonl');
  File get _checkpoint => File('${pasta.path}/checkpoint.json');

  bool get existe => _checkpoint.existsSync();

  void garantirPasta() {
    if (!pasta.existsSync()) pasta.createSync(recursive: true);
  }

  /// Ciclos registrados. Linha ilegível lança [FormatException]: a retomada
  /// recusa em vez de inventar ciclos.
  List<Ciclo> lerCiclos() {
    if (!_ciclos.existsSync()) return [];
    return [
      for (final linha in _ciclos.readAsLinesSync())
        if (linha.trim().isNotEmpty)
          Ciclo.fromJson(Map<String, dynamic>.from(jsonDecode(linha) as Map)),
    ];
  }

  void acrescentarCiclo(Ciclo c) {
    garantirPasta();
    _ciclos.writeAsStringSync(
      '${jsonEncode(c.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Periodo? lerCheckpoint() {
    if (!_checkpoint.existsSync()) return null;
    return Periodo.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(_checkpoint.readAsStringSync()) as Map,
      ),
    );
  }

  void gravarCheckpoint(Periodo p) {
    garantirPasta();
    final temporario = File('${_checkpoint.path}.tmp');
    temporario.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(p.toJson()),
      flush: true,
    );
    temporario.renameSync(_checkpoint.path);
  }
}
