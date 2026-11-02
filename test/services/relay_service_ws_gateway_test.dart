import 'dart:convert';

import 'package:driver/domain/driver_coverage.dart';
import 'package:driver/domain/nostr_event.dart' as domain;
import 'package:driver/domain/relay.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:driver/services/relay_service.dart';
import 'package:driver/services/ws_relay_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_relay_transport.dart';

/// O `RelayService` de produção sobre o `WsRelayGateway` novo, com transporte
/// dublê: a reconexão e a sonda funcionam como antes da troca (feature 028,
/// US2). Prazos curtos de verdade; nenhuma rede.
void main() {
  const a = 'wss://a.test';
  const kinds = [
    domain.NostrEvent.kindRideRequest,
    domain.NostrEvent.kindQuoteAccepted,
  ];

  late FakeRelayTransport transport;
  late WsRelayGateway gateway;
  late RelayService service;

  setUp(() {
    transport = FakeRelayTransport();
    gateway = WsRelayGateway(
      transport: transport,
      connectionTimeout: const Duration(milliseconds: 100),
    );
    service = RelayService(
      gateway,
      subscriptionKinds: kinds,
      connectTimeout: const Duration(milliseconds: 100),
      livenessTimeout: const Duration(milliseconds: 40),
    );
  });

  tearDown(() async {
    await service.dispose();
    await gateway.dispose();
  });

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 5));

  Relay relay() => service.relays.single;

  final cobertura = DriverCoverage.around(
    lat: -28.9298,
    lon: -49.4753,
    radiusKm: 10,
  );

  test('relay conecta e fica connected', () async {
    await service.connectAll([const Relay(url: a)]);

    expect(relay().status, RelayStatus.connected);
  });

  test(
    'queda da conexão: unavailable; reconexão reinscreve, 20001 incluso',
    () async {
      await service.connectAll([const Relay(url: a)]);
      await service.applyCoverage(cobertura);
      final antigo = transport.lastSocket(a);

      await antigo.closeFromRelay();
      await pump();
      expect(relay().status, RelayStatus.unavailable);

      await service.reconnectUnavailable();

      expect(relay().status, RelayStatus.connected);
      final novo = transport.lastSocket(a);
      expect(identical(novo, antigo), isFalse);
      final ids = [
        for (final texto in novo.sent)
          if ((jsonDecode(texto) as List)[0] == 'REQ')
            (jsonDecode(texto) as List)[1],
      ];
      expect(ids, containsAll(['tcc-geral', 'tcc-solicitacoes']));
    },
  );

  test('sonda sem resposta: unavailable e socket fechado', () async {
    await service.connectAll([const Relay(url: a)]);

    final futuro = service.reconnectNow();
    await pump();
    await futuro;

    // O dublê nunca responde à sonda: o prazo estoura e o relay sai de
    // `connected`; a retentativa da mesma rodada o reconecta num socket novo.
    expect(transport.socketsFor(a).first.closed, isTrue);
  });

  test('sonda respondida mantém a conexão', () async {
    await service.connectAll([const Relay(url: a)]);
    final socket = transport.lastSocket(a);
    socket.messages.listen((_) {});

    final futuro = service.reconnectNow();
    await pump();
    socket.push(jsonEncode(['EOSE', 'vivacidade']));
    await futuro;

    expect(relay().status, RelayStatus.connected);
    expect(socket.closed, isFalse);
  });

  test('falha de handshake aparece resumida, nunca como texto cru', () async {
    transport.failOn(a, Exception('SocketException: Failed host lookup: x'));

    await service.connectAll([const Relay(url: a)]);

    expect(relay().status, RelayStatus.unavailable);
    expect(relay().lastError, 'endereço não encontrado');
  });

  test('removeRelay durante o handshake não deixa conexão órfã', () async {
    final gate = transport.hold(a);
    final conectando = service.connectAll([const Relay(url: a)]);
    await pump();

    await service.removeRelay(a);
    gate.complete();
    await conectando;
    await pump();

    expect(service.relays, isEmpty);
    expect(transport.lastSocket(a).closed, isTrue);
  });

  test('evento recebido chega ao incoming do serviço', () async {
    final recebidos = <IncomingEvent>[];
    await service.connectAll([const Relay(url: a)]);
    service.incoming.listen(recebidos.add);

    transport
        .lastSocket(a)
        .push(
          jsonEncode([
            'EVENT',
            'tcc-geral',
            {'id': '1' * 64, 'kind': 20003},
          ]),
        );
    await pump();

    expect(recebidos.single.payload['id'], '1' * 64);
  });
}
