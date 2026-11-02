import 'dart:convert';

import '../domain/active_ride.dart';
import '../domain/driver_ride_status.dart';
import 'key_value_store.dart';

/// Persiste o estado do motorista introduzido pela feature 010 — mesmo
/// mecanismo já usado por `RelayRepository` (D1 de `research.md`).
///
/// Ao contrário de `AvailabilityStatus` (nunca persistido), este estado MUST
/// sobreviver ao fechamento do app (FR-003, FR-009).
abstract class RideStateStore {
  /// `(aguardandoSolicitacao, null)` se nenhum estado foi salvo ainda —
  /// mesmo default do enum quando não há nada persistido.
  Future<(DriverRideStatus, ActiveRide?)> load();

  /// Grava o par status + corrida ativa. `active` MUST ser `null` quando
  /// `status` é `aguardandoSolicitacao` — não há corrida ativa nesse estado.
  Future<void> save(DriverRideStatus status, ActiveRide? active);
}

/// Implementação real sobre `KeyValueStore`, como um único valor JSON —
/// mesma decisão de atomicidade já usada por `RelayRepository`.
class PreferencesRideStateStore implements RideStateStore {
  PreferencesRideStateStore(this._store);

  final KeyValueStore _store;

  static const String storageKey = 'driver_ride_state';

  @override
  Future<(DriverRideStatus, ActiveRide?)> load() async {
    final raw = await _store.read(storageKey);
    if (raw == null) {
      return (DriverRideStatus.aguardandoSolicitacao, null);
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final status = DriverRideStatus.values.byName(
        decoded['status'] as String,
      );
      if (status == DriverRideStatus.aguardandoSolicitacao) {
        return (status, null);
      }
      return (
        status,
        ActiveRide(
          quoteId: decoded['quoteId'] as String,
          passengerPubkey: decoded['passengerPubkey'] as String,
          originLat: (decoded['originLat'] as num).toDouble(),
          originLon: (decoded['originLon'] as num).toDouble(),
          destinationLat: (decoded['destinationLat'] as num).toDouble(),
          destinationLon: (decoded['destinationLon'] as num).toDouble(),
          destinationArrivalNotified:
              decoded['destinationArrivalNotified'] as bool? ?? false,
        ),
      );
    } catch (_) {
      // Estado corrompido não trava o app: volta ao default, mesma postura
      // de robustez já usada por `RelayRepository.load`.
      return (DriverRideStatus.aguardandoSolicitacao, null);
    }
  }

  @override
  Future<void> save(DriverRideStatus status, ActiveRide? active) async {
    await _store.write(
      storageKey,
      jsonEncode({
        'status': status.name,
        if (active != null) 'quoteId': active.quoteId,
        if (active != null) 'passengerPubkey': active.passengerPubkey,
        if (active != null) 'originLat': active.originLat,
        if (active != null) 'originLon': active.originLon,
        if (active != null) 'destinationLat': active.destinationLat,
        if (active != null) 'destinationLon': active.destinationLon,
        if (active != null)
          'destinationArrivalNotified': active.destinationArrivalNotified,
      }),
    );
  }
}
