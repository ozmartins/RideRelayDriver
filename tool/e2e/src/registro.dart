import 'dart:io';

/// Log do roteiro (`execucao.log`). Tudo que entra passa por [sanitizar]: nem uma
/// mensagem de erro inesperada pode levar chave, `content` ou a chave da ORS a
/// um arquivo ou à tela (FR-029).

final _nsec = RegExp(r'nsec1[a-z0-9]{20,}', caseSensitive: false);
final _hexLongo = RegExp(r'(?<![0-9a-fA-F])[0-9a-fA-F]{64,}(?![0-9a-fA-F])');
final _campoContent = RegExp(r'"content"\s*:\s*"(?:[^"\\]|\\.)*"');

String sanitizar(String texto, {String? chaveOrs}) {
  var s = texto
      .replaceAll(_nsec, '[nsec omitido]')
      .replaceAll(_campoContent, '"c":"[omitido]"')
      .replaceAll(_hexLongo, '[hex omitido]');
  if (chaveOrs != null && chaveOrs.length >= 8) {
    s = s.replaceAll(chaveOrs, '[chave omitida]');
  }
  return s;
}

class RegistroExecucao {
  RegistroExecucao({
    this.arquivo,
    this.chaveOrs,
    this.eco = true,
    DateTime Function()? agora,
  }) : _agora = agora ?? (() => DateTime.now().toUtc());

  final File? arquivo;
  final String? chaveOrs;
  final bool eco;
  final DateTime Function() _agora;

  void escrever(String mensagem) {
    final linha =
        '${_agora().toIso8601String()} ${sanitizar(mensagem, chaveOrs: chaveOrs)}';
    final a = arquivo;
    if (a != null) {
      if (!a.parent.existsSync()) a.parent.createSync(recursive: true);
      a.writeAsStringSync('$linha\n', mode: FileMode.append);
    }
    if (eco) stdout.writeln(linha);
  }
}
