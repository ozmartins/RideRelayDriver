import 'package:driver/domain/receipt.dart';
import 'package:driver/domain/reputation.dart';
import 'package:driver/services/receipt_signature.dart';
import 'package:driver/services/receipt_store.dart';
import 'package:driver/services/reputation_aggregator.dart';

/// Dublê em memória de [ReceiptStore], com a mesma semântica do SQLite:
/// recebidos imutáveis e revalidados na leitura, emitidos pendentes,
/// reputação declarada por corrida. Nenhum teste toca SQLite real.
class InMemoryReceiptStore implements ReceiptStore {
  final Map<String, Receipt> _received = {};
  final Map<String, Receipt> _issued = {};
  final Set<String> _pending = {};
  final Map<String, Reputation> _declared = {};
  final Map<String, String> _counterparts = {};

  /// Ordem das operações de escrita, para testes que conferem "grava antes de
  /// publicar".
  final List<String> log = [];

  /// Insere um recibo recebido **sem** validar nada, como uma linha adulterada
  /// no disco; a leitura deve ignorá-lo se a assinatura não conferir.
  void injectReceivedRaw(Receipt receipt) {
    _received[receipt.guidCorrida] = receipt;
  }

  bool _authentic(Receipt r) => ReceiptSignature.verify(r);

  @override
  Future<bool> saveReceived(Receipt receipt) async {
    if (_received.containsKey(receipt.guidCorrida) ||
        _received.values.any((r) => r.idRecibo == receipt.idRecibo)) {
      return false;
    }
    _received[receipt.guidCorrida] = receipt;
    log.add('saveReceived');
    return true;
  }

  @override
  Future<Receipt?> receivedFor(String guidCorrida) async {
    final r = _received[guidCorrida];
    return r != null && _authentic(r) ? r : null;
  }

  @override
  Future<Reputation> myReputation() async =>
      aggregateReputation(_received.values.where(_authentic).toList());

  @override
  Future<void> saveIssued(Receipt receipt) async {
    if (_issued.containsKey(receipt.guidCorrida)) return;
    _issued[receipt.guidCorrida] = receipt;
    _pending.add(receipt.idRecibo);
    log.add('saveIssued');
  }

  @override
  Future<Receipt?> issuedFor(String guidCorrida) async => _issued[guidCorrida];

  @override
  Future<List<Receipt>> pendingIssued() async => [
    for (final r in _issued.values)
      if (_pending.contains(r.idRecibo)) r,
  ];

  @override
  Future<void> markAcked(String idRecibo) async {
    _pending.remove(idRecibo);
    log.add('markAcked');
  }

  @override
  Future<void> saveDeclared(
    String quoteId,
    String avaliado,
    Reputation reputation,
  ) async {
    _declared.putIfAbsent(quoteId, () => reputation);
    _counterparts.putIfAbsent(quoteId, () => avaliado);
    log.add('saveDeclared');
  }

  @override
  Future<Reputation?> declaredFor(String quoteId) async => _declared[quoteId];

  @override
  Future<String?> counterpartOf(String quoteId) async => _counterparts[quoteId];
}
