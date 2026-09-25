/// Normalização e validação de CPF/CNPJ (somente dígitos + DV).
///
/// Alinhado ao ERP (`DocumentoBrasileiroValidator`): máscara irrelevante.
class DocumentoBrasileiro {
  DocumentoBrasileiro._();

  static String digits(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\D'), '');

  /// Dígitos para coluna indexada; vazio → null (vários NULL permitidos no UNIQUE).
  static String? digitsOrNull(String? value) {
    final d = digits(value);
    return d.isEmpty ? null : d;
  }

  static bool isValidCpf(String? value) {
    final d = digits(value);
    if (d.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false;

    for (var length = 9; length < 11; length++) {
      var sum = 0;
      for (var i = 0; i < length; i++) {
        sum += int.parse(d[i]) * ((length + 1) - i);
      }
      final check = ((10 * sum) % 11) % 10;
      if (int.parse(d[length]) != check) return false;
    }
    return true;
  }

  static bool isValidCnpj(String? value) {
    final d = digits(value);
    if (d.length != 14 || RegExp(r'^(\d)\1{13}$').hasMatch(d)) return false;

    const w1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const w2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

    for (var round = 0; round < 2; round++) {
      final weights = round == 0 ? w1 : w2;
      final limit = round == 0 ? 12 : 13;
      var sum = 0;
      for (var i = 0; i < limit; i++) {
        sum += int.parse(d[i]) * weights[i];
      }
      final rem = sum % 11;
      final check = rem < 2 ? 0 : 11 - rem;
      if (int.parse(d[12 + round]) != check) return false;
    }
    return true;
  }

  /// null = ok (vazio ou documento válido). Mensagens curtas para o form.
  static String? mensagemFormato(String? value) {
    final d = digits(value);
    if (d.isEmpty) return null;
    if (d.length == 11) {
      return isValidCpf(d) ? null : 'CPF inválido.';
    }
    if (d.length == 14) {
      return isValidCnpj(d) ? null : 'CNPJ inválido.';
    }
    return d.length < 14 ? 'CPF inválido.' : 'CNPJ inválido.';
  }

  static String mensagemDuplicado(String digits) {
    if (digits.length == 14) {
      return 'Já existe um cliente cadastrado com este CNPJ.';
    }
    return 'Já existe um cliente cadastrado com este CPF.';
  }

  static String mensagemDuplicadoComNome(String digits, String? nome) {
    final base = mensagemDuplicado(digits);
    final n = (nome ?? '').trim();
    if (n.isEmpty) return base;
    return '$base ($n)';
  }
}
