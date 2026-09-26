import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitec_forca_vendas/db/local_db.dart';
import 'package:unitec_forca_vendas/ui/email_basico.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('fv_email_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) {
      await tmpDir.delete(recursive: true);
    }
  });

  Future<LocalDb> open() => LocalDb.openForTest(p.join(tmpDir.path, 't.db'));

  Future<void> close(LocalDb local) async {
    await (await local.db).close();
  }

  test('formato básico: vazio vale, inválido não', () {
    expect(emailBasicoValido(''), isTrue);
    expect(emailBasicoValido('   '), isTrue);
    expect(emailBasicoValido('cliente@email.com'), isTrue);
    expect(emailBasicoMensagem('sem-arroba'), 'Informe um e-mail válido ou deixe em branco.');
    expect(emailBasicoMensagem('a@b'), isNotNull);
    expect(emailBasicoMensagem('a@b.c'), isNull);
  });

  test('cliente do ERP: grava local, fila só de e-mail, telefone intacto', () async {
    final local = await open();
    await local.upsertCustomer({
      'id': 42,
      'nome_razao': 'CLIENTE',
      'email': 'antes@email.com',
      'fone1': '4733334444',
      'celular1': '47999999999',
      'whatsapp': '47999999999',
      'ativo': 1,
    });

    await local.saveCustomerEmail(42, ' novo@email.com ');
    await local.saveCustomerEmail(42, '');

    final row = (await (await local.db).query('customers', where: 'id = 42')).single;
    expect(row['email'], '');
    expect(row['fone1'], '4733334444');
    expect(row['celular1'], '47999999999');
    expect(row['whatsapp'], '47999999999');
    expect(row['nome_razao'], 'CLIENTE');

    final fila = await local.pendingCustomerEmailUpdates();
    expect(fila, hasLength(1));
    expect(fila.single['person_id'], 42);
    expect(fila.single['campo'], 'email');
    expect(fila.single['valor'], '');
    expect(fila.single['status'], 'pendente');
    expect(await local.pendingCount(), 1);

    await (await local.db).update('customers', {'email': 'servidor@email.com'}, where: 'id = 42');
    await local.reapplyPendingCustomerEmailUpdates();
    final depoisPull = (await (await local.db).query('customers', where: 'id = 42')).single;
    expect(depoisPull['email'], '');
    expect(depoisPull['fone1'], '4733334444');

    await close(local);
  });

  test('cliente ainda offline: e-mail entra no payload do cadastro, sem fila paralela', () async {
    final local = await open();
    await local.upsertCustomer({
      'id': -8,
      'nome_razao': 'NOVO',
      'email': 'velho@email.com',
      'fone1': '4730000000',
      'ativo': 1,
    });
    await local.insertOutboxCustomer({
      'uuid': 'cad-1',
      'local_id': -8,
      'payload_json': jsonEncode({
        'nome_razao': 'NOVO',
        'email': 'velho@email.com',
        'fone1': '4730000000',
      }),
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pendente',
    });

    await local.saveCustomerEmail(-8, 'novo@email.com');

    final row = (await (await local.db).query('customers', where: 'id = -8')).single;
    expect(row['email'], 'novo@email.com');
    expect(row['fone1'], '4730000000');

    final outbox = (await (await local.db).query('outbox_customers')).single;
    final payload = jsonDecode(outbox['payload_json'] as String) as Map<String, dynamic>;
    expect(payload['email'], 'novo@email.com');
    expect(payload['nome_razao'], 'NOVO');
    expect(payload['fone1'], '4730000000');
    expect(await local.pendingCustomerEmailUpdates(), isEmpty);

    await close(local);
  });

  test('upgrade 19 para 20 cria a fila de e-mail', () async {
    final path = p.join(tmpDir.path, 'v19.db');
    final antigo = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 19,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE customers (id INTEGER PRIMARY KEY, nome_razao TEXT, email TEXT, '
            'fone1 TEXT, celular1 TEXT, whatsapp TEXT, ativo INTEGER, updated_at TEXT)',
          );
          await db.execute(
            'CREATE TABLE outbox_customers (uuid TEXT PRIMARY KEY, local_id INTEGER, '
            'payload_json TEXT, created_at TEXT, status TEXT, erro TEXT, server_id INTEGER)',
          );
          await db.execute('CREATE TABLE outbox_orders (uuid TEXT PRIMARY KEY, status TEXT)');
        },
      ),
    );
    await antigo.close();

    final local = await LocalDb.openForTest(path);
    await (await local.db).insert('customers', {
      'id': 7,
      'nome_razao': 'ANTIGO',
      'email': 'a@b.com',
      'fone1': '1',
      'ativo': 1,
    });
    await local.saveCustomerEmail(7, 'b@c.com');
    final fila = await local.pendingCustomerEmailUpdates();
    expect(fila.single['valor'], 'b@c.com');
    final row = (await (await local.db).query('customers', where: 'id = 7')).single;
    expect(row['fone1'], '1');
    await close(local);
  });
}
