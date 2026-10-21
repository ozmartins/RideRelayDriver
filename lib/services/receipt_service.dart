import 'dart:async';
import 'dart:convert';

import '../domain/identity.dart';
import '../domain/nostr_event.dart';
import '../domain/receipt.dart';
import 'identity_service.dart';
import 'receipt_store.dart';
import 'reputation_verifier.dart';

/// Orquestra os recibos de reputação do motorista (emenda 25 do contrato;
/// feature 026): recebe os recibos que o passageiro emite (1.8) e confirma o
/// recebimento. Sem plugin e sem rede própria: a publicação é uma função
/// injetada, então os testes rodam com dublês (Princípios II e III).
///
/// A chave privada nunca é lida aqui: [identity] devolve a [Identity] já em
/// memória, usada só para decifrar e assinar via [IdentityService], e nada do
/// que é decifrado vai a log.
class ReceiptService {
  ReceiptService({
    required this._store,
    required this._identityService,
    required this._identity,
    required this._publish,
  });

  final ReceiptStore _store;
  final IdentityService _identityService;
  final Identity? Function() _identity;

  /// Publica o evento nos relays; devolve verdadeiro se ao menos um aceitou.
  final Future<bool> Function(SignedEvent event) _publish;

  /// Recepção de um `kind: 20014` (1.8), **depois** das regras de recepção 1, 2
  /// e 6 (assinatura, deduplicação, marcador — feitas pelo `EventFeed`). Aplica a
  /// regra 7 (tag `p` e decifração) e valida o recibo; um recibo inválido, em
  /// claro ou endereçado a outro é descartado em silêncio e nunca altera a
  /// reputação. Recibo novo é gravado (imutável) e confirmado com `20015`;
  /// recibo repetido idêntico só reenvia a confirmação; repetido diferente é
  /// ignorado.
  Future<void> onReceiptEvent(NostrEvent event) async {
    final identity = _identity();
    if (identity == null || event.kind != NostrEvent.kindReceipt) return;

    final receipt = _decodeReceipt(identity, event);
    if (receipt == null) return;

    // 1.8: avaliado = eu, avaliador = autor do evento, corrida = tag `e`.
    if (!isReceiptValidFor(receipt, avaliado: identity.publicKey)) return;
    if (receipt.pubkeyAvaliador != event.authorPublicKey) return;
    if (receipt.guidCorrida != event.referencedEventId) return;

    final existing = await _store.receivedFor(receipt.guidCorrida);
    if (existing != null) {
      if (existing == receipt) await _ack(identity, receipt);
      return;
    }
    if (!await _store.saveReceived(receipt)) return;
    await _ack(identity, receipt);
  }

  /// Recepção de um `kind: 20015`: só vale confirmação **assinada pelo avaliado
  /// do recibo pendente**, da mesma corrida e com o `id_recibo` do recibo
  /// emitido. Qualquer outra é ignorada e o recibo segue pendente.
  Future<void> onAckEvent(NostrEvent event) async {
    final identity = _identity();
    if (identity == null || event.kind != NostrEvent.kindReceiptAck) return;

    final texto = _identityService.decryptContent(
      identity: identity,
      event: event,
    );
    if (texto == null) return;
    final String idRecibo;
    try {
      final json = jsonDecode(texto);
      final valor = json is Map<String, dynamic> ? json['id_recibo'] : null;
      if (valor is! String) return;
      idRecibo = valor;
    } on FormatException {
      return;
    }

    for (final pendente in await _store.pendingIssued()) {
      if (pendente.idRecibo == idRecibo &&
          pendente.pubkeyAvaliado == event.authorPublicKey &&
          pendente.guidCorrida == event.referencedEventId) {
        await _store.markAcked(idRecibo);
        return;
      }
    }
  }

  Receipt? _decodeReceipt(Identity identity, NostrEvent event) {
    final texto = _identityService.decryptContent(
      identity: identity,
      event: event,
    );
    if (texto == null) return null;
    try {
      return Receipt.fromJson(jsonDecode(texto));
    } on FormatException {
      return null;
    }
  }

  /// Confirma o recebimento ao avaliador. Falha de assinatura, cifra ou
  /// publicação é absorvida: o avaliador reenvia o recibo e a confirmação sai
  /// na próxima vez.
  Future<void> _ack(Identity identity, Receipt receipt) async {
    try {
      final signed = _identityService.signReceiptAck(
        identity: identity,
        guid: receipt.guidCorrida,
        idRecibo: receipt.idRecibo,
        avaliadorPubkey: receipt.pubkeyAvaliador,
      );
      await _publish(signed);
    } on Object {
      // Absorvida (ver acima).
    }
  }
}
