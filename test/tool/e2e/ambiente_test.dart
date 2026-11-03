import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/ambiente.dart';
import '../../../tool/e2e/src/preparo.dart';
import 'support/fake_adb.dart';
import 'support/relogio_falso.dart';

/// Sistema dublê: `adb devices` reflete os emuladores "iniciados" e cada
/// comando fica registrado.
class SistemaFalso implements Sistema {
  SistemaFalso(this.adb);

  final FakeAdb adb;
  final List<String> comandos = [];
  final Set<String> arquivos = {};
  final Map<String, int> saidas = {};
  final List<String> avdsParaSubir = [];
  bool emuladorNuncaAparece = false;
  bool bootNuncaTermina = false;
  var _proximaPorta = 5554;

  /// Leituras de `MemAvailable`, uma por consulta; a última se repete. Vazio ⇒
  /// memória sobrando.
  final List<int?> memorias = [];
  int consultasDeMemoria = 0;

  @override
  Future<ProcessResult> rodar(
    String executavel,
    List<String> args, {
    String? diretorio,
    required Duration timeout,
  }) async {
    final linha = '$executavel ${args.join(' ')}';
    comandos.add(diretorio == null ? linha : '$linha @ $diretorio');
    if (args.first == 'devices') {
      final saida = StringBuffer('List of devices attached\n');
      for (final s in adb.seriais) {
        saida.writeln('$s\tdevice');
      }
      return ProcessResult(0, 0, saida.toString(), '');
    }
    final codigo = saidas[executavel] ?? 0;
    final ok = args.contains('install') ? 'Success\n' : '';
    return ProcessResult(0, codigo, codigo == 0 ? ok : '', 'erro de teste');
  }

  @override
  Future<void> iniciarDestacado(String executavel, List<String> args) async {
    comandos.add('$executavel ${args.join(' ')}');
    if (emuladorNuncaAparece) return;
    while (adb.seriais.contains('emulator-$_proximaPorta')) {
      _proximaPorta += 2;
    }
    final serial = 'emulator-$_proximaPorta';
    adb.seriais = [...adb.seriais, serial];
    adb.avds[serial] = args[args.indexOf('-avd') + 1];
    adb.propriedades[serial] = {
      'sys.boot_completed': bootNuncaTermina ? '' : '1',
    };
    avdsParaSubir.add(args[args.indexOf('-avd') + 1]);
  }

  @override
  bool arquivoExiste(String caminho) => arquivos.contains(caminho);

  @override
  Future<int?> memoriaDisponivelMiB() async {
    final i = consultasDeMemoria++;
    if (memorias.isEmpty) return 8000;
    return memorias[i < memorias.length ? i : memorias.length - 1];
  }
}

