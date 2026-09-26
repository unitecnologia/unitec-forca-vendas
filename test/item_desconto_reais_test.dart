import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_forca_vendas/pricing/item_desconto.dart';

void main() {
  test('caso 1: 10 x 12,50 com R\$ 1,00 por unidade', () {
    final linha = descontoLinhaReais(
      valorDigitado: 1,
      quantidade: 10,
      precoUnitario: 12.50,
    );
    expect(linha, 10);
    expect(totalLiquidoItem(10, 12.50, linha), 115);
  });

  test('caso 2: 40 x 25,00 com R\$ 1,00 por unidade', () {
    final linha = descontoLinhaReais(
      valorDigitado: 1,
      quantidade: 40,
      precoUnitario: 25,
    );
    expect(linha, 40);
    expect(totalLiquidoItem(40, 25, linha), 960);
  });

  test('caso 3: quantidade 1 mantém desconto de R\$ 1,00', () {
    final linha = descontoLinhaReais(
      valorDigitado: 1,
      quantidade: 1,
      precoUnitario: 12.50,
    );
    expect(linha, 1);
    expect(totalLiquidoItem(1, 12.50, linha), 11.50);
  });

  test('caso 4: percentual continua bruto x % / 100', () {
    const bruto = 10 * 12.50;
    expect(descontoLinhaPercentual(bruto, 8), 10);
    expect(descontoLinhaPercentual(bruto, 10), 12.50);

    final map = mapaItemPedido(
      productId: 7,
      descricao: 'Item percentual',
      quantidade: 10,
      precoUnitario: 12.50,
      descontoPercentual: 10,
    );
    expect(map['desconto'], 12.50);
    expect(map.containsKey('desconto_unitario'), isFalse);
    expect(totalLiquidoItem(10, 12.50, map['desconto'] as double), 112.50);
  });

  test('quantidade 1 e depois 10 mantém R\$ 1,00 por unidade', () {
    const preco = 12.50;
    const unit = 1.0;

    final naUnidade = descontoEfetivo(
      quantidade: 1,
      precoUnitario: preco,
      descontoUnitario: unit,
    );
    expect(naUnidade, 1);
    expect(totalLiquidoItem(1, preco, naUnidade), 11.50);

    final emDez = descontoEfetivo(
      quantidade: 10,
      precoUnitario: preco,
      descontoUnitario: unit,
    );
    expect(emDez, 10);
    expect(totalLiquidoItem(10, preco, emDez), 115);
  });

  test('caso 5: offline grava e reabre com o mesmo desconto de linha', () {
    final salvo = mapaItemPedido(
      productId: 3,
      descricao: 'Produto',
      quantidade: 10,
      precoUnitario: 12.50,
      descontoUnitario: 1,
    );
    final reaberto = jsonDecode(jsonEncode(salvo)) as Map<String, dynamic>;

    final qtd = (reaberto['quantidade'] as num).toDouble();
    final preco = (reaberto['preco_unitario'] as num).toDouble();
    final unit = (reaberto['desconto_unitario'] as num).toDouble();
    final linha = descontoEfetivo(
      quantidade: qtd,
      precoUnitario: preco,
      descontoUnitario: unit,
      descontoValorLegado: (reaberto['desconto'] as num).toDouble(),
    );

    expect(reaberto['desconto'], 10);
    expect(unit, 1);
    expect(linha, 10);
    expect(totalLiquidoItem(qtd, preco, linha), 115);

    final depois = descontoEfetivo(
      quantidade: 10,
      precoUnitario: preco,
      descontoUnitario: unit,
    );
    expect(depois, 10);
  });

  test('caso 6: payload ao ERP manda o desconto total da linha', () {
    final item = mapaItemPedido(
      productId: 9,
      descricao: 'Produto',
      quantidade: 10,
      precoUnitario: 12.50,
      descontoUnitario: 1,
    );

    // ForcaVendasSyncService: total = round((quantidade * preco) - desconto, 2).
    expect(item['quantidade'], 10);
    expect(item['preco_unitario'], 12.50);
    expect(item['desconto'], 10);
    expect(item['desconto'], isNot(1));
    expect(totalLiquidoItem(10, 12.50, item['desconto'] as double), 115);

    final item40 = mapaItemPedido(
      productId: 9,
      descricao: 'Produto',
      quantidade: 40,
      precoUnitario: 25,
      descontoUnitario: 1,
    );
    expect(item40['desconto'], 40);
    expect(totalLiquidoItem(40, 25, item40['desconto'] as double), 960);
  });

  test('pedido antigo sem desconto_unitario não multiplica de novo', () {
    final linha = descontoEfetivo(
      quantidade: 10,
      precoUnitario: 12.50,
      descontoValorLegado: 1,
    );
    expect(linha, 1);
    expect(totalLiquidoItem(10, 12.50, linha), 124);
  });

  test('modo linha: 10 x 12,50 com R\$ 1,00 fica R\$ 1,00 na linha', () {
    final linha = descontoLinhaReaisNoModo(
      modo: descontoReaisModoLinha,
      valorDigitado: 1,
      quantidade: 10,
      precoUnitario: 12.50,
    );
    expect(linha, 1);
    expect(totalLiquidoItem(10, 12.50, linha), 124);

    final item = mapaItemPedido(
      productId: 4,
      descricao: 'Linha',
      quantidade: 10,
      precoUnitario: 12.50,
      descontoValorLegado: linha,
      descontoLinhaFixa: true,
    );
    expect(item['desconto'], 1);
    expect(item.containsKey('desconto_unitario'), isFalse);
    expect(item['desconto_reais_modo'], descontoReaisModoLinha);
  });

  test('quantidade muda nos dois modos', () {
    final unitario10 = descontoLinhaReaisNoModo(
      modo: descontoReaisModoUnitario,
      valorDigitado: 1,
      quantidade: 10,
      precoUnitario: 12.50,
    );
    final unitario11 = descontoLinhaReaisNoModo(
      modo: descontoReaisModoUnitario,
      valorDigitado: 1,
      quantidade: 11,
      precoUnitario: 12.50,
    );
    expect(unitario10, 10);
    expect(unitario11, 11);
    expect(totalLiquidoItem(11, 12.50, unitario11), 126.50);

    final linha10 = descontoLinhaValorInformado(10, 10 * 12.50);
    final linha11 = descontoEfetivo(
      quantidade: 11,
      precoUnitario: 12.50,
      descontoValorLegado: linha10,
    );
    expect(linha10, 10);
    expect(linha11, 10);
    expect(totalLiquidoItem(11, 12.50, linha11), 127.50);
  });

  test('percentual nao depende do modo de R\$', () {
    const bruto = 10 * 12.50;
    expect(descontoLinhaPercentual(bruto, 10), 12.50);

    for (final modo in [descontoReaisModoUnitario, descontoReaisModoLinha]) {
      expect(normalizarDescontoReaisItemModo(modo), modo);
      final item = mapaItemPedido(
        productId: 8,
        descricao: 'Percentual $modo',
        quantidade: 10,
        precoUnitario: 12.50,
        descontoPercentual: 10,
        descontoLinhaFixa: modo == descontoReaisModoLinha,
      );
      expect(item['desconto'], 12.50);
      expect(item.containsKey('desconto_unitario'), isFalse);
      expect(item.containsKey('desconto_reais_modo'), isFalse);
      expect(totalLiquidoItem(10, 12.50, item['desconto'] as double), 112.50);
    }
  });

  test('offline e reabertura de linha fixa e de pedido antigo', () {
    final salvo = mapaItemPedido(
      productId: 5,
      descricao: 'Linha offline',
      quantidade: 10,
      precoUnitario: 12.50,
      descontoValorLegado: 1,
      descontoLinhaFixa: true,
    );
    final reaberto = jsonDecode(jsonEncode(salvo)) as Map<String, dynamic>;
    expect(reaberto['desconto'], 1);
    expect(reaberto['desconto_reais_modo'], descontoReaisModoLinha);
    expect(reaberto.containsKey('desconto_unitario'), isFalse);

    final depois = descontoEfetivo(
      quantidade: 11,
      precoUnitario: (reaberto['preco_unitario'] as num).toDouble(),
      descontoValorLegado: (reaberto['desconto'] as num).toDouble(),
    );
    expect(depois, 1);
    expect(totalLiquidoItem(11, 12.50, depois), 136.50);

    final antigo = <String, dynamic>{
      'product_id': 1,
      'quantidade': 10.0,
      'preco_unitario': 12.5,
      'desconto': 1.0,
      'descricao': 'Pedido antigo',
    };
    expect(antigo.containsKey('desconto_unitario'), isFalse);
    expect(antigo.containsKey('desconto_reais_modo'), isFalse);
    final valorAntigo = descontoEfetivo(
      quantidade: (antigo['quantidade'] as num).toDouble(),
      precoUnitario: (antigo['preco_unitario'] as num).toDouble(),
      descontoValorLegado: (antigo['desconto'] as num).toDouble(),
    );
    expect(valorAntigo, 1);
    expect(totalLiquidoItem(10, 12.50, valorAntigo), 124);
  });

  test('sync ERP recebe o total da linha nos dois modos', () {
    final unitario = mapaItemPedido(
      productId: 9,
      descricao: 'Unitario',
      quantidade: 10,
      precoUnitario: 12.50,
      descontoUnitario: 1,
    );
    expect(unitario['desconto'], 10);
    expect(unitario['desconto_unitario'], 1);
    expect(unitario.containsKey('desconto_reais_modo'), isFalse);

    final linha = mapaItemPedido(
      productId: 9,
      descricao: 'Linha',
      quantidade: 10,
      precoUnitario: 12.50,
      descontoValorLegado: 1,
      descontoLinhaFixa: true,
    );
    expect(linha['desconto'], 1);
    expect(linha.containsKey('desconto_unitario'), isFalse);
    expect((10 * 12.50) - (linha['desconto'] as double), 124);
  });
}
