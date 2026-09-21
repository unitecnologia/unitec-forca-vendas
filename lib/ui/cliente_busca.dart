/// Busca de clientes com relevância (começa com o termo primeiro).
class ClienteBusca {
  ClienteBusca._();

  /// [alias] ex.: `'c.'` quando a query usa `FROM customers c`.
  static ({String whereMatch, List<Object?> args, String orderBy}) filtro(
    String termoBruto, {
    String alias = '',
  }) {
    final p = alias;
    final termo = termoBruto.trim().toUpperCase();

    if (termo.isEmpty) {
      return (
        whereMatch: '1=1',
        args: <Object?>[],
        orderBy: '${p}nome_razao',
      );
    }

    final like = '%$termo%';
    final prefix = '$termo%';
    final word = '% $termo%';

    final whereMatch = '('
        'UPPER(IFNULL(${p}nome_razao,\'\')) LIKE ? OR '
        'UPPER(IFNULL(${p}apelido_fantasia,\'\')) LIKE ? OR '
        'UPPER(IFNULL(${p}codigo,\'\')) LIKE ? OR '
        'IFNULL(${p}cpf_cnpj,\'\') LIKE ?'
        ')';

    final orderBy = '''
CASE
  WHEN UPPER(IFNULL(${p}nome_razao,'')) LIKE ? THEN 0
  WHEN UPPER(IFNULL(${p}apelido_fantasia,'')) LIKE ? THEN 1
  WHEN UPPER(IFNULL(${p}nome_razao,'')) LIKE ? THEN 2
  WHEN UPPER(IFNULL(${p}apelido_fantasia,'')) LIKE ? THEN 2
  WHEN UPPER(IFNULL(${p}codigo,'')) = ? THEN 3
  WHEN UPPER(IFNULL(${p}codigo,'')) LIKE ? THEN 4
  ELSE 5
END,
${p}nome_razao''';

    final args = <Object?>[
      like,
      like,
      like,
      like,
      prefix,
      prefix,
      word,
      word,
      termo,
      prefix,
    ];

    return (whereMatch: whereMatch, args: args, orderBy: orderBy);
  }
}
