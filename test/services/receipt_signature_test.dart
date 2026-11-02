import 'package:driver/domain/receipt.dart';
import 'package:driver/services/receipt_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/receipt_fixtures.dart';

Receipt _com({
  required Receipt r,
  String? guid,
  String? avaliado,
  int? nota,
  bool trocaNota = false,
  int? seq,
  String? assinatura,
}) => Receipt(
  v: r.v,
  guidCorrida: guid ?? r.guidCorrida,
  pubkeyAvaliador: r.pubkeyAvaliador,
  pubkeyAvaliado: avaliado ?? r.pubkeyAvaliado,
  nota: trocaNota ? nota : r.nota,
  criadoEm: r.criadoEm,
  seq: seq ?? r.seq,
  hashAnterior: r.hashAnterior,
  idRecibo: r.idRecibo,
  assinatura: assinatura ?? r.assinatura,
);

void main() {
  group('ReceiptSignature', () {
    test('recibo assinado pelo avaliador verifica', () {
      final avaliador = newTestIdentity();
      final r = signedReceipt(
        avaliador: avaliador,
        avaliado: newTestIdentity().publicKey,
        seq: 0,
        nota: 4,
      );
      expect(ReceiptSignature.verify(r), isTrue);
    });

    test('assinatura de outra chave não verifica', () {
      final avaliador = newTestIdentity();
      final impostor = newTestIdentity();
      final base = Receipt.unsigned(
        guidCorrida: fakeGuid(1),
        pubkeyAvaliador: avaliador.publicKey,
        pubkeyAvaliado: newTestIdentity().publicKey,
        nota: 5,
        criadoEm: 1760000000,
        seq: 0,
      );
      final forjado = base.withSignature(ReceiptSignature.sign(base, impostor));
      expect(ReceiptSignature.verify(forjado), isFalse);
    });

    test('campo adulterado com o id e a assinatura antigos não verifica', () {
      final r = signedReceipt(
        avaliador: newTestIdentity(),
        avaliado: newTestIdentity().publicKey,
        seq: 2,
        nota: 5,
        hashAnterior: fakeGuid(9),
      );
      expect(ReceiptSignature.verify(r), isTrue);
      expect(
        ReceiptSignature.verify(_com(r: r, nota: 1, trocaNota: true)),
        isFalse,
      );
      expect(ReceiptSignature.verify(_com(r: r, seq: 3)), isFalse);
      expect(ReceiptSignature.verify(_com(r: r, guid: fakeGuid(77))), isFalse);
      expect(
        ReceiptSignature.verify(_com(r: r, avaliado: fakeGuid(5))),
        isFalse,
      );
    });

    test('id recalculado e assinatura trocada por outra de outro recibo', () {
      final a = newTestIdentity();
      final alvo = newTestIdentity().publicKey;
      final r1 = signedReceipt(avaliador: a, avaliado: alvo, seq: 0, nota: 5);
      final r2 = signedReceipt(avaliador: a, avaliado: alvo, seq: 1, nota: 2);
      expect(
        ReceiptSignature.verify(_com(r: r1, assinatura: r2.assinatura)),
        isFalse,
      );
    });

    test('assinatura vazia ou mal formada falha sem lançar', () {
      final r = signedReceipt(
        avaliador: newTestIdentity(),
        avaliado: newTestIdentity().publicKey,
        seq: 0,
      );
      expect(ReceiptSignature.verify(_com(r: r, assinatura: '')), isFalse);
      expect(ReceiptSignature.verify(_com(r: r, assinatura: 'zz')), isFalse);
    });

    test('a chave privada não aparece no recibo assinado', () {
      final avaliador = newTestIdentity();
      final r = signedReceipt(
        avaliador: avaliador,
        avaliado: newTestIdentity().publicKey,
        seq: 0,
      );
      expect(r.toJson().values.join(), isNot(contains(avaliador.privateKey)));
    });
  });
}
