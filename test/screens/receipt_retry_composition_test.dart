import 'dart:async';

import 'package:driver/domain/driver_position.dart';
import 'package:driver/domain/nostr_event.dart';
import 'package:driver/main.dart';
import 'package:driver/services/default_relays.dart';
import 'package:driver/services/identity_service.dart';
import 'package:driver/services/key_store.dart';
import 'package:driver/services/key_value_store.dart';
import 'package:driver/services/location_service.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cadastro_store.dart';
import '../support/in_memory_receipt_store.dart';
import '../support/receipt_fixtures.dart';

class _Localizacao implements LocationService {
  @override
  Future<void> ensurePermission() async {}

  @override
  Stream<DriverPosition> get positions => const Stream.empty();
}

class _Chaves implements KeyStore {
  _Chaves(String privada)
    : values = {IdentityService.privateKeyStorageKey: privada};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Preferencias implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Gateway implements RelayGateway {
  final publicados = <NostrEvent>[];
  final _perdas = StreamController<String>.broadcast();

  void derrubar(String url) => _perdas.add(url);

  @override
  Stream<String> get connectionLost => _perdas.stream;

  @override
  Future<void> connect(String relayUrl) async {}

  @override
  Future<void> disconnect(String relayUrl) async {}

  @override
  Future<void> probe(String relayUrl) async {}

  @override
  Stream<IncomingEvent> subscribe({
    required List<int> kinds,
    List<String>? rideRequestCells,
  }) => const Stream.empty();

  @override
  Future<void> setRideRequestCells(List<String>? cells) async {}

  @override
  Stream<PublishOutcome> publish(
    NostrEvent event, {
    required Map<String, dynamic> payload,
  }) {
    publicados.add(event);
    return Stream.value(
      PublishOutcome(relayUrl: 'wss://a.test', accepted: true),
    );
  }
}

void main() {
  /// Abre o app com um recibo emitido pendente já em disco (de uma sessão
  /// anterior) e a identidade do motorista fixa.
  Future<({_Gateway gateway, InMemoryReceiptStore store})> abrir(
    WidgetTester tester,
  ) async {
    final motorista = newTestIdentity();
    final store = InMemoryReceiptStore();
    await store.saveIssued(
      signedReceipt(
        avaliador: motorista,
        avaliado: newTestIdentity().publicKey,
        seq: 0,
        nota: 5,
        guid: fakeGuid(90),
      ),
    );
    final gateway = _Gateway();
    await tester.pumpWidget(
      CorridasDriverApp(
        keyStore: _Chaves(motorista.privateKey),
        keyValueStore: _Preferencias(),
        gateway: gateway,
        cadastroStore: FakeCadastroStore(null),
        locationService: _Localizacao(),
        receiptStore: store,
      ),
    );
    await tester.pump();
    await tester.pump();
    return (gateway: gateway, store: store);
  }

  Iterable<NostrEvent> recibos(_Gateway g) =>
      g.publicados.where((e) => e.kind == NostrEvent.kindReceipt);

  Future<void> encerrar(WidgetTester tester) async {
    // Desmonta o app: cancela os temporizadores (RelayService e recibos).
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('ao abrir o app, o recibo pendente é reenviado', (tester) async {
    final a = await abrir(tester);

    expect(recibos(a.gateway), isNotEmpty);

    await encerrar(tester);
  });

  testWidgets('a cada 60 s o pendente é reenviado, até a confirmação', (
    tester,
  ) async {
    final a = await abrir(tester);
    final aoAbrir = recibos(a.gateway).length;

    await tester.pump(const Duration(seconds: 59));
    expect(recibos(a.gateway).length, aoAbrir);

    await tester.pump(const Duration(seconds: 1));
    expect(recibos(a.gateway).length, aoAbrir + 1);

    final pendente = (await a.store.pendingIssued()).single;
    await a.store.markAcked(pendente.idRecibo);
    await tester.pump(const Duration(seconds: 120));
    expect(recibos(a.gateway).length, aoAbrir + 1);

    await encerrar(tester);
  });

  testWidgets('a cada reconexão de relay o pendente é reenviado', (
    tester,
  ) async {
    final a = await abrir(tester);
    final aoAbrir = recibos(a.gateway).length;

    for (final url in defaultRelayUrls) {
      a.gateway.derrubar(url);
    }
    await tester.pump();
    // A retentativa automática do RelayService (15 s) reconecta e avisa.
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();

    expect(recibos(a.gateway).length, greaterThan(aoAbrir));

    await encerrar(tester);
  });

  testWidgets('ao desmontar o app o temporizador de recibos para', (
    tester,
  ) async {
    final a = await abrir(tester);
    final aoAbrir = recibos(a.gateway).length;

    await encerrar(tester);
    await tester.pump(const Duration(minutes: 5));

    expect(recibos(a.gateway).length, aoAbrir);
  });
}
