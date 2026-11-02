import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../domain/cadastro_progress.dart';
import '../domain/driver_profile.dart';
import 'cadastro_store.dart';

/// Implementação real de [CadastroStore], sobre SQLite via `sqflite`
/// (decisão D1 de `specs/003-cadastro-motorista/research.md`).
///
/// Uma tabela por etapa do wizard (`driver_personal`, `driver_vehicle`,
/// `driver_financial`), cada uma com no máximo uma linha (`id = 1`).
///
/// Único arquivo do aplicativo que importa `package:sqflite` — o domínio e as
/// telas conhecem só [CadastroStore] e os tipos de domínio (Princípio III).
class SqfliteCadastroStore implements CadastroStore {
  SqfliteCadastroStore({this.databaseName = 'cadastro_motorista.db'});

  /// Nome do arquivo de banco, dentro do diretório de bancos do aplicativo
  /// (`sqflite.getDatabasesPath()`). Parametrizável para facilitar testes de
  /// integração isolados, se algum dia forem necessários.
  final String databaseName;

  sqflite.Database? _db;

  static const _tabelaPessoal = 'driver_personal';
  static const _tabelaVeiculo = 'driver_vehicle';
  static const _tabelaFinanceiro = 'driver_financial';

  /// Versão do esquema. A 6 acrescenta o raio de atendimento à etapa 1 (feature
  /// 027).
  static const int versaoDoBanco = 6;

  /// Migração 5 → 6: quem se cadastrou antes da feature ganha o raio padrão,
  /// sem refazer o wizard (FR-003). Sem apagar nada.
  static const String sqlAdicionarRaio =
      'ALTER TABLE $_tabelaPessoal ADD COLUMN raio_atendimento_km '
      'INTEGER NOT NULL DEFAULT $kRaioPadraoKm';

  static Future<void> _criarTabelas(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE $_tabelaPessoal (
        id     INTEGER PRIMARY KEY CHECK (id = 1),
        nome   TEXT NOT NULL,
        uf     TEXT NOT NULL,
        cidade TEXT NOT NULL,
        raio_atendimento_km INTEGER NOT NULL DEFAULT $kRaioPadraoKm
      )
    ''');
    await db.execute('''
      CREATE TABLE $_tabelaVeiculo (
        id             INTEGER PRIMARY KEY CHECK (id = 1),
        marca_veiculo  TEXT NOT NULL,
        modelo_veiculo TEXT NOT NULL,
        ano_veiculo    INTEGER NOT NULL,
        cor_veiculo    TEXT NOT NULL,
        placa_veiculo  TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $_tabelaFinanceiro (
        id              INTEGER PRIMARY KEY CHECK (id = 1),
        payment_methods TEXT NOT NULL,
        preco_por_km    REAL NOT NULL
      )
    ''');
  }

  Future<sqflite.Database> _open() async {
    final aberto = _db;
    if (aberto != null) return aberto;
    try {
      final caminho = p.join(await sqflite.getDatabasesPath(), databaseName);
      final db = await sqflite.openDatabase(
        caminho,
        version: versaoDoBanco,
        onCreate: (db, version) => _criarTabelas(db),
        // Versão 5 (wizard em etapas): a tabela única `driver_profile` das
        // versões 1 a 4 dá lugar às três tabelas por etapa. O app está em
        // desenvolvimento, então o cadastro antigo é descartado e o
        // motorista refaz o wizard, sem migração de dado.
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 5) {
            await db.execute('DROP TABLE IF EXISTS driver_profile');
            await _criarTabelas(db);
            // `_criarTabelas` já cria a coluna do raio.
            return;
          }
          if (oldVersion < 6) await db.execute(sqlAdicionarRaio);
        },
      );
      _db = db;
      return db;
    } catch (error) {
      throw CadastroStoreUnavailable(error);
    }
  }

  Future<Map<String, Object?>?> _lerLinha(
    sqflite.Database db,
    String tabela,
  ) async {
    try {
      final linhas = await db.query(tabela, where: 'id = 1', limit: 1);
      return linhas.isEmpty ? null : linhas.single;
    } catch (error) {
      throw CadastroStoreUnavailable(error);
    }
  }

  @override
  Future<CadastroProgress> loadProgress() async {
    final db = await _open();
    final pessoal = await _lerLinha(db, _tabelaPessoal);
    final veiculo = await _lerLinha(db, _tabelaVeiculo);
    final financeiro = await _lerLinha(db, _tabelaFinanceiro);

    try {
      return ensureValid(
        CadastroProgress(
          personal: pessoal == null
              ? null
              : DriverPersonalData.fromMap(pessoal),
          vehicle: veiculo == null ? null : DriverVehicleData.fromMap(veiculo),
          financial: financeiro == null
              ? null
              : DriverFinancialData.fromMap(financeiro),
        ),
      );
    } on CorruptedDriverProfile {
      rethrow;
    } catch (error) {
      // Coluna com tipo inesperado, campo ausente: dado ilegível é tratado
      // como corrompido (FR-010), não como falha do armazenamento em si.
      throw CorruptedDriverProfile(error.toString());
    }
  }

  Future<void> _gravar(String tabela, Map<String, Object?> valores) async {
    try {
      final db = await _open();
      // `id = 1` fixo mais `replace`: sempre no máximo uma linha por etapa,
      // sem acumular histórico.
      await db.insert(tabela, {
        'id': 1,
        ...valores,
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
    } on CadastroStoreUnavailable {
      rethrow;
    } catch (error) {
      throw CadastroStoreUnavailable(error);
    }
  }

  @override
  Future<void> savePersonal(DriverPersonalData data) =>
      _gravar(_tabelaPessoal, data.toMap());

  @override
  Future<void> saveVehicle(DriverVehicleData data) =>
      _gravar(_tabelaVeiculo, data.toMap());

  @override
  Future<void> saveFinancial(DriverFinancialData data) =>
      _gravar(_tabelaFinanceiro, data.toMap());

  @override
  Future<DriverProfile?> load() async => (await loadProgress()).toProfile();
}
