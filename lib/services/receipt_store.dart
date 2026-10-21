import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../domain/receipt.dart';
import '../domain/reputation.dart';
import 'receipt_signature.dart';
import 'reputation_aggregator.dart';

/// Persistência dos recibos de reputação (emenda 25 do contrato; feature 026).
///
/// Abstração do projeto (Princípio III): a implementação real usa `sqflite`
/// num banco próprio, `receipts.db`; os testes usam um dublê em memória e
/// nenhum toca SQLite real. Não há *row signing* (feature 014): cada recibo
/// recebido se autentica pela assinatura do avaliador, revalidada em toda
/// leitura — linha que falhar é ignorada e não conta.
abstract class ReceiptStore {
  /// Grava um recibo **recebido**, imutável. Devolve falso, sem alterar nada,
  /// se já existe recibo para a mesma corrida (ou o mesmo `id_recibo`).
  Future<bool> saveReceived(Receipt receipt);

  /// O recibo recebido para [guidCorrida], se existir e ainda for autêntico.
  Future<Receipt?> receivedFor(String guidCorrida);

  /// A reputação declarada pelo próprio motorista, calculada só dos recibos
  /// recebidos autênticos (1.5 e 1.8).
  Future<Reputation> myReputation();

  /// Grava um recibo **emitido**, pendente de confirmação, **antes** de
  /// publicar (1.7 passo 4). No-op se já existe recibo para a corrida.
  Future<void> saveIssued(Receipt receipt);

  /// O recibo emitido para [guidCorrida], confirmado ou não; `null` se a
  /// corrida ainda não gerou recibo.
  Future<Receipt?> issuedFor(String guidCorrida);

  /// Recibos emitidos ainda sem confirmação.
  Future<List<Receipt>> pendingIssued();

  /// Marca como confirmado o recibo emitido de `id_recibo` [idRecibo].
  Future<void> markAcked(String idRecibo);

  /// Guarda a reputação do **passageiro** como veio na solicitação da corrida
  /// [quoteId]. [reputation] vazia (`Reputation.empty()`) = passageiro sem
  /// histórico. No-op se já existe registro para a corrida.
  Future<void> saveDeclared(
    String quoteId,
    String avaliado,
    Reputation reputation,
  );

  /// A reputação do passageiro guardada para [quoteId], ou `null` se a corrida
  /// não foi registrada.
  Future<Reputation?> declaredFor(String quoteId);
}

/// Implementação real: três tabelas em `receipts.db` (v1), conforme
/// `specs/026-recibos-de-reputacao/data-model.md`.
class SqfliteReceiptStore implements ReceiptStore {
  SqfliteReceiptStore({this.databaseName = 'receipts.db'});

  final String databaseName;

  sqflite.Database? _db;

  Future<sqflite.Database> _open() async {
    final aberto = _db;
    if (aberto != null) return aberto;
    final caminho = p.join(await sqflite.getDatabasesPath(), databaseName);
    final db = await sqflite.openDatabase(
      caminho,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recibos_recebidos (
            guid_corrida TEXT PRIMARY KEY,
            id_recibo    TEXT UNIQUE NOT NULL,
            seq          INTEGER NOT NULL,
            avaliador    TEXT NOT NULL,
            nota         INTEGER CHECK (nota BETWEEN 1 AND 5),
            json         TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE recibos_emitidos (
            guid_corrida TEXT PRIMARY KEY,
            id_recibo    TEXT NOT NULL,
            avaliado     TEXT NOT NULL,
            json         TEXT NOT NULL,
            pendente     INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE reputacao_declarada (
            quote_id TEXT PRIMARY KEY,
            avaliado TEXT NOT NULL,
            json     TEXT NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  @override
  Future<bool> saveReceived(Receipt receipt) async {
    final db = await _open();
    try {
      await db.insert('recibos_recebidos', {
        'guid_corrida': receipt.guidCorrida,
        'id_recibo': receipt.idRecibo,
        'seq': receipt.seq,
        'avaliador': receipt.pubkeyAvaliador,
        'nota': receipt.nota,
        'json': jsonEncode(receipt.toJson()),
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.abort);
      return true;
    } on sqflite.DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) return false;
      rethrow;
    }
  }

  @override
  Future<Receipt?> receivedFor(String guidCorrida) async {
    final db = await _open();
    final rows = await db.query(
      'recibos_recebidos',
      where: 'guid_corrida = ?',
      whereArgs: [guidCorrida],
    );
    if (rows.isEmpty) return null;
    return _authentic(rows.first['json']);
  }

  @override
  Future<Reputation> myReputation() async {
    final db = await _open();
    final rows = await db.query('recibos_recebidos');
    final autenticos = [for (final row in rows) ?_authentic(row['json'])];
    return aggregateReputation(autenticos);
  }

  @override
  Future<void> saveIssued(Receipt receipt) async {
    final db = await _open();
    await db.insert('recibos_emitidos', {
      'guid_corrida': receipt.guidCorrida,
      'id_recibo': receipt.idRecibo,
      'avaliado': receipt.pubkeyAvaliado,
      'json': jsonEncode(receipt.toJson()),
      'pendente': 1,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
  }

  @override
  Future<Receipt?> issuedFor(String guidCorrida) async {
    final db = await _open();
    final rows = await db.query(
      'recibos_emitidos',
      where: 'guid_corrida = ?',
      whereArgs: [guidCorrida],
    );
    return rows.isEmpty ? null : _parse(rows.first['json']);
  }

  @override
  Future<List<Receipt>> pendingIssued() async {
    final db = await _open();
    final rows = await db.query('recibos_emitidos', where: 'pendente = 1');
    return [for (final row in rows) ?_parse(row['json'])];
  }

  @override
  Future<void> markAcked(String idRecibo) async {
    final db = await _open();
    await db.update(
      'recibos_emitidos',
      {'pendente': 0},
      where: 'id_recibo = ?',
      whereArgs: [idRecibo],
    );
  }

  @override
  Future<void> saveDeclared(
    String quoteId,
    String avaliado,
    Reputation reputation,
  ) async {
    final db = await _open();
    await db.insert('reputacao_declarada', {
      'quote_id': quoteId,
      'avaliado': avaliado,
      'json': jsonEncode(reputation.toJson()),
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
  }

  @override
  Future<Reputation?> declaredFor(String quoteId) async {
    final db = await _open();
    final rows = await db.query(
      'reputacao_declarada',
      where: 'quote_id = ?',
      whereArgs: [quoteId],
    );
    if (rows.isEmpty) return null;
    try {
      return Reputation.fromJson(jsonDecode(rows.first['json'] as String));
    } on Object {
      return null; // linha corrompida = ausente
    }
  }

  static Receipt? _parse(Object? json) {
    try {
      return Receipt.fromJson(jsonDecode(json as String));
    } on Object {
      return null;
    }
  }

  static Receipt? _authentic(Object? json) {
    final receipt = _parse(json);
    return receipt != null && ReceiptSignature.verify(receipt) ? receipt : null;
  }
}
