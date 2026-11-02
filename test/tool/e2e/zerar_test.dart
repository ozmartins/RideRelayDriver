import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/opcoes.dart';
import '../../../tool/e2e/src/zerar.dart';

void main() {
  late Directory saida;
  late List<String> mensagens;

  setUp(() {
    saida = Directory.systemTemp.createTempSync('zerar_test');
    Directory('${saida.path}/execucao').createSync();
    File('${saida.path}/execucao/checkpoint.json').writeAsStringSync('{}');
    File('${saida.path}/relatorio.md').writeAsStringSync('# r');
    Directory('${saida.path}/dados').createSync();
    Directory('${saida.path}/ensaio-20260101-1000').createSync();
    mensagens = [];
  });

  tearDown(() => saida.deleteSync(recursive: true));

  int rodar(String? resposta) => zerarExecucao(
    saida: saida,
    lerLinha: () => resposta,
    escrever: mensagens.add,
  );

  test('--zerar é um comando próprio e não combina com outro', () {
    expect(parseOpcoes(['--zerar']).comando, Comando.zerar);
    expect(
      () => parseOpcoes(['--zerar', '--executar']),
      throwsA(isA<OpcoesInvalidas>()),
    );
  });

  test('confirmando, apaga a execução e o relatório, mas não os ensaios', () {
    expect(rodar('zerar'), 0);
    expect(Directory('${saida.path}/execucao').existsSync(), isFalse);
    expect(File('${saida.path}/relatorio.md').existsSync(), isFalse);
    expect(Directory('${saida.path}/dados').existsSync(), isFalse);
    expect(
      Directory('${saida.path}/ensaio-20260101-1000').existsSync(),
      isTrue,
    );
  });

  test('lista o que será apagado antes de pedir a confirmação', () {
    rodar('zerar');
    expect(mensagens.any((m) => m.contains('execucao')), isTrue);
    expect(mensagens.any((m) => m.contains(palavraDeConfirmacao)), isTrue);
  });

  for (final resposta in ['n', '', 'sim', 'ZERAR!', null]) {
    test('resposta ${resposta == null ? 'ausente' : '"$resposta"'} não apaga '
        'nada e sai com 2', () {
      expect(rodar(resposta), 2);
      expect(Directory('${saida.path}/execucao').existsSync(), isTrue);
      expect(File('${saida.path}/relatorio.md').existsSync(), isTrue);
      expect(Directory('${saida.path}/dados').existsSync(), isTrue);
    });
  }

  test('sem nada a apagar, não pergunta e sai com 0', () {
    saida.deleteSync(recursive: true);
    saida.createSync();
    var perguntou = false;
    final codigo = zerarExecucao(
      saida: saida,
      lerLinha: () {
        perguntou = true;
        return 'zerar';
      },
      escrever: mensagens.add,
    );
    expect(codigo, 0);
    expect(perguntou, isFalse);
  });
}
