import 'package:dart_nostr/dart_nostr.dart' as nostr;

import '../domain/identity.dart';
import '../domain/receipt.dart';

/// Assinatura e verificação de [Receipt] (emenda 25 do contrato, seção 1.2;
/// feature 026).
///
/// Funções puras, no estilo de `RideRatingSignature`: mesma API
/// `keys.sign/verify`, e a mensagem assinada é o `id_recibo`. Testáveis sem
/// SQLite nem relay (Princípio II).
class ReceiptSignature {
  const ReceiptSignature._();

  /// Assina `receipt.idRecibo` com a chave privada de [identity]. A chave nunca
  /// entra em hash, log ou evento (Princípio I).
  static String sign(Receipt receipt, Identity identity) => nostr
      .Nostr
      .instance
      .services
      .keys
      .sign(privateKey: identity.privateKey, message: receipt.idRecibo);

  /// Verdadeiro somente se o `id_recibo` confere com a forma canônica **e** a
  /// assinatura vale para `pubkey_avaliador`. Conferir só a assinatura deixaria
  /// passar um campo adulterado com o `id_recibo` antigo.
  static bool verify(Receipt receipt) {
    if (!receipt.hasConsistentId) return false;
    try {
      return nostr.Nostr.instance.services.keys.verify(
        publicKey: receipt.pubkeyAvaliador,
        message: receipt.idRecibo,
        signature: receipt.assinatura,
      );
    } on Object {
      return false; // assinatura ou chave em formato inválido não é fatal
    }
  }
}
