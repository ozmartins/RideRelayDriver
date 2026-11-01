import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/e2e/src/varredura_saida.dart';

String _hex(String c, [int n = 64]) => List.filled(n, c).join();

void main() {
  late Directory raiz;
  final idEvento = _hex('a');
  final pubMotorista = _hex('b');

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('varredura_');
    final periodo = Directory('${raiz.path}/periodo-1')..createSync();
    File('${periodo.path}/eventos.jsonl')
        .writeAsStringSync('${jsonEncode({'id': idEvento, 'kind': 20001})}\n');
    File('${periodo.path}/checkpoint.json').writeAsStringSync(
      jsonEncode({
        'identidades': {
          'motorista_pub': pubMotorista,
          'passageiro_pub': _hex('c'),
        },
      }),
    );
  });

  tearDown(() => raiz.deleteSync(recursive: true));

  void plantar(String conteudo, [String nome = 'plantado.txt']) =>
      File('${raiz.path}/$nome').writeAsStringSync(conteudo);

  test(
    'saída legítima passa: ids observados, chaves públicas e content-desc',
    () {
      plantar(
        '<node content-desc="Aceitar" /> id $idEvento pub $pubMotorista',
        'dump.xml',
      );
      expect(varrerSaida(raiz), isEmpty);
    },
  );

  test('reprova nsec1 sem imprimir o valor', () {
    final nsec = 'nsec1${'q' * 58}';
    plantar('segredo: $nsec');
    final achados = varrerSaida(raiz);
    expect(achados.map((a) => a.padrao), contains('nsec'));
    expect(achados.join(), isNot(contains(nsec)));
  });

  test('reprova hex de 64 que não é id observado nem chave pública', () {
    plantar('chave ${_hex('d')}');
    expect(
      varrerSaida(raiz).map((a) => a.padrao),
      contains('hex de 64 caracteres fora da lista de permitidos'),
    );
  });

  test('reprova hex de 128 (assinatura)', () {
    plantar('sig ${_hex('e', 128)}');
    expect(
      varrerSaida(raiz).map((a) => a.padrao),
      contains('hex de 128 caracteres'),
    );
  });

  test('reprova "content" como chave JSON', () {
    plantar('{"content": "x"}', 'plantado.jsonl');
    expect(varrerSaida(raiz).map((a) => a.padrao), contains('campo "content"'));
  });

  test('reprova a chave do openrouteservice como substring', () {
    plantar('url ...?api_key=5b3ce3597851110001cf6248abcdef12');
    expect(
      varrerSaida(
        raiz,
        chaveOrs: '5b3ce3597851110001cf6248abcdef12',
      ).map((a) => a.padrao),
      contains('chave do openrouteservice'),
    );
  });

  test('sem chave da ORS a varredura segue sem esse padrão', () {
    plantar('url ...?api_key=5b3ce3597851110001cf6248abcdef12');
    expect(varrerSaida(raiz), isEmpty);
  });

  test('o achado indica o arquivo relativo', () {
    plantar('{"content":"x"}', 'plantado.jsonl');
    expect(varrerSaida(raiz).first.arquivo, 'plantado.jsonl');
  });

  test('lerChaveOrs: ambiente tem precedência e a ausência devolve null', () {
    expect(lerChaveOrs(ambiente: {'ORS_API_KEY': ' abc12345 '}), 'abc12345');
    expect(
      lerChaveOrs(
        ambiente: const {},
        caminhoArquivo: '${raiz.path}/nao_existe',
      ),
      isNull,
    );
  });
}
