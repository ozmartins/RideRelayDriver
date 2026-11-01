import 'dart:io';

import 'package:driver/services/event_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/checkpoint.dart';
import '../../../tool/e2e/src/ciclo.dart';
import '../../../tool/e2e/src/config.dart';
import '../../../tool/e2e/src/evidencia.dart';
import '../../../tool/e2e/src/observador.dart';
import '../../../tool/e2e/src/periodo.dart';
import '../../support/fake_relay_transport.dart';
import 'support/fake_adb.dart';
import 'support/relogio_falso.dart';

/// Ciclo sintético para o laço do período (o fluxo em si é testado em
/// `ciclo_test.dart`).
Ciclo _ciclo(
  int n,
  RelogioFalso r, {
  String resultado = 'sucesso',
  bool valido = true,
  String? origem,
  Duration duracao = const Duration(minutes: 4),
}) {
  final inicio = r.agora();
  r.avancar(duracao);
  return Ciclo(
    ciclo: n,
    periodo: 'ensaio',
    inicioUtc: inicio,
    fimUtc: r.agora(),
    etapas: const [],
    resultado: resultado,
    valido: valido,
    etapaFalha: resultado == 'sucesso' ? null : 'E04',
    origem: origem,
  );
}

void main() {
  late Directory pasta;
  late RelogioFalso relogio;
  late RepositorioPeriodo repo;
  late ContextoCiclo contexto;

  Periodo novoPeriodo({int meta = 3, int teto = 40, Duration? orcamento}) =>
      Periodo(
        periodo: 'ensaio',
        metaValidos: meta,
        tetoExecutados: teto,
        orcamentoMs: (orcamento ?? const Duration(hours: 3)).inMilliseconds,
        motoristaPub: 'a' * 64,
        passageiroPub: 'b' * 64,
      );

  ExecutorPeriodo executor(
    Periodo p,
    Future<ResultadoCiclo> Function(int) ciclos, {
    Future<bool> Function()? pronto,
  }) => ExecutorPeriodo(
    periodo: p,
    repositorio: repo,
    relogio: relogio,
    contexto: contexto,
    executarCiclo: ciclos,
    prontoParaCiclo: pronto ?? () async => true,
  );

  setUp(() {
    pasta = Directory.systemTemp.createTempSync('periodo_');
    relogio = RelogioFalso();
    repo = RepositorioPeriodo(Directory('${pasta.path}/ensaio'));
    final adb = FakeAdb(relogio: relogio);
    contexto = ContextoCiclo(
      adb: adb,
      serialMotorista: 'a',
      serialPassageiro: 'b',
      observador: Observador(
        transport: FakeRelayTransport(),
        verifier: const NostrEventVerifier(),
        identidades: const Identidades(motorista: 'a', passageiro: 'b'),
        relogio: relogio,
      ),
      evidencia: Evidencia(adb: adb, pasta: Directory('${pasta.path}/c')),
      relogio: relogio,
      periodo: 'ensaio',
    );
  });

  tearDown(() => pasta.deleteSync(recursive: true));

  test('atinge a meta de válidos e conclui', () async {
    final p = novoPeriodo(meta: 3);
    final r = await executor(
      p,
      (n) async => ResultadoCiclo(ciclo: _ciclo(n, relogio)),
    ).executar();

    expect(r.estado, EstadoPeriodo.concluido);
    expect(repo.lerCiclos(), hasLength(3));
    expect(repo.lerCheckpoint()!.estado, EstadoPeriodo.concluido);
  });

  test('ciclo externo não é válido e é reposto por um novo ciclo', () async {
    final p = novoPeriodo(meta: 2);
    final r = await executor(p, (n) async {
      final externo = n == 1;
      return ResultadoCiclo(
        ciclo: _ciclo(
          n,
          relogio,
          resultado: externo ? 'falha' : 'sucesso',
          valido: !externo,
          origem: externo ? 'servico_externo' : null,
        ),
      );
    }).executar();

    expect(r.estado, EstadoPeriodo.concluido);
    final ciclos = repo.lerCiclos();
    expect(ciclos.map((c) => c.ciclo), [1, 2, 3]);
    final cont = Contadores.de(ciclos);
    expect(cont.executados, 3);
    expect(cont.validos, 2);
    expect(cont.externosRepostos, 1);
    expect(cont.falhasValidas, 0);
    expect(cont.falhasTotais, 1);
  });

  test('falha de outra origem conta como válida e como falha', () async {
    final p = novoPeriodo(meta: 2);
    await executor(p, (n) async {
      return ResultadoCiclo(
        ciclo: _ciclo(
          n,
          relogio,
          resultado: n == 1 ? 'falha' : 'sucesso',
          origem: n == 1 ? 'aplicativo' : null,
        ),
      );
    }).executar();

    final cont = Contadores.de(repo.lerCiclos());
    expect(cont.validos, 2);
    expect(cont.falhasValidas, 1);
    expect(cont.executados, 2);
  });

  test(
    'teto de ciclos executados sem a meta: parcial teto_executados',
    () async {
      final p = novoPeriodo(meta: 5, teto: 3);
      final r = await executor(p, (n) async {
        return ResultadoCiclo(
          ciclo: _ciclo(
            n,
            relogio,
            resultado: 'falha',
            valido: false,
            origem: 'servico_externo',
          ),
        );
      }).executar();

      expect(r.estado, EstadoPeriodo.parcial);
      expect(r.motivoParcial, 'teto_executados');
      expect(repo.lerCiclos(), hasLength(3));
    },
  );

  test('orçamento esgotado entre ciclos: parcial orcamento', () async {
    final p = novoPeriodo(meta: 10, orcamento: const Duration(minutes: 10));
    final r = await executor(
      p,
      (n) async => ResultadoCiclo(ciclo: _ciclo(n, relogio)),
    ).executar();

    expect(r.estado, EstadoPeriodo.parcial);
    expect(r.motivoParcial, 'orcamento');
    expect(repo.lerCiclos().length, 3); // 4 + 4 + 4 min ≥ 10
    expect(r.tempoAtivoMs, greaterThanOrEqualTo(10 * 60 * 1000));
  });

  test(
    'orçamento estoura no meio do ciclo: ciclo interrompido, não válido',
    () async {
      final p = novoPeriodo(meta: 10, orcamento: const Duration(minutes: 10));
      final r = await executor(p, (n) async {
        if (n == 3) {
          return ResultadoCiclo(
            ciclo: _ciclo(n, relogio, resultado: 'interrompido', valido: false),
          );
        }
        return ResultadoCiclo(
          ciclo: _ciclo(n, relogio, duracao: const Duration(minutes: 3)),
        );
      }).executar();

      expect(r.estado, EstadoPeriodo.parcial);
      expect(r.motivoParcial, 'orcamento');
      final ciclos = repo.lerCiclos();
      expect(ciclos.last.resultado, 'interrompido');
      expect(ciclos.last.valido, isFalse);
      expect(Contadores.de(ciclos).interrompidos, 1);
    },
  );

  test('o prazo global do ciclo é o saldo do orçamento', () async {
    final p = novoPeriodo(meta: 1, orcamento: const Duration(hours: 1));
    DateTime? visto;
    final inicio = relogio.agora();
    await executor(p, (n) async {
      visto = contexto.prazoGlobal;
      return ResultadoCiclo(ciclo: _ciclo(n, relogio));
    }).executar();

    expect(visto, inicio.add(const Duration(hours: 1)));
  });

  test('retomada: soma o tempo ativo e não refaz nem duplica ciclos', () async {
    final p = novoPeriodo(meta: 3, orcamento: const Duration(minutes: 30));
    // Primeira execução: 1 ciclo e para (pedido de parada).
    late ExecutorPeriodo e1;
    e1 = executor(p, (n) async {
      final c = _ciclo(n, relogio);
      e1.pedirParada();
      return ResultadoCiclo(ciclo: c);
    });
    final r1 = await e1.executar();
    expect(r1.motivoParcial, 'interrompido');
    expect(repo.lerCiclos().map((c) => c.ciclo), [1]);
    final tempo1 = r1.tempoAtivoMs;
    expect(tempo1, greaterThan(0));

    // Passa-se um dia; o orçamento continua do saldo, não do relógio de parede.
    relogio.avancar(const Duration(hours: 20));
    final retomado = repo.lerCheckpoint()!;
    contexto.prazoGlobal = null;
    final numeros = <int>[];
    final r2 = await executor(retomado, (n) async {
      numeros.add(n);
      return ResultadoCiclo(ciclo: _ciclo(n, relogio));
    }).executar();

    expect(numeros, [2, 3]);
    expect(r2.estado, EstadoPeriodo.concluido);
    expect(repo.lerCiclos().map((c) => c.ciclo), [1, 2, 3]);
    expect(r2.tempoAtivoMs, greaterThan(tempo1));
    expect(r2.tempoAtivoMs, lessThan(const Duration(hours: 1).inMilliseconds));
    expect(r2.execucoes, hasLength(2));
  });

  test('sinal de cota diária da ORS: para de forma controlada', () async {
    final p = novoPeriodo(meta: 10);
    final r = await executor(p, (n) async {
      return ResultadoCiclo(
        ciclo: _ciclo(
          n,
          relogio,
          resultado: 'falha',
          valido: false,
          origem: 'servico_externo',
        ),
        limiteDiarioOrs: n == 2,
      );
    }).executar();

    expect(r.estado, EstadoPeriodo.parcial);
    expect(r.motivoParcial, 'limite_diario_ors');
    expect(repo.lerCiclos(), hasLength(2));
  });

  test('observador sem conexão: parcial ambiente, sem iniciar ciclo', () async {
    final p = novoPeriodo();
    var chamadas = 0;
    final r = await executor(p, (n) async {
      chamadas++;
      return ResultadoCiclo(ciclo: _ciclo(n, relogio));
    }, pronto: () async => false).executar();

    expect(chamadas, 0);
    expect(r.motivoParcial, 'ambiente');
  });

  test('recuperação que falha: parcial ambiente', () async {
    final p = novoPeriodo(meta: 5);
    final r = await executor(p, (n) async {
      return ResultadoCiclo(
        ciclo: _ciclo(n, relogio, resultado: 'falha', origem: 'aplicativo'),
        recuperacaoFalhou: true,
      );
    }).executar();

    expect(r.motivoParcial, 'ambiente');
    expect(repo.lerCiclos(), hasLength(1));
  });

  group('persistência', () {
    test('checkpoint ida e volta e escrita atômica sem arquivo temporário', () {
      final p = novoPeriodo()..telasCapturadas = ['solicitacao-enviada'];
      repo.gravarCheckpoint(p);
      final lido = repo.lerCheckpoint()!;
      expect(lido.periodo, 'ensaio');
      expect(lido.telasCapturadas, ['solicitacao-enviada']);
      expect(lido.motoristaPub, 'a' * 64);
      expect(
        File('${repo.pasta.path}/checkpoint.json.tmp').existsSync(),
        isFalse,
      );
    });

    test('ciclos.jsonl corrompido: lança em vez de inventar ciclos', () {
      repo.garantirPasta();
      File('${repo.pasta.path}/ciclos.jsonl').writeAsStringSync('{ nao json\n');
      expect(() => repo.lerCiclos(), throwsFormatException);
    });

    test('tetos: 40 no período 1; 80 menos os executados no 2', () {
      expect(tetoDoPeriodo(1), 40);
      expect(tetoDoPeriodo(2, executadosPeriodo1: 32), 48);
      expect(tetoDoPeriodo(2, executadosPeriodo1: 40), 40);
      expect(tetoDoPeriodo(2, executadosPeriodo1: 90), 0);
    });

    test('ciclo ida e volta preserva origem, origem_bruta e sinal', () {
      final c = Ciclo(
        ciclo: 7,
        periodo: '1',
        inicioUtc: DateTime.utc(2026, 11, 1),
        fimUtc: DateTime.utc(2026, 11, 1, 0, 3),
        etapas: [
          Etapa(
            id: 'E02',
            resultado: 'ok',
            inicioUtc: DateTime.utc(2026, 11, 1),
            fimUtc: DateTime.utc(2026, 11, 1, 0, 1),
            limiteMs: 60000,
            acoes: [
              Acao(
                id: 'solicitar',
                tipo: 'toque',
                inicioUtc: DateTime.utc(2026, 11, 1),
                fimUtc: DateTime.utc(2026, 11, 1, 0, 0, 1),
              ),
            ],
          ),
        ],
        resultado: 'falha',
        valido: false,
        etapaFalha: 'E02',
        origem: 'servico_externo',
        servicoExterno: 'Photon',
        origemBruta: 'servico_externo',
        sinalExterno: {'fonte': 'ui', 'servico': 'Photon', 'http': null},
      );
      final de = Ciclo.fromJson(c.toJson());
      expect(de.servicoExterno, 'Photon');
      expect(de.etapas.single.acoes.single.id, 'solicitar');
      expect(de.valido, isFalse);
      expect(de.sinalExterno, {
        'fonte': 'ui',
        'servico': 'Photon',
        'http': null,
      });
    });
  });
}
