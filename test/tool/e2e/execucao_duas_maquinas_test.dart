import 'dart:io';

import 'package:driver/services/event_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/checkpoint.dart';
import '../../../tool/e2e/src/ciclo.dart';
import '../../../tool/e2e/src/coordenacao.dart';
import '../../../tool/e2e/src/evidencia.dart';
import '../../../tool/e2e/src/execucao.dart';
import '../../../tool/e2e/src/observador.dart';
import '../../../tool/e2e/src/opcoes.dart' show Papel;
import '../../support/fake_relay_transport.dart';
import 'support/fake_adb.dart';
import 'support/relogio_falso.dart';

Ciclo _ciclo(
  int n,
  RelogioFalso r, {
  String resultado = 'sucesso',
  bool valido = true,
  String? origem,
  String? etapaFalha,
}) {
  final inicio = r.agora();
  r.avancar(const Duration(minutes: 1));
  return Ciclo(
    ciclo: n,
    inicioUtc: inicio,
    fimUtc: r.agora(),
    etapas: const [],
    resultado: resultado,
    valido: valido,
    etapaFalha: resultado == 'sucesso' ? null : (etapaFalha ?? 'E04'),
    origem: origem,
  );
}

class _Lado {
  _Lado(this.papel, this.pasta, this.relogio, Coordenacao coord)
    : repo = RepositorioExecucao(Directory('${pasta.path}/${papel.name}')),
      coordenacao = coord {
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
      evidencia: Evidencia(
        adb: adb,
        pasta: Directory('${pasta.path}/${papel.name}-c'),
      ),
      relogio: relogio,
    );
  }

  final Papel papel;
  final Directory pasta;
  final RelogioFalso relogio;
  final RepositorioExecucao repo;
  final Coordenacao coordenacao;
  late final ContextoCiclo contexto;
  final List<String> reinicios = [];

  Future<Execucao> rodar({
    int meta = 2,
    int teto = 80,
    Future<ResultadoCiclo> Function(int)? ciclo,
    Future<bool> Function()? entreCiclos,
    void Function(ExecutorExecucao)? aoCriar,
  }) {
    final e = ExecutorExecucao(
      execucao: Execucao(
        ensaio: true,
        metaValidos: meta,
        tetoExecutados: teto,
        orcamentoMs: const Duration(hours: 12).inMilliseconds,
        motoristaPub: 'a' * 64,
        passageiroPub: 'b' * 64,
      ),
      repositorio: repo,
      relogio: relogio,
      contexto: contexto,
      executarCiclo:
          ciclo ?? (n) async => ResultadoCiclo(ciclo: _ciclo(n, relogio)),
      prontoParaCiclo: () async => true,
      entreCiclos:
          entreCiclos ??
          () async {
            reinicios.add(papel.name);
            return true;
          },
      coordenacao: coordenacao,
      papel: papel,
    );
    aoCriar?.call(e);
    return e.executar();
  }
}

