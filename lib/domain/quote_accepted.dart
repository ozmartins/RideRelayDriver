import 'nostr_event.dart';

/// Aceitação de orçamento recebida, já verificada e deduplicada pelo
/// `EventFeed` (regras de recepção do contrato de eventos) antes de chegar
/// aqui.
///
/// Formato definido na emenda 07 do contrato
/// (`specs/002-nostr-relay-connection/contracts/nostr-events.md`) —
/// `data-model.md` da feature 010.
class QuoteAccepted {
  const QuoteAccepted({
    required this.eventId,
    required this.quoteId,
    required this.passengerPubkey,
  });

  /// `id` do próprio evento de aceitação (`kind: 20003`) — usado para
  /// deduplicação (FR-012).
  final String eventId;

  /// `id` do orçamento (`kind: 20002`) aceito, lido da tag `["e", ...]`.
  final String quoteId;

  /// Chave pública de quem aceitou, lida do campo `pubkey` (autor) do
  /// evento — não de uma tag (a tag `["p", ...]` da aceitação aponta ao
  /// motorista, não ao passageiro).
  final String passengerPubkey;

  /// Decodifica um [NostrEvent] de `kind: 20003` para esta entidade.
  ///
  /// Lança [FormatException] se a tag `["e", "<id>"]` estiver ausente —
  /// quem chama descarta o evento sem modal nem notificação, nunca
  /// processando uma tag malformada (regra 3 de recepção: `content`/tags são
  /// dado, mesmo padrão de `RideRequestReceived.fromNostrEvent`).
  factory QuoteAccepted.fromNostrEvent(NostrEvent event) {
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 'e') {
        return QuoteAccepted(
          eventId: event.id,
          quoteId: tag[1],
          passengerPubkey: event.authorPublicKey,
        );
      }
    }
    throw const FormatException(
      'Aceitação de orçamento sem tag "e" referenciando o orçamento',
    );
  }

  @override
  String toString() =>
      'QuoteAccepted($eventId, quote: $quoteId, passenger: $passengerPubkey)';
}
