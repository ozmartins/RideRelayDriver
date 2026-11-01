import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/registro.dart';
import '../../../tool/e2e/src/varredura_saida.dart';

void main() {
  const chaveOrs = '5b3ce3597851110001cf6248abcdef12';
  final hex = 'ab' * 32;
  final nsec = 'nsec1${'q' * 58}';

  test('sanitizar remove nsec, hex longo, content e a chave da ORS', () {
    final s = sanitizar(
      'falha $nsec chave $hex sig ${'cd' * 64} {"content":"texto secreto"} '
      'url ?api_key=$chaveOrs',
      chaveOrs: chaveOrs,
    );
    expect(s.contains(nsec), isFalse);
    expect(s.contains(hex), isFalse);
    expect(s.contains('texto secreto'), isFalse);
    expect(s.contains(chaveOrs), isFalse);
    expect(s, contains('[nsec omitido]'));
    expect(s, contains('[hex omitido]'));
    expect(s, contains('[chave omitida]'));
  });

  test('mensagens comuns passam intactas', () {
    expect(sanitizar('ciclo 3: sucesso em E12'), 'ciclo 3: sucesso em E12');
  });

  test('o arquivo de log com entradas perigosas passa na varredura', () {
    final tmp = Directory.systemTemp.createTempSync('log_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final log = RegistroExecucao(
      arquivo: File('${tmp.path}/execucao.log'),
      chaveOrs: chaveOrs,
      eco: false,
      agora: () => DateTime.utc(2026, 11, 1),
    );
    log.escrever('erro: $nsec');
    log.escrever('evento {"content":"nao pode"} id $hex');
    log.escrever('url https://api.exemplo/rota?api_key=$chaveOrs');
    log.escrever('ciclo 1: sucesso');

    final texto = File('${tmp.path}/execucao.log').readAsStringSync();
    expect(texto, contains('ciclo 1: sucesso'));
    expect(varrerSaida(tmp, chaveOrs: chaveOrs), isEmpty);
  });
}
