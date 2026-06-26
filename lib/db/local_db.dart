import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Banco local SQLite (offline-first). Catálogo é read-only (pull);
/// pedidos ficam numa fila (outbox) até subirem no push.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'unitec_fv.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY,
            codigo TEXT, codigo_barras TEXT, descricao TEXT, unidade TEXT,
            marca TEXT, grupo TEXT,
            preco_venda REAL, preco_venda_prazo REAL, preco_atacado REAL, qtd_atacado REAL,
            estoque REAL, usa_tab_preco INTEGER, mostrar_no_app INTEGER,
            promo_preco_venda REAL, foto_url TEXT, ativo INTEGER, updated_at TEXT
          )''');
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY,
            codigo TEXT, nome_razao TEXT, apelido_fantasia TEXT, cpf_cnpj TEXT,
            endereco TEXT, numero TEXT, bairro TEXT, cidade_nome TEXT, uf TEXT, cep TEXT,
            email TEXT, fone1 TEXT, celular1 TEXT, whatsapp TEXT,
            limite_credito REAL, dia_pgto INTEGER, ativo INTEGER, updated_at TEXT
          )''');
        await db.execute('''
          CREATE TABLE price_tables (
            id INTEGER PRIMARY KEY, codigo TEXT, descricao TEXT, ativo INTEGER, updated_at TEXT
          )''');
        await db.execute('''
          CREATE TABLE price_table_items (
            id INTEGER PRIMARY KEY, product_id INTEGER, price_table_id INTEGER,
            valor REAL, fator REAL, updated_at TEXT
          )''');
        await db.execute('''
          CREATE TABLE vendedores (
            id INTEGER PRIMARY KEY, codigo TEXT, nome TEXT, ativo INTEGER
          )''');
        await db.execute('''
          CREATE TABLE financeiro (
            id INTEGER PRIMARY KEY, numero TEXT, documento TEXT, cliente_id INTEGER,
            emissao TEXT, vencimento TEXT, valor REAL, saldo REAL, forma TEXT
          )''');
        await db.execute('''
          CREATE TABLE historico_vendas (
            id INTEGER PRIMARY KEY, numero TEXT, data TEXT, cliente_id INTEGER,
            total REAL, status TEXT, tipo TEXT
          )''');
        await db.execute('''
          CREATE TABLE outbox_orders (
            uuid TEXT PRIMARY KEY,
            cliente_id INTEGER, tipo TEXT, observacoes TEXT,
            desconto_valor REAL, total REAL,
            latitude REAL, longitude REAL,
            itens_json TEXT,
            created_at TEXT,
            status TEXT,        -- pendente | enviado | erro
            erro TEXT,
            numero TEXT
          )''');
        await db.execute('''
          CREATE TABLE sync_meta ( k TEXT PRIMARY KEY, v TEXT )''');
      },
    );
  }

  // ---- Catálogo (pull, upsert) -------------------------------------------

  Future<void> upsertAll(String table, List<dynamic> rows, Map<String, dynamic> Function(Map<String, dynamic>) map) async {
    if (rows.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final r in rows) {
      batch.insert(table, map(Map<String, dynamic>.from(r as Map)),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> query(String sql, [List<Object?>? args]) async {
    final database = await db;
    return database.rawQuery(sql, args);
  }

  Future<int> count(String table) async {
    final database = await db;
    final r = await database.rawQuery('SELECT COUNT(*) c FROM $table');
    return (r.first['c'] as int?) ?? 0;
  }

  // ---- Meta ---------------------------------------------------------------

  Future<String?> getMeta(String k) async {
    final database = await db;
    final r = await database.query('sync_meta', where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  Future<void> setMeta(String k, String v) async {
    final database = await db;
    await database.insert('sync_meta', {'k': k, 'v': v},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- Outbox -------------------------------------------------------------

  Future<void> insertOutbox(Map<String, dynamic> order) async {
    final database = await db;
    await database.insert('outbox_orders', order,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> pendingOrders() async {
    final database = await db;
    return database.query('outbox_orders',
        where: "status = ?", whereArgs: ['pendente'], orderBy: 'created_at');
  }

  Future<void> markOrder(String uuid, String status, {String? erro, String? numero}) async {
    final database = await db;
    await database.update(
      'outbox_orders',
      {'status': status, 'erro': erro, 'numero': numero},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<int> pendingCount() async {
    final database = await db;
    final r = await database
        .rawQuery("SELECT COUNT(*) c FROM outbox_orders WHERE status = 'pendente'");
    return (r.first['c'] as int?) ?? 0;
  }
}
