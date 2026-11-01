import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/config.dart';
import '../../../tool/e2e/src/preparo.dart';
import 'support/fake_adb.dart';
import 'support/relogio_falso.dart';

const _mot = 'emulator-5554';
const _pax = 'emulator-5556';
final _pub = 'ab' * 32;

FakeAdb _adbComDoisEmuladores({String api = '34', String abi = 'x86_64'}) {
  final adb = FakeAdb(relogio: RelogioFalso());
  adb.seriais = [_mot, _pax];
  adb.avds[_mot] = avdMotorista;
  adb.avds[_pax] = avdPassageiro;
  for (final s in [_mot, _pax]) {
    adb.propriedades[s] = {
      'ro.build.version.sdk': api,
      'ro.product.cpu.abi': abi,
      'ro.product.model': 'sdk_gphone64_x86_64',
    };
  }
  return adb;
}

void main() {
  group('verificarEmuladores', () {
    test('aceita dois emuladores com os AVDs, API 34 e x86_64', () async {
      final ambiente = await verificarEmuladores(_adbComDoisEmuladores());
      expect(ambiente.serialMotorista, _mot);
      expect(ambiente.serialPassageiro, _pax);
      expect(ambiente.descricao['api'], '34');
      expect(ambiente.descricao['relays'], relaysDoRoteiro);
    });

    test('mapeia pelo nome do AVD, não pela ordem dos seriais', () async {
      final adb = _adbComDoisEmuladores()..seriais = [_pax, _mot];
      final ambiente = await verificarEmuladores(adb);
      expect(ambiente.serialMotorista, _mot);
    });

    test('recusa com um só emulador', () async {
      final adb = _adbComDoisEmuladores()..seriais = [_mot];
      expect(verificarEmuladores(adb), throwsA(isA<PreCondicaoFalha>()));
    });

    test(
      'recusa AVD inesperado, API diferente de 34 e ABI diferente',
      () async {
        final outroAvd = _adbComDoisEmuladores()..avds[_pax] = 'Outro_AVD';
        expect(verificarEmuladores(outroAvd), throwsA(isA<PreCondicaoFalha>()));
        expect(
          verificarEmuladores(_adbComDoisEmuladores(api: '33')),
          throwsA(isA<PreCondicaoFalha>()),
        );
        expect(
          verificarEmuladores(_adbComDoisEmuladores(abi: 'arm64-v8a')),
          throwsA(isA<PreCondicaoFalha>()),
        );
      },
    );

    test('adb indisponível vira pré-condição não atendida', () async {
      final adb = _adbComDoisEmuladores()..falhaGeral = 'sem adb';
      expect(verificarEmuladores(adb), throwsA(isA<PreCondicaoFalha>()));
    });
  });

  test('limparEConceder: pm clear e depois as três permissões', () async {
    final adb = _adbComDoisEmuladores();
    await limparEConceder(adb, _mot, pacoteMotorista);
    expect(adb.chamadas.first, 'pm-clear:$_mot:$pacoteMotorista');
    expect(
      adb.chamadas.where((c) => c.startsWith('pm-grant')),
      hasLength(permissoesConcedidas.length),
    );
  });

  group('telas de configuração (só em memória)', () {
    late FakeAdb adb;
    late RelogioFalso relogio;

    setUp(() {
      relogio = RelogioFalso();
      adb = FakeAdb(relogio: relogio);
      adb.telas[_mot] = const [
        ElementoFake('Mapa', clicavel: true),
        ElementoFake('Mais', clicavel: true),
      ];
    });

    void navegar({required String item, required List<ElementoFake> destino}) {
      adb.aoTocar = (serial, e, i) {
        if (e.rotulo == 'Mais') {
          adb.telas[serial] = [
            const ElementoFake('Mais'),
            ElementoFake(item, clicavel: true),
          ];
        } else if (e.rotulo == item) {
          adb.telas[serial] = destino;
        }
      };
      adb.aoTecla = (serial, codigo) {
        adb.telas[serial] = const [ElementoFake('Mapa', clicavel: true)];
      };
    }

    test('lê a chave pública sem captura nem salvar o dump', () async {
      navegar(
        item: 'Minha identidade',
        destino: [const ElementoFake('Chave pública'), ElementoFake(_pub)],
      );
      final chave = await lerChavePublica(adb, relogio, _mot);

      expect(chave, _pub);
      expect(adb.chamadas.where((c) => c.startsWith('captura')), isEmpty);
      expect(adb.chamadas, contains('tecla:$_mot:4'));
    });

    test('chave pública ausente na tela: pré-condição não atendida', () async {
      navegar(
        item: 'Minha identidade',
        destino: const [ElementoFake('Chave pública')],
      );
      expect(
        lerChavePublica(adb, relogio, _mot),
        throwsA(isA<PreCondicaoFalha>()),
      );
    });

    test('aceita a lista completa de três relays', () async {
      navegar(
        item: 'Relays',
        destino: [
          const ElementoFake('Servidores por onde o app se comunica'),
          for (final u in relaysEsperados) ElementoFake(u),
        ],
      );
      await conferirRelays(adb, relogio, _mot);
      expect(adb.chamadas.where((c) => c.startsWith('captura')), isEmpty);
    });

    test('recusa lista reduzida a um relay', () async {
      navegar(
        item: 'Relays',
        destino: const [
          ElementoFake('Servidores por onde o app se comunica'),
          ElementoFake('wss://nos.lol'),
        ],
      );
      expect(
        conferirRelays(adb, relogio, _mot),
        throwsA(isA<PreCondicaoFalha>()),
      );
    });

    test('recusa lista com relay a mais ou diferente', () async {
      navegar(
        item: 'Relays',
        destino: [
          const ElementoFake('Servidores por onde o app se comunica'),
          for (final u in relaysEsperados) ElementoFake(u),
          const ElementoFake('wss://outro.relay'),
        ],
      );
      expect(
        conferirRelays(adb, relogio, _mot),
        throwsA(isA<PreCondicaoFalha>()),
      );
    });
  });
}
