import 'dart:convert';

import 'package:driver/domain/active_ride.dart';
import 'package:driver/domain/driver_ride_status.dart';
import 'package:driver/services/key_value_store.dart';
import 'package:driver/services/ride_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemoryStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _activeRide = ActiveRide(
  quoteId: 'quote-1',
  passengerPubkey: 'pub-1',
  originLat: -28.9298,
  originLon: -49.4753,
  destinationLat: -28.6721,
  destinationLon: -49.3671,
);

void main() {
  late InMemoryStore store;
  late RideStateStore repo;

  setUp(() {
    store = InMemoryStore();
    repo = PreferencesRideStateStore(store);
  });

  test(
    'na primeira execução devolve aguardandoSolicitacao sem corrida ativa',
    () async {
      final (status, active) = await repo.load();

      expect(status, DriverRideStatus.aguardandoSolicitacao);
      expect(active, isNull);
    },
  );

  test(
    'persiste e restaura o estado deslocandoAtePassageiro (FR-003)',
    () async {
      await repo.save(DriverRideStatus.deslocandoAtePassageiro, _activeRide);

      final (status, active) = await PreferencesRideStateStore(store).load();

      expect(status, DriverRideStatus.deslocandoAtePassageiro);
      expect(active, _activeRide);
    },
  );

  test('um registro antigo com arrivalNotified (feature 011) carrega sem erro '
      'e a chave é ignorada (feature 021)', () async {
    await store.write(
      PreferencesRideStateStore.storageKey,
      jsonEncode({
        'status': DriverRideStatus.deslocandoAtePassageiro.name,
        'quoteId': _activeRide.quoteId,
        'passengerPubkey': _activeRide.passengerPubkey,
        'originLat': _activeRide.originLat,
        'originLon': _activeRide.originLon,
        'destinationLat': _activeRide.destinationLat,
        'destinationLon': _activeRide.destinationLon,
        'arrivalNotified': true,
      }),
    );

    final (status, active) = await PreferencesRideStateStore(store).load();

    expect(status, DriverRideStatus.deslocandoAtePassageiro);
    expect(active, _activeRide);
  });

  test(
    'persiste e restaura destinationArrivalNotified: true (feature 012)',
    () async {
      final comChegadaAoDestinoAvisada = _activeRide.copyWith(
        destinationArrivalNotified: true,
      );
      await repo.save(DriverRideStatus.emCorrida, comChegadaAoDestinoAvisada);

      final (status, active) = await PreferencesRideStateStore(store).load();

      expect(status, DriverRideStatus.emCorrida);
      expect(active, comChegadaAoDestinoAvisada);
      expect(active!.destinationArrivalNotified, isTrue);
    },
  );

  test('salvar aguardandoSolicitacao limpa a corrida ativa', () async {
    await repo.save(DriverRideStatus.deslocandoAtePassageiro, _activeRide);

    await repo.save(DriverRideStatus.aguardandoSolicitacao, null);

    final (status, active) = await repo.load();
    expect(status, DriverRideStatus.aguardandoSolicitacao);
    expect(active, isNull);
  });

  test('estado corrompido volta ao default sem travar', () async {
    store.values[PreferencesRideStateStore.storageKey] = 'não é json';

    final (status, active) = await repo.load();

    expect(status, DriverRideStatus.aguardandoSolicitacao);
    expect(active, isNull);
  });
}
