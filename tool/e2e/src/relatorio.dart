import 'dart:convert';
import 'dart:io';

import 'checkpoint.dart';
import 'config.dart';
import 'estatistica.dart';
import 'latencia.dart';
import 'observador.dart';

/// Relatório do TCC (FR-030 a FR-038): Markdown com as oito seções fixas e CSV,
/// gerado só a partir dos registros do disco. Não contém chave privada,
/// `content`, linha de logcat, chave da ORS nem critério de aceitação de
/// latência.

class DadosExecucao {
  const DadosExecucao({
    required this.execucao,
    required this.ciclos,
    required this.eventos,
  });

  final Execucao execucao;
  final List<Ciclo> ciclos;
  final List<EventoObservado> eventos;
}

class Relatorio {
  const Relatorio(this.markdown, this.csvs);

  final String markdown;

  /// nome do arquivo (relativo a `dados/`) → conteúdo.
  final Map<String, String> csvs;
}

/// Lê a execução gravada: checkpoint, ciclos e eventos.
DadosExecucao lerDadosExecucao(Directory pasta) {
  final repo = RepositorioExecucao(pasta);
  final execucao = repo.lerCheckpoint();
  if (execucao == null) {
    throw FormatException('${pasta.path} não tem checkpoint.json');
  }
  final eventos = <EventoObservado>[];
  final arquivo = File('${pasta.path}/eventos.jsonl');
  if (arquivo.existsSync()) {
    for (final linha in arquivo.readAsLinesSync()) {
      if (linha.trim().isEmpty) continue;
      eventos.add(
        EventoObservado.fromJson(
          Map<String, dynamic>.from(jsonDecode(linha) as Map),
        ),
      );
    }
  }
  return DadosExecucao(
    execucao: execucao,
    ciclos: repo.lerCiclos(),
    eventos: eventos,
  );
}

/// ATENDIDO com 0 falhas; PARCIALMENTE ATENDIDO com 1 a 3; NÃO ATENDIDO com
/// mais de 3 (FR-031).
String veredito(int falhas) {
  if (falhas == 0) return 'ATENDIDO';
  if (falhas <= 3) return 'PARCIALMENTE ATENDIDO';
  return 'NÃO ATENDIDO';
}

String _pct(double v) =>
    '${(v * 100).toStringAsFixed(2).replaceAll('.', ',')}%';
