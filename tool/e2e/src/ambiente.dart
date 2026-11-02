import 'dart:convert';
import 'dart:io';

import 'adb.dart';
import 'preparo.dart';
import 'relogio.dart';
import 'ui.dart';

/// Preparo do ambiente da execução: sobe os dois emuladores e instala os apps
/// do motorista e do passageiro. Só mexe em processos do hospedeiro (emulador,
/// `flutter build`, `adb install`); não apaga dados nem abre telas dos apps, o
/// que continua sendo do preparo em `preparo.dart`.

/// Acesso aos processos do hospedeiro. Interface porque o teste usa um dublê e a
/// execução real, [SistemaReal].
abstract interface class Sistema {
  Future<ProcessResult> rodar(
    String executavel,
    List<String> args, {
    String? diretorio,
    required Duration timeout,
  });

  /// Inicia [executavel] desligado deste processo (o emulador segue vivo depois
  /// que o roteiro termina) e sem ler a saída.
  Future<void> iniciarDestacado(String executavel, List<String> args);

  bool arquivoExiste(String caminho);
}

class SistemaReal implements Sistema {
  const SistemaReal();

  @override
  Future<ProcessResult> rodar(
    String executavel,
    List<String> args, {
    String? diretorio,
    required Duration timeout,
  }) async {
    try {
      return await Process.run(
        executavel,
        args,
        workingDirectory: diretorio,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
    } on ProcessException catch (e) {
      throw PreCondicaoFalha(
        'não foi possível executar $executavel: ${e.message}',
      );
    } on Exception catch (e) {
      // TimeoutException e afins.
      throw PreCondicaoFalha('$executavel ${args.take(2).join(' ')}: $e');
    }
  }

  @override
  Future<void> iniciarDestacado(String executavel, List<String> args) async {
    try {
      await Process.start(executavel, args, mode: ProcessStartMode.detached);
    } on ProcessException catch (e) {
      throw PreCondicaoFalha(
        'não foi possível executar $executavel: ${e.message}',
      );
    }
  }

  @override
  bool arquivoExiste(String caminho) => File(caminho).existsSync();
}

/// Caminho do binário `emulator`: `ANDROID_HOME`, `ANDROID_SDK_ROOT` e
/// `~/Android/Sdk`, nesta ordem; se nenhum existir, confia no `PATH`.
String localizarEmulator(Map<String, String> env, Sistema sistema) {
  final home = env['HOME'];
  final candidatos = [
    env['ANDROID_HOME'],
    env['ANDROID_SDK_ROOT'],
    if (home != null) '$home/Android/Sdk',
  ];
  for (final sdk in candidatos) {
    if (sdk == null || sdk.isEmpty) continue;
    final caminho = '$sdk/emulator/emulator';
    if (sistema.arquivoExiste(caminho)) return caminho;
  }
  return 'emulator';
}

/// Seriais de `adb devices` em qualquer estado (`offline` e `unauthorized`
/// também), que é como o emulador aparece logo depois de iniciar.
Set<String> parseSeriais(String saida) => {
  for (final linha in const LineSplitter().convert(saida).skip(1))
    if (linha.trim().isNotEmpty && linha.contains('\t'))
      linha.split(RegExp(r'\s+')).first,
};

class PreparoAmbiente {
  PreparoAmbiente({
    required this.sistema,
    required this.adb,
    required this.relogio,
    required this.emulator,
    required this.log,
    this.semJanela = false,
    this.adbExecutavel = 'adb',
    this.flutter = 'flutter',
    this.esperaSurgir = const Duration(seconds: 90),
    this.esperaBoot = const Duration(minutes: 5),
    this.esperaBuild = const Duration(minutes: 20),
    this.esperaInstalar = const Duration(minutes: 3),
  });

  final Sistema sistema;
  final Adb adb;
  final Relogio relogio;
  final String emulator;
  final void Function(String) log;
  final bool semJanela;
  final String adbExecutavel;
  final String flutter;
  final Duration esperaSurgir;
  final Duration esperaBoot;
  final Duration esperaBuild;
  final Duration esperaInstalar;

  Future<Set<String>> _todosOsSeriais() async {
    final r = await sistema.rodar(adbExecutavel, [
      'devices',
    ], timeout: const Duration(seconds: 30));
    return parseSeriais(r.stdout as String);
  }

  Future<String?> _avdDe(String serial) async {
    try {
      return await adb.nomeAvd(serial);
    } on AdbFalha {
      return null; // ainda subindo
    }
  }

