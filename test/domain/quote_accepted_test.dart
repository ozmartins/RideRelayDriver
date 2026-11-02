import 'package:driver/domain/nostr_event.dart';
import 'package:driver/domain/quote_accepted.dart';
import 'package:flutter_test/flutter_test.dart';

NostrEvent eventoDeAceitacao({
  String id = 'id-da-aceitacao',
  String pubkey = 'pubkey-do-passageiro',
  List<List<String>> tags = const [
    ['t', 'tcc-ufsc-caronas'],
    ['e', 'id-do-orcamento'],
    ['p', 'pubkey-do-motorista'],
  ],
}) => NostrEvent(
  id: id,
  authorPublicKey: pubkey,
  createdAt: DateTime.now(),
  kind: NostrEvent.kindQuoteAccepted,
  content: '',
  isSignatureValid: true,
  tags: tags,
);

void main() {
  group('QuoteAccepted.fromNostrEvent (Princípio II)', () {
    test('decodifica um evento válido', () {
      final aceitacao = QuoteAccepted.fromNostrEvent(eventoDeAceitacao());

      expect(aceitacao.eventId, 'id-da-aceitacao');
      expect(aceitacao.quoteId, 'id-do-orcamento');
      expect(aceitacao.passengerPubkey, 'pubkey-do-passageiro');
    });

    test('lança FormatException quando a tag "e" está ausente', () {
      final evento = eventoDeAceitacao(
        tags: const [
          ['t', 'tcc-ufsc-caronas'],
          ['p', 'pubkey-do-motorista'],
        ],
      );

      expect(() => QuoteAccepted.fromNostrEvent(evento), throwsFormatException);
    });

    test('lança FormatException quando não há nenhuma tag', () {
      final evento = eventoDeAceitacao(tags: const []);

      expect(() => QuoteAccepted.fromNostrEvent(evento), throwsFormatException);
    });
  });
}
