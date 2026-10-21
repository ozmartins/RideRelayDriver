import 'package:driver/domain/receipt.dart';
import 'package:driver/domain/reputation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_receipt_store.dart';
import '../support/receipt_fixtures.dart';

Receipt _adulterado(Receipt r) => Receipt(
  v: r.v,
  guidCorrida: r.guidCorrida,
  pubkeyAvaliador: r.pubkeyAvaliador,
  pubkeyAvaliado: r.pubkeyAvaliado,
  nota: 1,
  criadoEm: r.criadoEm,
  seq: r.seq,
  hashAnterior: r.hashAnterior,
  idRecibo: r.idRecibo,
  assinatura: r.assinatura,
);

void main() {
  final dono = newTestIdentity().publicKey;

  group('ReceiptStore (dublê em memória)', () {
    test(
      'saveReceived é imutável: a segunda gravação da corrida falha',
      () async {
        final store = InMemoryReceiptStore();
        final original = signedReceipt(
          avaliador: newTestIdentity(),
          avaliado: dono,
          seq: 0,
          nota: 5,
        );
        final outro = signedReceipt(
          avaliador: newTestIdentity(),
          avaliado: dono,
          seq: 0,
          nota: 1,
          guid: original.guidCorrida, // mesma corrida
        );

        expect(await store.saveReceived(original), isTrue);
        expect(await store.saveReceived(outro), isFalse);
        expect(await store.receivedFor(original.guidCorrida), original);
      },
    );

    test('myReputation sem recibos é vazia', () async {
      expect(
        await InMemoryReceiptStore().myReputation(),
        const Reputation.empty(),
      );
    });

    test('myReputation agrega os recibos recebidos', () async {
      final store = InMemoryReceiptStore();
      for (final r in signedChain(avaliado: dono, notas: [5, 3])) {
        await store.saveReceived(r);
      }
      final rep = await store.myReputation();
      expect(rep.corridas, 2);
      expect(rep.media, 4.0);
      expect(rep.seqProximo, 2);
    });

    test('linha com assinatura adulterada é ignorada e não conta', () async {
      final store = InMemoryReceiptStore();
      final cadeia = signedChain(avaliado: dono, notas: [5, 5]);
      await store.saveReceived(cadeia[0]);
      store.injectReceivedRaw(_adulterado(cadeia[1]));

      expect(await store.receivedFor(cadeia[1].guidCorrida), isNull);
      final rep = await store.myReputation();
      expect(rep.corridas, 1);
      expect(rep.seqProximo, 1);
      expect(rep.head, cadeia[0].idRecibo);
    });

    test(
      'recibo emitido nasce pendente, vira confirmado e não duplica',
      () async {
        final store = InMemoryReceiptStore();
        final r = signedReceipt(
          avaliador: newTestIdentity(),
          avaliado: dono,
          seq: 0,
        );
        await store.saveIssued(r);
        await store.saveIssued(r);

        expect(await store.pendingIssued(), [r]);
        await store.markAcked(r.idRecibo);
        expect(await store.pendingIssued(), isEmpty);
      },
    );

    test(
      'issuedFor devolve o recibo emitido, pendente ou confirmado',
      () async {
        final store = InMemoryReceiptStore();
        final r = signedReceipt(
          avaliador: newTestIdentity(),
          avaliado: dono,
          seq: 0,
        );
        expect(await store.issuedFor(r.guidCorrida), isNull);
        await store.saveIssued(r);
        expect(await store.issuedFor(r.guidCorrida), r);
        await store.markAcked(r.idRecibo);
        expect(await store.issuedFor(r.guidCorrida), r);
      },
    );

    test('markAcked de id desconhecido não altera os pendentes', () async {
      final store = InMemoryReceiptStore();
      final r = signedReceipt(
        avaliador: newTestIdentity(),
        avaliado: dono,
        seq: 0,
      );
      await store.saveIssued(r);
      await store.markAcked(fakeGuid(404));
      expect(await store.pendingIssued(), [r]);
    });

    test(
      'counterpartOf devolve o passageiro registrado, ou null se desconhecida',
      () async {
        final store = InMemoryReceiptStore();
        expect(await store.counterpartOf('q1'), isNull);

        await store.saveDeclared('q1', dono, const Reputation.empty());
        expect(await store.counterpartOf('q1'), dono);

        // Imutável: outro registro da mesma corrida não troca a contraparte.
        await store.saveDeclared('q1', fakeGuid(5), const Reputation.empty());
        expect(await store.counterpartOf('q1'), dono);
        expect(await store.counterpartOf('q2'), isNull);
      },
    );

    test('reputação declarada: ausente, vazia e preenchida', () async {
      final store = InMemoryReceiptStore();
      expect(await store.declaredFor('q1'), isNull);

      await store.saveDeclared('q1', dono, const Reputation.empty());
      expect(await store.declaredFor('q1'), const Reputation.empty());

      final cadeia = signedChain(avaliado: dono, notas: [4]);
      final rep = Reputation(
        corridas: 1,
        avaliacoes: 1,
        media: 4.0,
        seqProximo: 1,
        head: cadeia.single.idRecibo,
        recibos: cadeia,
      );
      await store.saveDeclared('q2', dono, rep);
      expect(await store.declaredFor('q2'), rep);
      // Imutável: um segundo registro da mesma corrida não substitui o primeiro.
      await store.saveDeclared('q2', dono, const Reputation.empty());
      expect(await store.declaredFor('q2'), rep);
    });
  });
}
