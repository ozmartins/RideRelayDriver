import 'dart:convert';

import 'package:driver/domain/driver_ride_status.dart';
import 'package:driver/domain/relay.dart';
import 'package:driver/domain/service_state.dart';
import 'package:driver/services/background/service_messages.dart';
import 'package:driver/services/relay_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

const _payload = <String, dynamic>{
  'id': 'abc',
  'pubkey': 'p',
  'kind': 20001,
  'content': '{}',
  'tags': [
    ['t', 'tcc-ufsc-caronas'],
  ],
  'sig': 's',
};

const _relays = [
  Relay(url: 'wss://a.test', status: RelayStatus.connected, isDefault: true),
  Relay(
    url: 'wss://b.test',
    status: RelayStatus.unavailable,
    lastError: 'sem resposta',
  ),
];

final List<ServiceMessage> _todas = [
  const ServiceReady(),
  const ServiceHello(foreground: true),
  const ServiceHelloAck(online: true, relays: _relays, pending: [_payload]),
  const ServiceStateUpdate(
    ServiceState(
      online: true,
      acceptedPayments: {'pix'},
      rideStatus: DriverRideStatus.emCorrida,
      appInForeground: true,
    ),
  ),
  const ServiceConnectAll(_relays),
  const ServiceAddRelay('wss://c.test'),
  const ServiceRemoveRelay('wss://c.test'),
  const ServiceReconnectNow(),
  const ServicePublish(reqId: 7, id: 'abc', payload: _payload),
  const ServicePublishResult(
    reqId: 7,
    outcomes: [
      PublishOutcome(relayUrl: 'wss://a.test', accepted: true),
      PublishOutcome(
        relayUrl: 'wss://b.test',
        accepted: false,
        message: 'blocked',
      ),
    ],
    done: true,
    error: 'no_relay',
  ),
  const ServiceRelaysChanged(_relays),
  const ServiceIncoming(relayUrl: 'wss://a.test', payload: _payload),
  const ServiceStop(),
];

void main() {
  group('ServiceMessage (contrato interno UI ↔ serviço, feature 025)', () {
    test('toda mensagem sobrevive à ida e volta pelo mapa', () {
      for (final mensagem in _todas) {
        final volta = ServiceMessage.fromMap(mensagem.toMap());

        expect(volta, isNotNull, reason: mensagem.type);
        expect(volta.runtimeType, mensagem.runtimeType);
        expect(volta!.toMap(), mensagem.toMap(), reason: mensagem.type);
      }
    });

    test(
      'o mapa é só de tipos primitivos, como o canal entre isolates exige',
      () {
        for (final mensagem in _todas) {
          // jsonEncode lança para qualquer objeto que não seja JSON puro.
          expect(() => jsonEncode(mensagem.toMap()), returnsNormally);
        }
      },
    );

    test('a ida e volta preserva os campos de ServiceHelloAck', () {
      final ack = ServiceMessage.fromMap(
        const ServiceHelloAck(
          online: true,
          relays: _relays,
          pending: [_payload],
        ).toMap(),
      ) as ServiceHelloAck;

      expect(ack.online, isTrue);
      expect(ack.relays.map((r) => r.url), ['wss://a.test', 'wss://b.test']);
      expect(ack.relays[0].status, RelayStatus.connected);
      expect(ack.relays[0].isDefault, isTrue);
      expect(ack.relays[1].lastError, 'sem resposta');
      expect(ack.pending.single['id'], 'abc');
    });

    test(
      'a ida e volta preserva ServiceStateUpdate e ServicePublishResult',
      () {
        final estado = ServiceMessage.fromMap(
          ServiceStateUpdate(
            const ServiceState(
              online: true,
              acceptedPayments: {'pix', 'cartao'},
              rideStatus: DriverRideStatus.deslocandoAtePassageiro,
            ),
          ).toMap(),
        ) as ServiceStateUpdate;
        expect(estado.state.online, isTrue);
        expect(estado.state.acceptedPayments, {'pix', 'cartao'});
        expect(
          estado.state.rideStatus,
          DriverRideStatus.deslocandoAtePassageiro,
        );

        final resultado =
            ServiceMessage.fromMap(_todas[9].toMap()) as ServicePublishResult;
        expect(resultado.reqId, 7);
        expect(resultado.done, isTrue);
        expect(resultado.error, 'no_relay');
        expect(resultado.outcomes[1].accepted, isFalse);
        expect(resultado.outcomes[1].message, 'blocked');
      },
    );

    test('versão diferente é ignorada sem erro', () {
      final mapa = const ServiceHello(foreground: true).toMap()..['v'] = 2;

      expect(ServiceMessage.fromMap(mapa), isNull);
    });

    test('tipo desconhecido é ignorado sem erro', () {
      expect(ServiceMessage.fromMap({'t': 'novo', 'v': 1}), isNull);
    });

    test('dado malformado nunca lança', () {
      for (final lixo in <Object?>[
        null,
        'texto',
        42,
        <Object?>[],
        <String, dynamic>{},
        {'t': 'hello', 'v': 1},
        {'t': 'publish', 'v': 1, 'reqId': 'x', 'id': 1, 'payload': 3},
        {'t': 'incoming', 'v': 1, 'relayUrl': null},
        {'t': 'relaysChanged', 'v': 1, 'relays': 'não é lista'},
      ]) {
        expect(
          () => ServiceMessage.fromMap(lixo),
          returnsNormally,
          reason: '$lixo',
        );
        expect(ServiceMessage.fromMap(lixo), isNull, reason: '$lixo');
      }
    });

    test(
      'nenhuma mensagem tem campo de chave, semente ou segredo (Princípio I)',
      () {
        final proibidos = RegExp(
          'priv|secret|nsec|seed|mnemonic',
          caseSensitive: false,
        );
        for (final mensagem in _todas) {
          final json = jsonEncode(mensagem.toMap());
          expect(proibidos.hasMatch(json), isFalse, reason: mensagem.type);
        }
      },
    );
  });
}