void main() {
  late Directory pasta;
  late RelogioFalso relogio;
  late NucleoCoordenacao nucleo;
  late _Lado mot;
  late _Lado pax;

  setUp(() {
    pasta = Directory.systemTemp.createTempSync('duas_');
    relogio = RelogioFalso();
    nucleo = NucleoCoordenacao(espera: const Duration(seconds: 5));
    mot = _Lado(
      Papel.motorista,
      pasta,
      relogio,
      CoordenacaoLocal(nucleo, Papel.motorista),
    );
    pax = _Lado(
      Papel.passageiro,
      pasta,
      relogio,
      CoordenacaoLocal(nucleo, Papel.passageiro),
    );
  });

  tearDown(() => pasta.deleteSync(recursive: true));

  test('os dois lados rodam os mesmos ciclos e concluem juntos', () async {
    final r = await Future.wait([mot.rodar(), pax.rodar()]);

    expect(r[0].estado, EstadoExecucao.concluido);
    expect(r[1].estado, EstadoExecucao.concluido);
    expect(mot.repo.lerCiclos().map((c) => c.ciclo), [1, 2]);
    expect(pax.repo.lerCiclos().map((c) => c.ciclo), [1, 2]);
    // reinício só entre ciclos, nunca depois do último
    expect(mot.reinicios, hasLength(1));
    expect(pax.reinicios, hasLength(1));
  });

  test('falha de um lado invalida o ciclo nos dois e ele é reposto', () async {
    final r = await Future.wait([
      mot.rodar(
        meta: 1,
        ciclo: (n) async => ResultadoCiclo(
          ciclo: n == 1
              ? _ciclo(
                  n,
                  relogio,
                  resultado: 'falha',
                  valido: false,
                  origem: 'servico_externo',
                  etapaFalha: 'E03',
                )
              : _ciclo(n, relogio),
        ),
      ),
      pax.rodar(meta: 1),
    ]);

    expect(r[0].estado, EstadoExecucao.concluido);
    expect(r[1].estado, EstadoExecucao.concluido);
    for (final lado in [mot, pax]) {
      final ciclos = lado.repo.lerCiclos();
      expect(ciclos.map((c) => c.ciclo), [1, 2], reason: lado.papel.name);
      expect(ciclos.first.valido, isFalse);
      expect(ciclos.first.resultado, 'falha');
      expect(ciclos.first.etapaFalha, 'E03');
      expect(ciclos.first.origem, 'servico_externo');
      expect(ciclos.last.valido, isTrue);
    }
  });

  test('o motorista segue o coordenador ao atingir o teto de ciclos', () async {
    final r = await Future.wait([
      mot.rodar(meta: 10),
      pax.rodar(meta: 10, teto: 2),
    ]);

    expect(r[1].estado, EstadoExecucao.parcial);
    expect(r[1].motivoParcial, 'teto_executados');
    expect(r[0].estado, EstadoExecucao.parcial);
    expect(r[0].motivoParcial, 'teto_executados');
    expect(mot.repo.lerCiclos(), hasLength(2));
    expect(mot.reinicios, hasLength(1));
  });

  test('Ctrl+C no motorista solta o passageiro das barreiras', () async {
    late ExecutorExecucao exMot;
    final r = await Future.wait([
      mot.rodar(
        meta: 10,
        aoCriar: (e) => exMot = e,
        ciclo: (n) async {
          exMot.pedirParada();
          return ResultadoCiclo(
            ciclo: _ciclo(n, relogio, resultado: 'interrompido', valido: false),
          );
        },
      ),
      pax.rodar(meta: 10),
    ]);

    expect(r[0].estado, EstadoExecucao.parcial);
    expect(r[0].motivoParcial, 'interrompido');
    expect(r[1].estado, EstadoExecucao.parcial);
    expect(pax.repo.lerCiclos().single.resultado, 'interrompido');
    expect(pax.repo.lerCiclos().single.valido, isFalse);
  });

  test('ciclos que não conferem entre os lados param por ambiente', () async {
    // O motorista já tem um ciclo gravado que o passageiro desconhece.
    mot.repo.acrescentarCiclo(_ciclo(1, relogio));

    final r = await Future.wait([mot.rodar(), pax.rodar()]);

    expect(r[0].estado, EstadoExecucao.parcial);
    expect(r[0].motivoParcial, 'ambiente');
    expect(r[1].estado, EstadoExecucao.parcial);
  });

  test('fundirResultados: etapa mais cedo e serviço externo prevalecem', () {
    final local = ResultadoCiclo(
      ciclo: _ciclo(
        1,
        relogio,
        resultado: 'falha',
        etapaFalha: 'E08',
        origem: 'aplicativo',
      ),
    );
    final f1 = fundirResultados(
      local,
      const ResumoCiclo(
        resultado: 'falha',
        valido: true,
        etapaFalha: 'E05',
        origem: 'relays',
      ),
    );
    expect(f1.ciclo.etapaFalha, 'E05');
    expect(f1.ciclo.origem, 'relays');
    expect(f1.ciclo.valido, isTrue);

    final f2 = fundirResultados(
      local,
      const ResumoCiclo(
        resultado: 'falha',
        valido: false,
        etapaFalha: 'R',
        origem: 'servico_externo',
        servicoExterno: 'Photon',
      ),
    );
    expect(f2.ciclo.etapaFalha, 'R');
    expect(f2.ciclo.servicoExterno, 'Photon');
    expect(f2.ciclo.valido, isFalse);

    final f3 = fundirResultados(
      ResultadoCiclo(ciclo: _ciclo(1, relogio)),
      const ResumoCiclo(resultado: 'interrompido', valido: false),
    );
    expect(f3.ciclo.resultado, 'interrompido');
    expect(f3.ciclo.valido, isFalse);
  });

  test(
    'fundirResultados: a causa vale mais que o reflexo, mesmo mais tarde',
    () {
      final reflexo = ResultadoCiclo(
        ciclo: _ciclo(
          1,
          relogio,
          resultado: 'falha',
          etapaFalha: 'E03',
          origem: 'aplicativo',
        ),
        consequencia: true,
      );
      final f = fundirResultados(
        reflexo,
        const ResumoCiclo(
          resultado: 'falha',
          valido: true,
          etapaFalha: 'E05',
          origem: 'relays',
        ),
      );
      expect(f.ciclo.etapaFalha, 'E05');
      expect(f.ciclo.origem, 'relays');
    },
  );

  test('ResumoCiclo: ida e volta e entrada inválida', () {
    const r = ResumoCiclo(
      resultado: 'falha',
      valido: false,
      etapaFalha: 'E02',
      origem: 'servico_externo',
      limiteDiarioOrs: true,
      consequencia: true,
    );
    final volta = ResumoCiclo.fromJson(r.toJson())!;
    expect(volta.toJson(), r.toJson());
    expect(ResumoCiclo.fromJson(null), isNull);
    expect(ResumoCiclo.fromJson({'resultado': 'x', 'valido': true}), isNull);
  });
}
