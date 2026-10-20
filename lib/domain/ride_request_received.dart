import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'nostr_event.dart';

/// Solicitação de corrida recebida, já verificada e deduplicada pelo
/// `EventFeed` (regras de recepção do contrato de eventos) antes de chegar
/// aqui.
///
/// Formato de `content` definido na emenda 04 do contrato
/// (`specs/002-nostr-relay-connection/contracts/nostr-events.md`) —
/// `origin`, `destination` e `payment`. `data-model.md` da feature 007.
class RideRequestReceived {
  const RideRequestReceived({
    required this.requestId,
    required this.passengerPubkey,
    required this.origin,
    required this.destination,
    required this.payment,
  });

  /// O `id` do evento `kind: 20001` original — usado na tag `["e", ...]` do
  /// orçamento (FR-017) e como chave de apresentação única.
  final String requestId;

  /// Chave pública do autor da solicitação (`pubkey` do evento `20001`): é o
  /// destinatário do orçamento — a tag `["p", ...]` e a chave da cifra (FR-001a
  /// de `specs/019-mensagens-cifradas/spec.md`, emenda 17 do contrato).
  final String passengerPubkey;

  final LatLng origin;
  final LatLng destination;

  /// `"dinheiro"`, `"pix"` ou `"cartao"` — dado exibido, nunca interpretado
  /// (regra 3 de recepção do contrato).
  final String payment;

  /// Decodifica um [NostrEvent] de `kind: 20001` para esta entidade.
  ///
  /// Lança [FormatException] se `content` não seguir o formato da emenda 04
  /// — quem chama descarta o evento sem exibir modal, nunca processando um
  /// conteúdo malformado (regra 3 de recepção: `content` é dado).
  factory RideRequestReceived.fromNostrEvent(NostrEvent event) {
    final Map<String, dynamic> content;
    try {
      content = jsonDecode(event.content) as Map<String, dynamic>;
      final origin = content['origin'] as Map<String, dynamic>;
      final destination = content['destination'] as Map<String, dynamic>;
      return RideRequestReceived(
        requestId: event.id,
        passengerPubkey: event.authorPublicKey,
        origin: LatLng(
          (origin['lat'] as num).toDouble(),
          (origin['lon'] as num).toDouble(),
        ),
        destination: LatLng(
          (destination['lat'] as num).toDouble(),
          (destination['lon'] as num).toDouble(),
        ),
        payment: content['payment'] as String,
      );
    } on Object catch (erro) {
      throw FormatException('Solicitação de corrida malformada: $erro');
    }
  }

  @override
  String toString() =>
      'RideRequestReceived($requestId, $origin → $destination, $payment)';
}
