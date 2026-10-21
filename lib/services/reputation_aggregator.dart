import '../domain/receipt.dart';
import '../domain/reputation.dart';

/// Agrega os recibos **já autenticados** que o motorista recebeu na reputação
/// que ele declara (1.5 e 1.8 do contrato, emenda 25). Função pura, usada
/// pelas duas implementações de `ReceiptStore` — a regra existe uma só vez.
///
/// `seqProximo = max(seq) + 1` e `head` = `idRecibo` do recibo de maior `seq`.
/// Se dois recibos disputam o mesmo `seq` (ramo, 1.3), vence o de `criadoEm`
/// maior e, no empate, o de `idRecibo` lexicograficamente maior: a escolha é
/// determinística e a janela apresentada fica com `seq` estritamente
/// decrescente, como o verificador da contraparte exige (1.6 e).
Reputation aggregateReputation(List<Receipt> received) {
  if (received.isEmpty) return const Reputation.empty();

  final ordered = [...received]..sort(_newestFirst);
  final comNota = [
    for (final r in received)
      if (r.nota != null) r.nota!,
  ];

  final janela = <Receipt>[];
  for (final r in ordered) {
    if (janela.isNotEmpty && janela.last.seq == r.seq) continue;
    janela.add(r);
    if (janela.length == kReputacaoJanela) break;
  }

  return Reputation(
    corridas: received.length,
    avaliacoes: comNota.length,
    media: comNota.isEmpty
        ? null
        : comNota.reduce((a, b) => a + b) / comNota.length,
    seqProximo: ordered.first.seq + 1,
    head: ordered.first.idRecibo,
    recibos: janela,
  );
}

int _newestFirst(Receipt a, Receipt b) {
  if (a.seq != b.seq) return b.seq.compareTo(a.seq);
  if (a.criadoEm != b.criadoEm) return b.criadoEm.compareTo(a.criadoEm);
  return b.idRecibo.compareTo(a.idRecibo);
}
