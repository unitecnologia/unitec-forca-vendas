import 'package:flutter/material.dart';

/// Cores e helpers de identidade visual do app (padrão Unitecnologia).
class Brand {
  Brand._();

  static const Color blue = Color(0xFF1565C0);
  static const Color green = Color(0xFF2E7D32);

  /// Canvas do app (cinza leve — destaca cards brancos).
  static const Color bg = Color(0xFFE4E9EF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF16324A);

  /// Rótulos dos cards do menu home (+2 mm sobre 13,5 sp).
  static const double homeMenuLabelSize = 13.5 + (2 * 160 / 25.4);

  static List<BoxShadow> get cardShadow => const [
        BoxShadow(
          color: Color(0x1A0F172A),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ];

  static BoxDecoration surfaceCard({double radius = 12}) => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: cardShadow,
      );

  /// Estoque — cores fortes para leitura rápida no app.
  static const Color estoqueAtual = Color(0xFF0F2847);
  static const Color estoqueReservado = Color(0xFFFFC107);
  static const Color estoqueReservadoText = Color(0xFF422006);
  static const Color estoqueDisponivel = Color(0xFF16A34A);
  static const Color produtoCodigo = Color(0xFF475569);

  /// Preços no detalhe do produto.
  static const Color precoVista = Color(0xFF16A34A);
  static const Color precoPrazo = Color(0xFF1565C0);
  static const Color precoAtacado = Color(0xFFEA580C);
}
