import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/coordenacao.dart';
import '../../../tool/e2e/src/opcoes.dart' show Papel;
import '../../../tool/e2e/src/papel.dart';
import '../../../tool/e2e/src/preparo.dart';
import 'support/relogio_falso.dart';

final _pubMot = 'aa' * 32;
final _pubPax = 'bb' * 32;
const _versao = {'commit': 'abc123', 'alteracoes_locais': false};

class _CoordenacaoQueFalha extends CoordenacaoLocal {
  _CoordenacaoQueFalha(super.nucleo, super.papel, this.falhas);

  int falhas;

  @override
  Future<RespostaBarreira> barreira(
    String nome,
    int ciclo, {
    Map<String, Object?>? dados,
  }) {
    if (falhas-- > 0) throw CoordenadorInalcancavel('recusou');
    return super.barreira(nome, ciclo, dados: dados);
  }
}

void main() {
  late NucleoCoordenacao nucleo;
  late RelogioFalso relogio;

  setUp(() {
    nucleo = NucleoCoordenacao(espera: const Duration(seconds: 5));
    relogio = RelogioFalso();
  });

  Future<IdentidadeDoOutro> lado(
    Papel papel,
    String pub, {
    Coordenacao? coord,
    Duration prazo = const Duration(minutes: 10),
  }) => trocarIdentidades(
    coord ?? CoordenacaoLocal(nucleo, papel),
    minhaPub: pub,
    minhaVersao: _versao,
    relogio: relogio,
    prazo: prazo,
  );

  test('cada lado recebe a chave pública e a versão do outro', () async {
    final r = await Future.wait([
      lado(Papel.motorista, _pubMot),
      lado(Papel.passageiro, _pubPax),
    ]);
    expect(r[0].pub, _pubPax);
    expect(r[1].pub, _pubMot);
    expect(r[0].versao, _versao);
  });

  test('o motorista tenta de novo enquanto o coordenador não sobe', () async {
    final r = await Future.wait([
      lado(
        Papel.motorista,
        _pubMot,
        coord: _CoordenacaoQueFalha(nucleo, Papel.motorista, 3),
      ),
      lado(Papel.passageiro, _pubPax),
    ]);
    expect(r[0].pub, _pubPax);
  });

  test('desiste depois do prazo se o outro lado não aparece', () async {
    await expectLater(
      lado(
        Papel.motorista,
        _pubMot,
        coord: _CoordenacaoQueFalha(nucleo, Papel.motorista, 1 << 20),
        prazo: const Duration(seconds: 30),
      ),
      throwsA(isA<PreCondicaoFalha>()),
    );
  });

  test('recusa chave inválida e chave repetida', () async {
    await expectLater(
      Future.wait([
        lado(Papel.motorista, _pubMot),
        lado(Papel.passageiro, 'curta'),
      ]),
      throwsA(isA<PreCondicaoFalha>()),
    );
    final n2 = NucleoCoordenacao(espera: const Duration(seconds: 5));
    await expectLater(
      Future.wait([
        trocarIdentidades(
          CoordenacaoLocal(n2, Papel.motorista),
          minhaPub: _pubMot,
          minhaVersao: _versao,
          relogio: relogio,
        ),
        trocarIdentidades(
          CoordenacaoLocal(n2, Papel.passageiro),
          minhaPub: _pubMot,
          minhaVersao: _versao,
          relogio: relogio,
        ),
      ]),
      throwsA(isA<PreCondicaoFalha>()),
    );
  });

  test('a versão enviada só leva commit e alterações locais', () async {
    final r = await Future.wait([
      trocarIdentidades(
        CoordenacaoLocal(nucleo, Papel.motorista),
        minhaPub: _pubMot,
        minhaVersao: const {
          'commit': 'abc',
          'alteracoes_locais': true,
          'segredo': 'x',
        },
        relogio: relogio,
      ),
      lado(Papel.passageiro, _pubPax),
    ]);
    expect(r[1].versao, {'commit': 'abc', 'alteracoes_locais': true});
  });
}
