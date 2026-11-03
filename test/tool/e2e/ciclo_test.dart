import 'dart:io';

import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/services/event_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/ciclo.dart';
import '../../../tool/e2e/src/config.dart';
import '../../../tool/e2e/src/coordenacao.dart';
import '../../../tool/e2e/src/evidencia.dart';
import '../../../tool/e2e/src/latencia.dart';
import '../../../tool/e2e/src/observador.dart';
import '../../../tool/e2e/src/opcoes.dart' show Papel;
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

  ExecutorCiclo montar({
    Limites limites = const Limites(),
    Papel? papel,
    Coordenacao? coordenacao,
  }) {
    final ctx = ContextoCiclo(
      adb: adb,
      serialMotorista: papel == Papel.passageiro ? '' : _mot,
      serialPassageiro: papel == Papel.motorista ? '' : _pax,
      papel: papel,
      coordenacao: coordenacao,
      observador: observador,
      evidencia: Evidencia(
        adb: adb,
        pasta: Directory('${pasta.path}/capturas'),
      ),
      relogio: relogio,
      limites: limites,
      telasCapturadas: papel == null ? telas : <String>{},
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
    'duas máquinas: um executor por papel completa o ciclo, cada um só no seu '
    'emulador',
    () async {
      final rs = await Future.wait([
        montar(papel: Papel.motorista).executar(1),
        montar(papel: Papel.passageiro).executar(1),
      ]);
      final mot = rs[0].ciclo;
      final pax = rs[1].ciclo;

      expect(mot.resultado, 'sucesso', reason: '${mot.etapaFalha}');
      expect(pax.resultado, 'sucesso', reason: '${pax.etapaFalha}');
      for (final c in [mot, pax]) {
        expect(c.etapas.map((e) => e.id), [
          for (var i = 1; i <= 12; i++) 'E${i.toString().padLeft(2, '0')}',
          'R',
        ]);
      }
      expect(
        [for (final e in mot.etapas) ...e.acoes.map((a) => a.id)],
        [
          'orcamento',
          'chegada-origem',
          'chegada-destino',
          'avaliacao-motorista',
        ],
      );
      expect(
        [for (final e in pax.etapas) ...e.acoes.map((a) => a.id)],
        [
          'solicitar',
          'aceitar',
          'confirmar-encontro',
          'confirmar-destino',
          'avaliacao-passageiro',
        ],
      );
      expect(mot.capturas.every((x) => x.contains('motorista')), isTrue);
      expect(pax.capturas.every((x) => x.contains('passageiro')), isTrue);
    },
  );

  test('duas máquinas: o motorista para de esperar quando o passageiro já '
      'falhou, e a falha dele é só reflexo', () async {
    final nucleo = NucleoCoordenacao();
    nucleo.registrarFalha(1, Papel.passageiro, 'E01');

    final r = await montar(
      papel: Papel.motorista,
      coordenacao: CoordenacaoLocal(nucleo, Papel.motorista),
    ).executar(1);

    expect(r.ciclo.resultado, 'falha');
    expect(r.ciclo.etapaFalha, 'E01');
    expect(r.consequencia, isTrue);
    final e01 = r.ciclo.etapas.first;
    expect(
      e01.fimUtc.difference(e01.inicioUtc),
      lessThan(const Duration(seconds: 5)),
    );
    // Quem falha por reflexo não repete o aviso.
    expect(nucleo.falhaDoOutro(1, Papel.passageiro), isNull);
  });

  test('duas máquinas: quem falha avisa o outro lado', () async {
    final nucleo = NucleoCoordenacao();

    final r = await montar(
      papel: Papel.motorista,
      coordenacao: CoordenacaoLocal(nucleo, Papel.motorista),
    ).executar(1);

    expect(r.ciclo.resultado, 'falha');
    expect(r.consequencia, isFalse);
    expect(nucleo.falhaDoOutro(1, Papel.passageiro), r.ciclo.etapaFalha);
  });

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
      // 6 telas fixas dos dois apps + a tela do motorista antes e depois do
      // `geo fix` de chegada à origem.
      expect(pngs, hasLength(14));
      for (final rotulo in const [
        'chegada-origem-antes-motorista',
        'chegada-origem-depois-motorista',
      ]) {
        expect(pngs.any((p) => p.contains(rotulo)), isTrue, reason: rotulo);
      }
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
      expect(Directory('${pasta.path}/capturas').listSync(), hasLength(14));

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
    'E08 passa com o marcador do destino fora da tela do motorista',
    () async {
      sim.semMarcadorDeDestino = true;
      final r = await montar().executar(1);

      expect(r.ciclo.etapaFalha, isNull);
      expect(r.ciclo.resultado, 'sucesso');
    },
  );

  test(
    '429 da OpenRouteService no logcat: externo e fim controlado da execução',
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

  test('orçamento da execução esgotado no meio: ciclo interrompido, não válido, sem classificar', () async {
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

  test(
    'motorista offline: o roteiro liga o alternador (o texto não é clicável)',
    () async {
      sim.motoristaOffline = true;
      sim.iniciar();
      final c = (await montar().executar(1)).ciclo;

      expect(c.resultado, 'sucesso');
      expect(sim.ligadoPeloAlternador, 1);
    },
  );

  test('o destino é digitado só uma vez: no segundo ciclo o campo já vem preenchido', () async {
    final executor = montar();
    await executor.executar(1);
    await executor.executar(2);
    expect(adb.digitados, [destinoBusca]);
  });

  test('cada ciclo começa encerrando e abrindo os dois apps, antes de agir', () async {
    final executor = montar();
    await executor.executar(1);
    final fimDoCiclo1 = adb.chamadas.length;
    await executor.executar(2);

    for (final inicio in [0, fimDoCiclo1]) {
      final trecho = adb.chamadas.skip(inicio).toList();
      expect(trecho.take(4), [
        'parar:$_mot:$pacoteMotorista',
        'parar:$_pax:$pacotePassageiro',
        'iniciar:$_mot:$pacoteMotorista',
        'iniciar:$_pax:$pacotePassageiro',
      ]);
      // Nenhum toque nem posicionamento antes de os apps terem sido reabertos.
      final primeiraAcao = trecho.indexWhere(
        (c) => c.startsWith('toque:') || c.startsWith('geofix:'),
      );
      expect(primeiraAcao, greaterThan(3));
    }
    expect(adb.chamadas.where((c) => c.startsWith('parar:')), hasLength(4));
  });

  test(
    'app que reabre com uma corrida restaurada é devolvido ao mapa ocioso',
    () async {
      final executor = montar();
      await executor.executar(1);
      // O passageiro reabre com a corrida da execução anterior ainda gravada.
      final original = adb.aoTocar;
      sim.fase = Fase.aceita;
      adb.telas[_pax] = [
        const ElementoFake('Cancelar corrida', clicavel: true),
      ];
      adb.aoTocar = (serial, e, i) {
        if (serial == _pax && e.rotulo == 'Cancelar corrida') {
          adb.aoTocar = original;
          sim.iniciar();
          return;
        }
        original!(serial, e, i);
      };
      final r = await executor.executar(2);

      expect(r.ciclo.etapaFalha, isNull);
      expect(r.ciclo.resultado, 'sucesso');
    },
  );

  test(
    'falha do adb ao reiniciar os apps não lança; a etapa E01 a acusa',
    () async {
      adb.falhaGeral = 'adb offline';
      final r = await montar().executar(1);

      expect(r.ciclo.etapaFalha, 'E01');
    },
  );
}
