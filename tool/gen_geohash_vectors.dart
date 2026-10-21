// Gera `test/fixtures/geohash_vectors.json`: vetores do geohash da tag `g` do
// `kind: 20001` (emenda 27 do contrato; feature 027), compartilhados byte a
// byte com o app do passageiro.
//
// ignore_for_file: avoid_print — é uma ferramenta de linha de comando, em que a
// saída padrão é a própria interface; não faz parte do aplicativo.
// Uso: dart run tool/gen_geohash_vectors.dart
//
// Tudo é determinístico. As âncoras vêm da descrição pública do geohash
// (Wikipédia), não do código: servem para pegar erro de bits que o próprio
// gerador reproduziria.
import 'dart:convert';
import 'dart:io';

import 'package:driver/domain/geohash.dart';

const _pontos = <(String, double, double)>[
  ('ararangua', -28.9298, -49.4753),
  ('sao_paulo', -23.5505, -46.6333),
  ('chui', -33.6866, -53.4595),
  ('boa_vista', 2.8235, -60.6758),
  ('antimeridiano_leste', -16.5, 179.99),
  ('antimeridiano_oeste', -16.5, -179.99),
  ('perto_do_polo_norte', 89.99, 10.0),
  ('perto_do_polo_sul', -89.99, -170.0),
];

void main() {
  final pontos = [
    for (final (nome, lat, lon) in _pontos)
      {
        'nome': nome,
        'lat': lat,
        'lon': lon,
        // Prefixos do mesmo geohash: a tag `g` em 5, 4 e 3 caracteres.
        'tags_g': [
          for (final p in kPrecisoesDaTag) Geohash.encode(lat, lon, p),
        ],
        // As 9 células (a do ponto e as vizinhas), ordenadas: a ordem não faz
        // parte do contrato.
        'celulas': {
          for (final p in kPrecisoesDaTag)
            '$p': (Geohash.cellWithNeighbors(Geohash.encode(lat, lon, p))
              ..sort()),
        },
      },
  ];

  final dados = {
    'descricao':
        'Vetores do geohash da tag g do kind 20001 (emenda 27). Para cada ponto: '
        'as três tags g (precisões 5, 4 e 3) e as células do bloco 3x3 de cada '
        'precisão, ordenadas. Idêntico nos dois apps.',
    'ancoras': [
      {'lat': 42.605, 'lon': -5.603, 'precisao': 5, 'geohash': 'ezs42'},
      {
        'lat': 57.64911,
        'lon': 10.40744,
        'precisao': 11,
        'geohash': 'u4pruydqqvj',
      },
    ],
    'pontos': pontos,
  };

  final saida = File('test/fixtures/geohash_vectors.json');
  saida.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(dados)}\n',
  );
  print('Gravado ${saida.path} (${pontos.length} pontos).');
}
