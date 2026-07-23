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

/// Valor monetário sem o prefixo `R$` (ex.: `1.234,56`).
String brMoneyShort(num? value) {
  final full = brMoney(value);
  return full.startsWith('R\$ ') ? full.substring(3) : full.replaceFirst('R\$', '').trim();
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

/// Formata quantidade de estoque (0 decimais se inteiro).
String fmtEstoque(num? value) {
  final v = (value ?? 0).toDouble();
  return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
}

double estoqueAtual(Map<String, dynamic> p) =>
    (p['estoque'] as num?)?.toDouble() ?? 0;

double estoqueReservado(Map<String, dynamic> p) =>
    (p['estoque_reservado'] as num?)?.toDouble() ?? 0;

double estoqueDisponivel(Map<String, dynamic> p) {
  if (p.containsKey('estoque_disponivel') && p['estoque_disponivel'] != null) {
    return (p['estoque_disponivel'] as num).toDouble();
  }
  return estoqueAtual(p) - estoqueReservado(p);
}

/// Resumo compacto: Atual | Reserv. | Disp. (mesma ordem do ERP web).
String estoqueLinhaCompacta(Map<String, dynamic> p, {String? unidade}) {
  final u = (unidade ?? (p['unidade'] ?? '').toString()).trim();
  final suffix = u.isNotEmpty ? ' $u' : '';
  return 'Atual: ${fmtEstoque(estoqueAtual(p))} | '
      'Reserv.: ${fmtEstoque(estoqueReservado(p))} | '
      'Disp.: ${fmtEstoque(estoqueDisponivel(p))}$suffix';
}
