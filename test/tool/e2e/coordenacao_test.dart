import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/coordenacao.dart';
import '../../../tool/e2e/src/opcoes.dart';

void main() {
  group('NucleoCoordenacao', () {
    test('libera quando os dois papéis chegam', () async {
      final n = NucleoCoordenacao();
      final m = n.chegar('inicio-ciclo', 1, Papel.motorista);
      final p = n.chegar('inicio-ciclo', 1, Papel.passageiro);
      expect((await m).resultado, ResultadoBarreira.liberada);
      expect((await p).resultado, ResultadoBarreira.liberada);
    });

    test('barreiras de ciclos e nomes diferentes são independentes', () async {
      final n = NucleoCoordenacao(espera: const Duration(milliseconds: 50));
      final m = n.chegar('inicio-ciclo', 1, Papel.motorista);
      final p = n.chegar('inicio-ciclo', 2, Papel.passageiro);
      expect((await m).resultado, ResultadoBarreira.expirada);
      expect((await p).resultado, ResultadoBarreira.expirada);
    });

    test('expira sem o outro papel e permite nova tentativa', () async {
      final n = NucleoCoordenacao(espera: const Duration(milliseconds: 30));
      expect(
        (await n.chegar('fim-ciclo', 3, Papel.motorista)).resultado,
        ResultadoBarreira.expirada,
      );
      final m = n.chegar('fim-ciclo', 3, Papel.motorista);
      final p = n.chegar('fim-ciclo', 3, Papel.passageiro);
      expect((await m).resultado, ResultadoBarreira.liberada);
      expect((await p).resultado, ResultadoBarreira.liberada);
    });

    test('abortar solta quem espera e vale para barreiras seguintes', () async {
      final n = NucleoCoordenacao();
      final m = n.chegar('inicio-ciclo', 4, Papel.motorista);
      n.abortar(4, 'falha no emulador');
      expect((await m).resultado, ResultadoBarreira.abortado);
      expect(
        (await n.chegar('fim-ciclo', 4, Papel.passageiro)).resultado,
        ResultadoBarreira.abortado,
      );
      expect(n.motivoDeAborto(4), 'falha no emulador');
      expect(n.motivoDeAborto(5), isNull);
    });

    test('cada lado recebe os dados do outro', () async {
      final n = NucleoCoordenacao();
      final m = n.chegar(
        'fim-ciclo',
        1,
        Papel.motorista,
        dados: {'resultado': 'sucesso'},
      );
      final p = await n.chegar(
        'fim-ciclo',
        1,
        Papel.passageiro,
        dados: {'resultado': 'falha'},
      );
      expect(p.outro, {'resultado': 'sucesso'});
      expect((await m).outro, {'resultado': 'falha'});
    });

    test('falha de um lado é vista só pelo outro, por ciclo', () {
      final n = NucleoCoordenacao();
      n.registrarFalha(3, Papel.passageiro, 'E05');
      n.registrarFalha(3, Papel.passageiro, 'E09'); // vale a primeira
      expect(n.falhaDoOutro(3, Papel.motorista), 'E05');
      expect(n.falhaDoOutro(3, Papel.passageiro), isNull);
      expect(n.falhaDoOutro(4, Papel.motorista), isNull);
    });

    test('nome desconhecido e ciclo negativo são recusados', () {
      final n = NucleoCoordenacao();
      expect(
        () => n.chegar('outra', 1, Papel.motorista),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => n.chegar('fim-ciclo', -1, Papel.motorista),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  test('deslocamentoNtp: relógio do coordenador 5 s adiantado', () {
    final t0 = DateTime.utc(2026, 1, 1, 12);
    final d = deslocamentoNtp(
      t0: t0,
      t1: t0.add(const Duration(seconds: 5, milliseconds: 20)),
      t2: t0.add(const Duration(seconds: 5, milliseconds: 21)),
      t3: t0.add(const Duration(milliseconds: 41)),
    );
    expect(d, const Duration(seconds: 5));
  });

  test('SituacaoExecucao: ida e volta e entrada inválida', () {
    const e = SituacaoExecucao(
      ciclo: 2,
      validos: 1,
      executados: 2,
      ativoMs: 9,
      encerrado: true,
    );
    final volta = SituacaoExecucao.fromJson(
      jsonDecode(jsonEncode(e.toJson())),
    )!;
    expect(volta.toJson(), e.toJson());
    expect(SituacaoExecucao.fromJson({'ciclo': 'x'}), isNull);
    expect(SituacaoExecucao.fromJson(null), isNull);
  });

  group('servidor e cliente (loopback)', () {
    late NucleoCoordenacao nucleo;
    late ServidorCoordenacao servidor;
    late ClienteCoordenacao cliente;

    setUp(() async {
      nucleo = NucleoCoordenacao(espera: const Duration(milliseconds: 300));
      servidor = ServidorCoordenacao(nucleo: nucleo, token: 'segredo');
      await servidor.iniciar(porta: 0, endereco: InternetAddress.loopbackIPv4);
      cliente = ClienteCoordenacao(
        papel: Papel.motorista,
        host: '127.0.0.1',
        porta: servidor.porta,
        token: 'segredo',
        esperaBarreira: const Duration(milliseconds: 300),
      );
    });

    tearDown(() => servidor.parar());

    test('barreira libera quando o coordenador chega', () async {
      final remoto = cliente.barreira('inicio-ciclo', 1);
      final local = CoordenacaoLocal(nucleo, Papel.passageiro);
      expect(
        (await local.barreira('inicio-ciclo', 1)).resultado,
        ResultadoBarreira.liberada,
      );
      expect((await remoto).resultado, ResultadoBarreira.liberada);
    });

    test('barreira sem o outro lado expira (408)', () async {
      expect(
        (await cliente.barreira('inicio-ciclo', 1)).resultado,
        ResultadoBarreira.expirada,
      );
    });

    test('abortar chega ao coordenador e à barreira seguinte', () async {
      await cliente.abortar(7, 'sem rede');
      expect(nucleo.motivoDeAborto(7), 'sem rede');
      expect(
        (await cliente.barreira('fim-ciclo', 7)).resultado,
        ResultadoBarreira.abortado,
      );
    });

    test('estado reflete o que o coordenador publica', () async {
      nucleo.atualizarEstado(const SituacaoExecucao(ciclo: 3, validos: 2));
      final e = await cliente.estado();
      expect(e.ciclo, 3);
      expect(e.validos, 2);
    });

    test('relógio: mesmo hospedeiro dá deslocamento próximo de zero', () async {
      final d = await cliente.deslocamentoDeRelogio();
      expect(d.abs(), lessThan(const Duration(seconds: 1)));
    });

    test('falha: o motorista avisa e o passageiro consulta', () async {
      expect(await cliente.falhaDoOutro(2), isNull);
      await cliente.sinalizarFalha(2, 'E04');
      final local = CoordenacaoLocal(nucleo, Papel.passageiro);
      expect(await local.falhaDoOutro(2), 'E04');
      expect(await cliente.falhaDoOutro(2), isNull);
    });

    test('falha com etapa inválida é recusada', () async {
      await expectLater(
        cliente.sinalizarFalha(2, 'qualquer coisa'),
        throwsA(isA<CoordenadorInalcancavel>()),
      );
    });

    test('token errado é recusado com 401', () async {
      final intruso = ClienteCoordenacao(
        papel: Papel.motorista,
        host: '127.0.0.1',
        porta: servidor.porta,
        token: 'errado',
      );
      await expectLater(
        intruso.estado(),
        throwsA(isA<CoordenadorInalcancavel>()),
      );
    });

    test('corpo malformado e rota desconhecida', () async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      Future<int> chamar(String metodo, String caminho, String corpo) async {
        final r = await http.openUrl(
          metodo,
          Uri.parse('http://127.0.0.1:${servidor.porta}$caminho'),
        );
        r.headers.set('X-E2E-Token', 'segredo');
        r.write(corpo);
        final resp = await r.close();
        await resp.drain<void>();
        return resp.statusCode;
      }

      expect(await chamar('POST', '/barreira', 'não é json'), 400);
      expect(
        await chamar(
          'POST',
          '/barreira',
          '{"nome":"x","ciclo":1,"papel":"motorista"}',
        ),
        400,
      );
      expect(await chamar('POST', '/barreira', 'x' * 5000), 400);
      expect(await chamar('POST', '/nada', '{}'), 404);
    });

    test('coordenador fora do ar vira CoordenadorInalcancavel', () async {
      final porta = servidor.porta;
      await servidor.parar();
      final c = ClienteCoordenacao(
        papel: Papel.motorista,
        host: '127.0.0.1',
        porta: porta,
        token: 'segredo',
      );
      await expectLater(c.estado(), throwsA(isA<CoordenadorInalcancavel>()));
    });
  });
}
