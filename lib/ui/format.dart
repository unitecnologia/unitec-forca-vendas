/// Formatações simples no padrão brasileiro (sem depender de locale data).
String brMoney(num? value) {
  final v = (value ?? 0).toDouble();
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final dec = parts[1];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}R\$ ${buf.toString()},$dec';
}

/// Converte 'YYYY-MM-DD' (ou ISO) para 'dd/MM/yyyy'. Retorna '—' se vazio.
String brDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}
