import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/opcoes.dart';

void main() {
  test('--executar roda a avaliação completa, sem períodos', () {
    final o = parseOpcoes(['--executar']);
    expect(o.comando, Comando.executar);
    expect(o.retomar, isFalse);
    expect(o.ensaio, isFalse);
  });

  test('--periodo não existe mais', () {
    expect(
      () => parseOpcoes(['--periodo', '1']),
      throwsA(isA<OpcoesInvalidas>()),
    );
    expect(
      () => parseOpcoes(['--executar', '--teto-periodo-1-executados', '3']),
      throwsA(isA<OpcoesInvalidas>()),
    );
  });

  test('--retomar, --relatorio, --verificar-saida, --ajuda', () {
    expect(parseOpcoes(['--retomar']).retomar, isTrue);
    expect(parseOpcoes(['--retomar']).comando, Comando.executar);
    expect(parseOpcoes(['--relatorio']).comando, Comando.relatorio);
    expect(parseOpcoes(['--verificar-saida']).comando, Comando.verificarSaida);
    expect(parseOpcoes(['--ajuda']).comando, Comando.ajuda);
  });

  test('ensaio aceita meta e orçamento menores', () {
    final o = parseOpcoes([
      '--ensaio',
      '--meta-validos',
      '2',
      '--orcamento-min',
      '3',
    ]);
    expect(o.ensaio, isTrue);
    expect(o.metaValidos, 2);
    expect(o.orcamentoMin, 3);
  });

  test('meta e orçamento reduzidos fora do ensaio são recusados', () {
    expect(
      () => parseOpcoes(['--executar', '--meta-validos', '2']),
      throwsA(isA<OpcoesInvalidas>()),
    );
    expect(
      () => parseOpcoes(['--executar', '--orcamento-min', '3']),
      throwsA(isA<OpcoesInvalidas>()),
    );
  });

  test('entradas inválidas', () {
    for (final args in [
      <String>[], // sem intenção explícita não se apaga nada
      ['--desconhecida'],
      ['solto'],
      ['--executar', '--relatorio'],
      ['--relatorio', '--retomar'],
      ['--relatorio', '--ensaio'],
      ['--ensaio', '--meta-validos', '61'],
      ['--ensaio', '--orcamento-min', '721'],
      ['--ensaio', '--meta-validos', '0'],
    ]) {
      expect(
        () => parseOpcoes(args),
        throwsA(isA<OpcoesInvalidas>()),
        reason: '$args',
      );
    }
  });

  test('padrões: AVDs e pasta de saída', () {
    final o = parseOpcoes(['--executar']);
    expect(o.avdDoMotorista, 'Pixel_6_API34_1');
    expect(o.avdDoPassageiro, 'Pixel_6_API34_2');
    expect(o.saida, 'e2e_saida');
  });

  test('--preparar é um comando; --sem-preparo e --sem-janela são opções', () {
    expect(parseOpcoes(['--preparar']).comando, Comando.preparar);
    final o = parseOpcoes(['--executar', '--sem-preparo', '--sem-janela']);
    expect(o.semPreparo, isTrue);
    expect(o.semJanela, isTrue);
    expect(parseOpcoes(['--executar']).semPreparo, isFalse);
    expect(
      () => parseOpcoes(['--preparar', '--sem-preparo']),
      throwsA(isA<OpcoesInvalidas>()),
    );
    expect(
      () => parseOpcoes(['--preparar', '--executar']),
      throwsA(isA<OpcoesInvalidas>()),
    );
  });
}
