import 'dart:convert';

import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/reputation.dart';
import 'package:driver/domain/ride_request_received.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/receipt_fixtures.dart';

NostrEvent _eventoDe(String content, {String id = 'id-1'}) => NostrEvent(
  id: id,
  authorPublicKey: 'a' * 64,
  createdAt: DateTime.now(),
  kind: NostrEvent.kindRideRequest,
  content: content,
  isSignatureValid: true,
);

void main() {
  group(
    'RideRequestReceived.fromNostrEvent (data-model.md da feature 007)',
    () {
      test('decodifica origin, destination e payment de um content válido', () {
        final evento = _eventoDe(
          '{"origin":{"lat":-28.9298,"lon":-49.4753},'
          '"destination":{"lat":-28.6721,"lon":-49.3671},'
          '"payment":"pix"}',
          id: 'id-da-solicitacao',
        );

        final solicitacao = RideRequestReceived.fromNostrEvent(evento);

        expect(solicitacao.requestId, 'id-da-solicitacao');
        expect(solicitacao.origin, const LatLng(-28.9298, -49.4753));
        expect(solicitacao.destination, const LatLng(-28.6721, -49.3671));
        expect(solicitacao.payment, 'pix');
      });

      test('lança FormatException para content que não é JSON', () {
        expect(
          () => RideRequestReceived.fromNostrEvent(_eventoDe('não é json')),
          throwsFormatException,
        );
      });

      test('lança FormatException para content sem o campo origin', () {
        expect(
          () => RideRequestReceived.fromNostrEvent(
            _eventoDe('{"destination":{"lat":1,"lon":2},"payment":"pix"}'),
          ),
          throwsFormatException,
        );
      });
    },
  );

  group('RideRequestReceived — reputacao (emenda 25, feature 026)', () {
    Map<String, dynamic> base() => {
      'origin': {'lat': -28.9298, 'lon': -49.4753},
      'destination': {'lat': -28.6721, 'lon': -49.3671},
      'payment': 'pix',
    };

    NostrEvent evento(Map<String, dynamic> content) =>
        _eventoDe(jsonEncode(content));

    test('reputacao presente é lida', () {
      final dono = newTestIdentity().publicKey;
      final cadeia = signedChain(avaliado: dono, notas: [5, 4]);
      final rep = Reputation(
        corridas: 2,
        avaliacoes: 2,
        media: 4.5,
        seqProximo: 2,
        head: cadeia.last.idRecibo,
        recibos: cadeia.reversed.toList(),
      );

      final s = RideRequestReceived.fromNostrEvent(
        evento(base()..['reputacao'] = rep.toJson()),
      );

      expect(s.reputation, rep);
    });

    test('reputacao ausente → null', () {
      expect(
        RideRequestReceived.fromNostrEvent(evento(base())).reputation,
        isNull,
      );
    });

    test('reputacao malformada → null, e a solicitação continua válida', () {
      final malformadas = <Object?>[
        'texto',
        42,
        <String, dynamic>{},
        {
          'corridas': 'muitas',
          'avaliacoes': 0,
          'seq_proximo': 0,
          'recibos': [],
        },
        {
          'corridas': 1,
          'avaliacoes': 1,
          'seq_proximo': 1,
          'recibos': [
            {'v': 1},
          ],
        },
      ];
      for (final ruim in malformadas) {
        final s = RideRequestReceived.fromNostrEvent(
          evento(base()..['reputacao'] = ruim),
        );
        expect(s.reputation, isNull, reason: '$ruim');
        expect(s.payment, 'pix');
        expect(s.origin, const LatLng(-28.9298, -49.4753));
      }
    });

    test(
      'campo obrigatório faltando continua lançando, com ou sem reputacao',
      () {
        final semOrigem = base()
          ..remove('origin')
          ..['reputacao'] = const Reputation.empty().toJson();
        expect(
          () => RideRequestReceived.fromNostrEvent(evento(semOrigem)),
          throwsFormatException,
        );
      },
    );
  });
}
