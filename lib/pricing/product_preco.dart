import '../db/local_db.dart';

/// Resolve o preço do produto conforme a Lista de Preço / Tabela Venda.
///
/// Ordem:
/// 1. Item em `price_table_items` (se o produto usa tab. preço)
/// 2. Mapeamento da tabela: VAREJO → varejo, ATACADO → atacado,
///    ESPECIAL → especial (com fallback para varejo)
/// 3. Em VAREJO, se qty ≥ qtd_atacado → atacado
class ProductPreco {
  ProductPreco._();

  static String nivelDaTabela({String? codigo, String? descricao}) {
    final blob = '${codigo ?? ''} ${descricao ?? ''}'.toUpperCase();
    if (blob.contains('ESPECIAL')) return 'especial';
    if (blob.contains('ATACADO')) return 'atacado';
    if (blob.contains('VAREJO')) return 'varejo';
    // Legado: PADRAO / código 1
    if (blob.contains('PADRAO') || blob.contains('PADRÃO') || codigo == '1') {
      return 'varejo';
    }
    return 'varejo';
  }

  static double _num(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  static double precoVarejo(Map<String, dynamic> produto) {
    final promo = _num(produto['promo_preco_venda']);
    if (promo > 0) return promo;
    return _num(produto['preco_venda']);
  }

  static double precoAtacado(Map<String, dynamic> produto) {
    final atacado = _num(produto['preco_atacado']);
    if (atacado > 0) return atacado;
    return precoVarejo(produto);
  }

  static double precoEspecial(Map<String, dynamic> produto) {
    final especial = _num(produto['preco_especial']);
    if (especial > 0) return especial;
    return precoVarejo(produto);
  }

  static double precoBasePorNivel(
    Map<String, dynamic> produto,
    String nivel, {
    double quantidade = 1,
  }) {
    switch (nivel) {
      case 'atacado':
        return precoAtacado(produto);
      case 'especial':
        return precoEspecial(produto);
      case 'varejo':
      default:
        final qtdAtacado = _num(produto['qtd_atacado']);
        final atacado = _num(produto['preco_atacado']);
        if (qtdAtacado > 0 && atacado > 0 && quantidade >= qtdAtacado) {
          return atacado;
        }
        return precoVarejo(produto);
    }
  }

  /// Resolve preço síncrono (sem consultar itens de tabela nomeada).
  static double resolveSync(
    Map<String, dynamic> produto, {
    Map<String, dynamic>? listaPreco,
    double quantidade = 1,
  }) {
    final nivel = nivelDaTabela(
      codigo: listaPreco?['codigo']?.toString(),
      descricao: listaPreco?['descricao']?.toString(),
    );
    return precoBasePorNivel(produto, nivel, quantidade: quantidade);
  }

  /// Resolve com overlay de `price_table_items` quando `usa_tab_preco`.
  static Future<double> resolve(
    Map<String, dynamic> produto, {
    Map<String, dynamic>? listaPreco,
    double quantidade = 1,
    LocalDb? db,
  }) async {
    final nivel = nivelDaTabela(
      codigo: listaPreco?['codigo']?.toString(),
      descricao: listaPreco?['descricao']?.toString(),
    );
    final base = precoBasePorNivel(produto, nivel, quantidade: quantidade);

    final usaTab = produto['usa_tab_preco'] == 1 || produto['usa_tab_preco'] == true;
    final tableId = listaPreco?['id'];
    final productId = produto['id'];
    if (!usaTab || tableId == null || productId == null) {
      return base;
    }

    final database = db ?? LocalDb.instance;
    final rows = await database.query(
      'SELECT valor, fator FROM price_table_items '
      'WHERE product_id = ? AND price_table_id = ? LIMIT 1',
      [productId, tableId],
    );
    if (rows.isEmpty) return base;

    final valor = _num(rows.first['valor']);
    if (valor > 0) return double.parse(valor.toStringAsFixed(2));

    final fator = _num(rows.first['fator']);
    if (fator > 0) {
      return double.parse((base * fator).toStringAsFixed(2));
    }
    return base;
  }
}
