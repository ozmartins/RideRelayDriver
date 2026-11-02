import 'package:dart_nostr/dart_nostr.dart' as nostr;

import '../domain/identity.dart';
import '../domain/ride_rating.dart';

/// Canonicalização, assinatura e verificação das linhas de `ride_ratings`
/// (Row Signing, feature 014, D1/D2 de `research.md`).
///
/// Funções puras: nenhuma delas toca `sqflite` — testáveis diretamente,
/// como o Princípio II (NÃO NEGOCIÁVEL) exige para código que assina ou
/// verifica assinaturas.
class RideRatingSignature {
  const RideRatingSignature._();

  /// Representação canônica dos campos de dado de [rating] — `rideId`,
  /// `stars` e `ratedAt`, sempre nesta ordem, unidos por `|` (D2 de
  /// `research.md`). Nunca inclui `signature` nem `tampered`.
  static String canonicalPayload(RideRating rating) =>
      '${rating.rideId}|${rating.stars}|${rating.ratedAt.toIso8601String()}';

  /// Assina o payload canônico de [rating] com a chave privada de
  /// [identity]. `Nostr.instance.services.keys.sign` já calcula o hash
  /// SHA-256 do payload internamente antes de assinar (D1 de
  /// `research.md`) — nenhum hashing manual aqui.
  static String sign(RideRating rating, Identity identity) => nostr
      .Nostr
      .instance
      .services
      .keys
      .sign(privateKey: identity.privateKey, message: canonicalPayload(rating));

  /// Verdadeiro somente se [signature] validar contra o payload canônico
  /// de [rating] e a chave pública de [identity]. `signature: null`
  /// (registro sem assinatura, FR-007) sempre devolve falso, pelo mesmo
  /// caminho de uma assinatura adulterada.
  static bool verify(RideRating rating, String? signature, Identity identity) {
    if (signature == null) return false;
    try {
      return nostr.Nostr.instance.services.keys.verify(
        publicKey: identity.publicKey,
        message: canonicalPayload(rating),
        signature: signature,
      );
    } on Object {
      return false; // assinatura em formato inválido não é um erro fatal
    }
  }
}
