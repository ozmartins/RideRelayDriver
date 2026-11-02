import 'dart:convert';

import 'package:driver/domain/ride_route_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

List<LatLng> rota(int n) => [
  for (var i = 0; i < n; i++) LatLng(-28.9 + i * 0.0001, -49.4 + i * 0.0001),
];

void main() {
  group('RideRouteContent.reduce', () {
    test('devolve a lista intacta com até 1000 pontos', () {
      final pontos = rota(1000);

      expect(RideRouteContent.reduce(pontos), pontos);
      expect(RideRouteContent.reduce(rota(2)), rota(2));
    });

    test('com 2500 pontos devolve exatamente 1000, com primeiro, último e '
        'ordem preservados', () {
      final pontos = rota(2500);

      final reduzida = RideRouteContent.reduce(pontos);

      expect(reduzida, hasLength(1000));
      expect(reduzida.first, pontos.first);
      expect(reduzida.last, pontos.last);
      for (var i = 1; i < reduzida.length; i++) {
        expect(reduzida[i].latitude, greaterThan(reduzida[i - 1].latitude));
      }
    });

    test('com 1001 e com 1999 pontos devolve exatamente 1000 (nunca 1001)', () {
      for (final n in [1001, 1999]) {
        final pontos = rota(n);

        final reduzida = RideRouteContent.reduce(pontos);

        expect(reduzida, hasLength(RideRouteContent.maxPoints), reason: '$n');
        expect(reduzida.first, pontos.first);
        expect(reduzida.last, pontos.last);
      }
    });
  });

  group('RideRouteContent.encode', () {
    test('produz {"points":[[lat,lon],...]} com 5 casas decimais', () {
      final json = jsonDecode(
        RideRouteContent.encode([
          const LatLng(-28.9312345678, -49.4889012345),
          const LatLng(-28.93140, -49.48870),
        ]),
      ) as Map<String, dynamic>;

      expect(json.keys, ['points']);
      expect(json['points'], [
        [-28.93123, -49.4889],
        [-28.9314, -49.4887],
      ]);
    });

    test('1000 pontos realistas ficam abaixo de 30 000 bytes', () {
      final conteudo = RideRouteContent.encode(rota(1000));

      expect(utf8.encode(conteudo).length, lessThan(30000));
    });

    test('reduz antes de codificar quando passa de 1000 pontos', () {
      final json = jsonDecode(
        RideRouteContent.encode(rota(4000)),
      ) as Map<String, dynamic>;

      expect(json['points'] as List<dynamic>, hasLength(1000));
    });

    test('com menos de 2 pontos lança ArgumentError', () {
      expect(() => RideRouteContent.encode([]), throwsArgumentError);
      expect(
        () => RideRouteContent.encode([const LatLng(-28.9, -49.4)]),
        throwsArgumentError,
      );
    });
  });
}
