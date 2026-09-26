/// Formato básico de e-mail. Vazio é válido (o campo pode ser limpo).
bool emailBasicoValido(String value) {
  final v = value.trim();
  if (v.isEmpty) return true;
  if (v.length > 255) return false;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v);
}

/// Mensagem para a ficha, ou null quando o valor pode ser salvo.
String? emailBasicoMensagem(String value) {
  if (emailBasicoValido(value)) return null;
  return 'Informe um e-mail válido ou deixe em branco.';
}
