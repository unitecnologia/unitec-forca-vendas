import 'package:flutter/material.dart';

import 'brand.dart';
import 'format.dart';

/// Chips de estoque: Atual (azul escuro), Reserv. (amarelo), Disp. (verde).
class EstoqueChips extends StatelessWidget {
  const EstoqueChips({
    super.key,
    required this.produto,
    this.mostrarUnidadeNoDisponivel = true,
    this.compact = false,
  });

  final Map<String, dynamic> produto;
  final bool mostrarUnidadeNoDisponivel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final unidade = (produto['unidade'] ?? '').toString().trim();
    final dispValor = fmtEstoque(estoqueDisponivel(produto));
    final dispTexto = mostrarUnidadeNoDisponivel && unidade.isNotEmpty
        ? '$dispValor $unidade'
        : dispValor;

    return Wrap(
      spacing: compact ? 4 : 6,
      runSpacing: 4,
      children: [
        _chip(
          'Atual',
          fmtEstoque(estoqueAtual(produto)),
          Brand.estoqueAtual,
          Colors.white,
        ),
        _chip(
          'Reserv.',
          fmtEstoque(estoqueReservado(produto)),
          Brand.estoqueReservado,
          Brand.estoqueReservadoText,
        ),
        _chip(
          'Disp.',
          dispTexto,
          Brand.estoqueDisponivel,
          Colors.white,
        ),
      ],
    );
  }

  Widget _chip(String label, String valor, Color bg, Color fg) {
    final padH = compact ? 6.0 : 8.0;
    final padV = compact ? 3.0 : 4.0;
    final labelSize = compact ? 9.0 : 10.0;
    final valorSize = compact ? 11.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.28),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: labelSize, color: fg.withValues(alpha: 0.92)),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: valor,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: valorSize,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linha de estoque colorida para modais (três colunas alinhadas).
class EstoquePainel extends StatelessWidget {
  const EstoquePainel({super.key, required this.produto});

  final Map<String, dynamic> produto;

  @override
  Widget build(BuildContext context) {
    final unidade = (produto['unidade'] ?? '').toString().trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estoque',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _coluna(
                  'Atual',
                  fmtEstoque(estoqueAtual(produto)),
                  unidade,
                  Brand.estoqueAtual,
                  Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _coluna(
                  'Reservado',
                  fmtEstoque(estoqueReservado(produto)),
                  unidade,
                  Brand.estoqueReservado,
                  Brand.estoqueReservadoText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _coluna(
                  'Disponível',
                  fmtEstoque(estoqueDisponivel(produto)),
                  unidade,
                  Brand.estoqueDisponivel,
                  Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _coluna(String titulo, String valor, String unidade, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.22),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
            textAlign: TextAlign.center,
          ),
          if (unidade.isNotEmpty)
            Text(
              unidade,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: fg.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }
}
