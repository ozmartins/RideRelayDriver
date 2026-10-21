import 'package:driver/domain/reputation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/receipt_fixtures.dart';

void main() {
  group('Reputation', () {
    test('vazia: sem recibos, próximo seq 0, sem media nem head', () {
      const r = Reputation.empty();
      expect(r.corridas, 0);
      expect(r.seqProximo, 0);
      expect(r.media, isNull);
      expect(r.head, isNull);
      expect(r.recibos, isEmpty);
    });

    test('ida e volta com recibos reais', () {
      final dono = newTestIdentity().publicKey;
      final cadeia = signedChain(avaliado: dono, notas: [5, null, 3]);
      final original = Reputation(
        corridas: 3,
        avaliacoes: 2,
        media: 4.0,
        seqProximo: 3,
        head: cadeia.last.idRecibo,
        recibos: cadeia.reversed.toList(),
      );

      expect(Reputation.fromJson(original.toJson()), original);
    });

    test('media e head ausentes são omitidos do JSON, nunca null', () {
      final json = const Reputation.empty().toJson();
      expect(json.containsKey('media'), isFalse);
      expect(json.containsKey('head'), isFalse);
      expect(json['seq_proximo'], 0);
      expect(json['recibos'], isEmpty);
    });

    test('media inteira no JSON vira double', () {
      final r = Reputation.fromJson({
        'corridas': 1,
        'avaliacoes': 1,
        'media': 5,
        'seq_proximo': 1,
        'head': 'a' * 64,
        'recibos': <dynamic>[],
      });
      expect(r.media, 5.0);
    });

    test('kReputacaoJanela é 5', () => expect(kReputacaoJanela, 5));

    Map<String, dynamic> base() => {
      'corridas': 0,
      'avaliacoes': 0,
      'seq_proximo': 0,
      'recibos': <dynamic>[],
    };

    test('campo obrigatório faltando → FormatException', () {
      for (final chave in [
        'corridas',
        'avaliacoes',
        'seq_proximo',
        'recibos',
      ]) {
        expect(
          () => Reputation.fromJson(base()..remove(chave)),
          throwsFormatException,
          reason: chave,
        );
      }
    });

    test('tipo errado → FormatException', () {
      expect(
        () => Reputation.fromJson(base()..['corridas'] = '1'),
        throwsFormatException,
      );
      expect(
        () => Reputation.fromJson(base()..['corridas'] = -1),
        throwsFormatException,
      );
      expect(
        () => Reputation.fromJson(base()..['media'] = 'x'),
        throwsFormatException,
      );
      expect(
        () => Reputation.fromJson(base()..['head'] = 'curto'),
        throwsFormatException,
      );
      expect(
        () => Reputation.fromJson(base()..['recibos'] = {}),
        throwsFormatException,
      );
      expect(() => Reputation.fromJson([]), throwsFormatException);
    });

    test('recibo malformado dentro da lista → FormatException', () {
      expect(
        () => Reputation.fromJson(
          base()
            ..['recibos'] = [
              <String, dynamic>{'v': 1},
            ],
        ),
        throwsFormatException,
      );
    });

    test('mais de kReputacaoJanela recibos → FormatException', () {
      final dono = newTestIdentity().publicKey;
      final cadeia = signedChain(avaliado: dono, notas: List.filled(6, 5));
      final json = base()..['recibos'] = cadeia.map((r) => r.toJson()).toList();
      expect(() => Reputation.fromJson(json), throwsFormatException);
    });
  });
}
