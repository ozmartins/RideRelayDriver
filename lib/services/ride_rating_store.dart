import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../domain/identity.dart';
import '../domain/ride_rating.dart';
import 'ride_rating_signature.dart';

/// Persistência das avaliações de corrida feitas pelo motorista.
///
/// Abstração do projeto (Princípio III): a implementação real usa `sqflite`
/// (D1 de `specs/013-avaliar-corrida/research.md`, mesma biblioteca já
/// usada por `SqfliteCadastroStore`); os testes usam um dublê em memória —
/// nenhum teste toca SQLite real.
///
/// Desde a feature 014 (Row Signing), `save`/`forRide` recebem [Identity]
/// para assinar e validar cada linha (D1/D2 de
/// `specs/014-integridade-row-signing/research.md`).
abstract class RideRatingStore {
  /// Assina [rating] com [identity] e persiste, incluindo a assinatura
  /// (FR-002 da feature 014). Chamado uma vez por avaliação confirmada.
  Future<void> save(RideRating rating, Identity identity);

  /// A avaliação já registrada para [rideId], validada contra [identity] —
  /// `null` se não existe, se a assinatura não confere (marca a violação,
  /// FR-004/FR-006 da feature 014), ou se já estava marcada como violada
  /// (FR-005).
  Future<RideRating?> forRide(String rideId, Identity identity);
}

/// Implementação real: uma tabela SQLite, `ride_ratings`, num banco próprio
/// (D1/D2 de `specs/013-avaliar-corrida/research.md`) — não segue o estilo
/// de exceções/migração de `SqfliteCadastroStore`, que resolve um problema
/// diferente (cadastro obrigatório de uma única linha). Migrada para v2
/// pela feature 014 — `signature`/`tampered`, D2 de
/// `specs/014-integridade-row-signing/data-model.md`.
class SqfliteRideRatingStore implements RideRatingStore {
  SqfliteRideRatingStore({this.databaseName = 'ride_ratings.db'});

  final String databaseName;

  sqflite.Database? _db;

  Future<sqflite.Database> _open() async {
    final aberto = _db;
    if (aberto != null) return aberto;
    final caminho = p.join(await sqflite.getDatabasesPath(), databaseName);
    final db = await sqflite.openDatabase(
      caminho,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ride_ratings (
            ride_id   TEXT PRIMARY KEY,
            stars     INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
            rated_at  TEXT NOT NULL,
            signature TEXT,
            tampered  INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE ride_ratings ADD COLUMN signature TEXT',
          );
          await db.execute(
            'ALTER TABLE ride_ratings ADD COLUMN tampered INTEGER NOT NULL '
            'DEFAULT 0',
          );
        }
      },
    );
    _db = db;
    return db;
  }

  @override
  Future<void> save(RideRating rating, Identity identity) async {
    final db = await _open();
    final assinatura = RideRatingSignature.sign(rating, identity);
    await db.insert('ride_ratings', {
      'ride_id': rating.rideId,
      'stars': rating.stars,
      'rated_at': rating.ratedAt.toIso8601String(),
      'signature': assinatura,
      'tampered': 0,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  @override
  Future<RideRating?> forRide(String rideId, Identity identity) async {
    final db = await _open();
    final linhas = await db.query(
      'ride_ratings',
      where: 'ride_id = ?',
      whereArgs: [rideId],
    );
    if (linhas.isEmpty) return null;

    final linha = linhas.first;
    // Já marcado como violado numa leitura anterior: excluído sem repetir a
    // validação (FR-005 da feature 014).
    if ((linha['tampered'] as int) == 1) return null;

    final rating = _fromRow(linha);
    final assinatura = linha['signature'] as String?;
    if (!RideRatingSignature.verify(rating, assinatura, identity)) {
      await db.update(
        'ride_ratings',
        {'tampered': 1},
        where: 'ride_id = ?',
        whereArgs: [rideId],
      );
      return null;
    }

    return rating;
  }

  static RideRating _fromRow(Map<String, Object?> linha) => RideRating(
    rideId: linha['ride_id'] as String,
    stars: linha['stars'] as int,
    ratedAt: DateTime.parse(linha['rated_at'] as String),
  );
}
