import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/checkpoint.dart';
import '../../../tool/e2e/src/latencia.dart';
import '../../../tool/e2e/src/observador.dart';
import '../../../tool/e2e/src/relatorio.dart';

final _t0 = DateTime.utc(2026, 11, 1, 12);

Ciclo _ciclo(int n, String acaoId, {Duration deslocamento = Duration.zero}) {
  final i = _t0.add(Duration(minutes: n * 5)).add(deslocamento);
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
            id: acaoId,
            tipo: 'toque',
            inicioUtc: i.add(const Duration(seconds: 10)),
            fimUtc: i.add(const Duration(seconds: 10, milliseconds: 100)),
          ),
        ],
      ),
    ],
    resultado: 'sucesso',
    valido: true,
    capturas: ['c$n-$acaoId.png'],
  );
}

/// Evento publicado pelo autor da ação, visto [ms] depois dela no relógio da
/// máquina que o observou.
EventoObservado _ev(Ciclo c, int kind, String autor, int ms, String relay) =>
    EventoObservado(
      relay: relay,
      kind: kind,
      id: '${kind + c.ciclo}'.padLeft(64, 'a'),
      createdAt: 0,
      recebidoUtc: c.inicioUtc.add(Duration(seconds: 10, milliseconds: ms)),
      autor: autor,
      destinatario: null,
    );

Execucao _execucao({String pubMot = 'a', EstadoExecucao? estado}) => Execucao(
  ensaio: true,
  metaValidos: 1,
  tetoExecutados: 4,
  orcamentoMs: const Duration(hours: 1).inMilliseconds,
  motoristaPub: pubMot * 64,
  passageiroPub: 'b' * 64,
  estado: estado ?? EstadoExecucao.concluido,
  ambiente: {
    'deriva_relogio_s': {'x': 1},
  },
);

void main() {
  // Motorista com o relógio 1 h adiantado em relação ao passageiro: uma junção
  // que misturasse os eventos daria latências absurdas.
  final cMot = _ciclo(1, 'orcamento', deslocamento: const Duration(hours: 1));
  final cPax = _ciclo(1, 'solicitar');
  final mot = DadosExecucao(
    execucao: _execucao(),
    ciclos: [cMot],
    eventos: [_ev(cMot, 20002, 'motorista', 140, 'wss://relay.damus.io')],
  );
  final pax = DadosExecucao(
    execucao: _execucao(),
    ciclos: [cPax],
    eventos: [_ev(cPax, 20001, 'passageiro', 160, 'wss://relay.primal.net')],
  );

  test('une as ações do ciclo e as capturas das duas máquinas', () {
    final j = juntarDados(mot, pax);
    expect(j.ciclos, hasLength(1));
    final acoes = [for (final e in j.ciclos.single.etapas) ...e.acoes];
    expect(acoes.map((a) => a.id), ['orcamento', 'solicitar']);
    expect(j.ciclos.single.capturas, hasLength(2));
    expect(j.execucao.ambiente['papel'], 'motorista+passageiro');
  });

  test('a latência é calculada por máquina, sem cruzar relógios', () {
    final j = juntarDados(mot, pax);
    final r = gerarRelatorio(j, geradoEm: _t0);
    // 20002 medido no motorista: ~40 ms; 20001 no passageiro: ~60 ms.
    expect(r.markdown, contains('| 20002 Orçamento de corrida | 1 | 40 |'));
    expect(r.markdown, contains('| 20001 Solicitação de corrida | 1 | 60 |'));
  });

  test('os eventos por relay somam os das duas máquinas', () {
    final r = gerarRelatorio(juntarDados(mot, pax), geradoEm: _t0);
    expect(r.markdown, contains('| wss://relay.damus.io | 1 | 1 |'));
    expect(r.markdown, contains('| wss://relay.primal.net | 1 | 1 |'));
  });

  test('recusa dados de execuções diferentes', () {
    final outra = DadosExecucao(
      execucao: _execucao(pubMot: 'c'),
      ciclos: [cPax],
      eventos: const [],
    );
    expect(() => juntarDados(mot, outra), throwsA(isA<FormatException>()));

    final semCiclo = DadosExecucao(
      execucao: _execucao(),
      ciclos: const [],
      eventos: const [],
    );
    expect(() => juntarDados(mot, semCiclo), throwsA(isA<FormatException>()));
  });

  test('o estado que não concluiu prevalece', () {
    final parcial = DadosExecucao(
      execucao: _execucao(estado: EstadoExecucao.parcial),
      ciclos: [cPax],
      eventos: const [],
    );
    expect(juntarDados(mot, parcial).execucao.estado, EstadoExecucao.parcial);
    expect(juntarDados(parcial, mot).execucao.estado, EstadoExecucao.parcial);
  });

  test('tiposDeLatencia continua com o autor de cada ação', () {
    expect(
      tiposDeLatencia.firstWhere((t) => t.id == 'orcamento').autor,
      'motorista',
    );
  });
}
