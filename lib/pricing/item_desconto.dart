// Desconto do item no pedido da Força de Vendas.
// Percentual: total da linha = bruto × % / 100. Não depende do parâmetro da empresa.
// R$: a empresa define se o valor digitado é por unidade ou o total da linha.
// O campo `desconto` gravado e enviado ao ERP é sempre o total da linha.

const descontoReaisModoUnitario = 'unitario';
const descontoReaisModoLinha = 'linha';

String normalizarDescontoReaisItemModo(Object? raw) {
  return raw?.toString() == descontoReaisModoLinha ? descontoReaisModoLinha : descontoReaisModoUnitario;
}

double dinheiroCentavos(double v) {
  if (v.isNaN || v.isInfinite) return 0;
  return double.parse(v.toStringAsFixed(2));
}

/// Fórmula atual do modo %. Não arredondar aqui.
double descontoLinhaPercentual(double bruto, double percentual) {
  if (percentual <= 0 || bruto <= 0) return 0;
  return (bruto * percentual / 100).clamp(0.0, bruto).toDouble();
}

/// Desconto unitário aplicado, limitado ao preço (não deixa líquido negativo).
double descontoUnitarioAplicado(double valorDigitado, double precoUnitario) {
  final unit = dinheiroCentavos(valorDigitado);
  if (unit <= 0) return 0;
  final preco = dinheiroCentavos(precoUnitario);
  if (preco > 0 && unit > preco) return preco;
  return unit;
}

/// Total de desconto da linha no modo R$ por unidade: unitário × quantidade.
double descontoLinhaReais({
  required double valorDigitado,
  required double quantidade,
  required double precoUnitario,
}) {
  final unit = descontoUnitarioAplicado(valorDigitado, precoUnitario);
  if (unit <= 0 || quantidade <= 0) return 0;
  final linha = dinheiroCentavos(unit * quantidade);
  final bruto = quantidade * precoUnitario;
  if (bruto <= 0) return 0;
  if (linha > bruto) return dinheiroCentavos(bruto);
  return linha;
}

/// Modo linha: o valor digitado é o desconto da linha, uma vez só.
double descontoLinhaValorInformado(double valorDigitado, double bruto) {
  final valor = dinheiroCentavos(valorDigitado);
  if (valor <= 0 || bruto <= 0) return 0;
  if (valor > bruto) return dinheiroCentavos(bruto);
  return valor;
}

/// R$ conforme o parâmetro da empresa. Percentual não passa por aqui.
double descontoLinhaReaisNoModo({
  required String modo,
  required double valorDigitado,
  required double quantidade,
  required double precoUnitario,
}) {
  final bruto = quantidade * precoUnitario;
  if (normalizarDescontoReaisItemModo(modo) == descontoReaisModoLinha) {
    return descontoLinhaValorInformado(valorDigitado, bruto);
  }
  return descontoLinhaReais(
    valorDigitado: valorDigitado,
    quantidade: quantidade,
    precoUnitario: precoUnitario,
  );
}

double descontoEfetivo({
  required double quantidade,
  required double precoUnitario,
  double? descontoPercentual,
  double? descontoUnitario,
  double descontoValorLegado = 0,
}) {
  final bruto = quantidade * precoUnitario;
  if (descontoPercentual != null && descontoPercentual > 0) {
    return descontoLinhaPercentual(bruto, descontoPercentual);
  }
  if (descontoUnitario != null && descontoUnitario > 0) {
    return descontoLinhaReais(
      valorDigitado: descontoUnitario,
      quantidade: quantidade,
      precoUnitario: precoUnitario,
    );
  }
  if (bruto <= 0) return 0;
  return descontoValorLegado.clamp(0.0, bruto).toDouble();
}

/// Mesma conta do ERP ao importar o item: (qtd × preço) − desconto da linha.
double totalLiquidoItem(double quantidade, double precoUnitario, double descontoLinha) {
  final bruto = quantidade * precoUnitario;
  final desc = descontoLinha.clamp(0.0, bruto > 0 ? bruto : 0.0).toDouble();
  return dinheiroCentavos(bruto - desc);
}

/// JSON do item (outbox local e payload enviado ao ERP).
/// `desconto` é o total da linha.
/// `desconto_unitario` só no modo R$ por unidade.
/// `desconto_reais_modo` = linha só quando o R$ é valor fixo da linha.
Map<String, dynamic> mapaItemPedido({
  required int productId,
  required String descricao,
  required double quantidade,
  required double precoUnitario,
  double? descontoPercentual,
  double? descontoUnitario,
  double descontoValorLegado = 0,
  bool descontoLinhaFixa = false,
}) {
  final linha = descontoEfetivo(
    quantidade: quantidade,
    precoUnitario: precoUnitario,
    descontoPercentual: descontoPercentual,
    descontoUnitario: descontoUnitario,
    descontoValorLegado: descontoValorLegado,
  );
  final percentual = descontoPercentual != null && descontoPercentual > 0;
  final unitario = descontoUnitario != null && descontoUnitario > 0;
  return {
    'product_id': productId,
    'quantidade': quantidade,
    'preco_unitario': precoUnitario,
    'desconto': linha,
    'descricao': descricao,
    if (unitario) 'desconto_unitario': descontoUnitario,
    if (descontoLinhaFixa && !percentual && !unitario) 'desconto_reais_modo': descontoReaisModoLinha,
  };
}
