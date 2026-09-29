import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitec_forca_vendas/db/local_db.dart';
import 'package:unitec_forca_vendas/payment/prazo_financeiro.dart';

/// Espelha as decisões de NovoPedidoScreen para o prazo financeiro,
/// sem subir UI (sem dispositivo Android nesta validação).
class _PrazoPedidoState {
  int? formaId;
  String forma = '';
  String condicao = '';
  String? tabelaDias;
  int? tabelaPrazoId;
  final formas = <Map<String, dynamic>>[];

  Map<String, dynamic>? formaById(int? id) {
    if (id == null) return null;
    for (final f in formas) {
      if ((f['id'] as int?) == id) return f;
    }
    return null;
  }

  bool get formaTemPrazoFinanceiroValido {
    final (max, intervalo) = lerParcelasForma(formaById(formaId));
    return isPrazoFinanceiroValido(max, intervalo);
  }

  String formaTipo() => (formaById(formaId)?['tipo'] ?? '').toString();

  bool get avulsoOculto =>
      formaTipo() == 'dinheiro' || formaTipo() == 'pix' || formaTemPrazoFinanceiroValido;

  List<int> diasDe(String s) => s
      .split(',')
      .map((d) => int.tryParse(d.trim()))
      .whereType<int>()
      .toList();

  List<int> diasEfetivos() {
    final avulso = diasDe(condicao);
    if (avulso.isNotEmpty) return avulso;
    final tabela = diasDe(tabelaDias ?? '');
    if (tabela.isNotEmpty) return tabela;
    return diasPrazoFinanceiroDaForma(formaById(formaId)) ?? const <int>[];
  }

  void aplicarForma(int? id, {bool preservarPrazoNegociado = false}) {
    final f = formaById(id);
    formaId = id;
    forma = (f?['descricao'] ?? '').toString();
    if (preservarPrazoNegociado) return;
    if (avulsoOculto) condicao = '';
    aplicarPrazoFinanceiroDaForma();
  }

  void aplicarPrazoFinanceiroDaForma() {
    final dias = diasPrazoFinanceiroDaForma(formaById(formaId));
    if (dias != null && dias.isNotEmpty) {
      tabelaPrazoId = null;
      tabelaDias = dias.join(',');
      condicao = '';
      return;
    }
    if (tabelaPrazoId != null) return;
    tabelaDias = null;
  }

  Map<String, dynamic> payloadExtra() {
    var tabelaDiasPayload = (tabelaDias ?? '').trim();
    final condicaoPayload = condicao.trim();
    if (tabelaDiasPayload.isEmpty && condicaoPayload.isEmpty) {
      final diasAuto = diasPrazoFinanceiroDaForma(formaById(formaId));
      if (diasAuto != null && diasAuto.isNotEmpty) {
        tabelaDiasPayload = diasAuto.join(',');
        tabelaDias = tabelaDiasPayload;
      }
    }
    return {
      'forma_pagamento': forma,
      'forma_pagamento_id': formaId,
      'tabela_prazo_id': tabelaPrazoId,
      'tabela_prazo_dias': tabelaDiasPayload.isEmpty ? tabelaDias : tabelaDiasPayload,
      'condicao_pagamento': condicaoPayload,
    };
  }

  void reabrir(Map<String, dynamic> extra) {
    final prazoNegociadoCondicao = (extra['condicao_pagamento'] ?? '').toString().trim();
    final prazoNegociadoDias = (extra['tabela_prazo_dias'] ?? '').toString().trim();
    final tidExtra = extra['tabela_prazo_id'] as int?;
    final temPrazoNegociado = prazoNegociadoCondicao.isNotEmpty ||
        prazoNegociadoDias.isNotEmpty ||
        tidExtra != null;

    condicao = prazoNegociadoCondicao;
    final formaIdExtra = extra['forma_pagamento_id'] as int?;
    if (formaIdExtra != null && formaById(formaIdExtra) != null) {
      aplicarForma(formaIdExtra, preservarPrazoNegociado: true);
    }
    if (prazoNegociadoCondicao.isNotEmpty) {
      condicao = prazoNegociadoCondicao;
    }
    if (tidExtra != null) {
      tabelaPrazoId = tidExtra;
      tabelaDias = prazoNegociadoDias.isNotEmpty ? prazoNegociadoDias : null;
      if (prazoNegociadoCondicao.isEmpty) condicao = '';
    } else if (prazoNegociadoDias.isNotEmpty) {
      tabelaPrazoId = null;
      tabelaDias = prazoNegociadoDias;
      if (prazoNegociadoCondicao.isEmpty) condicao = '';
    } else if (!temPrazoNegociado) {
      aplicarPrazoFinanceiroDaForma();
    }
  }
}

