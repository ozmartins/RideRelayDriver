import 'package:driver/services/ride_request_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RideRequestNotificationContent (SC-003 da feature 025)', () {
    test('título e corpo são fixos, independentes do evento', () {
      final a = RideRequestNotificationContent.forEvent('a' * 64);
      final b = RideRequestNotificationContent.forEvent('b' * 64);

      expect(a.title, 'Nova solicitação de corrida');
      expect(a.body, 'Toque para ver');
      expect(b.title, a.title);
      expect(b.body, a.body);
    });

    test('nada do evento aparece no texto, nem o próprio id', () {
      const idDoEvento =
          '3f1c9a7e5b2d4c8e9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f708192a3b4c5';

      final conteudo = RideRequestNotificationContent.forEvent(idDoEvento);

      expect(conteudo.title, isNot(contains(idDoEvento.substring(0, 8))));
      expect(conteudo.body, isNot(contains(idDoEvento.substring(0, 8))));
      // Nenhum dado de localização ou de pessoa entra no texto.
      final texto = '${conteudo.title} ${conteudo.body}'.toLowerCase();
      for (final proibido in ['rua', 'lat', 'lon', 'pubkey', 'npub']) {
        expect(texto, isNot(contains(proibido)), reason: proibido);
      }
    });

    test('o id do aviso é estável por evento e nunca negativo', () {
      final primeiro = RideRequestNotificationContent.forEvent('abc');
      final segundo = RideRequestNotificationContent.forEvent('abc');
      final outro = RideRequestNotificationContent.forEvent('abd');

      expect(primeiro.id, segundo.id);
      expect(primeiro.id, isNot(outro.id));
      for (final id in ['a', 'b' * 64, '', 'ç' * 10]) {
        expect(RideRequestNotificationContent.forEvent(id).id, isNonNegative);
      }
    });
  });
}
