import 'package:driver/domain/geohash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Geohash.encode', () {
    test('bate com as âncoras publicadas na descrição do geohash', () {
      expect(Geohash.encode(42.605, -5.603, 5), 'ezs42');
      expect(Geohash.encode(57.64911, 10.40744, 11), 'u4pruydqqvj');
    });

    test('as precisões menores são prefixos da maior', () {
      final g5 = Geohash.encode(-28.9298, -49.4753, 5);
      expect(Geohash.encode(-28.9298, -49.4753, 4), g5.substring(0, 4));
      expect(Geohash.encode(-28.9298, -49.4753, 3), g5.substring(0, 3));
    });

    test('aceita os extremos da faixa', () {
      expect(Geohash.encode(90, 180, 5), hasLength(5));
      expect(Geohash.encode(-90, -180, 5), hasLength(5));
    });

    test('latitude ou longitude fora da faixa lançam ArgumentError', () {
      expect(() => Geohash.encode(90.1, 0, 5), throwsArgumentError);
      expect(() => Geohash.encode(-90.1, 0, 5), throwsArgumentError);
      expect(() => Geohash.encode(0, 180.1, 5), throwsArgumentError);
      expect(() => Geohash.encode(0, -180.1, 5), throwsArgumentError);
      expect(() => Geohash.encode(double.nan, 0, 5), throwsArgumentError);
    });

    test('precisão fora de 1–12 lança ArgumentError', () {
      expect(() => Geohash.encode(0, 0, 0), throwsArgumentError);
      expect(() => Geohash.encode(0, 0, 13), throwsArgumentError);
    });
  });

  group('Geohash.neighbors', () {
    test('no meio do mapa são 8 células distintas, sem a própria', () {
      final celula = Geohash.encode(-28.9298, -49.4753, 5);
      final vizinhas = Geohash.neighbors(celula);
      expect(vizinhas, hasLength(8));
      expect(vizinhas.toSet(), hasLength(8));
      expect(vizinhas, isNot(contains(celula)));
      expect(vizinhas.every((v) => v.length == 5), isTrue);
    });

    test('as vizinhas de uma célula têm a célula entre as suas vizinhas', () {
      final celula = Geohash.encode(-28.9298, -49.4753, 4);
      for (final v in Geohash.neighbors(celula)) {
        expect(Geohash.neighbors(v), contains(celula));
      }
    });

    test('o ponto a poucos metros da borda cai numa das 9 células', () {
      final celula = Geohash.encode(-28.9298, -49.4753, 5);
      final b = Geohash.bounds(celula);
      // Logo além da borda leste e da borda norte.
      final alem = Geohash.encode(b.maxLat + 0.00005, b.maxLon + 0.00005, 5);
      expect(Geohash.cellWithNeighbors(celula), contains(alem));
    });

    test('dá a volta no antimeridiano', () {
      final leste = Geohash.encode(0, 179.99, 3);
      final oeste = Geohash.encode(0, -179.99, 3);
      expect(Geohash.neighbors(leste), contains(oeste));
      expect(Geohash.neighbors(oeste), contains(leste));
    });

    test('perto do polo não há vizinha além dele', () {
      final celula = Geohash.encode(89.99, 10, 3);
      final vizinhas = Geohash.neighbors(celula);
      expect(vizinhas.length, lessThan(8));
      expect(vizinhas.toSet(), hasLength(vizinhas.length));
      expect(vizinhas, isNot(contains(celula)));
    });

    test('cellWithNeighbors começa pela própria célula, sem repetição', () {
      final celula = Geohash.encode(-28.9298, -49.4753, 5);
      final todas = Geohash.cellWithNeighbors(celula);
      expect(todas.first, celula);
      expect(todas, hasLength(9));
      expect(todas.toSet(), hasLength(9));
    });
  });

  group('Geohash.isValid', () {
    test('aceita comprimento 3 a 5 no alfabeto', () {
      expect(Geohash.isValid('6gkzw'), isTrue);
      expect(Geohash.isValid('6gkz'), isTrue);
      expect(Geohash.isValid('6gk'), isTrue);
    });

    test(
      'recusa vazio, comprimento fora de 3–5, maiúscula e fora do alfabeto',
      () {
        expect(Geohash.isValid(''), isFalse);
        expect(Geohash.isValid('6g'), isFalse);
        expect(Geohash.isValid('6gkzwq'), isFalse);
        expect(Geohash.isValid('6GKZW'), isFalse);
        for (final c in ['a', 'i', 'l', 'o']) {
          expect(Geohash.isValid('6gk${c}w'), isFalse, reason: c);
        }
      },
    );
  });

  group('dimensões da célula', () {
    test('batem com a tabela do research (R3)', () {
      expect(Geohash.cellHeightKm(5), closeTo(4.89, 0.01));
      expect(Geohash.cellHeightKm(4), closeTo(19.55, 0.01));
      expect(Geohash.cellHeightKm(3), closeTo(156.37, 0.01));
      expect(Geohash.cellWidthKm(5, 0), closeTo(4.89, 0.01));
      expect(Geohash.cellWidthKm(4, 0), closeTo(39.09, 0.01));
      expect(Geohash.cellWidthKm(3, 0), closeTo(156.37, 0.01));
      expect(Geohash.cellWidthKm(5, -28.9), closeTo(4.28, 0.01));
      expect(Geohash.cellWidthKm(3, -28.9), closeTo(136.89, 0.01));
    });

    test('as precisões da tag são 5, 4 e 3', () {
      expect(kPrecisoesDaTag, [5, 4, 3]);
    });
  });
}
