import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Falha de infraestrutura do `adb`: dispositivo ausente, comando sem resposta.
/// Vira falha de **ambiente de teste** na classificação (D9, regra 1).
class AdbFalha implements Exception {
  AdbFalha(this.mensagem);

  final String mensagem;

  @override
  String toString() => 'AdbFalha: $mensagem';
}

/// Operações de ADB usadas pelo roteiro. Interface porque o teste usa um dublê
/// (`test/tool/e2e/support/fake_adb.dart`) e a execução real, [AdbProcesso].
abstract interface class Adb {
  /// Seriais dos dispositivos no estado `device`.
  Future<List<String>> dispositivos();

  /// Nome do AVD (`adb -s S emu avd name`).
  Future<String> nomeAvd(String serial);

  /// Propriedade do sistema (`getprop`), por exemplo `ro.build.version.sdk`.
  Future<String> propriedade(String serial, String nome);

  /// Segundos desde a época segundo o relógio do emulador.
  Future<int> epochEmulador(String serial);

  Future<void> iniciarApp(String serial, String pacote);
  Future<bool> processoVivo(String serial, String pacote);
  Future<void> pmClear(String serial, String pacote);
  Future<void> pmGrant(String serial, String pacote, String permissao);

  Future<void> tocar(String serial, int x, int y);

  /// Digita [texto] (só ASCII; espaço vira `%s`).
  Future<void> digitar(String serial, String texto);
  Future<void> tecla(String serial, int codigo);

  /// Desliza do ponto (x1, y1) ao (x2, y2) em [duracaoMs] ms.
  Future<void> deslizar(
    String serial,
    int x1,
    int y1,
    int x2,
    int y2, {
    int duracaoMs = 300,
  });

  /// XML do `uiautomator dump`.
  Future<String> dump(String serial);

  /// PNG de `screencap -p`.
  Future<List<int>> captura(String serial);

  /// `adb emu geo fix`: **longitude antes de latitude**.
  Future<void> geoFix(String serial, double lat, double lon);

  /// Linhas do `logcat` (o chamador classifica; nunca grava as linhas brutas).
  Future<List<String>> logcat(String serial);

  /// Esvazia o buffer do `logcat` (`logcat -c`), no início de cada ciclo, para
  /// que os sinais lidos na falha sejam só os do ciclo.
  Future<void> limparLogcat(String serial);
}

class AdbProcesso implements Adb {
  AdbProcesso({
    this.executavel = 'adb',
    this.timeoutPadrao = const Duration(seconds: 30),
  });

  final String executavel;
  final Duration timeoutPadrao;

  Future<ProcessResult> _rodar(
    List<String> args, {
    bool binario = false,
  }) async {
    try {
      final r = await Process.run(
        executavel,
        args,
        stdoutEncoding: binario ? null : utf8,
        stderrEncoding: utf8,
      ).timeout(timeoutPadrao);
      if (r.exitCode != 0) {
        throw AdbFalha('adb ${args.take(3).join(' ')} saiu com ${r.exitCode}');
      }
      return r;
    } on TimeoutException {
      throw AdbFalha('adb ${args.take(3).join(' ')} sem resposta');
    } on ProcessException catch (e) {
      throw AdbFalha('não foi possível executar o adb: ${e.message}');
    }
  }

  Future<String> _texto(List<String> args) async =>
      (await _rodar(args)).stdout as String;

  @override
  Future<List<String>> dispositivos() async {
    final saida = await _texto(['devices']);
    return [
      for (final linha in const LineSplitter().convert(saida).skip(1))
        if (linha.trim().endsWith('device')) linha.split(RegExp(r'\s+')).first,
    ];
  }

  @override
  Future<String> nomeAvd(String serial) async {
    final saida = await _texto(['-s', serial, 'emu', 'avd', 'name']);
    return const LineSplitter().convert(saida).first.trim();
  }

  @override
  Future<String> propriedade(String serial, String nome) async =>
      (await _texto(['-s', serial, 'shell', 'getprop', nome])).trim();

  @override
  Future<int> epochEmulador(String serial) async =>
      int.parse((await _texto(['-s', serial, 'shell', 'date', '+%s'])).trim());

  @override
  Future<void> iniciarApp(String serial, String pacote) async {
    await _rodar([
      '-s',
      serial,
      'shell',
      'monkey',
      '-p',
      pacote,
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ]);
  }

  @override
  Future<bool> processoVivo(String serial, String pacote) async {
    try {
      final r = await Process.run(executavel, [
        '-s',
        serial,
        'shell',
        'pidof',
        pacote,
      ]).timeout(timeoutPadrao);
      return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
    } on TimeoutException {
      throw AdbFalha('pidof sem resposta');
    }
  }

  @override
  Future<void> pmClear(String serial, String pacote) async {
    await _rodar(['-s', serial, 'shell', 'pm', 'clear', pacote]);
  }

  @override
  Future<void> pmGrant(String serial, String pacote, String permissao) async {
    await _rodar(['-s', serial, 'shell', 'pm', 'grant', pacote, permissao]);
  }

  @override
  Future<void> tocar(String serial, int x, int y) async {
    await _rodar(['-s', serial, 'shell', 'input', 'tap', '$x', '$y']);
  }

  @override
  Future<void> digitar(String serial, String texto) async {
    await _rodar([
      '-s',
      serial,
      'shell',
      'input',
      'text',
      texto.replaceAll(' ', '%s'),
    ]);
  }

  @override
  Future<void> tecla(String serial, int codigo) async {
    await _rodar(['-s', serial, 'shell', 'input', 'keyevent', '$codigo']);
  }

  @override
  Future<void> deslizar(
    String serial,
    int x1,
    int y1,
    int x2,
    int y2, {
    int duracaoMs = 300,
  }) async {
    await _rodar([
      '-s',
      serial,
      'shell',
      'input',
      'swipe',
      '$x1',
      '$y1',
      '$x2',
      '$y2',
      '$duracaoMs',
    ]);
  }

  @override
  Future<String> dump(String serial) async {
    final saida = await _texto([
      '-s',
      serial,
      'exec-out',
      'uiautomator',
      'dump',
      '/dev/tty',
    ]);
    final fim = saida.lastIndexOf('</hierarchy>');
    final ini = saida.indexOf('<');
    if (fim < 0 || ini < 0) throw AdbFalha('uiautomator dump sem hierarquia');
    return saida.substring(ini, fim + '</hierarchy>'.length);
  }

  @override
  Future<List<int>> captura(String serial) async {
    final r = await _rodar([
      '-s',
      serial,
      'exec-out',
      'screencap',
      '-p',
    ], binario: true);
    return r.stdout as List<int>;
  }

  @override
  Future<void> geoFix(String serial, double lat, double lon) async {
    await _rodar(['-s', serial, 'emu', 'geo', 'fix', '$lon', '$lat']);
  }

  @override
  Future<List<String>> logcat(String serial) async {
    final saida = await _texto([
      '-s',
      serial,
      'logcat',
      '-d',
      '-v',
      'time',
      'flutter:I',
      '*:S',
    ]);
    return const LineSplitter().convert(saida);
  }

  @override
  Future<void> limparLogcat(String serial) async {
    await _rodar(['-s', serial, 'logcat', '-c']);
  }
}