void main() {
  late RelogioFalso relogio;
  late FakeAdb adb;
  late SistemaFalso sistema;
  late List<String> log;

  late List<String> desvios;

  PreparoAmbiente preparo({bool semJanela = false}) => PreparoAmbiente(
    sistema: sistema,
    adb: adb,
    relogio: relogio,
    emulator: '/sdk/emulator/emulator',
    log: log.add,
    semJanela: semJanela,
    memoriaMinimaMiB: 3000,
    desvio: desvios.add,
  );

  setUp(() {
    relogio = RelogioFalso();
    adb = FakeAdb(relogio: relogio);
    sistema = SistemaFalso(adb);
    log = [];
    desvios = [];
  });

  group('subirEmuladores', () {
    test('inicia os dois AVDs, um de cada vez, e devolve os seriais', () async {
      final s = await preparo().subirEmuladores(
        avdMotorista: 'AVD_A',
        avdPassageiro: 'AVD_B',
      );
      expect(sistema.avdsParaSubir, ['AVD_A', 'AVD_B']);
      expect(s.motorista, 'emulator-5554');
      expect(s.passageiro, 'emulator-5556');
      expect(
        sistema.comandos.where((c) => c.contains('-avd AVD_A')).single,
        contains('-no-snapshot-save'),
      );
      expect(sistema.comandos.where((c) => c.contains('-no-window')), isEmpty);
    });

    test('--sem-janela acrescenta -no-window', () async {
      await preparo(semJanela: true)
          .subirEmuladores(avdMotorista: 'AVD_A', avdPassageiro: 'AVD_B');
      expect(
        sistema.comandos.where((c) => c.contains('-no-window')),
        hasLength(2),
      );
    });

    test('reaproveita o que já está online e sobe só o que falta', () async {
      adb.seriais = ['emulator-5554'];
      adb.avds['emulator-5554'] = 'AVD_A';
      adb.propriedades['emulator-5554'] = {'sys.boot_completed': '1'};
      final s = await preparo().subirEmuladores(
        avdMotorista: 'AVD_A',
        avdPassageiro: 'AVD_B',
      );
      expect(sistema.avdsParaSubir, ['AVD_B']);
      expect(s.motorista, 'emulator-5554');
      expect(s.passageiro, isNot('emulator-5554'));
    });

    test('recusa se o emulador nunca aparece no adb', () async {
      sistema.emuladorNuncaAparece = true;
      await expectLater(
        preparo().subirEmuladores(
          avdMotorista: 'AVD_A',
          avdPassageiro: 'AVD_B',
        ),
        throwsA(
          isA<PreCondicaoFalha>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('não apareceu'),
          ),
        ),
      );
    });

    test('recusa se o sistema não termina de iniciar', () async {
      sistema.bootNuncaTermina = true;
      await expectLater(
        preparo().subirEmuladores(
          avdMotorista: 'AVD_A',
          avdPassageiro: 'AVD_B',
        ),
        throwsA(
          isA<PreCondicaoFalha>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('não terminou de iniciar'),
          ),
        ),
      );
    });
  });

  group('um emulador por máquina', () {
    test('sobe só o AVD pedido', () async {
      final serial = await preparo().subirEmulador(avd: 'AVD_B');
      expect(sistema.avdsParaSubir, ['AVD_B']);
      expect(adb.avds[serial], 'AVD_B');
    });

    test('reinicia só o seu emulador, a frio e sem apagar dados', () async {
      final p = preparo();
      final serial = await p.subirEmulador(avd: 'AVD_A');
      sistema.comandos.clear();
      sistema.avdsParaSubir.clear();
      adb.chamadas.clear();

      final novo = await p.reiniciarEmulador(avd: 'AVD_A', serial: serial);

      expect(adb.chamadas, ['desligar:$serial']);
      expect(sistema.avdsParaSubir, ['AVD_A']);
      final subida = sistema.comandos.singleWhere((c) => c.contains('-avd'));
      expect(subida, contains('-no-snapshot'));
      expect(subida, isNot(contains('-wipe-data')));
      expect(adb.avds[novo], 'AVD_A');
    });
  });

  group('reiniciarEmuladores', () {
    Future<({String motorista, String passageiro})> reiniciar() async {
      final p = preparo();
      final s = await p.subirEmuladores(
        avdMotorista: 'AVD_A',
        avdPassageiro: 'AVD_B',
      );
      sistema.comandos.clear();
      sistema.avdsParaSubir.clear();
      adb.chamadas.clear();
      log.clear();
      return p.reiniciarEmuladores(
        avdMotorista: 'AVD_A',
        avdPassageiro: 'AVD_B',
        serialMotorista: s.motorista,
        serialPassageiro: s.passageiro,
      );
    }

    test('desliga os dois, espera a memória e sobe os dois a frio', () async {
      sistema.memorias.addAll([1000, 2000, 3500]);
      final s = await reiniciar();

      expect(adb.chamadas, [
        'desligar:emulator-5554',
        'desligar:emulator-5556',
      ]);
      expect(sistema.consultasDeMemoria, greaterThanOrEqualTo(3));
      expect(sistema.avdsParaSubir, ['AVD_A', 'AVD_B']);
      final subidas = sistema.comandos.where((c) => c.contains('-avd'));
      expect(subidas, hasLength(2));
      for (final c in subidas) {
        expect(c, contains('-no-snapshot'));
        expect(c, isNot(contains('-no-snapshot-save')));
        expect(c, isNot(contains('-wipe-data')));
      }
      // Os seriais podem mudar: o dublê sempre dá a próxima porta.
      expect(adb.avds[s.motorista], 'AVD_A');
      expect(adb.avds[s.passageiro], 'AVD_B');
      expect(adb.seriais, [s.motorista, s.passageiro]);
      expect(desvios, isEmpty);
    });

    test('a memória só é conferida depois que os emuladores sumiram', () async {
      await reiniciar();
      expect(
        log.indexWhere((l) => l.startsWith('desligando')),
        lessThan(log.indexWhere((l) => l.startsWith('memória disponível'))),
      );
    });

    test('memória que não volta: sobe mesmo assim e registra desvio', () async {
      sistema.memorias.add(500);
      final s = await reiniciar();

      expect(s.motorista, isNotEmpty);
      expect(sistema.avdsParaSubir, ['AVD_A', 'AVD_B']);
      expect(desvios, hasLength(1));
      expect(desvios.single, contains('500 MiB'));
    });

    test('memória que o sistema não informa não atrasa o reinício', () async {
      sistema.memorias.add(null);
      await reiniciar();
      expect(sistema.consultasDeMemoria, 1);
      expect(desvios, isEmpty);
    });

    test('sem efeito do reboot -p, recorre ao emu kill', () async {
      adb.desligarSemEfeito = true;
      final s = await reiniciar();

      expect(adb.chamadas, [
        'desligar:emulator-5554',
        'desligar:emulator-5556',
        'emu-kill:emulator-5554',
        'emu-kill:emulator-5556',
      ]);
      expect(s.passageiro, isNotEmpty);
    });

    test('emulador que não sai do adb nem com emu kill: recusa', () async {
      adb.desligarSemEfeito = true;
      adb.emuKillSemEfeito = true;
      await expectLater(
        reiniciar(),
        throwsA(
          isA<PreCondicaoFalha>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('continuam no adb'),
          ),
        ),
      );
      expect(sistema.avdsParaSubir, isEmpty);
    });

    test('emulador que não volta a subir: recusa', () async {
      final p = preparo();
      final s = await p.subirEmuladores(
        avdMotorista: 'AVD_A',
        avdPassageiro: 'AVD_B',
      );
      sistema.emuladorNuncaAparece = true;
      await expectLater(
        p.reiniciarEmuladores(
          avdMotorista: 'AVD_A',
          avdPassageiro: 'AVD_B',
          serialMotorista: s.motorista,
          serialPassageiro: s.passageiro,
        ),
        throwsA(
          isA<PreCondicaoFalha>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('não apareceu'),
          ),
        ),
      );
    });
  });

  test('parseMemAvailableMiB lê a linha MemAvailable do meminfo', () {
    const meminfo =
        'MemTotal:       14680064 kB\n'
        'MemFree:         8912344 kB\n'
        'MemAvailable:   11534336 kB\n'
        'Buffers:          123456 kB\n';
    expect(parseMemAvailableMiB(meminfo), 11264);
    expect(parseMemAvailableMiB('MemTotal: 1 kB\n'), isNull);
    expect(parseMemAvailableMiB(''), isNull);
  });

  group('compilarEInstalar', () {
    const dir = '/repo/app';
    const apk = '$dir/build/app/outputs/flutter-apk/app-debug.apk';

    test('compila e instala o APK de depuração com -r', () async {
      sistema.arquivos.add(apk);
      await preparo().compilarEInstalar(
        rotulo: 'motorista',
        diretorio: dir,
        serial: 'emulator-5554',
      );
      expect(sistema.comandos, [
        'flutter build apk --debug @ $dir',
        'adb -s emulator-5554 install -r $apk',
      ]);
    });

    test('falha do build interrompe antes de instalar', () async {
      sistema.saidas['flutter'] = 1;
      await expectLater(
        preparo().compilarEInstalar(
          rotulo: 'motorista',
          diretorio: dir,
          serial: 'emulator-5554',
        ),
        throwsA(isA<PreCondicaoFalha>()),
      );
      expect(sistema.comandos.where((c) => c.contains('install')), isEmpty);
    });

    test('APK ausente depois do build é recusado', () async {
      await expectLater(
        preparo().compilarEInstalar(
          rotulo: 'passageiro',
          diretorio: dir,
          serial: 'emulator-5554',
        ),
        throwsA(
          isA<PreCondicaoFalha>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('APK do passageiro'),
          ),
        ),
      );
    });

    test('falha do adb install é recusada', () async {
      sistema.arquivos.add(apk);
      sistema.saidas['adb'] = 1;
      await expectLater(
        preparo().compilarEInstalar(
          rotulo: 'motorista',
          diretorio: dir,
          serial: 'emulator-5554',
        ),
        throwsA(isA<PreCondicaoFalha>()),
      );
    });
  });

  group('auxiliares', () {
    test('parseSeriais lê qualquer estado e ignora o cabeçalho', () {
      expect(
        parseSeriais(
          'List of devices attached\n'
          'emulator-5554\toffline\n'
          'emulator-5556\tdevice\n\n',
        ),
        {'emulator-5554', 'emulator-5556'},
      );
    });

    test('localizarEmulator usa o SDK que existir, ou o PATH', () {
      sistema.arquivos.add('/home/u/Android/Sdk/emulator/emulator');
      expect(
        localizarEmulator({'HOME': '/home/u'}, sistema),
        '/home/u/Android/Sdk/emulator/emulator',
      );
      expect(localizarEmulator({}, sistema), 'emulator');
    });
  });
}
