import '../e2e/src/estatistica.dart';
import 'analise.dart';

String _pct(double v) =>
    '${(v * 100).toStringAsFixed(2).replaceAll('.', ',')}%';
String _taxa(int x, int n) => n == 0 ? '—' : _pct(x / n);
String _ms(double? v) => v == null ? '—' : v.toStringAsFixed(0);
String _csv(Object? v) {
  final s = v?.toString() ?? '';
  return s.contains(RegExp(r'[",\n;]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String _linhaCsv(List<Object?> c) => c.map(_csv).join(',');

String veredito(int falhas) => falhas == 0
    ? 'ATENDIDO'
    : falhas <= 3
    ? 'PARCIALMENTE ATENDIDO'
    : 'NÃO ATENDIDO';

String _ic(int x, int n, {bool sucesso = false}) {
  if (n == 0) return '—';
  final ic = clopperPearson(x, n);
  return sucesso
      ? '[${_pct(1 - ic.superior)}; ${_pct(1 - ic.inferior)}]'
      : '[${_pct(ic.inferior)}; ${_pct(ic.superior)}]';
}

class SaidaLogs {
  SaidaLogs(this.markdown, this.csvs);
  final String markdown;

  /// nome do arquivo → conteúdo
  final Map<String, String> csvs;
}

/// Relatório do TCC a partir dos logs (FR-058). Mesmas oito seções e mesmos
/// critérios de `relatorio.dart`; a fonte é o log dos aplicativos.
SaidaLogs gerarRelatorioLogs(
  Analise a, {
  int meta = 60,
  DateTime? geradoEm,
  int linhasInvalidas = 0,
}) {
  final agora = (geradoEm ?? DateTime.now()).toUtc();
  final validos = a.validos, falhas = a.falhas;
  final parcial = validos < meta;
  final b = StringBuffer();

  b.writeln('# Relatório — fluxo completo da corrida (execução manual, logs)');
  b.writeln();
  if (parcial) {
    b.writeln(
      '> **RELATÓRIO PARCIAL.** $validos ciclos válidos de $meta previstos.',
    );
    b.writeln();
  }

  b.writeln('## 1. Metadados');
  b.writeln();
  b.writeln('- Relatório gerado em: ${agora.toIso8601String()}');
  b.writeln(
    '- Fontes: motorista ${a.temMotorista ? 'sim' : 'NÃO'}; '
    'passageiro ${a.temPassageiro ? 'sim' : 'NÃO'}',
  );
  b.writeln('- Execuções (`exec`) nos logs: ${a.execs.join(', ')}');
  b.writeln('- Linhas de log ignoradas por formato inválido: $linhasInvalidas');
  b.writeln(
    '- Ciclos detectados: ${a.ciclos.length}; válidos: $validos; '
    'externos (não contam): ${a.externos}',
  );
  b.writeln('- Solicitações do passageiro registradas: ${a.solicitacoes}');
  b.writeln('- Relatório parcial: ${parcial ? 'SIM' : 'não'}');
  b.writeln();

  b.writeln('## 2. Resultado do critério de sucesso');
  b.writeln();
  b.writeln(
    'n = ciclos válidos ($validos); falhas, sem as atribuídas a serviço '
    'externo: $falhas. ATENDIDO com 0 falhas; PARCIALMENTE ATENDIDO com 1 a 3; '
    'NÃO ATENDIDO com mais de 3.',
  );
  b.writeln();
  b.writeln('**Veredito: ${veredito(falhas)}**');
  b.writeln();

  final concluidos = a.ciclos.length;
  b.writeln('## 3. Taxa de falha total (inclui externas) — informativo');
  b.writeln();
  b.writeln(
    '${a.ciclos.where((c) => !c.sucesso).length} de $concluidos ciclos: '
    '${_taxa(a.ciclos.where((c) => !c.sucesso).length, concluidos)}',
  );
  b.writeln();

  b.writeln('## 4. Taxas com intervalo de Clopper-Pearson (95%, bilateral)');
  b.writeln();
  b.writeln('| Medida | Valor | IC 95% |');
  b.writeln('|---|---|---|');
  b.writeln(
    '| Falha | ${_taxa(falhas, validos)} ($falhas/$validos) | '
    '${_ic(falhas, validos)} |',
  );
  b.writeln(
    '| Sucesso | ${_taxa(validos - falhas, validos)} '
    '(${validos - falhas}/$validos) | '
    '${_ic(falhas, validos, sucesso: true)} |',
  );
  b.writeln();

  b.writeln('## 5. Latência entre aplicativos (ms)');
  b.writeln();
  b.writeln(
    'Método: instante da linha `evento.publicou` de um app menos o da primeira '
    'linha `evento.recebeu` do **outro** app com o mesmo `id`. Eco do próprio '
    'evento não conta. Latência negativa (relógios) é descartada e contada; '
    'evento sem recepção não gera amostra.',
  );
  b.writeln();
  final porTipo = <String, List<int>>{};
  for (final s in a.latencias) {
    porTipo.putIfAbsent(s.tipo, () => []).add(s.ms);
  }
  b.writeln('| Tipo (kind remetente→receptor) | n | Mediana | P95 |');
  b.writeln('|---|---|---|---|');
  for (final t in porTipo.keys.toList()..sort()) {
    final v = porTipo[t]!;
    b.writeln(
      '| $t | ${v.length} | ${_ms(mediana(v))} | ${_ms(postoMaisProximo(v, 95))} |',
    );
  }
  final todas = [for (final s in a.latencias) s.ms];
  b.writeln(
    '| **geral** | ${todas.length} | ${_ms(mediana(todas))} | '
    '${_ms(postoMaisProximo(todas, 95))} |',
  );
  b.writeln();
  b.writeln(
    'Amostras descartadas por latência negativa: '
    '${a.latenciasDescartadas}.',
  );
  b.writeln();

  b.writeln('## 6. Falhas por origem');
  b.writeln();
  final falhosTodos = a.ciclos.where((c) => !c.sucesso).toList();
  int conta(bool Function(CicloLog) f) => falhosTodos.where(f).length;
  b.writeln(
    '- aplicativo: ${conta((c) => c.origem == 'aplicativo')} '
    '(das quais indeterminadas: '
    '${conta((c) => c.origemBruta == 'indeterminada')})',
  );
  b.writeln('- relays: ${conta((c) => c.origem == 'relays')}');
  b.writeln(
    '- serviço externo: ${conta((c) => c.origem == 'servico_externo')}',
  );
  b.writeln();
  if (falhosTodos.isEmpty) {
    b.writeln('Nenhuma falha.');
  } else {
    b.writeln('| Ciclo | guid | Último estado | Recibos (mot/pax) | Origem |');
    b.writeln('|---|---|---|---|---|');
    for (final c in falhosTodos) {
      b.writeln(
        '| ${c.numero} | `${c.guid.substring(0, 12)}…` | ${c.ultimoEstado} | '
        '${c.reciboMotorista ? 'sim' : 'não'}/'
        '${c.fontePassageiro ? (c.reciboPassageiro ? 'sim' : 'não') : 's/ log'}'
        ' | ${c.origem}'
        '${c.servicoExterno != null ? ' (${c.servicoExterno})' : ''}'
        '${c.origemBruta == 'indeterminada' ? ' [indeterminada]' : ''} |',
      );
    }
  }
  b.writeln();
  final comAnomalia = a.ciclos.where((c) => c.anomalias.isNotEmpty).toList();
  if (comAnomalia.isNotEmpty) {
    b.writeln(
      'Ciclos com kinds fora do caminho feliz (20004/20006/20012/20013): '
      '${[for (final c in comAnomalia) '${c.numero} (${c.anomalias.join(', ')})'].join('; ')}.',
    );
    b.writeln();
  }

  b.writeln('### Chamadas a serviços externos (descritivo)');
  b.writeln();
  if (a.chamadasExternas.isEmpty) {
    b.writeln('Nenhuma `externo.chamada` nos logs.');
  } else {
    b.writeln(
      '| Serviço | Componente | Chamadas | Falhas | Mediana (ms) | P95 (ms) |',
    );
    b.writeln('|---|---|---|---|---|---|');
    for (final k
        in a.chamadasExternas.keys.toList()..sort((x, y) {
          final c = x.$1.compareTo(y.$1);
          return c != 0 ? c : x.$2.compareTo(y.$2);
        })) {
      final v = a.chamadasExternas[k]!;
      final ms = [for (final c in v) c.ms];
      b.writeln(
        '| ${k.$1} | ${k.$2} | ${v.length} | ${v.where((c) => c.falhou).length} '
        '| ${_ms(mediana(ms))} | ${_ms(postoMaisProximo(ms, 95))} |',
      );
    }
  }
  b.writeln();

  b.writeln('## 7. Comportamento por relay (descritivo)');
  b.writeln();
  b.writeln('| Relay | Kind | Entregas | Primeiro a entregar |');
  b.writeln('|---|---|---|---|');
  final chaves = a.entregaPorRelay.keys.toList()
    ..sort((x, y) {
      final c = x.$1.compareTo(y.$1);
      return c != 0 ? c : x.$2.compareTo(y.$2);
    });
  for (final k in chaves) {
    b.writeln(
      '| ${k.$1} | ${k.$2} | ${a.entregaPorRelay[k]} | '
      '${a.primeiroPorRelay[k] ?? 0} |',
    );
  }
  b.writeln();

  b.writeln('## 8. Limitações');
  b.writeln();
  b.writeln(
    '- Execução **manual**; a evidência é o log dos apps, sem observador '
    'independente: o que um app não registrou não existe para o relatório.',
  );
  b.writeln(
    '- Ciclo = corrida que chegou à aceitação no log do motorista; '
    'solicitações que morreram antes (sem orçamento aceito) só aparecem na '
    'contagem de solicitações da seção 1.',
  );
  b.writeln(
    '- A latência entre aplicativos depende da coerência dos relógios dos '
    'aparelhos; amostras negativas foram descartadas '
    '(${a.latenciasDescartadas}).',
  );
  b.writeln(
    '- Falhas sem sinal no log ficam `indeterminada` e contam como '
    'aplicativo (FR-026). Serviço externo só é atribuído quando há '
    '`externo.falha` na janela do ciclo; falha de tile isolado do OpenFreeMap '
    'não é registrada (só a leitura do estilo).',
  );
  if (!a.temPassageiro) {
    b.writeln(
      '- **Sem log do passageiro**: sucesso = recibo do motorista; '
      'latência e recepção do lado do passageiro não são medidas.',
    );
  }
  if (a.semRecepcao.isNotEmpty) {
    b.writeln(
      '- Eventos publicados e nunca vistos pelo outro app, por kind: '
      '${a.semRecepcao.entries.map((e) => '${e.key}: ${e.value}').join('; ')}.',
    );
  }
  if (parcial) {
    b.writeln('- Execução parcial: $validos de $meta ciclos válidos.');
  }

  final csvs = <String, String>{
    'ciclos.csv': [
      _linhaCsv([
        'ciclo',
        'guid',
        'inicio_ms',
        'fim_ms',
        'sucesso',
        'valido',
        'ultimo_estado',
        'recibo_motorista',
        'recibo_passageiro',
        'origem',
        'servico_externo',
        'origem_bruta',
      ]),
      for (final c in a.ciclos)
        _linhaCsv([
          c.numero,
          c.guid,
          c.inicio,
          c.fim,
          c.sucesso,
          c.valido,
          c.ultimoEstado,
          c.reciboMotorista,
          c.fontePassageiro ? c.reciboPassageiro : '',
          c.origem,
          c.servicoExterno,
          c.origemBruta,
        ]),
    ].join('\n'),
    'latencias.csv': [
      _linhaCsv(['tipo', 'kind', 'id', 'latencia_ms', 'relay_primeiro']),
      for (final s in a.latencias)
        _linhaCsv([s.tipo, s.kind, s.id, s.ms, s.relayPrimeiro]),
    ].join('\n'),
    'relays.csv': [
      _linhaCsv(['relay', 'kind', 'entregas', 'primeiro']),
      for (final k in chaves)
        _linhaCsv([
          k.$1,
          k.$2,
          a.entregaPorRelay[k],
          a.primeiroPorRelay[k] ?? 0,
        ]),
    ].join('\n'),
  };
  csvs['externas.csv'] = [
    _linhaCsv([
      'servico',
      'componente',
      'chamadas',
      'falhas',
      'mediana_ms',
      'p95_ms',
    ]),
    for (final e in a.chamadasExternas.entries)
      _linhaCsv([
        e.key.$1,
        e.key.$2,
        e.value.length,
        e.value.where((c) => c.falhou).length,
        mediana([for (final c in e.value) c.ms]),
        postoMaisProximo([for (final c in e.value) c.ms], 95),
      ]),
  ].join('\n');
  return SaidaLogs(b.toString(), csvs);
}
