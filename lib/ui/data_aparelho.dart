/// Helpers de data do aparelho (só o dia, sem hora).
class DataAparelho {
  DataAparelho._();

  /// Data local de hoje no formato yyyy-MM-dd.
  static String hojeLocal() {
    final n = DateTime.now();
    return _ymd(n.year, n.month, n.day);
  }

  /// Extrai só a data (yyyy-MM-dd) de um ISO / datetime.
  static String? soData(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final t = raw.trim();
    if (t.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) {
      return t.substring(0, 10);
    }
    final dt = DateTime.tryParse(t);
    if (dt == null) return null;
    final local = dt.toLocal();
    return _ymd(local.year, local.month, local.day);
  }

  /// Exibe yyyy-MM-dd como dd/MM/yyyy.
  static String formatBr(String ymd) {
    final p = ymd.split('-');
    if (p.length != 3) return ymd;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  static String _ymd(int y, int m, int d) =>
      '${y.toString().padLeft(4, '0')}-'
      '${m.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}';

  static DateTime? parseYmd(String ymd) {
    final p = ymd.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}