String _ms(double? v) => v == null ? '—' : v.toStringAsFixed(0);
String _csv(Object? v) {
  final s = v?.toString() ?? '';
  return s.contains(RegExp(r'[",\n;]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String _linhaCsv(List<Object?> campos) => campos.map(_csv).join(',');

class _Totais {
  _Totais(Iterable<Ciclo> ciclos) : c = Contadores.de(ciclos);

  final Contadores c;

  /// Ciclos que chegaram ao fim (válidos ou externos), base da taxa total.
  int get concluidos => c.executados - c.interrompidos;
}

String _taxa(int x, int n) => n == 0 ? '—' : _pct(x / n);

String _ic(int x, int n) {
  if (n == 0) return '—';
  final ic = clopperPearson(x, n);
  return '[${_pct(ic.inferior)}; ${_pct(ic.superior)}]';
}

String _icSucesso(int x, int n) {
  if (n == 0) return '—';
  final ic = clopperPearson(x, n);
  return '[${_pct(1 - ic.superior)}; ${_pct(1 - ic.inferior)}]';
}

String _motivo(String? m) => switch (m) {
  'orcamento' => 'orçamento de 12 h atingido',
  'teto_executados' => 'teto de ciclos executados atingido',
  'limite_diario_ors' => 'limite diário da OpenRouteService esgotado',
  'ambiente' => 'falha do ambiente de teste',
  'interrompido' => 'execução interrompida',
  _ => m ?? '—',
};

const _telasFixas = <String>[
  'solicitacao-enviada',
  'orcamento-recebido',
  'motorista-a-caminho',
  'corrida-em-andamento',
  'corrida-encerrada',
  'avaliacao-concluida',
];

/// Gera o relatório de [dados] (a execução, ou um ensaio).
Relatorio gerarRelatorio(DadosExecucao dados, {DateTime? geradoEm}) {
  final agora = (geradoEm ?? DateTime.now()).toUtc();
  final ex = dados.execucao;
  final ensaio = ex.ensaio;
  final totais = _Totais(dados.ciclos);
  final parcial = ex.estado != EstadoExecucao.concluido;
  final b = StringBuffer();

  b.writeln(
    '# Relatório — Teste E2E do fluxo completo da corrida (caminho feliz)',
  );
  b.writeln();
  if (ensaio) {
    b.writeln(
      '> **ENSAIO — não vale para o TCC.** Dados de validação do roteiro.',
    );
    b.writeln();
  }
  if (parcial) {
    b.writeln(
      '> **RELATÓRIO PARCIAL.** A execução não terminou com a '
      'meta de ciclos válidos; os motivos estão na seção 1 e na seção 8.',
    );
    b.writeln();
  }

  // 1. Metadados
  b.writeln('## 1. Metadados da execução');
  b.writeln();
  b.writeln('- Relatório gerado em: ${agora.toIso8601String()}');
  b.writeln(
    '- Relays usados (lista padrão completa, simultâneos): '
    '${relaysDoRoteiro.join(', ')}',
  );
  b.writeln(
    '- Ciclos executados: ${totais.c.executados}; válidos: ${totais.c.validos}',
  );
  b.writeln('- Relatório parcial: ${parcial ? 'SIM' : 'não'}');
  b.writeln();
  {
    final p = ex;
    final c = totais.c;
    b.writeln(
      '- Estado: ${switch (p.estado) {
        EstadoExecucao.concluido => 'concluído',
        EstadoExecucao.emAndamento => 'em andamento (não finalizado)',
        EstadoExecucao.parcial => 'PARCIAL — ${_motivo(p.motivoParcial)}',
      }}',
    );
    b.writeln(
      '- Invocações (início → fim): '
      '${[for (final e in p.invocacoes) '${e['inicio_utc']} → ${e['fim_utc'] ?? '—'}'].join('; ')}',
    );
    b.writeln(
      '- Tempo ativo: ${p.tempoAtivo.inMinutes} min de ${p.orcamento.inMinutes} min; '
      'meta: ${p.metaValidos} ciclos válidos; teto de ciclos: ${p.tetoExecutados}',
    );
    b.writeln(
      '- Ciclos executados: ${c.executados}; válidos: ${c.validos}; '
      'externos repostos: ${c.externosRepostos}; interrompidos: ${c.interrompidos}',
    );
    final v = p.versoes;
    b.writeln(
      '- Versão do código — motorista: ${v['motorista'] ?? '—'}; '
      'passageiro: ${v['passageiro'] ?? '—'}',
    );
    final a = p.ambiente;
    b.writeln(
      '- Emuladores: motorista ${a['avd_motorista'] ?? '—'} '
      '(${a['serial_motorista'] ?? '—'}), passageiro ${a['avd_passageiro'] ?? '—'} '
      '(${a['serial_passageiro'] ?? '—'}); Android API ${a['api'] ?? '—'}, '
      'ABI ${a['abi'] ?? '—'}',
    );
    if (a['deriva_relogio_s'] != null) {
      b.writeln(
        '- Deriva de relógio dos emuladores em relação ao hospedeiro (s): '
        '${a['deriva_relogio_s']}',
      );
    }
    b.writeln();
  }
  const l = Limites();
  b.writeln(
    'Limites de tempo usados (limites **escolhidos, não medidos**): '
    'elemento local ${l.elementoLocal.inSeconds} s; busca Photon '
    '${l.buscaPhoton.inSeconds} s; efeito remoto ${l.efeitoRemoto.inSeconds} s; '
    'rota ${l.rota.inSeconds} s; posicionamento ${l.posicionamento.inSeconds} s; '
    'etapa ${l.etapa.inSeconds} s (E02 ${l.etapaComBusca.inSeconds} s, '
    'E04 ${l.etapaComRota.inSeconds} s); volta ao estado inicial '
    '${l.voltaAoInicio.inSeconds} s; ciclo ${l.ciclo.inMinutes} min; '
    'execução ${l.execucao.inHours} h.',
  );
  b.writeln();

  // 2. Critério de sucesso
  b.writeln('## 2. Resultado do critério de sucesso');
  b.writeln();
  b.writeln(
    'Taxa de falha calculada **sem** as falhas atribuídas a serviços '
    'externos; n = ciclos válidos. ATENDIDO com 0 falhas; PARCIALMENTE ATENDIDO '
    'com 1 a 3; NÃO ATENDIDO com mais de 3. O veredito é dado uma vez, sobre o '
    'total da execução.',
  );
  b.writeln();
  b.writeln('| Escopo | n (válidos) | Falhas (sem externas) | Taxa de falha |');
  b.writeln('|--------|-------------|-----------------------|---------------|');
  b.writeln(
    '| **total** | ${totais.c.validos} | ${totais.c.falhasValidas} | '
    '${_taxa(totais.c.falhasValidas, totais.c.validos)} |',
  );
  b.writeln();
  if (!ensaio) {
    b.writeln(
      '**Veredito (total): ${veredito(totais.c.falhasValidas)}** '
      '(n = ${totais.c.validos}${totais.c.validos < ex.metaValidos ? ', abaixo dos ${ex.metaValidos} ciclos válidos previstos' : ''}).',
    );
  } else {
    b.writeln(
      '**Veredito: não aplicável (ensaio).** '
      'As contagens acima são informativas.',
    );
  }
  b.writeln();

  // 3. Taxa de falha total
  b.writeln('## 3. Taxa de falha total (inclui serviços externos)');
  b.writeln();
  b.writeln(
    'Apenas informativa, **sem critério**. Base: ciclos concluídos '
    '(válidos mais externos repostos), sem os interrompidos.',
  );
  b.writeln();
  b.writeln(
    '| Escopo | Ciclos concluídos | Falhas (todas) | Taxa de falha total |',
  );
  b.writeln(
    '|--------|-------------------|----------------|---------------------|',
  );
  b.writeln(
    '| **total** | ${totais.concluidos} | ${totais.c.falhasTotais} | '
    '${_taxa(totais.c.falhasTotais, totais.concluidos)} |',
  );
  b.writeln();

  // 4. IC
  b.writeln(
    '## 4. Taxas de sucesso e de falha com IC de 95% (Clopper-Pearson, bilateral)',
  );
  b.writeln();
  b.writeln(
    '| Escopo | n | Falhas | Taxa de falha | IC 95% (falha) | Taxa de sucesso | IC 95% (sucesso) |',
  );
  b.writeln(
    '|--------|---|--------|---------------|----------------|-----------------|------------------|',
  );
  void linhaIc(String nome, Contadores c) {
    final n = c.validos, x = c.falhasValidas;
    b.writeln(
      '| $nome | $n | $x | ${_taxa(x, n)} | ${_ic(x, n)} | '
      '${_taxa(n - x, n)} | ${_icSucesso(x, n)} |',
    );
  }

  linhaIc('**total**', totais.c);
  b.writeln();

  // 5. Latência
  b.writeln(
    '## 5. Latência (descritiva: mediana e percentil 95, posto mais próximo)',
  );
  b.writeln();
  b.writeln(
    'Intervalo entre a ação do roteiro no emulador (toque, ou posicionamento '
    'nos tipos 20007 e 20009) e o recebimento do evento pelo observador, relógio '
    'do hospedeiro. A mediana é o percentil 50 pelo mesmo método. Sem IC e sem '
    'limite de aceitação.',
  );
  b.writeln();
  final todasAmostras = <AmostraLatencia>[];
  final desviosLatencia = <String>[];
  for (final c in dados.ciclos) {
    final doCiclo = [
      for (final e in dados.eventos)
        if (!e.recebidoUtc.isBefore(c.inicioUtc) &&
            !e.recebidoUtc.isAfter(c.fimUtc.add(const Duration(seconds: 60))))
          e,
    ];
    final r = calcularLatencias(c, doCiclo);
    todasAmostras.addAll(r.amostras);
    desviosLatencia.addAll(r.desvios);
  }
  b.writeln('| Tipo de evento | n | Mediana (ms) | P95 (ms) |');
  b.writeln('|----------------|---|--------------|----------|');
  for (final r in resumoPorTipo(todasAmostras).entries) {
    b.writeln(
      '| ${r.key} | ${r.value.n} | ${_ms(r.value.mediana)} | ${_ms(r.value.p95)} |',
    );
  }
  b.writeln();

  // 6. Falhas por origem
  b.writeln('## 6. Falhas por origem');
  b.writeln();
  final falhas = [
    for (final c in dados.ciclos)
      if (c.falhou) c,
  ];
  int conta(bool Function(Ciclo) f) => falhas.where(f).length;
  final app = conta((c) => c.origem == 'aplicativo');
  final appIndet = conta(
    (c) => c.origem == 'aplicativo' && c.origemBruta == 'indeterminada',
  );
  b.writeln('| Origem | Falhas |');
  b.writeln('|--------|--------|');
  b.writeln('| aplicativo | $app |');
  b.writeln('| — das quais `origem_bruta = indeterminada` | $appIndet |');
  b.writeln('| relays | ${conta((c) => c.origem == 'relays')} |');
  b.writeln(
    '| serviço externo — Photon | ${conta((c) => c.servicoExterno == 'Photon')} |',
  );
  b.writeln(
    '| serviço externo — OpenFreeMap | ${conta((c) => c.servicoExterno == 'OpenFreeMap')} |',
  );
  b.writeln(
    '| serviço externo — OpenRouteService | ${conta((c) => c.servicoExterno == 'OpenRouteService')} |',
  );
  b.writeln(
    '| ambiente de teste | ${conta((c) => c.origem == 'ambiente_teste')} |',
  );
  b.writeln();
  if (falhas.isEmpty) {
    b.writeln('Nenhuma falha registrada.');
  } else {
    b.writeln('| Ciclo | Etapa | Origem | Válido | Captura |');
    b.writeln('|-------|-------|--------|--------|---------|');
    for (final c in falhas) {
      final origem = c.origem == 'servico_externo'
          ? 'serviço externo (${c.servicoExterno})'
          : c.origem == 'aplicativo' && c.origemBruta == 'indeterminada'
          ? 'aplicativo (indeterminada)'
          : c.origem ?? '—';
      final capturas = c.capturas.isEmpty ? '—' : c.capturas.join('; ');
      b.writeln(
        '| ${c.ciclo} | ${c.etapaFalha ?? '—'} | $origem | '
        '${c.valido ? 'sim' : 'não (reposto)'} | $capturas |',
      );
    }
  }
  b.writeln();

  // 7. Relays
  b.writeln('## 7. Comportamento por relay (descritivo)');
  b.writeln();
  b.writeln(
    'Eventos entregues ao observador por relay, e quantos eventos chegaram '
    'primeiro por cada relay. Não é critério.',
  );
  b.writeln();
  final linhasRelay = <List<Object?>>[];
  b.writeln('| Relay | Eventos entregues | Entregou primeiro |');
  b.writeln('|-------|-------------------|-------------------|');
  final entregues = {for (final r in relaysDoRoteiro) r: 0};
  final primeiros = {for (final r in relaysDoRoteiro) r: 0};
  final primeiroPorId = <String, EventoObservado>{};
  for (final e in dados.eventos) {
    entregues.update(e.relay, (v) => v + 1, ifAbsent: () => 1);
    final atual = primeiroPorId[e.id];
    if (atual == null || e.recebidoUtc.isBefore(atual.recebidoUtc)) {
      primeiroPorId[e.id] = e;
    }
  }
  for (final e in primeiroPorId.values) {
    primeiros.update(e.relay, (v) => v + 1, ifAbsent: () => 1);
  }
  for (final r in entregues.keys) {
    b.writeln('| $r | ${entregues[r]} | ${primeiros[r] ?? 0} |');
    linhasRelay.add([r, entregues[r], primeiros[r] ?? 0]);
  }
  b.writeln();

  // 8. Limitações
  b.writeln('## 8. Limitações desta execução');
  b.writeln();
  final lim = <String>[];
  {
    final p = ex;
    final c = totais.c;
    if (p.estado != EstadoExecucao.concluido) {
      lim.add(
        'Execução parcial — ${_motivo(p.motivoParcial)}; '
        '${c.validos} de ${p.metaValidos} ciclos válidos.',
      );
    }
    if (p.invocacoes.length > 1) {
      lim.add(
        'A execução foi retomada ${p.invocacoes.length - 1} vez(es) com '
        '`--retomar` (invocações listadas na seção 1).',
      );
    }
    if (c.externosRepostos > 0) {
      lim.add(
        '${c.externosRepostos} ciclo(s) com falha de serviço '
        'externo, não contados como válidos e repostos por novos ciclos.',
      );
    }
    if (c.interrompidos > 0) {
      lim.add(
        '${c.interrompidos} ciclo(s) interrompido(s) '
        '(orçamento ou parada), nem válidos nem falhas.',
      );
    }
    final faltantes = [
      for (final t in _telasFixas)
        if (!p.telasCapturadas.contains(t)) t,
    ];
    if (faltantes.isNotEmpty) {
      lim.add('Telas fixas não capturadas: ${faltantes.join(', ')}.');
    }
    final omitidas = [
      for (final ci in dados.ciclos)
        for (final x in ci.capturas)
          if (x.contains('omitida')) x,
    ];
    if (omitidas.isNotEmpty) {
      lim.add('${omitidas.length} captura(s) omitida(s) por tela sensível.');
    }
  }
  final desvios = {
    for (final c in dados.ciclos) ...c.desvios,
    ...desviosLatencia,
  };
  for (final x in desvios) {
    lim.add('Desvio registrado: $x');
  }
  lim
    ..add(
      'O observador aproxima, mas não mede, a chegada do evento ao aplicativo '
      'destinatário.',
    )
    ..add(
      'Nos tipos 20007 e 20009 a "ação" é o posicionamento do emulador; a latência '
      'inclui a entrega da posição ao app e o intervalo mínimo de 5 s entre publicações.',
    )
    ..add(
      'Os limites de tempo são escolhidos, não medidos; ajustes e conferências '
      'manuais estão em `desvios.md` da execução.',
    )
    ..add(
      'Falhas sem sinal do próprio app não são atribuídas a serviço externo; '
      'a falha do OpenFreeMap só é atribuível quando o app a sinaliza.',
    );
  for (final x in lim) {
    b.writeln('- $x');
  }
  b.writeln();

  // CSV
  final ciclosCsv = StringBuffer(
    '${_linhaCsv(['ciclo', 'inicio_utc', 'fim_utc', 'duracao_s', 'resultado', 'valido', 'etapa_falha', 'origem', 'origem_bruta', 'servico_externo'])}\n',
  );
  final latCsv = StringBuffer(
    '${_linhaCsv(['ciclo', 'tipo', 'categoria', 'latencia_ms', 'relay'])}\n',
  );
  final falhasCsv = StringBuffer(
    '${_linhaCsv(['ciclo', 'etapa', 'origem', 'origem_bruta', 'servico_externo', 'valido', 'capturas'])}\n',
  );
  final relaysCsv = StringBuffer(
    '${_linhaCsv(['relay', 'eventos_entregues', 'entregou_primeiro'])}\n',
  );
  for (final c in dados.ciclos) {
    ciclosCsv.writeln(
      _linhaCsv([
        c.ciclo,
        c.inicioUtc.toIso8601String(),
        c.fimUtc.toIso8601String(),
        (c.fimUtc.difference(c.inicioUtc).inMilliseconds / 1000)
            .toStringAsFixed(1),
        c.resultado,
        c.valido,
        c.etapaFalha,
        c.origem,
        c.origemBruta,
        c.servicoExterno,
      ]),
    );
    if (c.falhou) {
      falhasCsv.writeln(
        _linhaCsv([
          c.ciclo,
          c.etapaFalha,
          c.origem,
          c.origemBruta,
          c.servicoExterno,
          c.valido,
          c.capturas.join(';'),
        ]),
      );
    }
  }
  for (final a in todasAmostras) {
    latCsv.writeln(
      _linhaCsv([
        a.ciclo,
        a.tipo.rotulo,
        a.tipo.categoria,
        a.latenciaMs.toStringAsFixed(1),
        a.relay,
      ]),
    );
  }
  for (final r in linhasRelay) {
    relaysCsv.writeln(_linhaCsv(r));
  }

  return Relatorio(b.toString(), {
    'ciclos.csv': ciclosCsv.toString(),
    'latencias.csv': latCsv.toString(),
    'falhas.csv': falhasCsv.toString(),
    'relays.csv': relaysCsv.toString(),
  });
}
