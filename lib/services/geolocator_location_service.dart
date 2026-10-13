import 'package:geolocator/geolocator.dart' as geo;

import '../domain/driver_position.dart';
import 'location_service.dart';

/// Implementação real de [LocationService], sobre `geolocator` (decisão D1
/// de `specs/004-mapa-status-motorista/research.md`).
///
/// Único arquivo do aplicativo que importa `package:geolocator` — o domínio
/// e as telas conhecem só [LocationService] e [DriverPosition] (Princípio
/// III).
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<void> ensurePermission() async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable('serviço de localização desligado');
    }

    var permissao = await geo.Geolocator.checkPermission();
    if (permissao == geo.LocationPermission.denied) {
      permissao = await geo.Geolocator.requestPermission();
    }

    switch (permissao) {
      case geo.LocationPermission.denied:
        throw const LocationPermissionDenied();
      case geo.LocationPermission.deniedForever:
        throw const LocationPermissionDenied(permanently: true);
      case geo.LocationPermission.whileInUse:
      case geo.LocationPermission.always:
      case geo.LocationPermission.unableToDetermine:
        return;
    }
  }

  @override
  Stream<DriverPosition> get positions => geo.Geolocator.getPositionStream(
    locationSettings: const geo.LocationSettings(
      accuracy: geo.LocationAccuracy.high,
      distanceFilter: 0,
    ),
  ).map(_paraDriverPosition).handleError(_traduzErro, test: (_) => true);

  static DriverPosition _paraDriverPosition(geo.Position posicao) =>
      DriverPosition(
        latitude: posicao.latitude,
        longitude: posicao.longitude,
        capturedAt: posicao.timestamp,
      );

  /// Traduz exceções de `geolocator` para as exceções próprias do projeto —
  /// nenhum tipo da biblioteca escapa desta camada (Princípio III).
  static Never _traduzErro(Object erro, StackTrace? stack) {
    switch (erro) {
      case geo.LocationServiceDisabledException():
        throw const LocationUnavailable('serviço de localização desligado');
      case geo.PermissionDeniedException():
        throw const LocationPermissionDenied();
      default:
        throw LocationUnavailable(erro);
    }
  }
}