  /// AVD → serial dos emuladores já em estado `device`.
  Future<Map<String, String>> _online() async {
    final mapa = <String, String>{};
    for (final s in await adb.dispositivos()) {
      final nome = await _avdDe(s);
      if (nome != null) mapa[nome] = s;
    }
    return mapa;
  }

  Future<bool> _bootCompleto(String serial) async {
    try {
      return await adb.propriedade(serial, 'sys.boot_completed') == '1';
    } on AdbFalha {
      return false;
    }
  }

  /// Garante os dois emuladores de pé e com o sistema iniciado; devolve os
  /// seriais (motorista, passageiro). Os que já estão online são reaproveitados.
  Future<({String motorista, String passageiro})> subirEmuladores({
    required String avdMotorista,
    required String avdPassageiro,
  }) async {
    await sistema.rodar(adbExecutavel, [
      'start-server',
    ], timeout: const Duration(seconds: 30));

    final seriais = <String, String>{};
    for (final avd in [avdMotorista, avdPassageiro]) {
      final online = await _online();
      var serial = online[avd];
      if (serial != null) {
        log('emulador $avd já está online ($serial)');
      } else {
        // Um de cada vez: dois emuladores iniciados juntos disputam as portas.
        final antes = await _todosOsSeriais();
        log('iniciando o emulador $avd');
        await sistema.iniciarDestacado(emulator, [
          '-avd',
          avd,
          '-no-snapshot-save',
          '-no-boot-anim',
          if (semJanela) '-no-window',
        ]);
        serial = await esperarCondicao<String>(relogio, () async {
          final novos = (await _todosOsSeriais()).difference(antes);
          return novos.isEmpty ? null : novos.first;
        }, timeout: esperaSurgir);
        if (serial == null) {
          throw PreCondicaoFalha(
            'o emulador $avd não apareceu no adb em ${esperaSurgir.inSeconds} s '
            '($emulator)',
          );
        }
      }
      final pronto = await esperarCondicao<bool>(
        relogio,
        () async {
          return await _bootCompleto(serial!) ? true : null;
        },
        timeout: esperaBoot,
        intervalo: const Duration(seconds: 3),
      );
      if (pronto == null) {
        throw PreCondicaoFalha(
          'o emulador $avd ($serial) não terminou de iniciar em '
          '${esperaBoot.inMinutes} min',
        );
      }
      final nome = await _avdDe(serial);
      if (nome != avd) {
        throw PreCondicaoFalha(
          'o dispositivo $serial é o AVD "$nome", e não "$avd"',
        );
      }
      seriais[avd] = serial;
      log('emulador $avd pronto ($serial)');
    }
    return (
      motorista: seriais[avdMotorista]!,
      passageiro: seriais[avdPassageiro]!,
    );
  }

  /// Compila o APK de depuração de [diretorio] e instala em [serial] (`-r`
  /// preserva os dados; o `pm clear` do preparo é quem os apaga).
  Future<void> compilarEInstalar({
    required String rotulo,
    required String diretorio,
    required String serial,
  }) async {
    log('compilando o app do $rotulo (flutter build apk --debug)');
    final build = await sistema.rodar(
      flutter,
      ['build', 'apk', '--debug'],
      diretorio: diretorio,
      timeout: esperaBuild,
    );
    if (build.exitCode != 0) {
      throw PreCondicaoFalha(
        'flutter build do $rotulo falhou (saída ${build.exitCode}):\n'
        '${_final(build)}',
      );
    }
    final apk = '$diretorio/build/app/outputs/flutter-apk/app-debug.apk';
    if (!sistema.arquivoExiste(apk)) {
      throw PreCondicaoFalha('APK do $rotulo não encontrado em $apk');
    }
    log('instalando o app do $rotulo em $serial');
    final inst = await sistema.rodar(adbExecutavel, [
      '-s',
      serial,
      'install',
      '-r',
      apk,
    ], timeout: esperaInstalar);
    if (inst.exitCode != 0 || !(inst.stdout as String).contains('Success')) {
      throw PreCondicaoFalha(
        'adb install do $rotulo falhou (saída ${inst.exitCode}):\n'
        '${_final(inst)}',
      );
    }
  }

  static String _final(ProcessResult r) {
    final linhas = const LineSplitter().convert('${r.stdout}\n${r.stderr}')
      ..removeWhere((l) => l.trim().isEmpty);
    return linhas.skip(linhas.length > 12 ? linhas.length - 12 : 0).join('\n');
  }
}
