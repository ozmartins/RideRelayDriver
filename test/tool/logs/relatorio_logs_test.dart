import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/logs/analise.dart';
import '../../../tool/logs/linhas.dart';
import '../../../tool/logs/relatorio_logs.dart';

String h(String c) => c * 64;

Linha l(
  int t,
  String papel,
  String op, {
  String res = 'info',
  int? kind,
  String? id,
  String? relay,
  String? guid,
  String? motivo,
  String? ext,
}) => Linha.tentar(
  jsonEncode({
    't': t,
    'papel': papel,
    'exec': 'e1',
    'iso': 'servico',
    'comp': op.startsWith('relay.') ? 'relay' : 'feed',
    'op': op,
    'res': res,
    'kind': ?kind,
    'id': ?id,
    'relay': ?relay,
    'guid': ?guid,
    'motivo': ?motivo,
    'ext': ?ext,
  }),
)!;

void main() {
  const r1 = 'wss://r1.test', r2 = 'wss://r2.test';

  // Ciclo 1: sucesso, com recibos nos dois lados. Evento 20002 publicado pelo
  // motorista em t=1000 e recebido pelo passageiro em t=1120 (r2) e 1300 (r1).
  // Ciclo 2: falha (sem recibo do passageiro), indeterminada.
  // Ciclo 3: falha com publicação recusada por todos os relays → relays.
  final mot = [
    l(
      900,
      'motorista',
      'corrida.estado',
      motivo: 'deslocandoatepassageiro',
      guid: h('a'),
    ),
    l(1000, 'motorista', 'evento.publicou', kind: 20002, id: h('1')),
    l(
      1010,
      'motorista',
      'evento.recebeu',
      res: 'ok',
      kind: 20002,
      id: h('1'),
      relay: r1,
    ), // eco
    l(2000, 'motorista', 'corrida.estado', motivo: 'emcorrida', guid: h('a')),
    l(3000, 'motorista', 'recibo.emitiu', res: 'ok', id: h('9'), guid: h('a')),
    l(
      4000,
      'motorista',
      'corrida.estado',
      motivo: 'deslocandoatepassageiro',
      guid: h('b'),
    ),
    l(4500, 'motorista', 'recibo.emitiu', res: 'ok', id: h('8'), guid: h('b')),
    l(
      6000,
      'motorista',
      'corrida.estado',
      motivo: 'deslocandoatepassageiro',
      guid: h('c'),
    ),
    l(6100, 'motorista', 'evento.publicou', kind: 20007, id: h('2')),
    l(
      6200,
      'motorista',
      'relay.ok',
      res: 'falha',
      kind: 20007,
      id: h('2'),
      relay: r1,
      motivo: 'rejeitado',
    ),
    l(
      6200,
      'motorista',
      'relay.ok',
      res: 'falha',
      kind: 20007,
      id: h('2'),
      relay: r2,
      motivo: 'sem_resposta',
    ),
  ];
  final pax = [
    l(
      1120,
      'passageiro',
      'evento.recebeu',
      res: 'ok',
      kind: 20002,
      id: h('1'),
      relay: r2,
    ),
    l(
      1300,
      'passageiro',
      'evento.descartou',
      res: 'descartado',
      kind: 20002,
      id: h('1'),
      relay: r1,
      motivo: 'duplicado',
    ),
    l(3100, 'passageiro', 'recibo.emitiu', res: 'ok', id: h('7'), guid: h('a')),
    l(
      500,
      'passageiro',
      'corrida.estado',
      motivo: 'aguardandoorcamentos',
      guid: h('d'),
    ),
  ];

  final a = analisar(mot, pax);

  test('detecta ciclos, sucesso e origem da falha', () {
    expect(a.ciclos.map((c) => c.sucesso), [true, false, false]);
    expect(a.ciclos[1].origem, 'aplicativo');
    expect(a.ciclos[1].origemBruta, 'indeterminada');
    expect(a.ciclos[2].origem, 'relays');
    expect(a.validos, 3);
    expect(a.falhas, 2);
    expect(a.solicitacoes, 1);
  });

  test('latência: do publicador à primeira recepção do outro, sem eco', () {
    expect(a.latencias, hasLength(1));
    expect(a.latencias.single.ms, 120);
    expect(a.latencias.single.tipo, '20002 motorista→passageiro');
    expect(a.latencias.single.relayPrimeiro, r2);
    expect(a.semRecepcao, {20007: 1});
  });

  test('latência negativa é descartada e contada', () {
    final b = analisar(
      [l(5000, 'motorista', 'evento.publicou', kind: 20002, id: h('3'))],
      [
        l(
          4000,
          'passageiro',
          'evento.recebeu',
          res: 'ok',
          kind: 20002,
          id: h('3'),
          relay: r1,
        ),
      ],
    );
    expect(b.latencias, isEmpty);
    expect(b.latenciasDescartadas, 1);
  });

  test(
    'entrega por relay conta recebeu e duplicado; primeiro só o recebeu',
    () {
      expect(a.entregaPorRelay[(r2, 20002)], 1);
      expect(a.primeiroPorRelay[(r2, 20002)], 1);
      expect(a.entregaPorRelay[(r1, 20002)], 2); // eco do motorista + duplicado
      expect(a.primeiroPorRelay[(r1, 20002)], 1);
    },
  );

  test('serviço externo não conta como válido nem como falha do critério', () {
    final b = analisar([
      l(
        100,
        'motorista',
        'corrida.estado',
        motivo: 'deslocandoatepassageiro',
        guid: h('a'),
      ),
      l(
        150,
        'motorista',
        'externo.falha',
        res: 'falha',
        ext: 'ors',
        motivo: 'http429',
      ),
    ], []);
    expect(b.ciclos.single.origem, 'servico_externo');
    expect(b.validos, 0);
    expect(b.falhas, 0);
    expect(b.externos, 1);
  });

  test('relatório traz as oito seções e o veredito', () {
    final s = gerarRelatorioLogs(
      a,
      meta: 60,
      geradoEm: DateTime.utc(2026, 11, 3),
    );
    for (var i = 1; i <= 8; i++) {
      expect(s.markdown, contains('## $i.'));
    }
    expect(s.markdown, contains('RELATÓRIO PARCIAL'));
    expect(s.markdown, contains('**Veredito: PARCIALMENTE ATENDIDO**'));
    expect(s.markdown, contains('20002 motorista→passageiro | 1 | 120 | 120'));
    expect(
      s.csvs.keys,
      containsAll(['ciclos.csv', 'latencias.csv', 'relays.csv']),
    );
    expect(s.csvs['ciclos.csv']!.split('\n'), hasLength(4));
  });

  test('0 falhas em 60 ciclos válidos: ATENDIDO e limite superior ≈ 5,96%', () {
    final ls = <Linha>[];
    for (var i = 0; i < 60; i++) {
      final g = i.toRadixString(16).padLeft(64, '0');
      ls
        ..add(
          l(
            i * 10,
            'motorista',
            'corrida.estado',
            motivo: 'emcorrida',
            guid: g,
          ),
        )
        ..add(l(i * 10 + 1, 'motorista', 'recibo.emitiu', res: 'ok', guid: g));
    }
    final s = gerarRelatorioLogs(analisar(ls, []));
    expect(s.markdown, contains('**Veredito: ATENDIDO**'));
    expect(s.markdown, contains('5,96%'));
    expect(s.markdown, isNot(contains('RELATÓRIO PARCIAL')));
  });

  test('linha malformada é ignorada, não derruba a leitura', () {
    final r = lerTexto([
      '{"t":1',
      'lixo',
      '[]',
      '{"t":1,"papel":"x","op":"a","res":"ok"}',
    ]);
    expect(r.linhas, hasLength(1));
    expect(r.invalidas, 3);
  });

  test('resume as chamadas a serviços externos por serviço e componente', () {
    Linha c(int ms, String res) => Linha.tentar(
      jsonEncode({
        't': 1,
        'papel': 'motorista',
        'exec': 'e',
        'iso': 'ui',
        'comp': 'tile',
        'op': 'externo.chamada',
        'res': res,
        'ext': 'openfreemap',
        'ms': ms,
      }),
    )!;
    final b = analisar([c(100, 'ok'), c(300, 'ok'), c(50, 'falha')], []);
    final s = gerarRelatorioLogs(b);
    expect(s.markdown, contains('| openfreemap | tile | 3 | 1 | 100 | 300 |'));
    expect(s.csvs['externas.csv'], contains('openfreemap,tile,3,1,100.0,300.0'));
  });
}
