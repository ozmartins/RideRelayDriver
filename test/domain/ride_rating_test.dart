import 'package:driver/domain/ride_rating.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RideRating', () {
    test('aceita notas de 1 a 5', () {
      for (var nota = 1; nota <= 5; nota++) {
        final rating = RideRating(
          rideId: 'quote-1',
          stars: nota,
          ratedAt: DateTime(2026, 9, 23),
        );

        expect(rating.stars, nota);
      }
    });

    test('recusa nota menor que 1', () {
      expect(
        () => RideRating(
          rideId: 'quote-1',
          stars: 0,
          ratedAt: DateTime(2026, 9, 23),
        ),
        throwsArgumentError,
      );
    });

    test('recusa nota maior que 5', () {
      expect(
        () => RideRating(
          rideId: 'quote-1',
          stars: 6,
          ratedAt: DateTime(2026, 9, 23),
        ),
        throwsArgumentError,
      );
    });

    test('duas instâncias com os mesmos campos são iguais', () {
      final data = DateTime(2026, 9, 23, 10);
      final a = RideRating(rideId: 'quote-1', stars: 3, ratedAt: data);
      final b = RideRating(rideId: 'quote-1', stars: 3, ratedAt: data);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('instâncias com rideId diferente não são iguais', () {
      final data = DateTime(2026, 9, 23, 10);
      final a = RideRating(rideId: 'quote-1', stars: 3, ratedAt: data);
      final b = RideRating(rideId: 'quote-2', stars: 3, ratedAt: data);

      expect(a, isNot(b));
    });

    test('instâncias com stars diferente não são iguais', () {
      final data = DateTime(2026, 9, 23, 10);
      final a = RideRating(rideId: 'quote-1', stars: 3, ratedAt: data);
      final b = RideRating(rideId: 'quote-1', stars: 4, ratedAt: data);

      expect(a, isNot(b));
    });
  });
}
