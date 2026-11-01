import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/checkpoint.dart';
import '../../../tool/e2e/src/relatorio.dart';
import '../../../tool/e2e/src/observador.dart';
import '../../../tool/e2e/src/varredura_saida.dart';

final _t0 = DateTime.utc(2026, 11, 1, 12);

Ciclo _ciclo(
  int n,
  String periodo, {
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
    periodo: periodo,
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

Periodo _periodo(
  String numero, {
  EstadoPeriodo estado = EstadoPeriodo.concluido,
  String? motivo,
  List<String>? telas,
  DateTime? inicio,
}) => Periodo(
  periodo: numero,
  metaValidos: 30,
  tetoExecutados: 40,
  orcamentoMs: const Duration(hours: 3).inMilliseconds,
  tempoAtivoMs: const Duration(hours: 2).inMilliseconds,
  execucoes: [
    {
      'inicio_utc': (inicio ?? _t0).toIso8601String(),
      'fim_utc': (inicio ?? _t0)
          .add(const Duration(hours: 2))
          .toIso8601String(),
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

DadosPeriodo _dados(
  String numero,
  List<Ciclo> ciclos, {
  Periodo? periodo,
  List<EventoObservado>? eventos,
}) => DadosPeriodo(
  periodo: periodo ?? _periodo(numero),
  ciclos: ciclos,
  eventos: eventos ?? const [],
);

List<Ciclo> _sucessos(String periodo, int n, {int desde = 1}) => [
  for (var i = desde; i < desde + n; i++) _ciclo(i, periodo),
];

void main() {
  test('veredito pelos limites do spec: 0, 1, 3 e 4 falhas', () {
    expect(veredito(0), 'ATENDIDO');
    expect(veredito(1), 'PARCIALMENTE ATENDIDO');
    expect(veredito(3), 'PARCIALMENTE ATENDIDO');
    expect(veredito(4), 'NÃO ATENDIDO');
  });

  test('0 falhas em 60 válidos: ATENDIDO, IC de falha [0; 5,96%], oito seções na ordem', () {
    final r = gerarRelatorio([
      _dados('1', _sucessos('1', 30)),
      _dados('2', _sucessos('2', 30)),
    ]);
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

  test(
    '1 a 3 falhas (sem externas) → PARCIALMENTE ATENDIDO; 4 → NÃO ATENDIDO',
    () {
      List<Ciclo> comFalhas(String per, int falhas) => [
        for (var i = 1; i <= 30; i++)
          i <= falhas
              ? _ciclo(i, per, resultado: 'falha', origem: 'aplicativo')
              : _ciclo(i, per),
      ];
      final tres = gerarRelatorio([
        _dados('1', comFalhas('1', 3)),
        _dados('2', _sucessos('2', 30)),
      ]).markdown;
      expect(tres, contains('**Veredito (total): PARCIALMENTE ATENDIDO**'));

      final quatro = gerarRelatorio([
        _dados('1', comFalhas('1', 2)),
        _dados('2', comFalhas('2', 2)),
      ]).markdown;
      expect(quatro, contains('**Veredito (total): NÃO ATENDIDO**'));
    },
  );

  test('falhas externas não entram no veredito, mas entram na taxa total', () {
    final p1 = [
      _ciclo(
        1,
        '1',
        resultado: 'falha',
        valido: false,
        origem: 'servico_externo',
        servico: 'OpenRouteService',
      ),
      ..._sucessos('1', 30, desde: 2),
    ];
    final md = gerarRelatorio([
      _dados('1', p1),
      _dados('2', _sucessos('2', 30)),
    ]).markdown;

    expect(md, contains('**Veredito (total): ATENDIDO**'));
    // taxa total: 1 falha em 61 concluídos
    expect(md, contains('| **total** | 61 | 1 | 1,64% |'));
    expect(md, contains('| serviço externo — OpenRouteService | 1 |'));
    expect(md, contains('não (reposto)'));
    expect(md, contains('ciclo(s) com falha de serviço externo'));
  });

  test('período único e ensaio: veredito não aplicável', () {
    final unico = gerarRelatorio([_dados('1', _sucessos('1', 30))]).markdown;
    expect(unico, contains('não aplicável (período único)'));
    expect(unico, contains('Período(s) ausente(s) neste relatório: 2'));

    final ens = gerarRelatorio([
      _dados('ensaio', _sucessos('ensaio', 2), periodo: _periodo('ensaio')),
    ]).markdown;
    expect(ens, contains('ENSAIO — não vale para o TCC'));
    expect(ens, contains('não aplicável (ensaio)'));
  });

  test('período parcial é dito no topo, na seção 1 e na seção 8', () {
    final md = gerarRelatorio([
      _dados(
        '1',
        _sucessos('1', 10),
        periodo: _periodo(
          '1',
          estado: EstadoPeriodo.parcial,
          motivo: 'orcamento',
        ),
      ),
      _dados('2', _sucessos('2', 30)),
    ]).markdown;

    expect(md, contains('RELATÓRIO PARCIAL'));
    expect(md, contains('PARCIAL — orçamento de 3 h atingido'));
    expect(md, contains('10 de 30 ciclos válidos'));
    expect(md, contains('abaixo dos 60 ciclos válidos previstos'));
  });

  test(
    'falhas por origem: indeterminada à parte, lista com etapa e captura',
    () {
      final md = gerarRelatorio([
        _dados('1', [
          _ciclo(
            1,
            '1',
            resultado: 'falha',
            origem: 'aplicativo',
            origemBruta: 'indeterminada',
            capturas: ['capturas/c001-E04-falha-motorista.png'],
          ),
          _ciclo(2, '1', resultado: 'falha', origem: 'relays'),
          _ciclo(3, '1', resultado: 'falha', origem: 'ambiente_teste'),
          _ciclo(
            4,
            '1',
            resultado: 'falha',
            valido: false,
            origem: 'servico_externo',
            servico: 'Photon',
          ),
        ]),
      ]).markdown;

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

  test('latência: mediana e P95 por período e total; relays que entregaram primeiro', () {
    final ciclos = [for (var i = 1; i <= 5; i++) _ciclo(i, '1')];
    final eventos = <EventoObservado>[
      // latência = recebido − fim da ação (100 ms depois do início de 10 s)
      for (var i = 0; i < 5; i++)
        _ev(ciclos[i], 100 + (i + 1) * 100, 'wss://nos.lol', id: 'abcde'[i]),
      _ev(ciclos[0], 900, 'wss://relay.primal.net', id: 'a'),
    ];
    final r = gerarRelatorio([_dados('1', ciclos, eventos: eventos)]);

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
  });

  test('limitações: telas fixas não capturadas e desvios dos ciclos', () {
    final md = gerarRelatorio([
      _dados('1', [
        _ciclo(1, '1', desvios: ['rótulo "OK" diferente no passageiro']),
      ], periodo: _periodo('1', telas: ['solicitacao-enviada'])),
    ]).markdown;

    expect(md, contains('telas fixas não capturadas: orcamento-recebido'));
    expect(
      md,
      contains('Desvio registrado: rótulo "OK" diferente no passageiro'),
    );
    expect(md, contains('aproxima, mas não mede'));
  });

  test('não há critério de aceitação de latência, nem content, nem chave', () {
    final r = gerarRelatorio([_dados('1', _sucessos('1', 3))]);
    expect(r.markdown.toLowerCase(), isNot(contains('aceitação de latência')));
    expect(r.markdown.contains('"content"'), isFalse);
    expect(r.markdown.contains('nsec1'), isFalse);
  });

  test('CSVs: cabeçalhos e uma linha por ciclo e por falha', () {
    final r = gerarRelatorio([
      _dados('1', [
        _ciclo(1, '1'),
        _ciclo(
          2,
          '1',
          resultado: 'falha',
          origem: 'aplicativo',
          capturas: ['a.png', 'b.png'],
        ),
      ]),
    ]);
    final ciclos = r.csvs['ciclos.csv']!.trim().split('\n');
    expect(ciclos.first, startsWith('periodo,ciclo,'));
    expect(ciclos, hasLength(3));
    final falhas = r.csvs['falhas.csv']!.trim().split('\n');
    expect(falhas, hasLength(2));
    expect(falhas.last, contains('a.png;b.png'));
    expect(
      r.csvs.keys,
      containsAll(['ciclos.csv', 'latencias.csv', 'falhas.csv', 'relays.csv']),
    );
  });

  test('lerDadosPeriodo lê o que o roteiro gravou', () {
    final tmp = Directory.systemTemp.createTempSync('rel_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = RepositorioPeriodo(Directory('${tmp.path}/periodo-1'));
    repo.gravarCheckpoint(_periodo('1'));
    repo.acrescentarCiclo(_ciclo(1, '1'));
    File('${tmp.path}/periodo-1/eventos.jsonl')
        .writeAsStringSync('${_evJson()}\n');

    final d = lerDadosPeriodo(Directory('${tmp.path}/periodo-1'));
    expect(d.ciclos, hasLength(1));
    expect(d.eventos.single.kind, 20001);
    expect(gerarRelatorio([d]).markdown, contains('período 1'));
    expect(
      () => lerDadosPeriodo(Directory('${tmp.path}/nao-existe')),
      throwsFormatException,
    );
  });

  test('o relatório gerado passa na varredura de vazamento', () {
    final tmp = Directory.systemTemp.createTempSync('rel_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ciclos = _sucessos('1', 3);
    final r = gerarRelatorio([
      _dados('1', ciclos, eventos: [_ev(ciclos[0], 300, 'wss://nos.lol')]),
    ]);
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
