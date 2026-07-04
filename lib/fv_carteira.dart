/// Filtro de carteira do vendedor logado (Força de Vendas).
class FvCarteira {
  FvCarteira._();

  /// SQL: coluna vendedor_fv_id = ? (retorna 1=0 se sem vendedor).
  static String sqlEquals(int? vendedorId, {String column = 'vendedor_fv_id'}) {
    if (vendedorId == null) return '1=0';
    return '$column = ?';
  }

  static List<Object?> args(int? vendedorId) =>
      vendedorId != null ? [vendedorId] : const [];
}
