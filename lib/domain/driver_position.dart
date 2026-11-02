/// Posição geográfica atual do motorista.
///
/// Existe apenas em memória, lida continuamente do sensor de localização do
/// aparelho enquanto a tela de mapa está em primeiro plano; nunca persistida
/// nem enviada a relay ou servidor nesta feature (Assumptions do `spec.md`).
class DriverPosition {
  const DriverPosition({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
  });

  /// Latitude em graus decimais.
  final double latitude;

  /// Longitude em graus decimais.
  final double longitude;

  /// Instante em que esta posição foi lida do sensor.
  final DateTime capturedAt;

  @override
  bool operator ==(Object other) =>
      other is DriverPosition &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.capturedAt == capturedAt;

  @override
  int get hashCode => Object.hash(latitude, longitude, capturedAt);

  @override
  String toString() => 'DriverPosition($latitude, $longitude em $capturedAt)';
}
