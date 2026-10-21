import 'package:driver/domain/identity.dart';
import 'package:driver/domain/receipt.dart';
import 'package:driver/domain/reputation.dart';
import 'package:driver/services/receipt_signature.dart';
import 'package:driver/services/reputation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/receipt_fixtures.dart';

/// Reputação coerente construída da [cadeia] (do mais antigo ao mais novo).
Reputation _rep(
  List<Receipt> cadeia, {
  int? corridas,
  int? avaliacoes,
  double? media,
}) => Reputation(
  corridas: corridas ?? cadeia.length,
  avaliacoes: avaliacoes ?? cadeia.where((r) => r.nota != null).length,
  media: media,
  seqProximo: cadeia.isEmpty ? 0 : cadeia.last.seq + 1,
  head: cadeia.isEmpty ? null : cadeia.last.idRecibo,
  recibos: cadeia.reversed.toList(),
);

Receipt _assinado(Receipt base, Identity avaliador) =>
    base.withSignature(ReceiptSignature.sign(base, avaliador));

void main() {
  final dono = newTestIdentity();
  final autor = dono.publicKey;

  group('verifyReputation — caso válido', () {
    test('tudo confere: contagem e média verificadas, nada descartado', () {
      final cadeia = signedChain(avaliado: autor, notas: [5, 3, null]);
      final view = verifyReputation(
        _rep(cadeia, corridas: 99, avaliacoes: 98, media: 1.0),
        authorPubkey: autor,
      );

      expect(view.verifiedCount, 3);
      expect(view.verifiedAverage, 4.0); // só 5 e 3; o recibo sem nota fora
      expect(view.invalidDiscarded, 0);
      expect(view.gaps, 0);
      expect(view.inconsistent, isFalse);
      // Declarado fica à parte e nunca se mistura com o verificado.
      expect(view.declared.corridas, 99);
      expect(view.declared.avaliacoes, 98);
      expect(view.declared.media, 1.0);
    });

    test('sem histórico (reputação vazia): não é inconsistente', () {
      final view = verifyReputation(
        const Reputation.empty(),
        authorPubkey: autor,
      );
      expect(view.verifiedCount, 0);
      expect(view.verifiedAverage, isNull);
      expect(view.invalidDiscarded, 0);
      expect(view.inconsistent, isFalse);
    });

    test('só recibos sem nota: média verificada é nula', () {
      final cadeia = signedChain(avaliado: autor, notas: [null, null]);
      final view = verifyReputation(_rep(cadeia), authorPubkey: autor);
      expect(view.verifiedCount, 2);
      expect(view.verifiedAverage, isNull);
    });
  });

  group('verifyReputation — regra 1.6 (a–g): recibo inválido é descartado e contado', () {
    test('(a) id_recibo não confere com a forma canônica', () {
      final cadeia = signedChain(avaliado: autor, notas: [5, 4]);
      final r = cadeia.last;
      final adulterado = Receipt(
        v: r.v,
        guidCorrida: r.guidCorrida,
        pubkeyAvaliador: r.pubkeyAvaliador,
        pubkeyAvaliado: r.pubkeyAvaliado,
        nota: 1, // nota trocada, id e assinatura antigos
        criadoEm: r.criadoEm,
        seq: r.seq,
        hashAnterior: r.hashAnterior,
        idRecibo: r.idRecibo,
        assinatura: r.assinatura,
      );
      final view = verifyReputation(
        _rep([cadeia.first, adulterado]),
        authorPubkey: autor,
      );
      expect(view.invalidDiscarded, 1);
      expect(view.verifiedCount, 1);
      expect(view.verifiedAverage, 5.0);
    });

    test('(b) assinatura de quem não é o avaliador', () {
      final avaliador = newTestIdentity();
      final base = Receipt.unsigned(
        guidCorrida: fakeGuid(1),
        pubkeyAvaliador: avaliador.publicKey,
        pubkeyAvaliado: autor,
        nota: 5,
        criadoEm: 1760000000,
        seq: 0,
      );
      final forjado = _assinado(base, newTestIdentity());
      final view = verifyReputation(_rep([forjado]), authorPubkey: autor);
      expect(view.invalidDiscarded, 1);
      expect(view.verifiedCount, 0);
    });

    test('(c) avaliado diferente do autor do evento', () {
      final cadeia = signedChain(avaliado: autor, notas: [5]);
      final view = verifyReputation(
        _rep(cadeia),
        authorPubkey: newTestIdentity().publicKey,
      );
      expect(view.invalidDiscarded, 1);
      expect(view.verifiedCount, 0);
    });

    test('(d) v diferente de 1', () {
      final avaliador = newTestIdentity();
      final base = signedReceipt(avaliador: avaliador, avaliado: autor, seq: 0);
      final v2 = Receipt(
        v: 2,
        guidCorrida: base.guidCorrida,
        pubkeyAvaliador: base.pubkeyAvaliador,
        pubkeyAvaliado: base.pubkeyAvaliado,
        nota: base.nota,
        criadoEm: base.criadoEm,
        seq: base.seq,
        hashAnterior: base.hashAnterior,
        idRecibo: base.idRecibo,
        assinatura: base.assinatura,
      );
      final view = verifyReputation(_rep([v2]), authorPubkey: autor);
      expect(view.invalidDiscarded, 1);
    });

    test('(d) nota fora de 1..5 (0 e 6), com assinatura válida', () {
      for (final nota in [0, 6]) {
        final avaliador = newTestIdentity();
        final base = Receipt.unsigned(
          guidCorrida: fakeGuid(1),
          pubkeyAvaliador: avaliador.publicKey,
          pubkeyAvaliado: autor,
          nota: nota,
          criadoEm: 1760000000,
          seq: 0,
        );
        final r = _assinado(base, avaliador);
        expect(ReceiptSignature.verify(r), isTrue, reason: 'pré-condição');
        final view = verifyReputation(_rep([r]), authorPubkey: autor);
        expect(view.invalidDiscarded, 1, reason: 'nota $nota');
        expect(view.verifiedAverage, isNull);
      }
    });

    test('(e) seq não estritamente decrescente na lista', () {
      final cadeia = signedChain(avaliado: autor, notas: [5, 4, 3]);
      // Lista fora de ordem: mais antigo primeiro.
      final foraDeOrdem = Reputation(
        corridas: 3,
        avaliacoes: 3,
        seqProximo: 3,
        head: cadeia.last.idRecibo,
        recibos: cadeia,
      );
      final view = verifyReputation(foraDeOrdem, authorPubkey: autor);
      // Só o primeiro (seq 0) entra; seq 1 e 2 não são menores que o anterior.
      expect(view.verifiedCount, 1);
      expect(view.invalidDiscarded, 2);
    });

    test('(e) seq repetido na lista', () {
      final avaliador = newTestIdentity();
      final a = signedReceipt(
        avaliador: avaliador,
        avaliado: autor,
        seq: 1,
        guid: fakeGuid(1),
      );
      final b = signedReceipt(
        avaliador: avaliador,
        avaliado: autor,
        seq: 1,
        guid: fakeGuid(2),
      );
      final rep = Reputation(
        corridas: 2,
        avaliacoes: 0,
        seqProximo: 2,
        head: a.idRecibo,
        recibos: [a, b],
      );
      final view = verifyReputation(rep, authorPubkey: autor);
      expect(view.verifiedCount, 1);
      expect(view.invalidDiscarded, 1);
    });

    test('(f) guid_corrida repetido', () {
      final avaliador = newTestIdentity();
      final novo = signedReceipt(
        avaliador: avaliador,
        avaliado: autor,
        seq: 1,
        guid: fakeGuid(1),
      );
      final velho = signedReceipt(
        avaliador: avaliador,
        avaliado: autor,
        seq: 0,
        guid: fakeGuid(1), // mesma corrida
      );
      final rep = Reputation(
        corridas: 2,
        avaliacoes: 0,
        seqProximo: 2,
        head: novo.idRecibo,
        recibos: [novo, velho],
      );
      final view = verifyReputation(rep, authorPubkey: autor);
      expect(view.verifiedCount, 1);
      expect(view.invalidDiscarded, 1);
    });

    test('(g) avaliador igual ao avaliado', () {
      final r = signedReceipt(avaliador: dono, avaliado: autor, seq: 0);
      final view = verifyReputation(_rep([r]), authorPubkey: autor);
      expect(view.invalidDiscarded, 1);
      expect(view.verifiedCount, 0);
    });

    test(
      'recibo de outro avaliado no meio da lista não contamina os demais',
      () {
        final cadeia = signedChain(avaliado: autor, notas: [5, 4]);
        final alheio = signedReceipt(
          avaliador: newTestIdentity(),
          avaliado: newTestIdentity().publicKey,
          seq: 0,
          guid: fakeGuid(50),
        );
        final rep = Reputation(
          corridas: 3,
          avaliacoes: 3,
          seqProximo: 2,
          head: cadeia.last.idRecibo,
          recibos: [cadeia.last, alheio, cadeia.first],
        );
        final view = verifyReputation(rep, authorPubkey: autor);
        expect(view.invalidDiscarded, 1);
        expect(view.verifiedCount, 2);
        expect(view.inconsistent, isFalse);
      },
    );
  });

  group('verifyReputation — regra 1.6 (h, i) e lacunas', () {
    test('(h) head que não é o recibo de seq_proximo − 1 → inconsistente', () {
      final cadeia = signedChain(avaliado: autor, notas: [5, 4]);
      final rep = Reputation(
        corridas: 2,
        avaliacoes: 2,
        seqProximo: 2,
        head: fakeGuid(123),
        recibos: cadeia.reversed.toList(),
      );
      expect(verifyReputation(rep, authorPubkey: autor).inconsistent, isTrue);
    });

    test('(h) recibo de seq_proximo − 1 ausente da lista → inconsistente', () {
      final cadeia = signedChain(avaliado: autor, notas: [5, 4, 3]);
      final semOMaisNovo = Reputation(
        corridas: 3,
        avaliacoes: 3,
        seqProximo: 3,
        head: cadeia.last.idRecibo,
        recibos: [cadeia[1], cadeia[0]],
      );
      expect(
        verifyReputation(semOMaisNovo, authorPubkey: autor).inconsistent,
        isTrue,
      );
    });

    test('(h) seq_proximo > 0 com lista vazia → inconsistente', () {
      final rep = Reputation(
        corridas: 4,
        avaliacoes: 4,
        seqProximo: 4,
        head: fakeGuid(1),
        recibos: const [],
      );
      expect(verifyReputation(rep, authorPubkey: autor).inconsistent, isTrue);
    });

    test(
      '(h) o recibo do head foi descartado por inválido → inconsistente',
      () {
        final cadeia = signedChain(avaliado: autor, notas: [5, 4]);
        final adulterado = Receipt(
          v: 1,
          guidCorrida: cadeia.last.guidCorrida,
          pubkeyAvaliador: cadeia.last.pubkeyAvaliador,
          pubkeyAvaliado: cadeia.last.pubkeyAvaliado,
          nota: 1,
          criadoEm: cadeia.last.criadoEm,
          seq: cadeia.last.seq,
          hashAnterior: cadeia.last.hashAnterior,
          idRecibo: cadeia.last.idRecibo,
          assinatura: cadeia.last.assinatura,
        );
        final view = verifyReputation(
          _rep([cadeia.first, adulterado]),
          authorPubkey: autor,
        );
        expect(view.invalidDiscarded, 1);
        expect(view.inconsistent, isTrue);
      },
    );

    test('(i) hash_anterior que não aponta para o seq − 1 presente', () {
      final avaliador = newTestIdentity();
      final r0 = signedReceipt(avaliador: avaliador, avaliado: autor, seq: 0);
      final r1 = signedReceipt(
        avaliador: avaliador,
        avaliado: autor,
        seq: 1,
        hashAnterior: fakeGuid(999), // não é o id do r0
      );
      final view = verifyReputation(_rep([r0, r1]), authorPubkey: autor);
      expect(view.invalidDiscarded, 0);
      expect(view.inconsistent, isTrue);
    });

    test(
      '(i) hash_anterior ausente num seq > 0 cujo anterior está presente',
      () {
        final avaliador = newTestIdentity();
        final r0 = signedReceipt(avaliador: avaliador, avaliado: autor, seq: 0);
        final r1 = signedReceipt(avaliador: avaliador, avaliado: autor, seq: 1);
        expect(
          verifyReputation(_rep([r0, r1]), authorPubkey: autor).inconsistent,
          isTrue,
        );
      },
    );

    test('lacuna de seq: "N recibos não apresentados", sem inconsistência', () {
      final avaliador = newTestIdentity();
      final r1 = signedReceipt(
        avaliador: avaliador,
        avaliado: autor,
        seq: 1,
        guid: fakeGuid(1),
      );
      final r4 = signedReceipt(
        avaliador: avaliador,
        avaliado: autor,
        seq: 4,
        guid: fakeGuid(4),
        hashAnterior: fakeGuid(3), // o seq 3 não está na lista
      );
      final rep = Reputation(
        corridas: 5,
        avaliacoes: 0,
        seqProximo: 5,
        head: r4.idRecibo,
        recibos: [r4, r1],
      );
      final view = verifyReputation(rep, authorPubkey: autor);
      expect(view.gaps, 2); // seq 2 e 3
      expect(view.inconsistent, isFalse);
      expect(view.verifiedCount, 2);
    });
  });
}
