import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/identity.dart';
import 'package:driver/domain/ride_rating.dart';
import 'package:driver/services/ride_rating_signature.dart';
import 'package:flutter_test/flutter_test.dart';

Identity _identidadeDeTeste() {
  final par = nostr.Nostr.instance.services.keys.generateKeyPair();
  return Identity(publicKey: par.public, privateKey: par.private);
}

void main() {
  group('RideRatingSignature', () {
    test('assinatura própria valida contra os mesmos valores', () {
      final identidade = _identidadeDeTeste();
      final rating = RideRating(
        rideId: 'quote-1',
        stars: 4,
        ratedAt: DateTime(2026, 9, 23, 10),
      );

      final assinatura = RideRatingSignature.sign(rating, identidade);

      expect(
        RideRatingSignature.verify(rating, assinatura, identidade),
        isTrue,
      );
    });

    test('dado adulterado depois de assinado não valida', () {
      final identidade = _identidadeDeTeste();
      final original = RideRating(
        rideId: 'quote-1',
        stars: 4,
        ratedAt: DateTime(2026, 9, 23, 10),
      );
      final assinatura = RideRatingSignature.sign(original, identidade);

      final adulterado = RideRating(
        rideId: 'quote-1',
        stars: 1,
        ratedAt: original.ratedAt,
      );

      expect(
        RideRatingSignature.verify(adulterado, assinatura, identidade),
        isFalse,
      );
    });

    test('assinatura de outra identidade não valida', () {
      final identidadeA = _identidadeDeTeste();
      final identidadeB = _identidadeDeTeste();
      final rating = RideRating(
        rideId: 'quote-1',
        stars: 4,
        ratedAt: DateTime(2026, 9, 23, 10),
      );

      final assinatura = RideRatingSignature.sign(rating, identidadeA);

      expect(
        RideRatingSignature.verify(rating, assinatura, identidadeB),
        isFalse,
      );
    });

    test('signature nula nunca valida', () {
      final identidade = _identidadeDeTeste();
      final rating = RideRating(
        rideId: 'quote-1',
        stars: 4,
        ratedAt: DateTime(2026, 9, 23, 10),
      );

      expect(RideRatingSignature.verify(rating, null, identidade), isFalse);
    });

    test('signature em formato inválido não lança, só falha a validação', () {
      final identidade = _identidadeDeTeste();
      final rating = RideRating(
        rideId: 'quote-1',
        stars: 4,
        ratedAt: DateTime(2026, 9, 23, 10),
      );

      expect(
        () => RideRatingSignature.verify(rating, 'não-é-hex', identidade),
        returnsNormally,
      );
      expect(
        RideRatingSignature.verify(rating, 'não-é-hex', identidade),
        isFalse,
      );
    });

    test('canonicalPayload é determinístico para os mesmos valores', () {
      final rating = RideRating(
        rideId: 'quote-1',
        stars: 4,
        ratedAt: DateTime(2026, 9, 23, 10),
      );

      expect(
        RideRatingSignature.canonicalPayload(rating),
        RideRatingSignature.canonicalPayload(rating),
      );
    });

    test('canonicalPayload difere para stars diferentes', () {
      final ratedAt = DateTime(2026, 9, 23, 10);
      final a = RideRating(rideId: 'quote-1', stars: 3, ratedAt: ratedAt);
      final b = RideRating(rideId: 'quote-1', stars: 4, ratedAt: ratedAt);

      expect(
        RideRatingSignature.canonicalPayload(a),
        isNot(RideRatingSignature.canonicalPayload(b)),
      );
    });
  });
}
