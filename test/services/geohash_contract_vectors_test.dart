import 'dart:convert';
import 'dart:io';

import 'package:driver/domain/geohash.dart';
import 'package:flutter_test/flutter_test.dart';

/// Teste de contrato (emenda 27): os vetores de `test/fixtures/geohash_vectors.json`
/// são idênticos, byte a byte, nos dois apps. O geohash que cada app calcula
/// MUST bater com o do arquivo, para que o `#g` do motorista case com a tag
/// `g` que o passageiro publica.
void main() {
  final dados = jsonDecode(
    File('test/fixtures/geohash_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final ancoras = (dados['ancoras'] as List).cast<Map<String, dynamic>>();
  final pontos = (dados['pontos'] as List).cast<Map<String, dynamic>>();

  test('o arquivo traz as âncoras e os pontos mínimos do contrato', () {
    expect(ancoras, isNotEmpty);
    expect(
      pontos.map((p) => p['nome']),
      containsAll([
        'ararangua',
        'sao_paulo',
        'chui',
        'boa_vista',
        'antimeridiano_leste',
        'antimeridiano_oeste',
        'perto_do_polo_norte',
        'perto_do_polo_sul',
      ]),
    );
  });

  test('as âncoras independentes batem', () {
    for (final a in ancoras) {
      expect(
        Geohash.encode(
          (a['lat'] as num).toDouble(),
          (a['lon'] as num).toDouble(),
          a['precisao'] as int,
        ),
        a['geohash'],
      );
    }
  });

  for (final p in pontos) {
    final lat = (p['lat'] as num).toDouble();
    final lon = (p['lon'] as num).toDouble();

    test('${p['nome']}: as três tags g', () {
      expect([
        for (final prec in kPrecisoesDaTag) Geohash.encode(lat, lon, prec),
      ], (p['tags_g'] as List).cast<String>());
    });

    test('${p['nome']}: as células do bloco 3×3 de cada precisão', () {
      final celulas = p['celulas'] as Map<String, dynamic>;
      for (final prec in kPrecisoesDaTag) {
        final esperado = (celulas['$prec'] as List).cast<String>();
        final obtido = Geohash.cellWithNeighbors(Geohash.encode(lat, lon, prec))
          ..sort();
        expect(obtido, esperado, reason: 'precisão $prec');
      }
    });
  }
}
