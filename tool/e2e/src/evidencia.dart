import 'dart:io';

import 'adb.dart';
import 'telas.dart';
import 'ui.dart';

/// Política de capturas e dumps (FR-027, D10). Telas de configuração, cadastro,
/// relays, identidade/chave e backup **nunca** são gravadas.
class Evidencia {
  Evidencia({required this.adb, required this.pasta});

  final Adb adb;

  /// Pasta `capturas/` do período.
  final Directory pasta;

  /// Falso se [tela] for sensível.
  static bool permitida(Tela tela) {
    final visivel = tela.textoVisivel;
    for (final marcador in marcadoresDeTelaSensivel) {
      if (visivel.contains(marcador)) return false;
    }
    return true;
  }

  /// Captura a tela de [serial] e, se [comDump], o dump XML. Devolve os
  /// caminhos relativos gravados, ou um item "omitida: tela sensível" quando a
  /// política barra. Falha de `adb` aqui não derruba o ciclo: devolve o motivo.
  Future<List<String>> capturar({
    required String serial,
    required String prefixo,
    bool comDump = false,
    Tela? telaAtual,
  }) async {
    try {
      final tela = telaAtual ?? Tela.parse(await adb.dump(serial));
      if (!permitida(tela)) {
        return ['$prefixo: captura omitida (tela sensível)'];
      }
      if (!pasta.existsSync()) pasta.createSync(recursive: true);
      final saidas = <String>[];
      final png = File('${pasta.path}/$prefixo.png');
      png.writeAsBytesSync(await adb.captura(serial));
      saidas.add('capturas/$prefixo.png');
      if (comDump) {
        File('${pasta.path}/$prefixo.xml').writeAsStringSync(tela.xml);
        saidas.add('capturas/$prefixo.xml');
      }
      return saidas;
    } on AdbFalha catch (e) {
      return ['$prefixo: captura não realizada (${e.mensagem})'];
    }
  }
}
