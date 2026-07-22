/// Busca de produtos com relevância (começa com o termo primeiro).
/// Também ignora espaços: "REDBULL" acha "RED BULL".
class ProdutoBusca {
  ProdutoBusca._();

  static String compact(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Retorna (sqlWhereComplemento vazio — montamos fora), args e orderBy.
  static ({String whereExtra, List<Object?> args, String orderBy}) filtro(
    String termoBruto, {
    String? grupo,
  }) {
    final termo = termoBruto.trim().toUpperCase();
    final like = '%$termo%';
    final compacto = compact(termo);
    final likeCompact = '%$compacto%';

    final where = StringBuffer(
      'ativo = 1 AND mostrar_no_app = 1 AND ('
      'descricao LIKE ? OR codigo LIKE ? OR codigo_barras LIKE ? OR marca LIKE ? '
      "OR REPLACE(REPLACE(REPLACE(UPPER(IFNULL(descricao,'')), ' ', ''), '-', ''), '.', '') LIKE ?"
      ')',
    );
    final args = <Object?>[like, like, like, like, likeCompact];

    if (grupo != null && grupo.isNotEmpty) {
      where.write(' AND grupo = ?');
      args.add(grupo);
    }

    // Relevância: começa com o termo → palavra → compacto → demais.
    final orderBy = '''
CASE
  WHEN UPPER(IFNULL(descricao,'')) LIKE ? THEN 0
  WHEN UPPER(IFNULL(descricao,'')) LIKE ? THEN 1
  WHEN REPLACE(REPLACE(REPLACE(UPPER(IFNULL(descricao,'')), ' ', ''), '-', ''), '.', '') LIKE ? THEN 2
  ELSE 3
END,
descricao''';

    args.addAll(['$termo%', '% $termo%', likeCompact]);

    return (whereExtra: where.toString(), args: args, orderBy: orderBy);
  }
}
