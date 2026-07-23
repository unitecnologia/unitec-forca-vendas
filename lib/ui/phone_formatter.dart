import 'package:flutter/services.dart';

/// Máscara de telefone BR: `(47)99644-9859` (11) ou `(47)9964-4985` (10).
class BrPhoneInputFormatter extends TextInputFormatter {
  const BrPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = onlyDigits(newValue.text);
    if (digits.startsWith('55') && digits.length > 11) {
      digits = digits.substring(2);
    }
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    final formatted = format(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Formata dígitos (DDD + número) no padrão visual do app.
  static String format(String raw) {
    var digits = onlyDigits(raw);
    if (digits.startsWith('55') && digits.length > 11) {
      digits = digits.substring(2);
    }
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }
    if (digits.isEmpty) return '';

    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 0) b.write('(');
      if (i == 2) b.write(')');
      // Celular 11: (XX)XXXXX-XXXX | Fixo 10: (XX)XXXX-XXXX
      if (digits.length >= 11 && i == 7) b.write('-');
      if (digits.length < 11 && i == 6) b.write('-');
      b.write(digits[i]);
    }
    return b.toString();
  }

  static String onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  /// Aceita DDD + número (10 ou 11 dígitos), com ou sem 55.
  static bool isValid(String value) {
    var digits = onlyDigits(value);
    if (digits.startsWith('55') && digits.length >= 12) {
      digits = digits.substring(2);
    }
    return digits.length == 10 || digits.length == 11;
  }
}
