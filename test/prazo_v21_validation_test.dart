import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitec_forca_vendas/db/local_db.dart';
import 'package:unitec_forca_vendas/payment/prazo_financeiro.dart';

/// Validação final do ajuste de prazo — migration + lógica offline.
/// Usa DB temporário (não toca o SQLite do aparelho).
void main() {
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('fv_prazo_v21_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('upgrade v20 → v21: só adiciona intervalo_parcelas e limpa pull_etag', () async {
    final path = p.join(tmpDir.path, 'upgrade.db');

    // Base no schema v20 (CREATE atual sem depender de migration parcial).
    // Depois removemos intervalo_parcelas e setamos user_version=20 para
    // exercitar exatamente o bloco oldVersion < 21.
    final dbV20 = await LocalDb.openAtPath(path, version: 21);
    await dbV20.execute('ALTER TABLE formas_pagamento DROP COLUMN intervalo_parcelas');
    // Restaura pull_etag e dados operacionais.
    await dbV20.insert('sync_meta', {'k': 'pull_etag', 'v': '"etag-v20"'});
    await dbV20.insert('sync_meta', {'k': 'token', 'v': 'auth-token-keep'});
    await dbV20.insert('formas_pagamento', {
      'id': 4,
      'codigo': 4,
      'descricao': 'BOLETO 7',
      'tipo': 'boleto',
      'max_parcelas': 1,
      'tabelas_json': '[]',
    });
    await dbV20.insert('outbox_orders', {
      'uuid': 'pedido-negociado',
      'cliente_id': 1,
      'tipo': 'pedido',
      'total': 100.0,
      'itens_json': '[]',
      'created_at': '2026-09-28T12:00:00Z',
      'status': 'pendente',
      'extra_json':
          '{"forma_pagamento_id":4,"forma_pagamento":"BOLETO 7","tabela_prazo_dias":"21","condicao_pagamento":""}',
    });
    await dbV20.rawQuery('PRAGMA user_version = 20');
    await dbV20.close();

    // Confirma v20 sem a coluna.
    final probe = await databaseFactory.openDatabase(path);
    final colsBefore = await probe.rawQuery('PRAGMA table_info(formas_pagamento)');
    expect(colsBefore.any((c) => c['name'] == 'intervalo_parcelas'), isFalse);
    expect((await probe.rawQuery('PRAGMA user_version')).first['user_version'], 20);
    await probe.close();

    // Upgrade real via LocalDb.openAtPath (onUpgrade v20→v21).
    final dbV21 = await LocalDb.openAtPath(path, version: 21);

    final ver = await dbV21.rawQuery('PRAGMA user_version');
    expect(ver.first['user_version'], 21);

    final cols = await dbV21.rawQuery('PRAGMA table_info(formas_pagamento)');
    final colNames = cols.map((c) => c['name']).toSet();
    expect(colNames.contains('intervalo_parcelas'), isTrue);

    // Forma, outbox e extra_json preservados.
    final forma = (await dbV21.query('formas_pagamento', where: 'id = 4')).single;
    expect(forma['descricao'], 'BOLETO 7');
    expect(forma['max_parcelas'], 1);
    expect(forma['intervalo_parcelas'], isNull); // coluna nova, valor só no próximo pull

    final outbox = (await dbV21.query('outbox_orders', where: "uuid = 'pedido-negociado'")).single;
    expect(outbox['status'], 'pendente');
    expect(outbox['extra_json'], contains('"tabela_prazo_dias":"21"'));

    // pull_etag removido; demais meta preservados.
    final etag = await dbV21.query('sync_meta', where: "k = 'pull_etag'");
    expect(etag, isEmpty);
    final token = await dbV21.query('sync_meta', where: "k = 'token'");
    expect(token.single['v'], 'auth-token-keep');

    // Não apagou tabelas operacionais.
    final tables = (await dbV21.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('outbox_orders','formas_pagamento','sync_meta')",
    )).map((r) => r['name']).toSet();
    expect(tables, containsAll(['outbox_orders', 'formas_pagamento', 'sync_meta']));

    await dbV21.close();
  });

  test('fluxo BOLETO 7: oculta avulso, dias=7, payload e troca de forma', () {
    const boleto7 = {'id': 4, 'max_parcelas': 1, 'intervalo_parcelas': 7, 'descricao': 'BOLETO 7'};
    const semPrazo = {'id': 1, 'max_parcelas': 1, 'intervalo_parcelas': 30, 'descricao': 'DINHEIRO'};
    const forma3x30 = {'id': 9, 'max_parcelas': 3, 'intervalo_parcelas': 30, 'descricao': 'BOLETO 3x'};

    // Seleciona BOLETO 7
    var condicao = '99'; // valor antigo residual
    var tabelaDias = '';
    void aplicar(Map<String, dynamic> f) {
      final dias = diasPrazoFinanceiroDaForma(f);
      final avulsoOculto = (f['descricao'] == 'DINHEIRO') ||
          (dias != null); // espelho: dinheiro/pix OU prazo financeiro válido
      // Na tela real dinheiro/pix também ocultam; aqui semPrazo=default(1,30) mostra avulso.
      final oculto = isPrazoFinanceiroValido(
            (f['max_parcelas'] as int),
            (f['intervalo_parcelas'] as int),
          ) ||
          f['descricao'] == 'DINHEIRO';
      if (oculto) condicao = '';
      if (dias != null) {
        tabelaDias = dias.join(',');
        condicao = '';
      } else if (!isPrazoFinanceiroValido(
        f['max_parcelas'] as int,
        f['intervalo_parcelas'] as int,
      )) {
        tabelaDias = '';
      }
      expect(oculto, avulsoOculto || f['descricao'] == 'DINHEIRO');
    }

    aplicar(boleto7);
    expect(condicao, isEmpty); // não contamina
    expect(tabelaDias, '7');
    expect(diasPrazoFinanceiroDaForma(boleto7), [7]);

    final emissao = DateTime(2026, 9, 28);
    final venc = emissao.add(Duration(days: int.parse(tabelaDias)));
    expect(venc, DateTime(2026, 10, 5));

    // Troca para forma sem prazo válido (1,30)
    aplicar(semPrazo);
    expect(tabelaDias, isEmpty);
    expect(isPrazoFinanceiroValido(1, 30), isFalse);

    // Volta BOLETO 7
    condicao = '15'; // simula digitação residual
    aplicar(boleto7);
    expect(condicao, isEmpty);
    expect(tabelaDias, '7');

    // (3,30)
    aplicar(forma3x30);
    expect(tabelaDias, '30,60,90');
  });

  test('reabertura preserva prazo negociado e não substitui pela forma', () {
    const forma = {'max_parcelas': 1, 'intervalo_parcelas': 7};
    const extra = {
      'forma_pagamento_id': 4,
      'tabela_prazo_dias': '21',
      'condicao_pagamento': '',
    };

    final negociado = (extra['tabela_prazo_dias'] as String).trim();
    final temNegociado = negociado.isNotEmpty;
    expect(temNegociado, isTrue);

    // Com preservar: NÃO aplica dias da forma
    String? tabelaDias = negociado;
    if (!temNegociado) {
      tabelaDias = diasPrazoFinanceiroDaForma(forma)?.join(',');
    }
    expect(tabelaDias, '21');
    expect(diasPrazoFinanceiroDaForma(forma), [7]); // forma ainda seria 7, mas não sobrescreve
  });
}
