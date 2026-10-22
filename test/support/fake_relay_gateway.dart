import 'dart:async';

import 'package:driver/domain/nostr_event.dart';
import 'package:driver/services/relay_gateway.dart';

/// Transporte dublê: nenhum teste toca a rede (decisão D5).
class FakeRelayGateway implements RelayGateway {
  final List<String> connected = [];
  final List<String> disconnected = [];
  final List<Map<String, dynamic>> published = [];
  final Map<String, int> probes = {};
  int subscribeCalls = 0;
  List<PublishOutcome> publishOutcomes = const [];

  final _events = StreamController<IncomingEvent>.broadcast();
  final _lost = StreamController<String>.broadcast();

  @override
  Stream<String> get connectionLost => _lost.stream;

  void drop(String relayUrl) => _lost.add(relayUrl);

  @override
  Future<void> connect(String relayUrl) async => connected.add(relayUrl);

  @override
  Future<void> disconnect(String relayUrl) async => disconnected.add(relayUrl);

  @override
  Future<void> probe(String relayUrl) async =>
      probes.update(relayUrl, (n) => n + 1, ifAbsent: () => 1);

  /// Células pedidas na última [subscribe] (nulas = sem `20001`).
  List<String>? subscribedCells;

  /// Cada chamada de [setRideRequestCells], em ordem.
  final List<List<String>?> cellsCalls = [];

  @override
  Stream<IncomingEvent> subscribe({
    required List<int> kinds,
    List<String>? rideRequestCells,
  }) {
    subscribeCalls++;
    subscribedCells = rideRequestCells;
    return _events.stream;
  }

  @override
  Future<void> setRideRequestCells(List<String>? cells) async =>
      cellsCalls.add(cells);

  @override
  Stream<PublishOutcome> publish(
    NostrEvent event, {
    required Map<String, dynamic> payload,
  }) {
    published.add(payload);
    return Stream.fromIterable(publishOutcomes);
  }

  void emitPayload(String relayUrl, Map<String, dynamic> payload) =>
      _events.add(IncomingEvent(relayUrl: relayUrl, payload: payload));
}
