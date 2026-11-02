/// Corrida em andamento — existe só quando o motorista está em
/// [DriverRideStatus.deslocandoAtePassageiro] ou [DriverRideStatus.emCorrida]
/// (`driver_ride_status.dart`).
///
/// `data-model.md` da feature 010, ampliada pela feature 011 com a origem
/// da solicitação, e pela feature 012 com o destino e a marca de chegada ao
/// destino já avisada. A marca de chegada à origem já avisada, da 011, foi
/// removida pela feature 021 (o aviso passou a ser periódico).
class ActiveRide {
  const ActiveRide({
    required this.quoteId,
    required this.passengerPubkey,
    required this.originLat,
    required this.originLon,
    required this.destinationLat,
    required this.destinationLon,
    this.destinationArrivalNotified = false,
  });

  /// `id` do evento `kind: 20002` (orçamento) que foi aceito — mesma
  /// referência usada na tag `["e", ...]` dos eventos publicados durante o
  /// deslocamento (`kind: 20005`/`20006`/`20007`/`20009`).
  final String quoteId;

  /// Chave pública do passageiro que aceitou, lida do campo `pubkey` (autor)
  /// do evento de aceitação (`kind: 20003`) — destinatário de toda
  /// publicação feita enquanto esta corrida estiver ativa.
  final String passengerPubkey;

  /// Coordenada de origem da solicitação (`kind: 20001`) respondida pelo
  /// orçamento aceito — lida de `SentQuotesStore.originFor` no momento em
  /// que a corrida começa (feature 011, D1 de `research.md`). Mesmo estilo
  /// de `DriverPosition`: dois `double`, sem tipo de terceiro no domínio.
  final double originLat;
  final double originLon;

  /// Coordenada de destino da mesma solicitação — lida de
  /// `SentQuotesStore.destinationFor` no mesmo momento (feature 012, D1/D2
  /// de `research.md` dela).
  final double destinationLat;
  final double destinationLon;

  /// Verdadeiro depois que a mensagem de chegada ao destino (`kind: 20009`)
  /// já foi publicada para esta corrida — impede reenvio, inclusive através de
  /// um reinício do app, já que `ActiveRide` é persistida por `RideStateStore`
  /// (FR-011 da feature 012, D2 de `research.md` dela). A chegada à origem
  /// (`kind: 20007`) não tem marca equivalente desde a feature 021: é
  /// publicada a cada 5 s enquanto vale, controlada só em memória.
  final bool destinationArrivalNotified;

  ActiveRide copyWith({bool? destinationArrivalNotified}) => ActiveRide(
    quoteId: quoteId,
    passengerPubkey: passengerPubkey,
    originLat: originLat,
    originLon: originLon,
    destinationLat: destinationLat,
    destinationLon: destinationLon,
    destinationArrivalNotified:
        destinationArrivalNotified ?? this.destinationArrivalNotified,
  );

  @override
  bool operator ==(Object other) =>
      other is ActiveRide &&
      other.quoteId == quoteId &&
      other.passengerPubkey == passengerPubkey &&
      other.originLat == originLat &&
      other.originLon == originLon &&
      other.destinationLat == destinationLat &&
      other.destinationLon == destinationLon &&
      other.destinationArrivalNotified == destinationArrivalNotified;

  @override
  int get hashCode => Object.hash(
    quoteId,
    passengerPubkey,
    originLat,
    originLon,
    destinationLat,
    destinationLon,
    destinationArrivalNotified,
  );

  @override
  String toString() =>
      'ActiveRide($quoteId, passenger: $passengerPubkey, '
      'origin: ($originLat, $originLon), '
      'destination: ($destinationLat, $destinationLon), '
      'destinationArrivalNotified: $destinationArrivalNotified)';
}
