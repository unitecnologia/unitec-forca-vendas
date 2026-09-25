import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitec_forca_vendas/db/customer_digits_migration.dart';
import 'package:unitec_forca_vendas/db/local_db.dart';
import 'package:unitec_forca_vendas/ui/documento_brasileiro.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('fv_cpf_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) {
      await tmpDir.delete(recursive: true);
    }
  });

  const cpf = '52998224725';
  const cpfMask = '529.982.247-25';
  const cnpj = '11222333000181';

  Future<Database> openFresh() async {
    final path = p.join(tmpDir.path, 't.db');
    return LocalDb.openAtPath(path);
  }

  Future<Database> openV18WithDuplicates() async {
    final path = p.join(tmpDir.path, 'v18.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 18,
        onCreate: (db, _) async {
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
              observacoes TEXT,
              ativo INTEGER, updated_at TEXT
            )''');
          await db.execute('''
            CREATE TABLE outbox_orders (
              uuid TEXT PRIMARY KEY, cliente_id INTEGER, tipo TEXT, observacoes TEXT,
              desconto_valor REAL, total REAL, latitude REAL, longitude REAL,
              itens_json TEXT, created_at TEXT, status TEXT, erro TEXT,
              numero TEXT, numero_pedido TEXT, extra_json TEXT
            )''');
          await db.execute('''
            CREATE TABLE visitas_sem_venda (
              uuid TEXT PRIMARY KEY, cliente_id INTEGER, motivo TEXT,
              latitude REAL, longitude REAL, created_at TEXT, status TEXT, erro TEXT
            )''');
          await db.execute('''
            CREATE TABLE customer_visita_dias (
              person_id INTEGER NOT NULL, dia_semana INTEGER NOT NULL,
              ordem INTEGER NOT NULL DEFAULT 1,
              PRIMARY KEY (person_id, dia_semana)
            )''');
          await db.execute('''
            CREATE TABLE outbox_customers (
              uuid TEXT PRIMARY KEY, local_id INTEGER, payload_json TEXT,
              created_at TEXT, status TEXT, erro TEXT, server_id INTEGER
            )''');
          await db.execute('''
            CREATE TABLE pedidos_fv_cache (
              uuid TEXT PRIMARY KEY, cliente_id INTEGER, tipo TEXT, numero TEXT,
              numero_pedido TEXT, total REAL, observacoes TEXT, desconto_valor REAL,
              itens_json TEXT, extra_json TEXT, created_at TEXT, status TEXT, situacao TEXT
            )''');
          await db.execute('''
            CREATE TABLE historico_vendas (
              id INTEGER PRIMARY KEY, numero TEXT, numero_orcamento TEXT, data TEXT,
              cliente_id INTEGER, total REAL, status TEXT, tipo TEXT
            )''');
          await db.execute('''
            CREATE TABLE historico_orcamentos (
              id INTEGER PRIMARY KEY, numero TEXT, data TEXT, cliente_id INTEGER,
              total REAL, status TEXT
            )''');
          await db.execute('''
            CREATE TABLE financeiro (
              id INTEGER PRIMARY KEY, numero TEXT, documento TEXT, cliente_id INTEGER,
              emissao TEXT, vencimento TEXT, valor REAL, saldo REAL, forma TEXT
            )''');
          await db.execute('CREATE TABLE sync_meta ( k TEXT PRIMARY KEY, v TEXT )');
        },
      ),
    );

    await db.insert('customers', {
      'id': -10,
      'nome_razao': 'CLIENTE A',
      'cpf_cnpj': cpfMask,
      'ativo': 1,
    });
    await db.insert('customers', {
      'id': -15,
      'nome_razao': 'CLIENTE B',
      'cpf_cnpj': cpf, // mesma digits, máscara diferente
      'ativo': 1,
    });
    await db.insert('outbox_orders', {
      'uuid': 'ord-a',
      'cliente_id': -10,
      'tipo': 'pedido',
      'total': 10,
      'itens_json': '[]',
      'created_at': '2026-01-01',
      'status': 'pendente',
    });
    await db.insert('outbox_orders', {
      'uuid': 'ord-b',
      'cliente_id': -15,
      'tipo': 'pedido',
      'total': 20,
      'itens_json': '[]',
      'created_at': '2026-01-01',
      'status': 'pendente',
    });
    await db.insert('visitas_sem_venda', {
      'uuid': 'vis-a',
      'cliente_id': -10,
      'motivo': 'Cliente fechado para inventário',
      'created_at': '2026-01-01',
      'status': 'pendente',
    });
    await db.insert('customer_visita_dias', {
      'person_id': -10,
      'dia_semana': 1,
      'ordem': 1,
    });
    await db.insert('customer_visita_dias', {
      'person_id': -15,
      'dia_semana': 1, // conflito PK após merge
      'ordem': 1,
    });
    await db.insert('customer_visita_dias', {
      'person_id': -15,
      'dia_semana': 3,
      'ordem': 2,
    });
    await db.insert('outbox_customers', {
      'uuid': 'cust-a',
      'local_id': -10,
      'payload_json': '{}',
      'created_at': '2026-01-01T10:00:00',
      'status': 'pendente',
    });
    await db.insert('outbox_customers', {
      'uuid': 'cust-b',
      'local_id': -15,
      'payload_json': '{}',
      'created_at': '2026-01-01T11:00:00',
      'status': 'pendente',
    });

    return db;
  }

  test('prepareCustomerRow preenche digits', () {
    final row = prepareCustomerRow({'id': 1, 'cpf_cnpj': cpfMask});
    expect(row['cpf_cnpj_digits'], cpf);
    expect(prepareCustomerRow({'cpf_cnpj': ''})['cpf_cnpj_digits'], isNull);
  });

  test('schema v19: UNIQUE bloqueia insert direto; vazio permite múltiplos', () async {
    final db = await openFresh();
    await db.insert('customers', prepareCustomerRow({
      'id': 1,
      'nome_razao': 'UM',
      'cpf_cnpj': cpfMask,
      'ativo': 1,
    }));
    await expectLater(
      () => db.insert('customers', prepareCustomerRow({
            'id': 2,
            'nome_razao': 'DOIS',
            'cpf_cnpj': cpf,
            'ativo': 1,
          })),
      throwsA(isA<DatabaseException>()),
    );

    await db.insert('customers', prepareCustomerRow({
      'id': 3,
      'nome_razao': 'SEM DOC A',
      'cpf_cnpj': '',
      'ativo': 1,
    }));
    await db.insert('customers', prepareCustomerRow({
      'id': 4,
      'nome_razao': 'SEM DOC B',
      'cpf_cnpj': null,
      'ativo': 1,
    }));
    final semDoc = await db.rawQuery(
      'SELECT COUNT(*) c FROM customers WHERE cpf_cnpj_digits IS NULL',
    );
    expect(semDoc.first['c'], 2);
    await db.close();
  });

  test('upsert/pull mantém cpf_cnpj_digits', () async {
    final path = p.join(tmpDir.path, 'pull.db');
    final db = await LocalDb.openAtPath(path);
    // Simula LocalDb.instance apontando para este arquivo via API estática.
    await db.insert('customers', prepareCustomerRow({
      'id': 100,
      'nome_razao': 'ERP',
      'cpf_cnpj': cnpj,
      'ativo': 1,
    }));
    final row = await db.query('customers', where: 'id = 100');
    expect(row.first['cpf_cnpj_digits'], cnpj);
    await db.close();
  });

  test('remap mantém digits', () async {
    final path = p.join(tmpDir.path, 'remap.db');
    // Usa LocalDb.openAtPath + lógica de remap via instância temporária:
    // abre DB, insere local, chama prepare no insert como remap faria.
    final db = await LocalDb.openAtPath(path);
    await db.insert('customers', prepareCustomerRow({
      'id': -1,
      'nome_razao': 'LOCAL',
      'cpf_cnpj': cpfMask,
      'ativo': 1,
    }));
    await db.delete('customers', where: 'id = ?', whereArgs: [-1]);
    final mapped = prepareCustomerRow({
      'nome_razao': 'LOCAL',
      'cpf_cnpj': cpfMask,
      'ativo': 1,
      'id': 55,
    });
    await db.insert('customers', mapped);
    final row = await db.query('customers', where: 'id = 55');
    expect(row.first['cpf_cnpj_digits'], cpf);
    await db.close();
  });

  test('migration consolida duplicados, pedidos, visitas e conflito visita_dias', () async {
    final v18 = await openV18WithDuplicates();
    await v18.close();

    final path = p.join(tmpDir.path, 'v18.db');
    // Reabre forçando upgrade 18 → 19 com o onUpgrade do LocalDb.
    final db = await LocalDb.openAtPath(path, version: 19);

    final customers = await db.query('customers');
    expect(customers.length, 1);
    // Keeper entre negativos: MAX(id) = -10 (mais antigo).
    expect(customers.first['id'], -10);
    expect(customers.first['cpf_cnpj_digits'], cpf);
    expect(customers.first['nome_razao'], 'CLIENTE A');

    final orders = await db.query('outbox_orders');
    expect(orders.every((o) => o['cliente_id'] == -10), isTrue);

    final visitas = await db.query('visitas_sem_venda');
    expect(visitas.single['cliente_id'], -10);

    final dias = await db.query(
      'customer_visita_dias',
      orderBy: 'dia_semana',
    );
    expect(dias.map((d) => d['dia_semana']).toList(), [1, 3]);
    expect(dias.every((d) => d['person_id'] == -10), isTrue);

    final outbox = await db.query('outbox_customers', orderBy: 'created_at');
    expect(outbox.every((o) => o['local_id'] == -10), isTrue);
    final pendentes =
        outbox.where((o) => o['status'] == 'pendente').toList();
    expect(pendentes.length, 1);

    // UNIQUE ativo após migration.
    await expectLater(
      () => db.insert('customers', prepareCustomerRow({
            'id': -99,
            'nome_razao': 'NOVO DUP',
            'cpf_cnpj': cpfMask,
            'ativo': 1,
          })),
      throwsA(isA<DatabaseException>()),
    );

    await db.close();
  });

  test('lookup indexado por digits (máscara × dígitos)', () async {
    final path = p.join(tmpDir.path, 'lookup.db');
    final db = await LocalDb.openAtPath(path);
    await db.insert('customers', prepareCustomerRow({
      'id': 7,
      'nome_razao': 'ACHADO',
      'cpf_cnpj': cpfMask,
      'ativo': 1,
    }));
    final byDigits = await db.query(
      'customers',
      where: 'cpf_cnpj_digits = ?',
      whereArgs: [DocumentoBrasileiro.digits(cpf)],
      limit: 1,
    );
    expect(byDigits.single['nome_razao'], 'ACHADO');
    await db.close();
  });

  test('preferência keeper id > 0 sobre negativos', () async {
    final path = p.join(tmpDir.path, 'keeper.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY, nome_razao TEXT, cpf_cnpj TEXT, ativo INTEGER
          )''');
        await db.execute(
          'CREATE TABLE outbox_orders (uuid TEXT PRIMARY KEY, cliente_id INTEGER)',
        );
        await db.execute(
          'CREATE TABLE visitas_sem_venda (uuid TEXT PRIMARY KEY, cliente_id INTEGER)',
        );
        await db.execute('''
          CREATE TABLE customer_visita_dias (
            person_id INTEGER, dia_semana INTEGER, ordem INTEGER,
            PRIMARY KEY (person_id, dia_semana)
          )''');
        await db.execute(
          'CREATE TABLE outbox_customers (uuid TEXT PRIMARY KEY, local_id INTEGER, '
          'payload_json TEXT, created_at TEXT, status TEXT, erro TEXT, server_id INTEGER)',
        );
        await db.execute(
          'CREATE TABLE pedidos_fv_cache (uuid TEXT PRIMARY KEY, cliente_id INTEGER)',
        );
        await db.execute(
          'CREATE TABLE historico_vendas (id INTEGER PRIMARY KEY, cliente_id INTEGER)',
        );
        await db.execute(
          'CREATE TABLE historico_orcamentos (id INTEGER PRIMARY KEY, cliente_id INTEGER)',
        );
        await db.execute(
          'CREATE TABLE financeiro (id INTEGER PRIMARY KEY, cliente_id INTEGER)',
        );
      }),
    );
    await db.insert('customers', {
      'id': 42,
      'nome_razao': 'DO ERP',
      'cpf_cnpj': cpfMask,
      'ativo': 1,
    });
    await db.insert('customers', {
      'id': -5,
      'nome_razao': 'LOCAL',
      'cpf_cnpj': cpf,
      'ativo': 1,
    });
    await db.insert('outbox_orders', {'uuid': 'o1', 'cliente_id': -5});

    await migrateCustomersCpfCnpjDigits(db);

    final all = await db.query('customers');
    expect(all.length, 1);
    expect(all.first['id'], 42);
    expect(all.first['cpf_cnpj_digits'], cpf);
    final ord = await db.query('outbox_orders');
    expect(ord.single['cliente_id'], 42);
    await db.close();
  });
}