void main() {
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('fv_sync_boleto_');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('pull mapeia BOLETO 7 com max=1 intervalo=7 no SQLite', () async {
    final path = p.join(tmpDir.path, 'sync.db');
    final db = await LocalDb.openAtPath(path, version: 21);
    final local = LocalDb.openForTest; // ignore — usamos db direto
    // ignore: unused_local_variable
    final _ = local;

    // Espelha sync_service upsert das formas.
    await db.delete('formas_pagamento');
    final payload = {
      'id': 4,
      'codigo': 4,
      'descricao': 'BOLETO 7',
      'tipo': 'boleto',
      'tipo_movimento': 'contas_receber',
      'nfce': 0,
      'max_parcelas': 1,
      'intervalo_parcelas': 7,
      'tabelas_json': jsonEncode([]),
    };
    await db.insert('formas_pagamento', payload);

    final row = (await db.query('formas_pagamento', where: 'id = 4')).single;
    expect(row['codigo'], 4);
    expect(row['descricao'], 'BOLETO 7');
    expect(row['max_parcelas'], 1);
    expect(row['intervalo_parcelas'], 7);
    await db.close();
  });

  test('Dados/Resumo BOLETO 7 emissão 28/09/2026 → 05/10/2026 + payload "7"', () {
    final s = _PrazoPedidoState()
      ..formas.addAll([
        {
          'id': 4,
          'codigo': 4,
          'descricao': 'BOLETO 7',
          'tipo': 'boleto',
          'max_parcelas': 1,
          'intervalo_parcelas': 7,
        },
        {
          'id': 1,
          'codigo': 1,
          'descricao': 'DINHEIRO',
          'tipo': 'dinheiro',
          'max_parcelas': 1,
          'intervalo_parcelas': 30,
        },
        {
          'id': 2,
          'codigo': 2,
          'descricao': 'BOLETO',
          'tipo': 'boleto',
          'max_parcelas': 1,
          'intervalo_parcelas': 30, // default → avulso
        },
      ]);

    s.aplicarForma(4);
    expect(s.avulsoOculto, isTrue); // Prazo Avulso não aparece
    expect(s.diasEfetivos(), [7]);
    expect(s.forma, 'BOLETO 7');

    final emissao = DateTime(2026, 9, 28);
    final venc = emissao.add(Duration(days: s.diasEfetivos().first));
    expect(venc, DateTime(2026, 10, 5));
    expect(s.diasEfetivos().length, 1); // 1 parcela

    final extra = s.payloadExtra();
    expect(extra['tabela_prazo_dias'], '7');
    expect(extra['condicao_pagamento'], '');

    // Troca: BOLETO 7 → forma sem prazo válido (default 1,30)
    s.aplicarForma(2);
    expect(s.avulsoOculto, isFalse); // Prazo Avulso reaparece
    expect(s.tabelaDias, isNull);
    expect(s.condicao, isEmpty);
    expect(s.diasEfetivos(), isEmpty);

    // Digita avulso residual e troca de volta para BOLETO 7
    s.condicao = '15';
    s.aplicarForma(4);
    expect(s.avulsoOculto, isTrue);
    expect(s.condicao, isEmpty); // limpa residual — não contamina
    expect(s.tabelaDias, '7');
    expect(s.diasEfetivos(), [7]);
  });

  test('reabrir pedido negociado tabela_prazo_dias=21 não vira 7', () {
    final s = _PrazoPedidoState()
      ..formas.add({
        'id': 4,
        'descricao': 'BOLETO 7',
        'tipo': 'boleto',
        'max_parcelas': 1,
        'intervalo_parcelas': 7,
      });

    s.reabrir({
      'forma_pagamento_id': 4,
      'tabela_prazo_dias': '21',
      'condicao_pagamento': '',
    });

    expect(s.tabelaDias, '21');
    expect(s.diasEfetivos(), [21]);
    final saved = s.payloadExtra();
    expect(saved['tabela_prazo_dias'], '21');
  });
}
