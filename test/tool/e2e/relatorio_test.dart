import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/checkpoint.dart';
import '../../../tool/e2e/src/relatorio.dart';
import '../../../tool/e2e/src/observador.dart';
import '../../../tool/e2e/src/varredura_saida.dart';

final _t0 = DateTime.utc(2026, 11, 1, 12);

Ciclo _ciclo(
  int n, {
  String resultado = 'sucesso',
  bool valido = true,
  String? origem,
  String? origemBruta,
  String? servico,
  List<String> capturas = const [],
  DateTime? inicio,
  List<String> desvios = const [],
}) {
  final i = inicio ?? _t0.add(Duration(minutes: n * 5));
  return Ciclo(
    ciclo: n,
    inicioUtc: i,
    fimUtc: i.add(const Duration(minutes: 3)),
    etapas: [
      Etapa(
        id: 'E02',
        resultado: 'ok',
        inicioUtc: i,
        fimUtc: i.add(const Duration(seconds: 20)),
        limiteMs: 120000,
        acoes: [
          Acao(
            id: 'solicitar',
            tipo: 'toque',
            inicioUtc: i.add(const Duration(seconds: 10)),
            fimUtc: i.add(const Duration(seconds: 10, milliseconds: 100)),
          ),
        ],
      ),
    ],
    resultado: resultado,
    valido: valido,
    etapaFalha: resultado == 'falha' ? 'E04' : null,
    origem: origem,
    origemBruta: origemBruta ?? origem,
    servicoExterno: servico,
    capturas: capturas,
    desvios: desvios,
  );
}

EventoObservado _ev(Ciclo c, int ms, String relay, {String id = 'a'}) =>
    EventoObservado(
      relay: relay,
      kind: 20001,
      id: id * 64,
      createdAt: 0,
      recebidoUtc: c.inicioUtc.add(Duration(seconds: 10, milliseconds: ms)),
      autor: 'passageiro',
      destinatario: null,
    );

Execucao _execucao({
  EstadoExecucao estado = EstadoExecucao.concluido,
  String? motivo,
  List<String>? telas,
  bool ensaio = false,
  int invocacoes = 1,
}) => Execucao(
  ensaio: ensaio,
  metaValidos: 60,
  tetoExecutados: 80,
  orcamentoMs: const Duration(hours: 12).inMilliseconds,
  tempoAtivoMs: const Duration(hours: 5).inMilliseconds,
  invocacoes: [
    for (var i = 0; i < invocacoes; i++)
      {
        'inicio_utc': _t0.add(Duration(days: i)).toIso8601String(),
        'fim_utc': _t0.add(Duration(days: i, hours: 2)).toIso8601String(),
        'motivo_parada': motivo ?? 'meta_atingida',
      },
  ],
  motoristaPub: 'a' * 64,
  passageiroPub: 'b' * 64,
  estado: estado,
  motivoParcial: motivo,
  versoes: {
    'motorista': {'commit': 'c' * 40, 'alteracoes_locais': false},
    'passageiro': {'commit': 'd' * 40, 'alteracoes_locais': false},
  },
  ambiente: {
    'avd_motorista': 'Pixel_6_API34_1',
    'avd_passageiro': 'Pixel_6_API34_2',
    'api': '34',
    'abi': 'x86_64',
  },
  telasCapturadas:
      telas ??
      const [
        'solicitacao-enviada',
        'orcamento-recebido',
        'motorista-a-caminho',
        'corrida-em-andamento',
        'corrida-encerrada',
        'avaliacao-concluida',
      ],
);

DadosExecucao _dados(
  List<Ciclo> ciclos, {
  Execucao? execucao,
  List<EventoObservado>? eventos,
}) => DadosExecucao(
  execucao: execucao ?? _execucao(),
  ciclos: ciclos,
  eventos: eventos ?? const [],
);

List<Ciclo> _sucessos(int n, {int desde = 1}) => [
  for (var i = desde; i < desde + n; i++) _ciclo(i),
];

