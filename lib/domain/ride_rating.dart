/// Avaliação de uma corrida feita pelo motorista — local ao app, nunca
/// publicada como evento Nostr (FR-005 da feature 013).
///
/// `data-model.md` da feature 013.
class RideRating {
  RideRating({
    required this.rideId,
    required this.stars,
    required this.ratedAt,
  }) {
    if (stars < 1 || stars > 5) {
      throw ArgumentError.value(stars, 'stars', 'deve ser um inteiro de 1 a 5');
    }
  }

  /// `ActiveRide.quoteId` da corrida avaliada — mesma referência já usada
  /// para correlacionar a corrida desde a feature 010. Identidade da
  /// avaliação: no máximo uma por corrida (FR-006).
  final String rideId;

  /// Nota de 1 a 5 (FR-003).
  final int stars;

  /// Momento em que a avaliação foi confirmada.
  final DateTime ratedAt;

  @override
  bool operator ==(Object other) =>
      other is RideRating &&
      other.rideId == rideId &&
      other.stars == stars &&
      other.ratedAt == ratedAt;

  @override
  int get hashCode => Object.hash(rideId, stars, ratedAt);

  @override
  String toString() => 'RideRating($rideId, stars: $stars, ratedAt: $ratedAt)';
}
