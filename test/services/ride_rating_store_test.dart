import 'package:dart_nostr/dart_nostr.dart' as nostr;
import 'package:driver/domain/identity.dart';
import 'package:driver/domain/ride_rating.dart';
import 'package:driver/services/ride_rating_signature.dart';
import 'package:driver/services/ride_rating_store.dart';
import 'package:flutter_test/flutter_test.dart';

Identity _identidadeDeTeste() {
  final par = nostr.Nostr.instance.services.keys.generateKeyPair();
  return Identity(publicKey: par.public, privateKey: par.private);
}

/// Linha crua, como estaria persistida no banco — usada para simular
/// adulteração (alterar um campo sem tocar na assinatura) e dados legados
/// (sem assinatura), sem precisar de SQLite real (D4 de `research.md` da
/// feature 014).
class LinhaBrutaDeTeste {
  LinhaBrutaDeTeste({required this.rating, this.signature});

  RideRating rating;
  String? signature;
  bool tampered = false;
}

/// Dublê em memória de `RideRatingStore` que reproduz a mesma lógica de
/// decisão da implementação real (`SqfliteRideRatingStore`) — usa as mesmas
/// funções puras de `RideRatingSignature` (D3/D4 de `research.md` da
/// feature 014). Exerce o contrato da store sem tocar SQLite.
class InMemoryRideRatingStore implements RideRatingStore {
  final _linhas = <String, LinhaBrutaDeTeste>{};

  /// Contagem de chamadas a `RideRatingSignature.verify` feitas por
  /// `forRide` — usada para provar que uma linha já marcada como violada
  /// não é revalidada (FR-005).
  int verifyCount = 0;

  /// Insere uma linha diretamente, simulando um estado já persistido (dado
  /// legado sem assinatura, ou um registro adulterado por fora do app) —
  /// sem passar por [save].
  void inserirBruta(LinhaBrutaDeTeste linha) =>
      _linhas[linha.rating.rideId] = linha;

  LinhaBrutaDeTeste? linhaCrua(String rideId) => _linhas[rideId];

  @override
  Future<void> save(RideRating rating, Identity identity) async {
    final assinatura = RideRatingSignature.sign(rating, identity);
    _linhas[rating.rideId] = LinhaBrutaDeTeste(
      rating: rating,
      signature: assinatura,
    );
  }

  @override
  Future<RideRating?> forRide(String rideId, Identity identity) async {
    final linha = _linhas[rideId];
    if (linha == null) return null;
    if (linha.tampered) return null;

    verifyCount++;
    final valido = RideRatingSignature.verify(
      linha.rating,
      linha.signature,
      identity,
    );
    if (!valido) {
      linha.tampered = true;
      return null;
    }
    return linha.rating;
  }
}

void main() {
  group(
    'RideRatingStore — US1: avaliação gravada com prova de integridade',
    () {
      test(
        'save persiste a linha com signature preenchida e tampered = false',
        () async {
          final store = InMemoryRideRatingStore();
          final identidade = _identidadeDeTeste();
          final rating = RideRating(
            rideId: 'quote-1',
            stars: 4,
            ratedAt: DateTime(2026, 9, 23, 10),
          );

          await store.save(rating, identidade);

          final linha = store.linhaCrua('quote-1')!;
          expect(linha.signature, isNotNull);
          expect(linha.tampered, isFalse);
        },
      );

      test('forRide, logo após save sem alteração externa, devolve a mesma '
          'avaliação', () async {
        final store = InMemoryRideRatingStore();
        final identidade = _identidadeDeTeste();
        final rating = RideRating(
          rideId: 'quote-1',
          stars: 4,
          ratedAt: DateTime(2026, 9, 23, 10),
        );
        await store.save(rating, identidade);

        final lida = await store.forRide('quote-1', identidade);

        expect(lida, isNotNull);
        expect(lida!.rideId, 'quote-1');
        expect(lida.stars, 4);
        expect(store.linhaCrua('quote-1')!.tampered, isFalse);
      });
    },
  );

  group('RideRatingStore — US2: registro adulterado é detectado e descartado '
      'na leitura', () {
    test('stars alterado diretamente faz forRide devolver null', () async {
      final store = InMemoryRideRatingStore();
      final identidade = _identidadeDeTeste();
      final original = RideRating(
        rideId: 'quote-1',
        stars: 4,
        ratedAt: DateTime(2026, 9, 23, 10),
      );
      await store.save(original, identidade);

      // Adulteração fora do app: o valor muda, a assinatura não.
      final linha = store.linhaCrua('quote-1')!;
      linha.rating = RideRating(
        rideId: 'quote-1',
        stars: 1,
        ratedAt: original.ratedAt,
      );

      final lida = await store.forRide('quote-1', identidade);

      expect(lida, isNull);
    });

    test('depois da adulteração detectada, a linha fica marcada como '
        'violada', () async {
      final store = InMemoryRideRatingStore();
      final identidade = _identidadeDeTeste();
      final original = RideRating(
        rideId: 'quote-1',
        stars: 4,
        ratedAt: DateTime(2026, 9, 23, 10),
      );
      await store.save(original, identidade);
      final linha = store.linhaCrua('quote-1')!;
      linha.rating = RideRating(
        rideId: 'quote-1',
        stars: 1,
        ratedAt: original.ratedAt,
      );

      await store.forRide('quote-1', identidade);

      expect(store.linhaCrua('quote-1')!.tampered, isTrue);
    });

    test('uma segunda leitura da linha já violada devolve null sem '
        'revalidar', () async {
      final store = InMemoryRideRatingStore();
      final identidade = _identidadeDeTeste();
      final original = RideRating(
        rideId: 'quote-1',
        stars: 4,
        ratedAt: DateTime(2026, 9, 23, 10),
      );
      await store.save(original, identidade);
      final linha = store.linhaCrua('quote-1')!;
      linha.rating = RideRating(
        rideId: 'quote-1',
        stars: 1,
        ratedAt: original.ratedAt,
      );
      await store.forRide('quote-1', identidade); // primeira leitura, marca

      final antes = store.verifyCount;
      final segunda = await store.forRide('quote-1', identidade);

      expect(segunda, isNull);
      expect(store.verifyCount, antes); // não chamou verify de novo
    });
  });

  group('RideRatingStore — US3: registros anteriores a este mecanismo são '
      'tratados como violados', () {
    test('linha sem signature faz forRide devolver null e marcar '
        'tampered', () async {
      final store = InMemoryRideRatingStore();
      final identidade = _identidadeDeTeste();
      store.inserirBruta(
        LinhaBrutaDeTeste(
          rating: RideRating(
            rideId: 'quote-legado',
            stars: 5,
            ratedAt: DateTime(2026, 9, 20, 8),
          ),
        ),
      );

      final lida = await store.forRide('quote-legado', identidade);

      expect(lida, isNull);
      expect(store.linhaCrua('quote-legado')!.tampered, isTrue);
    });
  });
}
