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
      version: 15,
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
        if (oldVersion < 5) {
          await db.execute(_createHistoricoOrcamentosSql);
        }
        if (oldVersion < 6) {
          await db.execute(_createVisitasSemVendaSql);
        }
        if (oldVersion < 7) {
          await db.execute('ALTER TABLE products ADD COLUMN estoque_reservado REAL DEFAULT 0');
          await db.execute('ALTER TABLE products ADD COLUMN estoque_disponivel REAL');
          await db.execute(
            'UPDATE products SET estoque_disponivel = estoque, estoque_reservado = 0 '
            'WHERE estoque_disponivel IS NULL',
          );
        }
        if (oldVersion < 8) {
          await db.execute('ALTER TABLE customers ADD COLUMN vendedor_fv_id INTEGER');
          await db.execute('ALTER TABLE customers ADD COLUMN vendedor_loja_id INTEGER');
        }
        if (oldVersion < 9) {
          await db.execute('ALTER TABLE outbox_orders ADD COLUMN numero_pedido TEXT');
          await db.execute('ALTER TABLE historico_vendas ADD COLUMN numero_orcamento TEXT');
        }
        if (oldVersion < 10) {
          await db.execute(_createPedidosFvCacheSql);
        }
        if (oldVersion < 11) {
          await db.execute('ALTER TABLE customers ADD COLUMN rg_ie TEXT');
        }
        if (oldVersion < 12) {
          await db.execute(_createCustomerVisitaDiasSql);
        }
        if (oldVersion < 13) {
          await db.execute(_createGruposSql);
        }
        if (oldVersion < 14) {
          await db.execute('ALTER TABLE products ADD COLUMN preco_especial REAL DEFAULT 0');
          await db.execute('ALTER TABLE vendedores ADD COLUMN tabela_venda_id INTEGER');
        }
        if (oldVersion < 15) {
          await db.execute('ALTER TABLE customers ADD COLUMN price_table_id INTEGER');
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY,
            codigo TEXT, codigo_barras TEXT, descricao TEXT, unidade TEXT,
            marca TEXT, grupo TEXT,
            preco_venda REAL, preco_venda_prazo REAL, preco_atacado REAL, preco_especial REAL,
            qtd_atacado REAL,
            estoque REAL, estoque_reservado REAL, estoque_disponivel REAL,
            usa_tab_preco INTEGER, mostrar_no_app INTEGER,
            promo_preco_venda REAL, foto_url TEXT, ativo INTEGER, updated_at TEXT
          )''');
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY,
            codigo TEXT, nome_razao TEXT, apelido_fantasia TEXT, cpf_cnpj TEXT, rg_ie TEXT,
            endereco TEXT, numero TEXT, bairro TEXT, cidade_nome TEXT, uf TEXT, cep TEXT,
            email TEXT, fone1 TEXT, celular1 TEXT, whatsapp TEXT,
            limite_credito REAL, dia_pgto INTEGER,
            forma_pagamento_id INTEGER, tabela_prazo_id INTEGER, tabela_prazo_dias TEXT,
            price_table_id INTEGER,
            vendedor_fv_id INTEGER, vendedor_loja_id INTEGER,
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
            id INTEGER PRIMARY KEY, codigo TEXT, nome TEXT, ativo INTEGER, tabela_venda_id INTEGER
          )''');
        await db.execute('''
          CREATE TABLE financeiro (
            id INTEGER PRIMARY KEY, numero TEXT, documento TEXT, cliente_id INTEGER,
            emissao TEXT, vencimento TEXT, valor REAL, saldo REAL, forma TEXT
          )''');
        await db.execute('''
          CREATE TABLE historico_vendas (
            id INTEGER PRIMARY KEY, numero TEXT, numero_orcamento TEXT, data TEXT, cliente_id INTEGER,
            total REAL, status TEXT, tipo TEXT
          )''');
        await db.execute(_createHistoricoOrcamentosSql);
        await db.execute(_createCustomerVisitaDiasSql);
        await db.execute(_createGruposSql);
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
            numero_pedido TEXT,
            extra_json TEXT     -- campos comerciais (forma, condicao, frete, lista, pct)
          )''');
        await db.execute('''
          CREATE TABLE sync_meta ( k TEXT PRIMARY KEY, v TEXT )''');
        await db.execute(_createOutboxCustomersSql);
        await db.execute(_createFormasPagamentoSql);
        await db.execute(_createVisitasSemVendaSql);
        await db.execute(_createPedidosFvCacheSql);
      },
    );
  }

  static const String _createPedidosFvCacheSql = '''
          CREATE TABLE IF NOT EXISTS pedidos_fv_cache (
            uuid TEXT PRIMARY KEY,
            cliente_id INTEGER,
            tipo TEXT,
            numero TEXT,
            numero_pedido TEXT,
            total REAL,
            observacoes TEXT,
            desconto_valor REAL,
            itens_json TEXT,
            extra_json TEXT,
            created_at TEXT,
            status TEXT,
            situacao TEXT
          )''';

  static const String _createVisitasSemVendaSql = '''
          CREATE TABLE IF NOT EXISTS visitas_sem_venda (
            uuid TEXT PRIMARY KEY,
            cliente_id INTEGER,
            motivo TEXT,
            latitude REAL,
            longitude REAL,
            created_at TEXT,
            status TEXT,
            erro TEXT
          )''';

  static const String _createHistoricoOrcamentosSql = '''
          CREATE TABLE IF NOT EXISTS historico_orcamentos (
            id INTEGER PRIMARY KEY, numero TEXT, data TEXT, cliente_id INTEGER,
            total REAL, status TEXT
          )''';

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

  static const String _createCustomerVisitaDiasSql = '''
          CREATE TABLE IF NOT EXISTS customer_visita_dias (
            person_id INTEGER NOT NULL,
            dia_semana INTEGER NOT NULL,
            ordem INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (person_id, dia_semana)
          )''';

  static const String _createGruposSql = '''
          CREATE TABLE IF NOT EXISTS grupos (
            id INTEGER PRIMARY KEY,
            nome TEXT,
            ativo INTEGER DEFAULT 1,
            mostrar_no_app INTEGER DEFAULT 1,
            updated_at TEXT
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

  /// Garante a tabela local de transportadoras (pedido pode abrir antes do sync).
  Future<void> ensureTransportadorasTable() async {
    final database = await db;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS transportadoras (
        id INTEGER PRIMARY KEY,
        codigo TEXT,
        nome TEXT,
        ativo INTEGER DEFAULT 1
      )''');
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

  Future<void> markOrder(String uuid, String status, {String? erro, String? numero, String? numeroPedido}) async {
    final database = await db;
    final data = <String, dynamic>{'status': status, 'erro': erro};
    if (numero != null) data['numero'] = numero;
    if (numeroPedido != null) data['numero_pedido'] = numeroPedido;
    await database.update(
      'outbox_orders',
      data,
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  /// Atualiza números/situação de pedidos já enviados (pull `pedidos_fv`).
  /// Se o ERP já reconhece o UUID, tira o pedido da fila pendente.
  Future<void> applyPedidoFvSync(Map<String, dynamic> row) async {
    final uuid = (row['uuid'] ?? '').toString();
    if (uuid.isEmpty) return;

    final database = await db;
    final existing = await database.query(
      'outbox_orders',
      columns: ['status'],
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (existing.isEmpty) return;

    final data = <String, dynamic>{};
    final numero = row['numero'];
    if (numero != null && numero.toString().isNotEmpty) {
      data['numero'] = numero.toString();
    }
    final numeroPedido = row['numero_pedido'];
    if (numeroPedido != null && numeroPedido.toString().isNotEmpty) {
      data['numero_pedido'] = numeroPedido.toString();
    }

    final situacao = (row['situacao'] ?? '').toString();
    final localStatus = (existing.first['status'] ?? '').toString();
    if (situacao == 'faturado') {
      data['status'] = 'faturado';
    } else if (situacao == 'cancelado') {
      data['status'] = 'cancelado';
    } else if (localStatus == 'pendente' || localStatus == 'erro') {
      // ERP já tem o pedido — não deve continuar contando como pendente no app.
      data['status'] = 'enviado';
      data['erro'] = null;
    }

    if (data.isEmpty) return;

    await database.update(
      'outbox_orders',
      data,
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<Map<String, dynamic>?> outboxOrderByUuid(String uuid) async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT o.*, c.nome_razao, c.cpf_cnpj, c.endereco, c.numero AS cliente_numero, '
      'c.bairro, c.cidade_nome, c.uf, c.cep, c.fone1, c.celular1, c.whatsapp '
      'FROM outbox_orders o '
      'LEFT JOIN customers c ON c.id = o.cliente_id '
      'WHERE o.uuid = ? LIMIT 1',
      [uuid],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Pedido completo para PDF: outbox local ou cache vindo do ERP (após reinstalar).
  Future<Map<String, dynamic>?> orderForPdf(String uuid) async {
    final outbox = await outboxOrderByUuid(uuid);
    if (outbox != null) {
      return outbox;
    }

    final database = await db;
    final rows = await database.rawQuery(
      'SELECT p.*, c.nome_razao, c.cpf_cnpj, c.endereco, c.numero AS cliente_numero, '
      'c.bairro, c.cidade_nome, c.uf, c.cep, c.fone1, c.celular1, c.whatsapp '
      'FROM pedidos_fv_cache p '
      'LEFT JOIN customers c ON c.id = p.cliente_id '
      'WHERE p.uuid = ? LIMIT 1',
      [uuid],
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertPedidoFvCache(Map<String, dynamic> row) async {
    final uuid = (row['uuid'] ?? '').toString();
    if (uuid.isEmpty) return;

    final database = await db;
    await database.insert(
      'pedidos_fv_cache',
      {
        'uuid': uuid,
        'cliente_id': row['cliente_id'],
        'tipo': row['tipo'] ?? 'pedido',
        'numero': row['numero']?.toString(),
        'numero_pedido': row['numero_pedido']?.toString(),
        'total': row['total'] ?? 0,
        'observacoes': row['observacoes']?.toString(),
        'desconto_valor': row['desconto_valor'] ?? 0,
        'itens_json': row['itens_json'] ?? '[]',
        'extra_json': row['extra_json'] ?? '{}',
        'created_at': row['created_at']?.toString() ?? row['data']?.toString(),
        'status': row['status']?.toString(),
        'situacao': row['situacao']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> pendingCount() async {
    final database = await db;
    final orders = await database
        .rawQuery("SELECT COUNT(*) c FROM outbox_orders WHERE status = 'pendente'");
    final customers = await database
        .rawQuery("SELECT COUNT(*) c FROM outbox_customers WHERE status = 'pendente'");
    return ((orders.first['c'] as int?) ?? 0) + ((customers.first['c'] as int?) ?? 0);
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

  /// Substitui os dias de visita locais do cliente (1=Seg … 7=Dom).
  Future<void> replaceCustomerVisitaDias(int personId, List<int> dias) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('customer_visita_dias',
          where: 'person_id = ?', whereArgs: [personId]);
      var ordem = 1;
      for (final dia in dias) {
        if (dia < 1 || dia > 7) continue;
        await txn.insert(
          'customer_visita_dias',
          {'person_id': personId, 'dia_semana': dia, 'ordem': ordem++},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Atualiza telefones do cliente na base local.
  Future<void> updateCustomerPhones(
    int id, {
    required String celular1,
    required String fone1,
    required String whatsapp,
  }) async {
    final database = await db;
    await database.update(
      'customers',
      {
        'celular1': celular1,
        'fone1': fone1,
        'whatsapp': whatsapp,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// Substitui o id local negativo pelo id real do ERP e atualiza pedidos/visitas pendentes.
  Future<void> remapCustomerId(int localId, int serverId, Map<String, dynamic> row) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('customers', where: 'id = ?', whereArgs: [localId]);
      final mapped = Map<String, dynamic>.from(row)
        ..remove('visita_dias');
      mapped['id'] = serverId;
      await txn.insert('customers', mapped, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.update(
        'outbox_orders',
        {'cliente_id': serverId, 'status': 'pendente', 'erro': null},
        where: 'cliente_id = ?',
        whereArgs: [localId],
      );
      await txn.update(
        'visitas_sem_venda',
        {'cliente_id': serverId, 'status': 'pendente', 'erro': null},
        where: 'cliente_id = ?',
        whereArgs: [localId],
      );
      await txn.update(
        'customer_visita_dias',
        {'person_id': serverId},
        where: 'person_id = ?',
        whereArgs: [localId],
      );
    });
  }

  // ---- Visitas sem venda -------------------------------------------------

  Future<void> insertVisitaSemVenda(Map<String, dynamic> row) async {
    final database = await db;
    await database.insert('visitas_sem_venda', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> pendingVisitasSemVenda() async {
    final database = await db;
    return database.query('visitas_sem_venda',
        where: 'status = ?', whereArgs: ['pendente'], orderBy: 'created_at');
  }

  Future<void> markVisitaSemVenda(String uuid, String status, {String? erro}) async {
    final database = await db;
    await database.update(
      'visitas_sem_venda',
      {'status': status, 'erro': erro},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  /// Clientes já atendidos na data local (pedido ou visita sem venda).
  /// Valor: `venda` | `visita`. Pedido tem prioridade sobre visita.
  Future<Map<int, String>> clientesAtendidosNoDia(DateTime diaLocal) async {
    final inicio = DateTime(diaLocal.year, diaLocal.month, diaLocal.day);
    final fim = inicio.add(const Duration(days: 1));
    final de = inicio.toUtc().toIso8601String();
    final ate = fim.toUtc().toIso8601String();

    final database = await db;
    final out = <int, String>{};

    void marcar(dynamic id, String tipo) {
      final cid = id is int ? id : int.tryParse('$id');
      if (cid == null) return;
      if (tipo == 'venda' || !out.containsKey(cid)) {
        out[cid] = tipo;
      }
    }

    final pedidos = await database.rawQuery(
      '''
      SELECT cliente_id FROM outbox_orders
      WHERE tipo = 'pedido'
        AND IFNULL(status, '') NOT IN ('rascunho', 'cancelado')
        AND cliente_id IS NOT NULL
        AND created_at >= ? AND created_at < ?
      UNION
      SELECT cliente_id FROM pedidos_fv_cache
      WHERE tipo = 'pedido'
        AND IFNULL(situacao, '') != 'cancelado'
        AND IFNULL(status, '') NOT IN ('rascunho', 'cancelado')
        AND cliente_id IS NOT NULL
        AND created_at >= ? AND created_at < ?
      ''',
      [de, ate, de, ate],
    );
    for (final r in pedidos) {
      marcar(r['cliente_id'], 'venda');
    }

    final visitas = await database.rawQuery(
      '''
      SELECT cliente_id FROM visitas_sem_venda
      WHERE cliente_id IS NOT NULL
        AND created_at >= ? AND created_at < ?
      ''',
      [de, ate],
    );
    for (final r in visitas) {
      marcar(r['cliente_id'], 'visita');
    }

    return out;
  }
}
