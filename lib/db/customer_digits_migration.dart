import 'package:sqflite/sqflite.dart';

import '../ui/documento_brasileiro.dart';

/// Migration v19: `cpf_cnpj_digits` + saneamento de duplicados + UNIQUE.
///
/// Expressão de dígitos espelha o uso típico do app (máscara `. - /` e espaços).
const String kCpfCnpjDigitsSqlExpr =
    "NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(IFNULL(cpf_cnpj,''), '.', ''), '-', ''), '/', ''), ' ', ''), '')";

/// Garante coluna indexada em qualquer mapa antes de gravar em `customers`.
Map<String, dynamic> prepareCustomerRow(Map<String, dynamic> row) {
  final out = Map<String, dynamic>.from(row);
  out['cpf_cnpj_digits'] = DocumentoBrasileiro.digitsOrNull(out['cpf_cnpj']?.toString());
  return out;
}

Future<void> migrateCustomersCpfCnpjDigits(DatabaseExecutor db) async {
  Future<void> body(DatabaseExecutor e) async {
    await e.execute('ALTER TABLE customers ADD COLUMN cpf_cnpj_digits TEXT');
    await e.execute(
      'UPDATE customers SET cpf_cnpj_digits = $kCpfCnpjDigitsSqlExpr',
    );
    await e.execute(
      "UPDATE customers SET cpf_cnpj_digits = NULL "
      "WHERE cpf_cnpj_digits IS NOT NULL AND TRIM(cpf_cnpj_digits) = ''",
    );

    await _consolidateDuplicateDigits(e);

    await e.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS customers_cpf_cnpj_digits_unique '
      'ON customers(cpf_cnpj_digits)',
    );
  }

  if (db is Database) {
    await db.transaction(body);
  } else {
    await body(db);
  }
}

/// Cria o índice UNIQUE em banco novo (onCreate já tem a coluna).
Future<void> createCustomersCpfCnpjDigitsUniqueIndex(DatabaseExecutor db) async {
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS customers_cpf_cnpj_digits_unique '
    'ON customers(cpf_cnpj_digits)',
  );
}

Future<void> _consolidateDuplicateDigits(DatabaseExecutor db) async {
  final groups = await db.rawQuery('''
    SELECT cpf_cnpj_digits AS digits
    FROM customers
    WHERE cpf_cnpj_digits IS NOT NULL
      AND length(cpf_cnpj_digits) IN (11, 14)
    GROUP BY cpf_cnpj_digits
    HAVING COUNT(*) > 1
  ''');

  for (final g in groups) {
    final digits = g['digits'] as String?;
    if (digits == null || digits.isEmpty) continue;

    final rows = await db.rawQuery(
      'SELECT id FROM customers WHERE cpf_cnpj_digits = ?',
      [digits],
    );
    final ids = rows
        .map((r) => (r['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (ids.length < 2) continue;

    final keeper = _pickKeeperId(ids);
    final losers = ids.where((id) => id != keeper).toList();

    for (final loser in losers) {
      await _repointCustomerRefs(db, loser, keeper);
      await db.delete('customers', where: 'id = ?', whereArgs: [loser]);
    }

    await _dedupeOutboxPendingForKeeper(db, keeper);
  }
}

/// Preferência: qualquer id > 0 (menor id); senão MAX entre negativos (mais antigo).
int _pickKeeperId(List<int> ids) {
  final positives = ids.where((id) => id > 0).toList()..sort();
  if (positives.isNotEmpty) return positives.first;
  final negatives = ids.where((id) => id < 0).toList()..sort();
  return negatives.last;
}

Future<void> _repointCustomerRefs(
  DatabaseExecutor db,
  int loser,
  int keeper,
) async {
  await db.update(
    'outbox_orders',
    {'cliente_id': keeper},
    where: 'cliente_id = ?',
    whereArgs: [loser],
  );
  await db.update(
    'visitas_sem_venda',
    {'cliente_id': keeper},
    where: 'cliente_id = ?',
    whereArgs: [loser],
  );
  await db.update(
    'pedidos_fv_cache',
    {'cliente_id': keeper},
    where: 'cliente_id = ?',
    whereArgs: [loser],
  );
  await db.update(
    'historico_vendas',
    {'cliente_id': keeper},
    where: 'cliente_id = ?',
    whereArgs: [loser],
  );
  await db.update(
    'historico_orcamentos',
    {'cliente_id': keeper},
    where: 'cliente_id = ?',
    whereArgs: [loser],
  );
  await db.update(
    'financeiro',
    {'cliente_id': keeper},
    where: 'cliente_id = ?',
    whereArgs: [loser],
  );
  await db.update(
    'outbox_customers',
    {'local_id': keeper},
    where: 'local_id = ?',
    whereArgs: [loser],
  );

  await _mergeVisitaDias(db, loser, keeper);
}

/// Evita violar PK (person_id, dia_semana): remove dias do loser que o keeper já tem.
Future<void> _mergeVisitaDias(
  DatabaseExecutor db,
  int loser,
  int keeper,
) async {
  final keeperDays = await db.query(
    'customer_visita_dias',
    columns: ['dia_semana'],
    where: 'person_id = ?',
    whereArgs: [keeper],
  );
  final keepSet = keeperDays.map((r) => r['dia_semana'] as int).toSet();

  final loserDays = await db.query(
    'customer_visita_dias',
    columns: ['dia_semana'],
    where: 'person_id = ?',
    whereArgs: [loser],
  );

  for (final row in loserDays) {
    final dia = row['dia_semana'] as int;
    if (keepSet.contains(dia)) {
      await db.delete(
        'customer_visita_dias',
        where: 'person_id = ? AND dia_semana = ?',
        whereArgs: [loser, dia],
      );
    }
  }

  await db.update(
    'customer_visita_dias',
    {'person_id': keeper},
    where: 'person_id = ?',
    whereArgs: [loser],
  );
}

/// Após consolidar, só um outbox `pendente` por keeper (o mais antigo).
Future<void> _dedupeOutboxPendingForKeeper(
  DatabaseExecutor db,
  int keeper,
) async {
  final pending = await db.query(
    'outbox_customers',
    where: 'local_id = ? AND status = ?',
    whereArgs: [keeper, 'pendente'],
    orderBy: 'created_at ASC',
  );
  if (pending.length < 2) return;

  for (var i = 1; i < pending.length; i++) {
    final uuid = pending[i]['uuid']?.toString();
    if (uuid == null) continue;
    await db.update(
      'outbox_customers',
      {
        'status': 'enviado',
        'erro': 'consolidado_local_cpf_cnpj',
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }
}
