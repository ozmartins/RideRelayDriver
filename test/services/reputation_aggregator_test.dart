import 'package:driver/domain/reputation.dart';
import 'package:driver/services/reputation_aggregator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/receipt_fixtures.dart';

void main() {
  final dono = newTestIdentity().publicKey;

  group('aggregateReputation', () {
    test('lista vazia: reputação vazia', () {
      expect(aggregateReputation(const []), const Reputation.empty());
    });

    test('calcula corridas, avaliações, média, seqProximo e head', () {
      final cadeia = signedChain(avaliado: dono, notas: [5, null, 3, 4]);
      final rep = aggregateReputation(cadeia);

      expect(rep.corridas, 4);
      expect(rep.avaliacoes, 3);
      expect(rep.media, 4.0);
      expect(rep.seqProximo, 4);
      expect(rep.head, cadeia.last.idRecibo);
    });

    test('média ausente quando nenhum recibo traz nota', () {
      final rep = aggregateReputation(
        signedChain(avaliado: dono, notas: [null, null]),
      );
      expect(rep.avaliacoes, 0);
      expect(rep.media, isNull);
    });

    test('ordem de chegada não importa: ordena por seq', () {
      final cadeia = signedChain(avaliado: dono, notas: [1, 2, 3]);
      final rep = aggregateReputation([cadeia[1], cadeia[2], cadeia[0]]);
      expect(rep.recibos.map((r) => r.seq), [2, 1, 0]);
      expect(rep.seqProximo, 3);
      expect(rep.head, cadeia[2].idRecibo);
    });

    test(
      'janela: só os $kReputacaoJanela mais recentes, do mais novo ao mais velho',
      () {
        final cadeia = signedChain(avaliado: dono, notas: List.filled(8, 5));
        final rep = aggregateReputation(cadeia);

        expect(rep.corridas, 8);
        expect(rep.recibos.length, kReputacaoJanela);
        expect(rep.recibos.map((r) => r.seq), [7, 6, 5, 4, 3]);
      },
    );

    test('ramo (mesmo seq): janela apresenta um só, determinístico', () {
      final a = signedReceipt(
        avaliador: newTestIdentity(),
        avaliado: dono,
        seq: 0,
        guid: fakeGuid(1),
        criadoEm: 100,
      );
      final b = signedReceipt(
        avaliador: newTestIdentity(),
        avaliado: dono,
        seq: 0,
        guid: fakeGuid(2),
        criadoEm: 200,
      );
      final rep1 = aggregateReputation([a, b]);
      final rep2 = aggregateReputation([b, a]);

      expect(rep1.corridas, 2); // as duas contam como corridas
      expect(rep1.recibos.length, 1);
      expect(rep1.recibos.single, b); // criadoEm maior vence
      expect(rep1.head, b.idRecibo);
      expect(rep2.recibos.single, b);
    });
  });
}
