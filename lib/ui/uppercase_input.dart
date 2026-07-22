import 'package:flutter/services.dart';

/// Força texto em CAIXA ALTA (padrão ERP / Força de Vendas).
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    return TextEditingValue(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

const upperCaseInput = UpperCaseTextFormatter();

/// Junta formatters existentes com caixa alta.
List<TextInputFormatter> withUpperCase([List<TextInputFormatter>? extra]) {
  return <TextInputFormatter>[
    if (extra != null) ...extra,
    upperCaseInput,
  ];
}
