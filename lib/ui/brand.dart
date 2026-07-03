import 'package:flutter/material.dart';

/// Cores e helpers de identidade visual do app (padrão Unitecnologia).
class Brand {
  Brand._();

  static const Color blue = Color(0xFF1565C0);
  static const Color green = Color(0xFF2E7D32);
  static const Color bg = Color(0xFFF1F4F8);

  /// Estoque — cores fortes para leitura rápida no app.
  static const Color estoqueAtual = Color(0xFF0F2847);
  static const Color estoqueReservado = Color(0xFFFFC107);
  static const Color estoqueReservadoText = Color(0xFF422006);
  static const Color estoqueDisponivel = Color(0xFF16A34A);

  /// Preços no detalhe do produto.
  static const Color precoVista = Color(0xFF16A34A);
  static const Color precoPrazo = Color(0xFF1565C0);
  static const Color precoAtacado = Color(0xFFEA580C);
}
