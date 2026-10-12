import '../db/local_db.dart';

/// Opção de Tab. Preço (nível habilitado no cadastro do produto).
class TabPrecoOpcao {
  const TabPrecoOpcao({
    required this.nivel,
    required this.priceTableId,
    required this.codigo,
    required this.descricao,
    required this.preco,
  });

  final String nivel;
  final int priceTableId;
  final String codigo;
  final String descricao;
  final double preco;

  String get label => '$codigo - $descricao';
}

/// Resolve o preço do produto conforme a Lista de Preço / Tabela Venda.
///
/// Com `usa_tab_preco`:
/// - `price_table_items` só habilita Varejo/Atacado/Especial;
/// - o valor vem da Precificação (`preco_venda` / `preco_atacado` / `preco_especial`);
/// - a escolha do nível é obrigatória no lançamento (mesmo com 1 opção).
///
/// Sem a flag: tabela do pedido (cliente/vendedor) + regra de qtd. atacado no varejo.
class ProductPreco {
  ProductPreco._();

  static const ordemNiveis = ['varejo', 'atacado', 'especial'];

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

  static String labelNivel(String nivel) {
    switch (nivel) {
      case 'atacado':
        return 'ATACADO';
      case 'especial':
        return 'ESPECIAL';
      case 'varejo':
      default:
        return 'VAREJO';
    }
  }

  static String codigoNivel(String nivel) {
    switch (nivel) {
      case 'atacado':
        return '2';
      case 'especial':
        return '3';
      case 'varejo':
      default:
        return '1';
    }
  }

  static bool usaTabPreco(Map<String, dynamic> produto) {
    final v = produto['usa_tab_preco'];
    return v == 1 || v == true || v == '1';
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

  /// Preço da Precificação para um nível escolhido (sem troca automática por qtd).
  static double precoDoNivel(Map<String, dynamic> produto, String nivel) {
    switch (nivel) {
      case 'atacado':
        return double.parse(precoAtacado(produto).toStringAsFixed(2));
      case 'especial':
        return double.parse(precoEspecial(produto).toStringAsFixed(2));
      case 'varejo':
      default:
        return double.parse(precoVarejo(produto).toStringAsFixed(2));
    }
  }

  /// Preço pela tabela do pedido (produtos sem Tab. Preço).
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

  /// Resolve preço síncrono (sem Tab. Preço / sem consultar itens).
  static double resolveSync(
    Map<String, dynamic> produto, {
    Map<String, dynamic>? listaPreco,
    double quantidade = 1,
    String? nivel,
  }) {
    if (usaTabPreco(produto) && nivel != null && nivel.isNotEmpty) {
      return precoDoNivel(produto, nivel);
    }

    final n = nivel ??
        nivelDaTabela(
          codigo: listaPreco?['codigo']?.toString(),
          descricao: listaPreco?['descricao']?.toString(),
        );
    return precoBasePorNivel(produto, n, quantidade: quantidade);
  }

  /// Níveis habilitados no produto (`price_table_items` = enablement).
  /// Offline: lê só o SQLite local.
  static Future<List<TabPrecoOpcao>> opcoesHabilitadas(
    Map<String, dynamic> produto, {
    LocalDb? db,
    double quantidade = 1,
  }) async {
    if (!usaTabPreco(produto)) return const [];

    final productId = produto['id'];
    if (productId == null) return const [];

    final database = db ?? LocalDb.instance;
    final rows = await database.query(
      'SELECT pti.price_table_id AS price_table_id, '
      'pti.nivel AS nivel, '
      'pt.codigo AS codigo, pt.descricao AS descricao '
      'FROM price_table_items pti '
      'LEFT JOIN price_tables pt ON pt.id = pti.price_table_id '
      'WHERE pti.product_id = ?',
      [productId],
    );

    final byNivel = <String, TabPrecoOpcao>{};
    for (final r in rows) {
      final tableId = (r['price_table_id'] as num?)?.toInt();
      if (tableId == null || tableId <= 0) continue;

      var nivel = (r['nivel'] ?? '').toString().trim().toLowerCase();
      if (nivel.isEmpty) {
        nivel = nivelDaTabela(
          codigo: r['codigo']?.toString(),
          descricao: r['descricao']?.toString(),
        );
      }
      if (!ordemNiveis.contains(nivel)) continue;

      byNivel[nivel] = TabPrecoOpcao(
        nivel: nivel,
        priceTableId: tableId,
        codigo: (r['codigo'] ?? codigoNivel(nivel)).toString(),
        descricao: (r['descricao'] ?? labelNivel(nivel)).toString(),
        preco: precoDoNivel(produto, nivel),
      );
    }

    final ordered = <TabPrecoOpcao>[];
    for (final n in ordemNiveis) {
      final op = byNivel[n];
      if (op != null) ordered.add(op);
    }
    return ordered;
  }

  /// Resolve preço. Com Tab. Preço exige [nivel] (ou usa o da [listaPreco] se
  /// estiver entre os habilitados — preferir seleção explícita na UI).
  static Future<double> resolve(
    Map<String, dynamic> produto, {
    Map<String, dynamic>? listaPreco,
    double quantidade = 1,
    LocalDb? db,
    String? nivel,
  }) async {
    if (!usaTabPreco(produto)) {
      return resolveSync(
        produto,
        listaPreco: listaPreco,
        quantidade: quantidade,
      );
    }

    if (nivel != null && nivel.isNotEmpty) {
      return precoDoNivel(produto, nivel);
    }

    final opcoes = await opcoesHabilitadas(
      produto,
      db: db,
      quantidade: quantidade,
    );
    if (opcoes.isEmpty) {
      return precoDoNivel(produto, 'varejo');
    }

    final nivelLista = nivelDaTabela(
      codigo: listaPreco?['codigo']?.toString(),
      descricao: listaPreco?['descricao']?.toString(),
    );
    for (final op in opcoes) {
      if (op.nivel == nivelLista) return op.preco;
    }
    return opcoes.first.preco;
  }
}
