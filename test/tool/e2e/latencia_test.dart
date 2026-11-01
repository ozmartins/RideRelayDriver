import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/checkpoint.dart';
import '../../../tool/e2e/src/latencia.dart';
import '../../../tool/e2e/src/observador.dart';

final _t0 = DateTime.utc(2026, 11, 1, 12);

EventoObservado _ev(
  int kind,
  String autor,
  Duration depois, {
  String relay = 'wss://nos.lol',
}) => EventoObservado(
  relay: relay,
  kind: kind,
  id: 'a' * 64,
  createdAt: 0,
  recebidoUtc: _t0.add(depois),
  autor: autor,
  destinatario: null,
);

Ciclo _ciclo(List<Acao> acoes) => Ciclo(
  ciclo: 3,
  periodo: '1',
  inicioUtc: _t0,
  fimUtc: _t0.add(const Duration(minutes: 3)),
  etapas: [
    Etapa(
      id: 'E02',
      resultado: 'ok',
      inicioUtc: _t0,
      fimUtc: _t0.add(const Duration(seconds: 10)),
      limiteMs: 60000,
      acoes: acoes,
    ),
  ],
  resultado: 'sucesso',
  valido: true,
);

Acao _acao(String id, String tipo, int inicioMs, int fimMs) => Acao(
  id: id,
  tipo: tipo,
  inicioUtc: _t0.add(Duration(milliseconds: inicioMs)),
  fimUtc: _t0.add(Duration(milliseconds: fimMs)),
);

void main() {
  test('a tabela tem as 9 linhas de FR-028, com 20014 nos dois sentidos', () {
    expect(tiposDeLatencia, hasLength(9));
    final k14 = tiposDeLatencia.where((t) => t.kind == 20014).toList();
    expect(k14.map((t) => t.autor).toSet(), {'motorista', 'passageiro'});
    expect(
      tiposDeLatencia
          .where((t) => t.categoria == 'posicionamento')
          .map((t) => t.kind),
      [20007, 20009],
    );
  });

  test('latência = menor instante entre relays − fim da ação', () {
    final r = calcularLatencias(
      _ciclo([_acao('solicitar', 'toque', 1000, 1100)]),
      [
        _ev(
          20001,
          'passageiro',
          const Duration(milliseconds: 1900),
          relay: 'a',
        ),
        _ev(
          20001,
          'passageiro',
          const Duration(milliseconds: 1600),
          relay: 'b',
        ),
      ],
    );
    expect(r.amostras, hasLength(1));
    expect(r.amostras.single.latenciaMs, closeTo(500, 1e-9));
    expect(r.amostras.single.relay, 'b');
    expect(r.desvios, isEmpty);
  });

  test('sem evento correspondente não há amostra (nunca zero)', () {
    final r = calcularLatencias(_ciclo([_acao('orcamento', 'toque', 0, 100)]), [
      _ev(20001, 'passageiro', const Duration(seconds: 1)),
    ]);
    expect(r.amostras, isEmpty);
  });

  test('evento de outro autor não conta', () {
    final r = calcularLatencias(_ciclo([_acao('solicitar', 'toque', 0, 100)]), [
      _ev(20001, 'motorista', const Duration(seconds: 1)),
    ]);
    expect(r.amostras, isEmpty);
  });

  test('latência negativa é descartada com desvio', () {
    final r = calcularLatencias(_ciclo([_acao('aceitar', 'toque', 0, 1000)]), [
      _ev(20003, 'passageiro', const Duration(milliseconds: 500)),
    ]);
    expect(r.amostras, isEmpty);
    expect(r.desvios.single, contains('negativa'));
  });

  test('evento anterior à ação não é associado', () {
    final r = calcularLatencias(
      _ciclo([_acao('solicitar', 'toque', 5000, 5100)]),
      [_ev(20001, 'passageiro', const Duration(seconds: 1))],
    );
    expect(r.amostras, isEmpty);
  });

  test('resumo separa toque e posicionamento e tem as três linhas gerais', () {
    final r = calcularLatencias(
      _ciclo([
        _acao('solicitar', 'toque', 0, 100),
        _acao('chegada-origem', 'posicionamento', 0, 100),
      ]),
      [
        _ev(20001, 'passageiro', const Duration(milliseconds: 300)),
        _ev(20007, 'motorista', const Duration(milliseconds: 5100)),
      ],
    );
    final m = resumoPorTipo(r.amostras);
    expect(m['geral (todas)']!.n, 2);
    expect(m['geral (toque)']!.n, 1);
    expect(m['geral (toque)']!.mediana, closeTo(200, 1e-9));
    expect(m['geral (posicionamento)']!.n, 1);
    expect(m['geral (posicionamento)']!.p95, closeTo(5000, 1e-9));
    expect(m['20002 Orçamento de corrida']!.n, 0);
    expect(m['20002 Orçamento de corrida']!.mediana, isNull);
  });
}
