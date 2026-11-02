import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/ui.dart';
import 'support/fake_adb.dart';
import 'support/relogio_falso.dart';

const _xml = '''<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node text="" content-desc="" clickable="false" enabled="true" bounds="[0,0][1080,2400]">
    <node text="" content-desc="Avalie a corrida &amp; confirme" clickable="false" enabled="true" bounds="[100,500][980,600]" />
    <node text="" content-desc="" clickable="true" enabled="true" bounds="[100,700][280,880]" />
    <node text="" content-desc="" clickable="true" enabled="true" bounds="[300,700][480,880]" />
    <node text="" content-desc="" clickable="true" enabled="true" bounds="[500,700][680,880]" />
    <node text="" content-desc="" clickable="true" enabled="true" bounds="[700,700][880,880]" />
    <node text="" content-desc="" clickable="true" enabled="true" bounds="[900,700][1080,880]" />
    <node text="" content-desc="" clickable="true" enabled="true" bounds="[100,1000][500,1100]">
      <node text="Pular" content-desc="" clickable="false" enabled="true" bounds="[110,1010][490,1090]" />
    </node>
    <node text="Confirmar" content-desc="" clickable="true" enabled="false" bounds="[550,1000][980,1100]" />
    <node text="a &gt; b" content-desc="" clickable="false" enabled="true" bounds="[0,1200][500,1300]" />
  </node>
</hierarchy>''';

void main() {
  group('Tela', () {
    final tela = Tela.parse(_xml);

    test('lê texto, content-desc com entidades e atributos com ">"', () {
      expect(tela.tem('Avalie a corrida & confirme'), isTrue);
      expect(tela.tem('a > b'), isTrue);
      expect(tela.tem('inexistente'), isFalse);
    });

    test('botao devolve o ancestral clicável do rótulo', () {
      final b = tela.botao('Pular')!;
      expect(b.clicavel, isTrue);
      expect(b.limites.centroX, 300);
      expect(b.limites.centroY, 1050);
    });

    test('botao respeita habilitado e exato', () {
      expect(tela.botao('Confirmar'), isNull);
      expect(tela.botao('Confirmar', habilitado: false), isNotNull);
      expect(tela.botao('Pul', exato: true), isNull);
      expect(tela.botao('Pular', exato: true), isNotNull);
    });

    test('estrelas: 5 clicáveis sem rótulo, da esquerda para a direita', () {
      final e = tela.estrelas('Avalie a corrida');
      expect(e, hasLength(5));
      expect(e.first.limites.esquerda, 100);
      expect(e.last.limites.esquerda, 900);
    });

    test('estrelas ausentes ou insuficientes: lista vazia', () {
      expect(tela.estrelas('Outra coisa'), isEmpty);
      expect(Tela.parse('<hierarchy></hierarchy>').estrelas('x'), isEmpty);
    });

    test('XML sem nós é uma tela vazia, sem lançar', () {
      expect(Tela.parse('lixo').todos, isEmpty);
    });
  });

  group('esperarCondicao', () {
    test('devolve assim que a condição aparece, antes do prazo', () async {
      final r = RelogioFalso();
      var chamadas = 0;
      final v = await esperarCondicao<String>(r, () async {
        chamadas++;
        return chamadas == 3 ? 'achei' : null;
      }, timeout: const Duration(seconds: 30));
      expect(v, 'achei');
      expect(chamadas, 3);
    });

    test(
      'estoura o prazo devolvendo null, sem lançar e sem espera fixa longa',
      () async {
        final r = RelogioFalso();
        final inicio = r.agora();
        final v = await esperarCondicao<String>(
          r,
          () async => null,
          timeout: const Duration(seconds: 15),
        );
        expect(v, isNull);
        expect(
          r.agora().difference(inicio),
          lessThan(const Duration(seconds: 17)),
        );
      },
    );

    test('usa o dump do FakeAdb', () async {
      final r = RelogioFalso();
      final adb = FakeAdb(relogio: r);
      adb.telas['s'] = const [ElementoFake('Aceitar', clicavel: true)];
      final t = await esperarCondicao<Tela>(r, () async {
        final tela = Tela.parse(await adb.dump('s'));
        return tela.botao('Aceitar') != null ? tela : null;
      }, timeout: const Duration(seconds: 5));
      expect(t, isNotNull);
    });
  });
}
