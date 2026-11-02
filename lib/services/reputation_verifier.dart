import '../domain/receipt.dart';
import '../domain/reputation.dart';
import '../domain/reputation_view.dart';
import 'receipt_signature.dart';

/// As regras por recibo da 1.6 que não dependem da lista: (a) `id_recibo`
/// confere, (b) assinatura do avaliador, (c) avaliado é [avaliado], (d) `v == 1`
/// e nota em 1..5 se presente, (g) avaliador diferente do avaliado. Usada
/// também ao **receber** um recibo (1.8), com [avaliado] = a própria chave.
bool isReceiptValidFor(Receipt r, {required String avaliado}) =>
    ReceiptSignature.verify(r) && // (a) e (b)
    r.pubkeyAvaliado == avaliado && // (c)
    r.v == 1 &&
    (r.nota == null || (r.nota! >= 1 && r.nota! <= 5)) && // (d)
    r.pubkeyAvaliador != r.pubkeyAvaliado; // (g)

/// Verifica a [Reputation] recebida (regra 1.6 do contrato, emenda 25).
///
/// Função pura: sem I/O, sem relógio. Serve à exibição da reputação do
/// passageiro e à decisão de emitir ou não o recibo (1.7).
///
/// Cada recibo passa por: (a) `id_recibo` recalculado confere e (b) assinatura
/// do avaliador — ambas em [ReceiptSignature.verify] —, (c) avaliado igual ao
/// autor do evento, (d) `v == 1` e nota em 1..5 se presente, (e) `seq`
/// estritamente decrescente na lista, (f) `guid_corrida` sem repetição, (g)
/// avaliador diferente do avaliado. Recibo inválido é descartado e contado.
/// Depois: (h) o `head` e (i) o encadeamento por `hash_anterior`.
ReputationView verifyReputation(
  Reputation reputation, {
  required String authorPubkey,
}) {
  final valid = <Receipt>[];
  final seenGuids = <String>{};
  var discarded = 0;
  int? lastSeq;

  for (final r in reputation.recibos) {
    final ok =
        isReceiptValidFor(r, avaliado: authorPubkey) && // (a)–(d), (g)
        (lastSeq == null || r.seq < lastSeq) && // (e)
        !seenGuids.contains(r.guidCorrida); // (f)
    if (!ok) {
      discarded++;
      continue;
    }
    valid.add(r);
    seenGuids.add(r.guidCorrida);
    lastSeq = r.seq;
  }

  var inconsistent = false;

  // (h) o head é o recibo de seq = seq_proximo − 1, presente na lista.
  if (reputation.seqProximo > 0) {
    final expected = valid
        .where((r) => r.seq == reputation.seqProximo - 1)
        .firstOrNull;
    if (expected == null || expected.idRecibo != reputation.head) {
      inconsistent = true;
    }
  }

  // (i) hash_anterior do mais novo aponta para o seq − 1 quando ele está na
  // lista; lacunas de seq viram "não apresentados".
  final bySeq = {for (final r in valid) r.seq: r};
  var gaps = 0;
  for (var i = 0; i < valid.length; i++) {
    final r = valid[i];
    final previous = bySeq[r.seq - 1];
    if (previous != null && r.hashAnterior != previous.idRecibo) {
      inconsistent = true;
    }
    if (i + 1 < valid.length) gaps += r.seq - valid[i + 1].seq - 1;
  }

  final notas = [
    for (final r in valid)
      if (r.nota != null) r.nota!,
  ];
  return ReputationView(
    verifiedCount: valid.length,
    verifiedAverage: notas.isEmpty
        ? null
        : notas.reduce((a, b) => a + b) / notas.length,
    declared: DeclaredReputation(
      corridas: reputation.corridas,
      avaliacoes: reputation.avaliacoes,
      media: reputation.media,
    ),
    invalidDiscarded: discarded,
    gaps: gaps,
    inconsistent: inconsistent,
  );
}
