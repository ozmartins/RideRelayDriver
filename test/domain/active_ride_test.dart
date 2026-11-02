import 'package:driver/domain/active_ride.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = ActiveRide(
  quoteId: 'quote-1',
  passengerPubkey: 'pub-1',
  originLat: -28.9298,
  originLon: -49.4753,
  destinationLat: -28.6721,
  destinationLon: -49.3671,
);

void main() {
  group('ActiveRide', () {
    test('duas instâncias com os mesmos campos são iguais', () {
      const a = _base;
      const b = ActiveRide(
        quoteId: 'quote-1',
        passengerPubkey: 'pub-1',
        originLat: -28.9298,
        originLon: -49.4753,
        destinationLat: -28.6721,
        destinationLon: -49.3671,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('instâncias com quoteId diferente não são iguais', () {
      final b = ActiveRide(
        quoteId: 'quote-2',
        passengerPubkey: _base.passengerPubkey,
        originLat: _base.originLat,
        originLon: _base.originLon,
        destinationLat: _base.destinationLat,
        destinationLon: _base.destinationLon,
      );

      expect(_base, isNot(b));
    });

    test('instâncias com passengerPubkey diferente não são iguais', () {
      final b = ActiveRide(
        quoteId: _base.quoteId,
        passengerPubkey: 'pub-2',
        originLat: _base.originLat,
        originLon: _base.originLon,
        destinationLat: _base.destinationLat,
        destinationLon: _base.destinationLon,
      );

      expect(_base, isNot(b));
    });

    test('instâncias com origem diferente não são iguais', () {
      final b = ActiveRide(
        quoteId: _base.quoteId,
        passengerPubkey: _base.passengerPubkey,
        originLat: 0,
        originLon: 0,
        destinationLat: _base.destinationLat,
        destinationLon: _base.destinationLon,
      );

      expect(_base, isNot(b));
    });

    test('instâncias com destino diferente não são iguais', () {
      final b = ActiveRide(
        quoteId: _base.quoteId,
        passengerPubkey: _base.passengerPubkey,
        originLat: _base.originLat,
        originLon: _base.originLon,
        destinationLat: 0,
        destinationLon: 0,
      );

      expect(_base, isNot(b));
    });

    test('destinationArrivalNotified é falso por padrão', () {
      expect(_base.destinationArrivalNotified, isFalse);
    });

    test(
      'instâncias com destinationArrivalNotified diferente não são iguais',
      () {
        final b = _base.copyWith(destinationArrivalNotified: true);

        expect(_base, isNot(b));
      },
    );

    test(
      'copyWith(destinationArrivalNotified: true) preserva os demais campos',
      () {
        final b = _base.copyWith(destinationArrivalNotified: true);

        expect(b.quoteId, _base.quoteId);
        expect(b.passengerPubkey, _base.passengerPubkey);
        expect(b.originLat, _base.originLat);
        expect(b.originLon, _base.originLon);
        expect(b.destinationLat, _base.destinationLat);
        expect(b.destinationLon, _base.destinationLon);
        expect(b.destinationArrivalNotified, isTrue);
      },
    );

    test('copyWith() sem argumentos devolve uma cópia equivalente', () {
      final b = _base.copyWith();

      expect(b, _base);
    });
  });
}
