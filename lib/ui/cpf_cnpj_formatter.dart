import 'package:flutter/services.dart';

/// Máscara dinâmica CPF (11) ou CNPJ (14).
class CpfCnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final limited = digits.length > 14 ? digits.substring(0, 14) : digits;
    final formatted = limited.length <= 11 ? _formatCpf(limited) : _formatCnpj(limited);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _formatCpf(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 3 || i == 6) b.write('.');
      if (i == 9) b.write('-');
      b.write(digits[i]);
    }
    return b.toString();
  }

  static String _formatCnpj(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5) b.write('.');
      if (i == 8) b.write('/');
      if (i == 12) b.write('-');
      b.write(digits[i]);
    }
    return b.toString();
  }

  static String onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');
}
