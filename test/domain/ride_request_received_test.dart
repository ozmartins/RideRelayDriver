import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/ride_request_received.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

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
}