void main() {
  test('veredito pelos limites do spec: 0, 1, 3 e 4 falhas', () {
    expect(veredito(0), 'ATENDIDO');
    expect(veredito(1), 'PARCIALMENTE ATENDIDO');
    expect(veredito(3), 'PARCIALMENTE ATENDIDO');
    expect(veredito(4), 'NÃO ATENDIDO');
  });

  test('0 falhas em 60 válidos: ATENDIDO, IC de falha [0; 5,96%], oito seções na ordem', () {
    final r = gerarRelatorio(_dados(_sucessos(60)));
    final md = r.markdown;

    expect(md, contains('**Veredito (total): ATENDIDO**'));
    expect(md, contains('[0,00%; 5,96%]'));
    expect(md, contains('[94,04%; 100,00%]'));
    final posicoes = [
      for (var i = 1; i <= 8; i++) md.indexOf(RegExp('\n## $i\\. ')),
    ];
    expect(posicoes.every((p) => p >= 0), isTrue);
    expect([...posicoes]..sort(), posicoes);
    expect(md, isNot(contains('RELATÓRIO PARCIAL')));
  });

  test('o relatório não tem recorte por período', () {
    final md = gerarRelatorio(_dados(_sucessos(60))).markdown;
    expect(md.toLowerCase(), isNot(contains('período')));
    expect(md, isNot(contains('dois períodos')));
  });

  test(
    '1 a 3 falhas (sem externas) → PARCIALMENTE ATENDIDO; 4 → NÃO ATENDIDO',
    () {
      List<Ciclo> comFalhas(int falhas) => [
        for (var i = 1; i <= 60; i++)
          i <= falhas
              ? _ciclo(i, resultado: 'falha', origem: 'aplicativo')
              : _ciclo(i),
      ];
      expect(
        gerarRelatorio(_dados(comFalhas(1))).markdown,
        contains('**Veredito (total): PARCIALMENTE ATENDIDO**'),
      );
      expect(
        gerarRelatorio(_dados(comFalhas(3))).markdown,
        contains('**Veredito (total): PARCIALMENTE ATENDIDO**'),
      );
      expect(
        gerarRelatorio(_dados(comFalhas(4))).markdown,
        contains('**Veredito (total): NÃO ATENDIDO**'),
      );
    },
  );

  test('falhas externas não entram no veredito, mas entram na taxa total', () {
    final ciclos = [
      _ciclo(
        1,
        resultado: 'falha',
        valido: false,
        origem: 'servico_externo',
        servico: 'OpenRouteService',
      ),
      ..._sucessos(60, desde: 2),
    ];
    final md = gerarRelatorio(_dados(ciclos)).markdown;

    expect(md, contains('**Veredito (total): ATENDIDO**'));
    // taxa total: 1 falha em 61 concluídos
    expect(md, contains('| **total** | 61 | 1 | 1,64% |'));
    expect(md, contains('| serviço externo — OpenRouteService | 1 |'));
    expect(md, contains('não (reposto)'));
    expect(md, contains('ciclo(s) com falha de serviço externo'));
  });

  test(
    'ensaio: veredito não aplicável e rótulo de que não vale para o TCC',
    () {
      final ens = gerarRelatorio(
        _dados(_sucessos(2), execucao: _execucao(ensaio: true)),
      ).markdown;
      expect(ens, contains('ENSAIO — não vale para o TCC'));
      expect(ens, contains('não aplicável (ensaio)'));
    },
  );

  test('execução parcial é dita no topo, na seção 1 e na seção 8', () {
    final md = gerarRelatorio(
      _dados(
        _sucessos(10),
        execucao: _execucao(
          estado: EstadoExecucao.parcial,
          motivo: 'orcamento',
        ),
      ),
    ).markdown;

    expect(md, contains('RELATÓRIO PARCIAL'));
    expect(md, contains('PARCIAL — orçamento de 12 h atingido'));
    expect(md, contains('10 de 60 ciclos válidos'));
    expect(md, contains('abaixo dos 60 ciclos válidos previstos'));
  });

  test('retomadas são declaradas nas limitações', () {
    final md = gerarRelatorio(
      _dados(_sucessos(60), execucao: _execucao(invocacoes: 3)),
    ).markdown;
    expect(md, contains('retomada 2 vez(es)'));
    final sem = gerarRelatorio(_dados(_sucessos(60))).markdown;
    expect(sem, isNot(contains('retomada')));
  });

  test(
    'falhas por origem: indeterminada à parte, lista com etapa e captura',
    () {
      final md = gerarRelatorio(
        _dados([
          _ciclo(
            1,
            resultado: 'falha',
            origem: 'aplicativo',
            origemBruta: 'indeterminada',
            capturas: ['capturas/c001-E04-falha-motorista.png'],
          ),
          _ciclo(2, resultado: 'falha', origem: 'relays'),
          _ciclo(3, resultado: 'falha', origem: 'ambiente_teste'),
          _ciclo(
            4,
            resultado: 'falha',
            valido: false,
            origem: 'servico_externo',
            servico: 'Photon',
          ),
        ]),
      ).markdown;

      expect(md, contains('| aplicativo | 1 |'));
      expect(
        md,
        contains('| — das quais `origem_bruta = indeterminada` | 1 |'),
      );
      expect(md, contains('| relays | 1 |'));
      expect(md, contains('| ambiente de teste | 1 |'));
      expect(md, contains('| serviço externo — Photon | 1 |'));
      expect(md, contains('aplicativo (indeterminada)'));
      expect(md, contains('capturas/c001-E04-falha-motorista.png'));
    },
  );

  test(
    'latência: mediana e P95 sobre o total; relays que entregaram primeiro',
    () {
      final ciclos = [for (var i = 1; i <= 5; i++) _ciclo(i)];
      final eventos = <EventoObservado>[
        // latência = recebido − fim da ação (100 ms depois do início de 10 s)
        for (var i = 0; i < 5; i++)
          _ev(ciclos[i], 100 + (i + 1) * 100, 'wss://nos.lol', id: 'abcde'[i]),
        _ev(ciclos[0], 900, 'wss://relay.primal.net', id: 'a'),
      ];
      final r = gerarRelatorio(_dados(ciclos, eventos: eventos));

      // amostras: 100, 200, 300, 400, 500 ms → mediana 300, P95 500
      expect(
        r.markdown,
        contains('| 20001 Solicitação de corrida | 5 | 300 | 500 |'),
      );
      expect(r.markdown, contains('| geral (toque) | 5 | 300 | 500 |'));
      expect(r.markdown, contains('| geral (posicionamento) | 0 | — | — |'));
      expect(r.markdown, contains('| wss://nos.lol | 5 | 5 |'));
      expect(r.markdown, contains('| wss://relay.primal.net | 1 | 0 |'));
      expect(r.csvs['latencias.csv']!.split('\n').length, greaterThan(5));
    },
  );

  test('limitações: telas fixas não capturadas e desvios dos ciclos', () {
    final md = gerarRelatorio(
      _dados([
        _ciclo(1, desvios: ['rótulo "OK" diferente no passageiro']),
      ], execucao: _execucao(telas: ['solicitacao-enviada'])),
    ).markdown;

    expect(md, contains('Telas fixas não capturadas: orcamento-recebido'));
    expect(
      md,
      contains('Desvio registrado: rótulo "OK" diferente no passageiro'),
    );
    expect(md, contains('aproxima, mas não mede'));
  });

  test('não há critério de aceitação de latência, nem content, nem chave', () {
    final r = gerarRelatorio(_dados(_sucessos(3)));
    expect(r.markdown.toLowerCase(), isNot(contains('aceitação de latência')));
    expect(r.markdown.contains('"content"'), isFalse);
    expect(r.markdown.contains('nsec1'), isFalse);
  });

  test('CSVs: cabeçalhos e uma linha por ciclo e por falha', () {
    final r = gerarRelatorio(
      _dados([
        _ciclo(1),
        _ciclo(
          2,
          resultado: 'falha',
          origem: 'aplicativo',
          capturas: ['a.png', 'b.png'],
        ),
      ]),
    );
    final ciclos = r.csvs['ciclos.csv']!.trim().split('\n');
    expect(ciclos.first, startsWith('ciclo,'));
    expect(ciclos.first, isNot(contains('periodo')));
    expect(ciclos, hasLength(3));
    final falhas = r.csvs['falhas.csv']!.trim().split('\n');
    expect(falhas, hasLength(2));
    expect(falhas.last, contains('a.png;b.png'));
    expect(
      r.csvs.keys,
      containsAll(['ciclos.csv', 'latencias.csv', 'falhas.csv', 'relays.csv']),
    );
  });

  test('lerDadosExecucao lê o que o roteiro gravou', () {
    final tmp = Directory.systemTemp.createTempSync('rel_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final pasta = Directory('${tmp.path}/execucao');
    final repo = RepositorioExecucao(pasta);
    repo.gravarCheckpoint(_execucao());
    repo.acrescentarCiclo(_ciclo(1));
    File('${pasta.path}/eventos.jsonl').writeAsStringSync('${_evJson()}\n');

    final d = lerDadosExecucao(pasta);
    expect(d.ciclos, hasLength(1));
    expect(d.eventos.single.kind, 20001);
    expect(gerarRelatorio(d).markdown, contains('Estado: concluído'));
    expect(
      () => lerDadosExecucao(Directory('${tmp.path}/nao-existe')),
      throwsFormatException,
    );
  });

  test('checkpoint do formato com períodos é recusado', () {
    final tmp = Directory.systemTemp.createTempSync('rel_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = RepositorioExecucao(Directory(tmp.path));
    repo.gravarCheckpoint(_execucao());
    final arquivo = File('${tmp.path}/checkpoint.json');
    final antigo = arquivo.readAsStringSync().replaceFirst(
      '"ensaio": false,',
      '"periodo": "1",',
    );
    arquivo.writeAsStringSync(antigo);
    expect(repo.lerCheckpoint, throwsFormatException);
  });

  test('o relatório gerado passa na varredura de vazamento', () {
    final tmp = Directory.systemTemp.createTempSync('rel_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ciclos = _sucessos(3);
    final r = gerarRelatorio(
      _dados(ciclos, eventos: [_ev(ciclos[0], 300, 'wss://nos.lol')]),
    );
    File('${tmp.path}/relatorio.md').writeAsStringSync(r.markdown);
    for (final e in r.csvs.entries) {
      File('${tmp.path}/${e.key}').writeAsStringSync(e.value);
    }
    expect(varrerSaida(tmp), isEmpty);
  });
}

String _evJson() =>
    '{"relay":"wss://nos.lol","kind":20001,"id":"${'a' * 64}","created_at":0,'
    '"recebido_utc":"2026-11-01T12:00:10.000Z","autor":"passageiro","destinatario":null,"ciclo":1}';
