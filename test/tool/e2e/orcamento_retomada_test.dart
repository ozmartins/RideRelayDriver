import 'dart:io';

import 'package:driver/services/event_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/checkpoint.dart';
import '../../../tool/e2e/src/ciclo.dart';
import '../../../tool/e2e/src/config.dart';
import '../../../tool/e2e/src/evidencia.dart';
import '../../../tool/e2e/src/execucao.dart';
import '../../../tool/e2e/src/observador.dart';
import '../../support/fake_relay_transport.dart';
import 'support/fake_adb.dart';
import 'support/relogio_falso.dart';

/// Ciclo sintético para o laço da execução (o fluxo em si é testado em
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
  late RepositorioExecucao repo;
  late ContextoCiclo contexto;

  Execucao novaExecucao({int meta = 3, int teto = 80, Duration? orcamento}) =>
      Execucao(
        ensaio: true,
        metaValidos: meta,
        tetoExecutados: teto,
        orcamentoMs: (orcamento ?? const Duration(hours: 12)).inMilliseconds,
        motoristaPub: 'a' * 64,
        passageiroPub: 'b' * 64,
      );

  ExecutorExecucao executor(
    Execucao p,
    Future<ResultadoCiclo> Function(int) ciclos, {
    Future<bool> Function()? pronto,
    Future<bool> Function()? entreCiclos,
  }) => ExecutorExecucao(
    execucao: p,
    repositorio: repo,
    relogio: relogio,
    contexto: contexto,
    executarCiclo: ciclos,
    prontoParaCiclo: pronto ?? () async => true,
    entreCiclos: entreCiclos,
  );

  setUp(() {
    pasta = Directory.systemTemp.createTempSync('execucao_');
    relogio = RelogioFalso();
    repo = RepositorioExecucao(Directory('${pasta.path}/ensaio'));
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
    );
  });

  tearDown(() => pasta.deleteSync(recursive: true));

  test('atinge a meta de válidos e conclui', () async {
    final p = novaExecucao(meta: 3);
    final r = await executor(
      p,
      (n) async => ResultadoCiclo(ciclo: _ciclo(n, relogio)),
    ).executar();

    expect(r.estado, EstadoExecucao.concluido);
    expect(repo.lerCiclos(), hasLength(3));
    expect(repo.lerCheckpoint()!.estado, EstadoExecucao.concluido);
  });

  test('ciclo externo não é válido e é reposto por um novo ciclo', () async {
    final p = novaExecucao(meta: 2);
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

    expect(r.estado, EstadoExecucao.concluido);
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
    final p = novaExecucao(meta: 2);
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
      final p = novaExecucao(meta: 5, teto: 3);
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

      expect(r.estado, EstadoExecucao.parcial);
      expect(r.motivoParcial, 'teto_executados');
      expect(repo.lerCiclos(), hasLength(3));
    },
  );

  test('orçamento esgotado entre ciclos: parcial orcamento', () async {
    final p = novaExecucao(meta: 10, orcamento: const Duration(minutes: 10));
    final r = await executor(
      p,
      (n) async => ResultadoCiclo(ciclo: _ciclo(n, relogio)),
    ).executar();

    expect(r.estado, EstadoExecucao.parcial);
    expect(r.motivoParcial, 'orcamento');
    expect(repo.lerCiclos().length, 3); // 4 + 4 + 4 min ≥ 10
    expect(r.tempoAtivoMs, greaterThanOrEqualTo(10 * 60 * 1000));
  });

  test(
    'orçamento estoura no meio do ciclo: ciclo interrompido, não válido',
    () async {
      final p = novaExecucao(meta: 10, orcamento: const Duration(minutes: 10));
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

      expect(r.estado, EstadoExecucao.parcial);
      expect(r.motivoParcial, 'orcamento');
      final ciclos = repo.lerCiclos();
      expect(ciclos.last.resultado, 'interrompido');
      expect(ciclos.last.valido, isFalse);
      expect(Contadores.de(ciclos).interrompidos, 1);
    },
  );

  test('o prazo global do ciclo é o saldo do orçamento', () async {
    final p = novaExecucao(meta: 1, orcamento: const Duration(hours: 1));
    DateTime? visto;
    final inicio = relogio.agora();
    await executor(p, (n) async {
      visto = contexto.prazoGlobal;
      return ResultadoCiclo(ciclo: _ciclo(n, relogio));
    }).executar();

    expect(visto, inicio.add(const Duration(hours: 1)));
  });

  test('retomada: soma o tempo ativo e não refaz nem duplica ciclos', () async {
    final p = novaExecucao(meta: 3, orcamento: const Duration(minutes: 30));
    // Primeira execução: 1 ciclo e para (pedido de parada).
    late ExecutorExecucao e1;
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
    expect(r2.estado, EstadoExecucao.concluido);
    expect(repo.lerCiclos().map((c) => c.ciclo), [1, 2, 3]);
    expect(r2.tempoAtivoMs, greaterThan(tempo1));
    expect(r2.tempoAtivoMs, lessThan(const Duration(hours: 1).inMilliseconds));
    expect(r2.invocacoes, hasLength(2));
  });

  test('sinal de cota diária da ORS: para de forma controlada', () async {
    final p = novaExecucao(meta: 10);
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

    expect(r.estado, EstadoExecucao.parcial);
    expect(r.motivoParcial, 'limite_diario_ors');
    expect(repo.lerCiclos(), hasLength(2));
  });

  test('observador sem conexão: parcial ambiente, sem iniciar ciclo', () async {
    final p = novaExecucao();
    var chamadas = 0;
    final r = await executor(p, (n) async {
      chamadas++;
      return ResultadoCiclo(ciclo: _ciclo(n, relogio));
    }, pronto: () async => false).executar();

    expect(chamadas, 0);
    expect(r.motivoParcial, 'ambiente');
  });

  test('recuperação que falha: parcial ambiente', () async {
    final p = novaExecucao(meta: 5);
    final r = await executor(p, (n) async {
      return ResultadoCiclo(
        ciclo: _ciclo(n, relogio, resultado: 'falha', origem: 'aplicativo'),
        recuperacaoFalhou: true,
      );
    }).executar();

    expect(r.motivoParcial, 'ambiente');
    expect(repo.lerCiclos(), hasLength(1));
  });

  group('entre ciclos', () {
    ResultadoCiclo ok(int n) => ResultadoCiclo(ciclo: _ciclo(n, relogio));

    test(
      'roda entre dois ciclos, nunca antes do primeiro nem depois do último',
      () async {
        final eventos = <String>[];
        final p = novaExecucao(meta: 3);
        final r = await executor(
          p,
          (n) async {
            eventos.add('ciclo $n');
            return ok(n);
          },
          entreCiclos: () async {
            eventos.add('reinicio');
            return true;
          },
        ).executar();

        expect(r.estado, EstadoExecucao.concluido);
        expect(eventos, [
          'ciclo 1',
          'reinicio',
          'ciclo 2',
          'reinicio',
          'ciclo 3',
        ]);
      },
    );

    test(
      'na retomada não reinicia antes do primeiro ciclo da invocação',
      () async {
        final p = novaExecucao(meta: 3);
        await executor(p, (n) async {
          return ok(n);
        }, pronto: () async => true).executar();
        // Já há 3 ciclos gravados; refaz a execução com meta maior.
        var reinicios = 0;
        final p2 = novaExecucao(meta: 4);
        await executor(
          p2,
          (n) async => ok(n),
          entreCiclos: () async {
            reinicios++;
            return true;
          },
        ).executar();
        expect(reinicios, 0);
        expect(repo.lerCiclos(), hasLength(4));
      },
    );

    test('o reinício fica fora do tempo e da janela do ciclo', () async {
      final p = novaExecucao(meta: 2);
      await executor(
        p,
        (n) async => ok(n),
        entreCiclos: () async {
          relogio.avancar(const Duration(minutes: 7));
          return true;
        },
      ).executar();

      final ciclos = repo.lerCiclos();
      final folga = ciclos[1].inicioUtc.difference(ciclos[0].fimUtc);
      expect(folga, const Duration(minutes: 7));
      for (final c in ciclos) {
        expect(c.fimUtc.difference(c.inicioUtc), const Duration(minutes: 4));
      }
    });

    test('mas conta no tempo ativo da execução', () async {
      final p = novaExecucao(meta: 2);
      final r = await executor(
        p,
        (n) async => ok(n),
        entreCiclos: () async {
          relogio.avancar(const Duration(minutes: 7));
          return true;
        },
      ).executar();
      expect(r.tempoAtivoMs, const Duration(minutes: 15).inMilliseconds);
    });

    test(
      'reinício que falha: parcial ambiente, sem iniciar outro ciclo',
      () async {
        var ciclos = 0;
        final p = novaExecucao(meta: 3);
        final r = await executor(p, (n) async {
          ciclos++;
          return ok(n);
        }, entreCiclos: () async => false).executar();

        expect(r.estado, EstadoExecucao.parcial);
        expect(r.motivoParcial, 'ambiente');
        expect(ciclos, 1);
        expect(repo.lerCheckpoint()!.estado, EstadoExecucao.parcial);
      },
    );

    test('reinício que consome o orçamento: parcial orcamento', () async {
      var ciclos = 0;
      final p = novaExecucao(meta: 3, orcamento: const Duration(minutes: 10));
      final r = await executor(
        p,
        (n) async {
          ciclos++;
          return ok(n);
        },
        entreCiclos: () async {
          relogio.avancar(const Duration(minutes: 8));
          return true;
        },
      ).executar();

      expect(r.estado, EstadoExecucao.parcial);
      expect(r.motivoParcial, 'orcamento');
      expect(ciclos, 1);
    });

    test('ciclo interrompido não dispara o reinício', () async {
      var reinicios = 0;
      final p = novaExecucao(meta: 3);
      await executor(
        p,
        (n) async => ResultadoCiclo(
          ciclo: _ciclo(n, relogio, resultado: 'interrompido', valido: false),
        ),
        entreCiclos: () async {
          reinicios++;
          return true;
        },
      ).executar();
      expect(reinicios, 0);
    });
  });

  group('persistência', () {
    test('checkpoint ida e volta e escrita atômica sem arquivo temporário', () {
      final p = novaExecucao()..telasCapturadas = ['solicitacao-enviada'];
      repo.gravarCheckpoint(p);
      final lido = repo.lerCheckpoint()!;
      expect(lido.ensaio, isTrue);
      expect(lido.metaValidos, 3);
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

    test('limites da execução: 60 válidos, teto 80, orçamento 12 h', () {
      expect(metaValidosDaExecucao, 60);
      expect(tetoDeCiclosExecutados, 80);
      expect(const Limites().execucao, const Duration(hours: 12));
    });

    test('checkpoint do formato com períodos não é retomado', () {
      repo.gravarCheckpoint(novaExecucao());
      final arquivo = File('${repo.pasta.path}/checkpoint.json');
      arquivo.writeAsStringSync(
        arquivo.readAsStringSync().replaceFirst(
          '"ensaio": true,',
          '"periodo": "1",',
        ),
      );
      expect(() => repo.lerCheckpoint(), throwsFormatException);
    });

    test('ciclo ida e volta preserva origem, origem_bruta e sinal', () {
      final c = Ciclo(
        ciclo: 7,
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
