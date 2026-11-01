import 'dart:io';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/services/event_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/ciclo.dart';
import '../../../tool/e2e/src/config.dart';
import '../../../tool/e2e/src/evidencia.dart';
import '../../../tool/e2e/src/latencia.dart';
import '../../../tool/e2e/src/observador.dart';
import '../../support/fake_relay_transport.dart';
import 'support/fake_adb.dart';
import 'support/relogio_falso.dart';
import 'support/simulador_corrida.dart';

class _LimitesCurtos extends Limites {
  const _LimitesCurtos();

  @override
  Duration get ciclo => const Duration(seconds: 1);
}

const _mot = 'emulator-5554';
const _pax = 'emulator-5556';

void main() {
  late RelogioFalso relogio;
  late FakeAdb adb;
  late FakeRelayTransport transporte;
  late nostr.NostrKeyPairs motorista;
  late nostr.NostrKeyPairs passageiro;
  late Observador observador;
  late Directory pasta;
  late SimuladorCorrida sim;
  late Set<String> telas;

  ExecutorCiclo montar({Limites limites = const Limites()}) {
    final ctx = ContextoCiclo(
      adb: adb,
      serialMotorista: _mot,
      serialPassageiro: _pax,
      observador: observador,
      evidencia: Evidencia(
        adb: adb,
        pasta: Directory('${pasta.path}/capturas'),
      ),
      relogio: relogio,
      periodo: 'ensaio',
      limites: limites,
      telasCapturadas: telas,
    );
    return ExecutorCiclo(ctx);
  }

  setUp(() async {
    relogio = RelogioFalso();
    adb = FakeAdb(relogio: relogio);
    transporte = FakeRelayTransport();
    motorista = nostr.Nostr.instance.services.keys.generateKeyPair();
    passageiro = nostr.Nostr.instance.services.keys.generateKeyPair();
    observador = Observador(
      transport: transporte,
      verifier: const NostrEventVerifier(),
      identidades: Identidades(
        motorista: motorista.public,
        passageiro: passageiro.public,
      ),
      relogio: relogio,
    );
    await observador.iniciar();
    pasta = Directory.systemTemp.createTempSync('ciclo_');
    telas = {};
    sim = SimuladorCorrida(
      adb: adb,
      transporte: transporte,
      serialMot: _mot,
      serialPax: _pax,
      motorista: motorista,
      passageiro: passageiro,
      relogio: relogio,
    )..iniciar();
  });

  tearDown(() => pasta.deleteSync(recursive: true));

  test(
    'ciclo feliz: E01–E12 e R ok, ações registradas, 6 telas × 2 capturadas',
    () async {
      final r = await montar().executar(1);
      final c = r.ciclo;

      expect(c.resultado, 'sucesso');
      expect(c.valido, isTrue);
      expect(c.origem, isNull);
      expect(c.etapas.map((e) => e.id), [
        for (var i = 1; i <= 12; i++) 'E${i.toString().padLeft(2, '0')}',
        'R',
      ]);
      expect(c.etapas.every((e) => e.resultado == 'ok'), isTrue);

      final acoes = [for (final e in c.etapas) ...e.acoes];
      expect(acoes.map((a) => a.id), [
        'solicitar',
        'orcamento',
        'aceitar',
        'chegada-origem',
        'confirmar-encontro',
        'chegada-destino',
        'confirmar-destino',
        'avaliacao-motorista',
        'avaliacao-passageiro',
      ]);
      expect(acoes.where((a) => a.tipo == 'posicionamento').map((a) => a.id), [
        'chegada-origem',
        'chegada-destino',
      ]);
      for (final a in acoes) {
        expect(a.fimUtc.isBefore(a.inicioUtc), isFalse);
      }

      final pngs = c.capturas.where((x) => x.endsWith('.png')).toList();
      expect(pngs, hasLength(12));
      for (final rotulo in const [
        'solicitacao-enviada',
        'orcamento-recebido',
        'motorista-a-caminho',
        'corrida-em-andamento',
        'corrida-encerrada',
        'avaliacao-concluida',
      ]) {
        expect(
          pngs.any((p) => p.contains('$rotulo-motorista')),
          isTrue,
          reason: rotulo,
        );
        expect(
          pngs.any((p) => p.contains('$rotulo-passageiro')),
          isTrue,
          reason: rotulo,
        );
      }
      expect(Directory('${pasta.path}/capturas').listSync(), hasLength(12));

      final latencias = calcularLatencias(
        c,
        observador.naJanela(c.inicioUtc, c.fimUtc),
      );
      expect(latencias.amostras, hasLength(9));
      expect(latencias.desvios, isEmpty);
    },
  );

  test('segundo ciclo não repete as capturas fixas', () async {
    final executor = montar();
    await executor.executar(1);
    final c2 = (await executor.executar(2)).ciclo;
    expect(
      c2.resultado,
      'sucesso',
      reason: '${c2.etapaFalha} ${c2.etapas.last.resultado}',
    );
    expect(c2.capturas, isEmpty);
  });

  test('o registro do ciclo não contém content nem chaves', () async {
    final c = (await montar().executar(1)).ciclo;
    final texto = c.toJson().toString();
    expect(texto.contains('SEGREDO'), isFalse);
    expect(texto.contains('content'), isFalse);
    expect(c.eventos, isNotEmpty);
  });

  test('timeout de etapa: falha registrada, origem relays, captura + dump dos dois', () async {
    sim.semEfeitoRemoto.add('orcamento');
    final r = await montar().executar(1);
    final c = r.ciclo;

    expect(c.resultado, 'falha');
    expect(c.etapaFalha, 'E04');
    expect(c.etapas.last.id, 'E04');
    expect(c.etapas.last.resultado, 'timeout');
    expect(c.origem, 'relays');
    expect(c.valido, isTrue);
    final falha = c.capturas.where((x) => x.contains('E04-falha')).toList();
    expect(falha.where((x) => x.endsWith('.png')), hasLength(2));
    expect(falha.where((x) => x.endsWith('.xml')), hasLength(2));
  });

  test('ação feita e evento em nenhum relay: aplicativo, origem_bruta indeterminada', () async {
    sim.semEfeitoRemoto.add('orcamento');
    sim.naoPublicar.add(20002);
    final c = (await montar().executar(1)).ciclo;

    expect(c.origem, 'aplicativo');
    expect(c.origemBruta, 'indeterminada');
    expect(c.valido, isTrue);
  });

  test('falha do Photon: serviço externo, ciclo não é válido', () async {
    sim.photonFalha = true;
    final c = (await montar().executar(1)).ciclo;

    expect(c.etapaFalha, 'E02');
    expect(c.origem, 'servico_externo');
    expect(c.servicoExterno, 'Photon');
    expect(c.valido, isFalse);
    expect(c.sinalExterno, {'fonte': 'ui', 'servico': 'Photon', 'http': null});
  });

  test(
    '429 da OpenRouteService no logcat: externo e fim controlado do período',
    () async {
      sim.semBotaoDeOrcamento = true;
      final original = adb.aoTocar;
      adb.aoTocar = (serial, e, i) {
        original!(serial, e, i);
        if (e.rotulo == 'Solicitar corrida') {
          adb.logs[_mot] = [
            'I/flutter ( 1): Distância motorista→origem falhou: 429',
          ];
        }
      };
      final r = await montar().executar(1);

      expect(r.ciclo.etapaFalha, 'E04');
      expect(r.ciclo.origem, 'servico_externo');
      expect(r.ciclo.servicoExterno, 'OpenRouteService');
      expect(r.limiteDiarioOrs, isTrue);
      expect(r.ciclo.valido, isFalse);
      expect(
        r.ciclo.toJson().toString().contains('Distância motorista'),
        isFalse,
      );
    },
  );

  test('adb indisponível no meio: ambiente de teste, sem capturas', () async {
    final original = adb.aoTocar;
    adb.aoTocar = (serial, e, i) {
      original!(serial, e, i);
      if (e.rotulo == 'Solicitar corrida') {
        adb.falhaGeral = 'dispositivo offline';
      }
    };
    final c = (await montar().executar(1)).ciclo;

    expect(c.origem, 'ambiente_teste');
    expect(c.valido, isTrue);
    expect(c.capturas, isEmpty);
  });

  test('observador sem nenhum relay: ambiente de teste', () async {
    final t = FakeRelayTransport();
    for (final u in relaysDoRoteiro) {
      t.failOn(u);
    }
    observador = Observador(
      transport: t,
      verifier: const NostrEventVerifier(),
      identidades: Identidades(
        motorista: motorista.public,
        passageiro: passageiro.public,
      ),
      relogio: relogio,
    );
    await observador.iniciar();
    sim.semEfeitoRemoto.add('solicitar');
    final c = (await montar().executar(1)).ciclo;

    expect(c.etapaFalha, 'E03');
    expect(c.origem, 'ambiente_teste');
  });

  test(
    'o tempo máximo do ciclo vira falha de etapa e o roteiro segue',
    () async {
      final executor = montar(limites: const _LimitesCurtos());
      final c = (await executor.executar(1)).ciclo;

      expect(c.resultado, 'falha');
      expect(c.etapas.last.resultado, 'timeout');
      final proximo = await montar().executar(2);
      expect(proximo.ciclo.ciclo, 2);
    },
  );

  test('falha no meio da corrida: recuperação por cancelamento fora da janela do ciclo', () async {
    sim.semEfeitoRemoto.add('aceitar');
    final r = await montar().executar(1);

    expect(r.ciclo.etapaFalha, 'E05');
    expect(r.recuperacaoFalhou, isFalse);
    expect(sim.publicados, anyOf(contains(20012), contains(20013)));
    expect(r.ciclo.anomalias, isEmpty);

    // E o próximo ciclo parte do estado inicial.
    sim.semEfeitoRemoto.clear();
    final c2 = (await montar().executar(2)).ciclo;
    expect(c2.resultado, 'sucesso');
  });

  test('recuperação que não consegue limpar os apps é informada', () async {
    sim.semEfeitoRemoto.add('aceitar');
    final original = adb.aoTocar;
    adb.aoTocar = (serial, e, i) {
      if (e.rotulo == 'Cancelar corrida') return; // o cancelar não faz nada
      original!(serial, e, i);
    };
    final r = await montar().executar(1);
    expect(r.recuperacaoFalhou, isTrue);
  });

  test('tela sensível no momento da falha: captura omitida', () async {
    sim.semEfeitoRemoto.add('orcamento');
    final original = adb.aoTocar;
    adb.aoTocar = (serial, e, i) {
      original!(serial, e, i);
      if (e.rotulo == 'Enviar orçamento') {
        adb.telas[_pax] = const [
          ElementoFake('Minha identidade'),
          ElementoFake('Chave pública'),
        ];
      }
    };
    final c = (await montar().executar(1)).ciclo;

    final paxFalha = c.capturas.where(
      (x) => x.contains('E04-falha-passageiro'),
    );
    expect(paxFalha.single, contains('omitida'));
    expect(paxFalha.any((x) => x.endsWith('.png')), isFalse);
  });

  test('orçamento do período esgotado no meio: ciclo interrompido, não válido, sem classificar', () async {
    final executor = montar();
    // O orçamento acaba logo depois do início: a primeira espera longa o detecta.
    executor.ctx.prazoGlobal = relogio.agora().add(const Duration(seconds: 2));
    sim.semEfeitoRemoto.add('solicitar');
    final r = await executor.executar(1);

    expect(r.ciclo.resultado, 'interrompido');
    expect(r.ciclo.valido, isFalse);
    expect(r.ciclo.origem, isNull);
    expect(r.ciclo.capturas.where((x) => x.contains('falha')), isEmpty);
    expect(r.recuperacaoFalhou, isFalse);
  });

  test(
    'pedido de parada antes do ciclo: interrompido já na primeira etapa',
    () async {
      final executor = montar();
      executor.ctx.prazoGlobal = relogio.agora();
      final r = await executor.executar(1);
      expect(r.ciclo.resultado, 'interrompido');
      expect(r.ciclo.etapas.single.resultado, 'interrompido');
    },
  );
}
