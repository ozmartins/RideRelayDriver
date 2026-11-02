import 'dart:async';
import 'dart:convert';

import '../domain/active_ride.dart';
import '../domain/identity.dart';
import '../domain/nostr_event.dart';
import '../domain/receipt.dart';
import 'identity_service.dart';
import 'receipt_store.dart';
import 'receipt_signature.dart';
import 'reputation_verifier.dart';

/// Resultado de [ReceiptService.issueFor].
enum ReceiptIssue {
  /// Recibo gravado como pendente e publicado (ou à espera de reenvio).
  issued,

  /// Já havia recibo para a corrida; nada novo.
  alreadyIssued,

  /// Reputação declarada pelo passageiro inconsistente: nada emitido (1.7 passo 2).
  inconsistent,

  /// Sem identidade ou sem registro da reputação da corrida: nada emitido.
  skipped,
}

/// Orquestra os recibos de reputação do motorista (emenda 25 do contrato;
/// feature 026): emite o recibo ao fim da corrida e o reenvia até a
/// confirmação (1.7), e recebe os recibos que o passageiro emite (1.8),
/// confirmando o recebimento. Sem plugin e sem rede própria: a publicação é uma função
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
    DateTime Function()? now,
    this.retryInterval = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  /// Intervalo do reenvio dos recibos pendentes (1.7 passo 5).
  final Duration retryInterval;

  final DateTime Function() _now;
  Timer? _timer;
  var _retrying = false;

  final ReceiptStore _store;
  final IdentityService _identityService;
  final Identity? Function() _identity;

  /// Publica o evento nos relays; devolve verdadeiro se ao menos um aceitou.
  final Future<bool> Function(SignedEvent event) _publish;

  /// Liga o reenvio periódico dos recibos pendentes, a cada [retryInterval]
  /// enquanto a interface do app existir (R3 de `specs/026-recibos-de-reputacao/
  /// research.md`). Idempotente.
  void start() {
    _timer ??= Timer.periodic(retryInterval, (_) => unawaited(retryPending()));
  }

  /// Desliga o reenvio periódico.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// Emite o recibo da corrida [ride] ao passageiro (1.7 passos 1 a 4 e a
  /// primeira publicação). [stars] nulo = o motorista pulou a avaliação: o
  /// recibo conta como corrida, não como avaliação.
  ///
  /// Usa a reputação que o passageiro declarou **nesta** corrida
  /// (`declaredFor`), verificada: inconsistente → nada é emitido
  /// ([ReceiptIssue.inconsistent]). Corrida sem registro de reputação (anterior
  /// à feature, ou gravação que falhou) → [ReceiptIssue.skipped], sem chute de
  /// `seq`. O recibo é gravado como pendente **antes** de publicar; falha de
  /// publicação é absorvida e [retryPending] cuida do reenvio.
  Future<ReceiptIssue> issueFor(ActiveRide ride, int? stars) async {
    final identity = _identity();
    if (identity == null) return ReceiptIssue.skipped;

    if (await _store.issuedFor(ride.quoteId) != null) {
      return ReceiptIssue.alreadyIssued;
    }
    final declarada = await _store.declaredFor(ride.quoteId);
    if (declarada == null) return ReceiptIssue.skipped;

    final view = verifyReputation(
      declarada,
      authorPubkey: ride.passengerPubkey,
    );
    if (view.inconsistent) return ReceiptIssue.inconsistent;

    final base = Receipt.unsigned(
      guidCorrida: ride.quoteId,
      pubkeyAvaliador: identity.publicKey,
      pubkeyAvaliado: ride.passengerPubkey,
      nota: stars,
      criadoEm: _now().millisecondsSinceEpoch ~/ 1000,
      seq: declarada.seqProximo,
      hashAnterior: declarada.head,
    );
    final recibo = base.withSignature(ReceiptSignature.sign(base, identity));

    await _store.saveIssued(recibo); // antes de publicar: sobrevive a reinício
    await _publishReceipt(identity, recibo);
    return ReceiptIssue.issued;
  }

  /// Republica os recibos emitidos ainda sem confirmação (1.7 passo 5), cada um
  /// como um evento novo (R2). Chamado ao abrir o app, a cada reconexão de relay
  /// e pelo temporizador. Uma execução por vez; falhas são absorvidas.
  Future<void> retryPending() async {
    final identity = _identity();
    if (identity == null || _retrying) return;
    _retrying = true;
    try {
      for (final recibo in await _store.pendingIssued()) {
        await _publishReceipt(identity, recibo);
      }
    } on Object {
      // Absorvida: o próximo ciclo tenta de novo.
    } finally {
      _retrying = false;
    }
  }

  Future<void> _publishReceipt(Identity identity, Receipt recibo) async {
    try {
      await _publish(
        _identityService.signReceipt(identity: identity, receipt: recibo),
      );
    } on Object {
      // Absorvida: o recibo segue pendente e será reenviado.
    }
  }

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

    // Emenda 26: só vale recibo de uma corrida que este motorista já conhecia
    // com o avaliador — o orçamento foi enviado a ele. Consulta só o registro
    // local, nunca dados do recibo; quem nunca negociou com o motorista não
    // consegue lhe empurrar recibos de corridas inventadas.
    if (await _store.counterpartOf(receipt.guidCorrida) !=
        receipt.pubkeyAvaliador) {
      return;
    }

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
