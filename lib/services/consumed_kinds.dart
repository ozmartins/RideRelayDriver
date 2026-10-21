import '../domain/nostr_event.dart';

/// Kinds que este app efetivamente consome — MUST corresponder à seção
/// "Forma da inscrição" do contrato de eventos, e MUST ser o mesmo conjunto
/// usado na inscrição real ao relay (`RelayService.subscriptionKinds`) e no
/// filtro do `EventFeed` (`acceptedKinds`). Vive aqui, e não em `main.dart`,
/// porque o serviço em segundo plano (feature 025) assina com o mesmo conjunto.
///
/// `kindQuoteAccepted` (20003) entrou na feature 010: sem ele, a aceitação de
/// um orçamento nunca chega.
const Set<int> driverConsumedKinds = {
  NostrEvent.kindRideRequest,
  NostrEvent.kindQuoteAccepted,
  NostrEvent.kindMeetingConfirmed,
  NostrEvent.kindDestinationConfirmed,
  NostrEvent.kindRideCancelledByPassenger,
  // Emenda 25 (feature 026): recibos de avaliação e confirmações.
  NostrEvent.kindReceipt,
  NostrEvent.kindReceiptAck,
};
