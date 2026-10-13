import 'package:dart_nostr/dart_nostr.dart' as nostr;

/// Verificação criptográfica de um evento recebido.
///
/// Abstração do projeto: permite dublê em teste e mantém `dart_nostr` fora do
/// `EventFeed` (Princípio III).
abstract class EventVerifier {
  /// Verdadeiro somente se o identificador confere com o conteúdo **e** a
  /// assinatura confere com a chave pública do autor.
  bool isValid(Map<String, dynamic> payload);
}

/// Implementação sobre `dart_nostr`.
///
/// Atenção: `NostrEvent.isVerified()` da biblioteca apenas confere a assinatura
/// sobre o `id` informado — **não** recalcula o `id` a partir do conteúdo. Um
/// evento com conteúdo adulterado e `id`/`sig` originais passaria por aquela
/// checagem. Por isso esta classe recalcula o identificador canônico antes de
/// verificar a assinatura (FR-009).
class NostrEventVerifier implements EventVerifier {
  const NostrEventVerifier();

  @override
  bool isValid(Map<String, dynamic> payload) {
    try {
      final id = payload['id'] as String?;
      final pubkey = payload['pubkey'] as String?;
      final sig = payload['sig'] as String?;
      final kind = payload['kind'] as int?;
      final content = payload['content'] as String?;
      final createdAtRaw = payload['created_at'] as int?;
      final tagsRaw = payload['tags'] as List<dynamic>?;

      if (id == null ||
          pubkey == null ||
          sig == null ||
          kind == null ||
          content == null ||
          createdAtRaw == null) {
        return false; // campo obrigatório ausente
      }

      final tags = (tagsRaw ?? const <dynamic>[])
          .map((t) => (t as List<dynamic>).map((e) => e.toString()).toList())
          .toList();

      final recomputedId = nostr.NostrEvent.getEventId(
        kind: kind,
        content: content,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtRaw * 1000),
        tags: tags,
        pubkey: pubkey,
      );

      if (recomputedId != id) return false; // conteúdo adulterado

      return nostr.NostrKeyPairs.verify(pubkey, id, sig);
    } catch (_) {
      // Evento malformado é evento inválido, nunca uma exceção que sobe à UI.
      return false;
    }
  }
}
