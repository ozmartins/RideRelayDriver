import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/opcoes.dart';

void main() {
  test('--periodo 1 e --periodo=2', () {
    expect(parseOpcoes(['--periodo', '1']).periodo, 1);
    expect(parseOpcoes(['--periodo=2']).periodo, 2);
    expect(parseOpcoes(['--periodo', '1']).comando, Comando.periodo);
  });

  test('--retomar, --relatorio, --verificar-saida, --ajuda', () {
    expect(parseOpcoes(['--periodo', '1', '--retomar']).retomar, isTrue);
    expect(parseOpcoes(['--relatorio']).comando, Comando.relatorio);
    expect(parseOpcoes(['--verificar-saida']).comando, Comando.verificarSaida);
    expect(parseOpcoes(['--ajuda']).comando, Comando.ajuda);
  });

  test('ensaio aceita meta e orçamento menores', () {
    final o = parseOpcoes([
      '--periodo',
      '1',
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
      () => parseOpcoes(['--periodo', '1', '--meta-validos', '2']),
      throwsA(isA<OpcoesInvalidas>()),
    );
    expect(
      () => parseOpcoes(['--periodo', '1', '--orcamento-min', '3']),
      throwsA(isA<OpcoesInvalidas>()),
    );
  });

  test('--teto-periodo-1-executados só no período 2', () {
    expect(
      parseOpcoes(['--periodo', '2', '--teto-periodo-1-executados', '32'])
          .tetoPeriodo1Executados,
      32,
    );
    expect(
      () =>
          parseOpcoes(['--periodo', '1', '--teto-periodo-1-executados', '32']),
      throwsA(isA<OpcoesInvalidas>()),
    );
  });

  test('entradas inválidas', () {
    for (final args in [
      <String>[],
      ['--periodo', '3'],
      ['--periodo', 'x'],
      ['--periodo'],
      ['--desconhecida'],
      ['solto'],
      ['--periodo', '1', '--relatorio'],
      ['--relatorio', '--retomar'],
      ['--relatorio', '--ensaio'],
      ['--periodo', '1', '--ensaio', '--meta-validos', '31'],
      ['--periodo', '1', '--ensaio', '--orcamento-min', '181'],
    ]) {
      expect(
        () => parseOpcoes(args),
        throwsA(isA<OpcoesInvalidas>()),
        reason: '$args',
      );
    }
  });

  test('padrões: AVDs e pasta de saída', () {
    final o = parseOpcoes(['--periodo', '1']);
    expect(o.avdDoMotorista, 'Pixel_6_API34_1');
    expect(o.avdDoPassageiro, 'Pixel_6_API34_2');
    expect(o.saida, 'e2e_saida');
  });
}
