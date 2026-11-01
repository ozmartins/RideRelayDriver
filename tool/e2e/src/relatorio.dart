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

class DadosPeriodo {
  const DadosPeriodo({
    required this.periodo,
    required this.ciclos,
    required this.eventos,
  });

  final Periodo periodo;
  final List<Ciclo> ciclos;
  final List<EventoObservado> eventos;
}

class Relatorio {
  const Relatorio(this.markdown, this.csvs);

  final String markdown;

  /// nome do arquivo (relativo a `dados/`) → conteúdo.
  final Map<String, String> csvs;
}

/// Lê um período gravado: checkpoint, ciclos e eventos.
DadosPeriodo lerDadosPeriodo(Directory pasta) {
  final repo = RepositorioPeriodo(pasta);
  final periodo = repo.lerCheckpoint();
  if (periodo == null) {
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
  return DadosPeriodo(
    periodo: periodo,
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
  'orcamento' => 'orçamento de 3 h atingido',
  'teto_executados' => 'teto de ciclos executados atingido',
  'limite_diario_ors' => 'limite diário da OpenRouteService esgotado',
  'ambiente' => 'falha do ambiente de teste',
  'interrompido' => 'execução interrompida',
  _ => m ?? '—',
};

String _nomePeriodo(Periodo p) =>
    p.periodo == 'ensaio' ? 'ensaio' : 'período ${p.periodo}';

const _telasFixas = <String>[
  'solicitacao-enviada',
  'orcamento-recebido',
  'motorista-a-caminho',
  'corrida-em-andamento',
  'corrida-encerrada',
  'avaliacao-concluida',
];

/// Gera o relatório de [dados] (um ou dois períodos, ou um ensaio).
Relatorio gerarRelatorio(List<DadosPeriodo> dados, {DateTime? geradoEm}) {
  final agora = (geradoEm ?? DateTime.now()).toUtc();
  final ensaio = dados.any((d) => d.periodo.periodo == 'ensaio');
  final todosCiclos = [for (final d in dados) ...d.ciclos];
  final totais = _Totais(todosCiclos);
  final periodosReais = {
    for (final d in dados)
      if (d.periodo.periodo != 'ensaio') d.periodo.periodo,
  };
  final parcial = dados.any((d) => d.periodo.estado != EstadoPeriodo.concluido);
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
      '> **RELATÓRIO PARCIAL.** Pelo menos um período não terminou com a '
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
  for (final d in dados) {
    final p = d.periodo;
    final c = Contadores.de(d.ciclos);
    b.writeln('### ${_nomePeriodo(p)}');
    b.writeln();
    b.writeln(
      '- Estado: ${switch (p.estado) {
        EstadoPeriodo.concluido => 'concluído',
        EstadoPeriodo.emAndamento => 'em andamento (não finalizado)',
        EstadoPeriodo.parcial => 'PARCIAL — ${_motivo(p.motivoParcial)}',
      }}',
    );
    b.writeln(
      '- Execuções (início → fim): '
      '${[for (final e in p.execucoes) '${e['inicio_utc']} → ${e['fim_utc'] ?? '—'}'].join('; ')}',
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
    'período ${l.periodo.inHours} h.',
  );
  b.writeln();

  // 2. Critério de sucesso
  b.writeln('## 2. Resultado do critério de sucesso');
  b.writeln();
  b.writeln(
    'Taxa de falha calculada **sem** as falhas atribuídas a serviços '
    'externos; n = ciclos válidos. ATENDIDO com 0 falhas; PARCIALMENTE ATENDIDO '
    'com 1 a 3; NÃO ATENDIDO com mais de 3. O veredito é dado uma vez, sobre o '
    'total dos dois períodos.',
  );
  b.writeln();
  b.writeln('| Escopo | n (válidos) | Falhas (sem externas) | Taxa de falha |');
  b.writeln('|--------|-------------|-----------------------|---------------|');
  for (final d in dados) {
    final c = Contadores.de(d.ciclos);
    b.writeln(
      '| ${_nomePeriodo(d.periodo)} | ${c.validos} | ${c.falhasValidas} | '
      '${_taxa(c.falhasValidas, c.validos)} |',
    );
  }
  b.writeln(
    '| **total** | ${totais.c.validos} | ${totais.c.falhasValidas} | '
    '${_taxa(totais.c.falhasValidas, totais.c.validos)} |',
  );
  b.writeln();
  if (periodosReais.length >= 2 && !ensaio) {
    b.writeln(
      '**Veredito (total): ${veredito(totais.c.falhasValidas)}** '
      '(n = ${totais.c.validos}${totais.c.validos < 60 ? ', abaixo dos 60 ciclos válidos previstos' : ''}).',
    );
  } else {
    b.writeln(
      '**Veredito: não aplicável (${ensaio ? 'ensaio' : 'período único'}).** '
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
  for (final d in dados) {
    final t = _Totais(d.ciclos);
    b.writeln(
      '| ${_nomePeriodo(d.periodo)} | ${t.concluidos} | ${t.c.falhasTotais} | '
      '${_taxa(t.c.falhasTotais, t.concluidos)} |',
    );
  }
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

  for (final d in dados) {
    linhaIc(_nomePeriodo(d.periodo), Contadores.de(d.ciclos));
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
  final amostrasPor = <String, List<AmostraLatencia>>{};
  final desviosLatencia = <String>[];
  for (final d in dados) {
    final amostras = <AmostraLatencia>[];
    for (final c in d.ciclos) {
      final doCiclo = [
        for (final e in d.eventos)
          if (!e.recebidoUtc.isBefore(c.inicioUtc) &&
              !e.recebidoUtc.isAfter(c.fimUtc.add(const Duration(seconds: 60))))
            e,
      ];
      final r = calcularLatencias(c, doCiclo);
      amostras.addAll(r.amostras);
      desviosLatencia.addAll(r.desvios);
    }
    amostrasPor[_nomePeriodo(d.periodo)] = amostras;
  }
  final todasAmostras = [for (final v in amostrasPor.values) ...v];
  final escoposLatencia = <String, List<AmostraLatencia>>{
    ...amostrasPor,
    'total': todasAmostras,
  };
  for (final entrada in escoposLatencia.entries) {
    b.writeln('### ${entrada.key}');
    b.writeln();
    b.writeln('| Tipo de evento | n | Mediana (ms) | P95 (ms) |');
    b.writeln('|----------------|---|--------------|----------|');
    final resumo = resumoPorTipo(entrada.value);
    for (final r in resumo.entries) {
      b.writeln(
        '| ${r.key} | ${r.value.n} | ${_ms(r.value.mediana)} | ${_ms(r.value.p95)} |',
      );
    }
    b.writeln();
  }

  // 6. Falhas por origem
  b.writeln('## 6. Falhas por origem');
  b.writeln();
  final falhas = [
    for (final d in dados)
      for (final c in d.ciclos)
        if (c.falhou) (d.periodo, c),
  ];
  int conta(bool Function(Ciclo) f) => falhas.where((x) => f(x.$2)).length;
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
    b.writeln('| Período | Ciclo | Etapa | Origem | Válido | Captura |');
    b.writeln('|---------|-------|-------|--------|--------|---------|');
    for (final (p, c) in falhas) {
      final origem = c.origem == 'servico_externo'
          ? 'serviço externo (${c.servicoExterno})'
          : c.origem == 'aplicativo' && c.origemBruta == 'indeterminada'
          ? 'aplicativo (indeterminada)'
          : c.origem ?? '—';
      final capturas = c.capturas.isEmpty ? '—' : c.capturas.join('; ');
      b.writeln(
        '| ${_nomePeriodo(p)} | ${c.ciclo} | ${c.etapaFalha ?? '—'} | $origem | '
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
  for (final d in dados) {
    b.writeln('### ${_nomePeriodo(d.periodo)}');
    b.writeln();
    b.writeln('| Relay | Eventos entregues | Entregou primeiro |');
    b.writeln('|-------|-------------------|-------------------|');
    final entregues = {for (final r in relaysDoRoteiro) r: 0};
    final primeiros = {for (final r in relaysDoRoteiro) r: 0};
    final primeiroPorId = <String, EventoObservado>{};
    for (final e in d.eventos) {
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
      linhasRelay.add([d.periodo.periodo, r, entregues[r], primeiros[r] ?? 0]);
    }
    b.writeln();
  }

  // 8. Limitações
  b.writeln('## 8. Limitações desta execução');
  b.writeln();
  final lim = <String>[];
  if (!ensaio && periodosReais.length < 2) {
    final faltam = {'1', '2'}.difference(periodosReais);
    lim.add('Período(s) ausente(s) neste relatório: ${faltam.join(', ')}.');
  }
  for (final d in dados) {
    final p = d.periodo;
    final c = Contadores.de(d.ciclos);
    if (p.estado != EstadoPeriodo.concluido) {
      lim.add(
        '${_nomePeriodo(p)}: parcial — ${_motivo(p.motivoParcial)}; '
        '${c.validos} de ${p.metaValidos} ciclos válidos.',
      );
    }
    if (c.externosRepostos > 0) {
      lim.add(
        '${_nomePeriodo(p)}: ${c.externosRepostos} ciclo(s) com falha de serviço '
        'externo, não contados como válidos e repostos por novos ciclos.',
      );
    }
    if (c.interrompidos > 0) {
      lim.add(
        '${_nomePeriodo(p)}: ${c.interrompidos} ciclo(s) interrompido(s) '
        '(orçamento ou parada), nem válidos nem falhas.',
      );
    }
    final faltantes = [
      for (final t in _telasFixas)
        if (!p.telasCapturadas.contains(t)) t,
    ];
    if (faltantes.isNotEmpty) {
      lim.add(
        '${_nomePeriodo(p)}: telas fixas não capturadas: ${faltantes.join(', ')}.',
      );
    }
    final omitidas = [
      for (final ci in d.ciclos)
        for (final x in ci.capturas)
          if (x.contains('omitida')) x,
    ];
    if (omitidas.isNotEmpty) {
      lim.add(
        '${_nomePeriodo(p)}: ${omitidas.length} captura(s) omitida(s) por tela sensível.',
      );
    }
  }
  final datas = {
    for (final d in dados)
      if (d.periodo.periodo != 'ensaio' && d.periodo.execucoes.isNotEmpty)
        (d.periodo.execucoes.first['inicio_utc'] as String).substring(0, 10),
  };
  if (periodosReais.length >= 2 && datas.length < 2) {
    lim.add(
      'Os dois períodos começaram no mesmo dia, ao contrário do previsto.',
    );
  }
  final desvios = {
    for (final d in dados)
      for (final c in d.ciclos) ...c.desvios,
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
      'manuais estão em `desvios.md` de cada período.',
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
    '${_linhaCsv(['periodo', 'ciclo', 'inicio_utc', 'fim_utc', 'duracao_s', 'resultado', 'valido', 'etapa_falha', 'origem', 'origem_bruta', 'servico_externo'])}\n',
  );
  final latCsv = StringBuffer(
    '${_linhaCsv(['periodo', 'ciclo', 'tipo', 'categoria', 'latencia_ms', 'relay'])}\n',
  );
  final falhasCsv = StringBuffer(
    '${_linhaCsv(['periodo', 'ciclo', 'etapa', 'origem', 'origem_bruta', 'servico_externo', 'valido', 'capturas'])}\n',
  );
  final relaysCsv = StringBuffer(
    '${_linhaCsv(['periodo', 'relay', 'eventos_entregues', 'entregou_primeiro'])}\n',
  );
  for (final d in dados) {
    final per = d.periodo.periodo;
    for (final c in d.ciclos) {
      ciclosCsv.writeln(
        _linhaCsv([
          per,
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
            per,
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
  }
  for (final entrada in amostrasPor.entries) {
    final per = entrada.key.replaceFirst('período ', '');
    for (final a in entrada.value) {
      latCsv.writeln(
        _linhaCsv([
          per,
          a.ciclo,
          a.tipo.rotulo,
          a.tipo.categoria,
          a.latenciaMs.toStringAsFixed(1),
          a.relay,
        ]),
      );
    }
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
