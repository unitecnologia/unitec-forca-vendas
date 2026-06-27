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
      version: 4,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(_createOutboxCustomersSql);
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE outbox_orders ADD COLUMN extra_json TEXT');
        }
        if (oldVersion < 4) {
          await db.execute(_createFormasPagamentoSql);
          await db.execute('ALTER TABLE customers ADD COLUMN forma_pagamento_id INTEGER');
          await db.execute('ALTER TABLE customers ADD COLUMN tabela_prazo_id INTEGER');
          await db.execute('ALTER TABLE customers ADD COLUMN tabela_prazo_dias TEXT');
        }
      },
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
            limite_credito REAL, dia_pgto INTEGER,
            forma_pagamento_id INTEGER, tabela_prazo_id INTEGER, tabela_prazo_dias TEXT,
            ativo INTEGER, updated_at TEXT
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
            status TEXT,        -- pendente | enviado | erro | rascunho
            erro TEXT,
            numero TEXT,
            extra_json TEXT     -- campos comerciais (forma, condicao, frete, lista, pct)
          )''');
        await db.execute('''
          CREATE TABLE sync_meta ( k TEXT PRIMARY KEY, v TEXT )''');
        await db.execute(_createOutboxCustomersSql);
        await db.execute(_createFormasPagamentoSql);
      },
    );
  }

  static const String _createFormasPagamentoSql = '''
          CREATE TABLE IF NOT EXISTS formas_pagamento (
            id INTEGER PRIMARY KEY,
            codigo INTEGER, descricao TEXT, tipo TEXT,
            nfce INTEGER, max_parcelas INTEGER,
            tabelas_json TEXT   -- [{id, dias, ordem}, ...]
          )''';

  static const String _createOutboxCustomersSql = '''
          CREATE TABLE IF NOT EXISTS outbox_customers (
            uuid TEXT PRIMARY KEY,
            local_id INTEGER,
            payload_json TEXT,
            created_at TEXT,
            status TEXT,        -- pendente | enviado | erro
            erro TEXT,
            server_id INTEGER
          )''';

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

  Future<void> deleteAll(String table) async {
    final database = await db;
    await database.delete(table);
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

  // ---- Clientes (cadastro local + fila p/ ERP) ---------------------------

  /// Gera um id local negativo (não colide com ids do ERP, que são positivos).
  int newLocalId() => -DateTime.now().millisecondsSinceEpoch;

  /// Insere/atualiza um cliente na base local (visível na lista e nos pedidos).
  Future<void> upsertCustomer(Map<String, dynamic> row) async {
    final database = await db;
    await database.insert('customers', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Enfileira um cliente novo para envio ao ERP na próxima sincronização.
  Future<void> insertOutboxCustomer(Map<String, dynamic> row) async {
    final database = await db;
    await database.insert('outbox_customers', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> pendingCustomers() async {
    final database = await db;
    return database.query('outbox_customers',
        where: 'status = ?', whereArgs: ['pendente'], orderBy: 'created_at');
  }

  Future<void> markCustomer(String uuid, String status, {String? erro, int? serverId}) async {
    final database = await db;
    await database.update(
      'outbox_customers',
      {'status': status, 'erro': erro, 'server_id': serverId},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }
}
