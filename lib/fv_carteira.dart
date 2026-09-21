/// Filtro de carteira do vendedor logado (Força de Vendas).
///
/// Com [verTodos] (flag da empresa no ERP), o app lista todos os clientes
/// baixados no sync — sem filtrar por `vendedor_fv_id`.
class FvCarteira {
  FvCarteira._();

  /// SQL: coluna vendedor_fv_id = ? (ou 1=1 se verTodos; 1=0 se sem vendedor).
  static String sqlEquals(
    int? vendedorId, {
    String column = 'vendedor_fv_id',
    bool verTodos = false,
  }) {
    if (verTodos) return '1=1';
    if (vendedorId == null) return '1=0';
    return '$column = ?';
  }

  static List<Object?> args(int? vendedorId, {bool verTodos = false}) =>
      (!verTodos && vendedorId != null) ? [vendedorId] : const [];
}
