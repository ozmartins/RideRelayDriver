import '../domain/driver_position.dart';

/// Acesso à localização do aparelho.
///
/// Abstração do projeto (Princípio III): a implementação real usa
/// `geolocator` (decisão D1 de `specs/004-mapa-status-motorista/research.md`);
/// os testes usam um dublê em memória, seguindo o mesmo padrão de
/// `CadastroStore` e `KeyStore` — nenhum teste toca sensor real.
abstract class LocationService {
  /// Fluxo de posições do motorista, uma nova [DriverPosition] a cada leitura
  /// do sensor, enquanto a tela de mapa estiver em uso (FR-003).
  ///
  /// Emite [LocationPermissionDenied] como erro do fluxo se a permissão for
  /// negada (inclusive se revogada em uso), ou [LocationUnavailable] se a
  /// localização deixar de estar disponível por qualquer outro motivo — sinal
  /// perdido, serviço de localização desligado no aparelho.
  Stream<DriverPosition> get positions;

  /// Confere a permissão de localização e a solicita ao motorista se ainda
  /// não tiver sido concedida, explicando o motivo (FR-004).
  ///
  /// Lança [LocationPermissionDenied] se o motorista negar, ou
  /// [LocationUnavailable] se o serviço de localização do aparelho estiver
  /// desligado.
  Future<void> ensurePermission();
}

/// O motorista negou a permissão de localização — ou nunca a concedeu.
class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied({this.permanently = false});

  /// Verdadeiro quando o sistema não vai perguntar de novo (motorista marcou
  /// "não perguntar novamente") — a mensagem exibida precisa indicar as
  /// configurações do aparelho em vez de insistir com o pedido.
  final bool permanently;

  @override
  String toString() =>
      'Permissão de localização negada'
      '${permanently ? ' (permanentemente)' : ''}.';
}

/// A localização está indisponível por um motivo que não é falta de
/// permissão — serviço de localização desligado, sinal perdido.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.cause);
  final Object? cause;

  @override
  String toString() => 'Localização indisponível: ${cause ?? "sinal perdido"}';
}
