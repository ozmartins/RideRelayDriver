import 'dart:io';

/// Palavra que o usuário precisa digitar para confirmar o `--zerar`.
const palavraDeConfirmacao = 'zerar';

/// Apaga a execução do TCC (`<saida>/execucao`) e o que o relatório gerou a
/// partir dela (`<saida>/relatorio.md`, `<saida>/dados`), depois de uma
/// confirmação digitada. Os ensaios (`ensaio-*`) não são tocados.
///
/// [lerLinha] devolve a linha digitada (ou `null` se a entrada acabou) e
/// [escrever] mostra uma mensagem; os dois são injetados para o teste não
/// depender do terminal. Devolve o código de saída: 0 apagou ou não havia o
/// que apagar; 2 não confirmado (nada foi apagado).
int zerarExecucao({
  required Directory saida,
  required String? Function() lerLinha,
  required void Function(String) escrever,
}) {
  final execucao = Directory('${saida.path}/execucao');
  final relatorio = File('${saida.path}/relatorio.md');
  final dados = Directory('${saida.path}/dados');

  final alvos = <FileSystemEntity>[
    if (execucao.existsSync()) execucao,
    if (relatorio.existsSync()) relatorio,
    if (dados.existsSync()) dados,
  ];
  if (alvos.isEmpty) {
    escrever('nada a zerar em ${saida.path}');
    return 0;
  }

  escrever('Isto apaga, de forma irreversível:');
  for (final a in alvos) {
    escrever('  ${a.path}');
  }
  escrever('Os ensaios (ensaio-*) e os apps nos emuladores não são alterados.');
  escrever('Digite "$palavraDeConfirmacao" para confirmar: ');

  final resposta = lerLinha()?.trim();
  if (resposta != palavraDeConfirmacao) {
    escrever('não confirmado; nada foi apagado');
    return 2;
  }
  for (final a in alvos) {
    a.deleteSync(recursive: true);
  }
  escrever(
    'execução zerada; rode --executar para recomeçar '
    '(o preparo limpa os apps)',
  );
  return 0;
}
