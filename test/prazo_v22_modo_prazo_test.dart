import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitec_forca_vendas/db/local_db.dart';
import 'package:unitec_forca_vendas/payment/prazo_financeiro.dart';

/// Migration v22 (modo_prazo) + regra offline.
void main() {
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('fv_prazo_v22_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('upgrade v21 → v22: adiciona modo_prazo e limpa pull_etag', () async {
    final path = p.join(tmpDir.path, 'upgrade.db');

    // Cria schema atual e remove modo_prazo para simular DB em v21.
    final seed = await LocalDb.openAtPath(path, version: 22);
    await seed.execute('ALTER TABLE formas_pagamento DROP COLUMN modo_prazo');
    await seed.insert('sync_meta', {'k': 'pull_etag', 'v': '"etag-v21"'});
    await seed.insert('sync_meta', {'k': 'token', 'v': 'auth-token-keep'});
    await seed.insert('formas_pagamento', {
      'id': 4,
      'codigo': 4,
      'descricao': 'BOLETO 7',
      'tipo': 'boleto',
      'max_parcelas': 1,
      'intervalo_parcelas': 7,
    });
    await seed.execute('PRAGMA user_version = 21');
    await seed.close();

    final probe = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final colsBefore = await probe.rawQuery('PRAGMA table_info(formas_pagamento)');
    expect(colsBefore.any((c) => c['name'] == 'modo_prazo'), isFalse);
    final verBefore = await probe.rawQuery('PRAGMA user_version');
    expect(verBefore.first['user_version'], 21);
    await probe.close();

    final dbV22 = await LocalDb.openAtPath(path, version: 22);
    final cols = await dbV22.rawQuery('PRAGMA table_info(formas_pagamento)');
    final colNames = cols.map((c) => c['name']).toSet();
    expect(colNames.contains('modo_prazo'), isTrue);

    final etag = await dbV22.query('sync_meta', where: 'k = ?', whereArgs: ['pull_etag']);
    expect(etag, isEmpty);

    final token = await dbV22.query('sync_meta', where: 'k = ?', whereArgs: ['token']);
    expect(token.single['v'], 'auth-token-keep');

    final forma = (await dbV22.query('formas_pagamento', where: 'id = 4')).single;
    expect(forma['max_parcelas'], 1);
    expect(forma['intervalo_parcelas'], 7);
    expect(forma['modo_prazo'], isNull); // valor só no próximo pull

    await dbV22.close();
  });

  test('modo_prazo tabela ignora 1×7 residual no SQLite', () {
    expect(
      diasPrazoFinanceiroDaForma({
        'max_parcelas': 1,
        'intervalo_parcelas': 7,
        'modo_prazo': 'tabela',
      }),
      isNull,
    );
    expect(
      diasPrazoFinanceiroDaForma({
        'max_parcelas': 1,
        'intervalo_parcelas': 7,
        'modo_prazo': 'financeiro',
      }),
      [7],
    );
  });
}
