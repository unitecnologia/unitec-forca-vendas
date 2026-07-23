import 'package:flutter/material.dart';

import 'cliente_credito_check.dart';

/// Diálogo de pendência financeira — mesmo padrão compacto/amarelo do ERP.
class CreditoAlertDialog extends StatelessWidget {
  const CreditoAlertDialog({
    super.key,
    required this.alerta,
    required this.onConfirm,
    required this.onCancel,
  });

  final ClienteCreditoAlerta alerta;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  static const _amber = Color(0xFFCA8A04);
  static const _amberBorder = Color(0xFFEAB308);
  static const _amberTitle = Color(0xFFA16207);
  static const _amberBg = Color(0xFFFFFBEB);
  static const _amberSoft = Color(0xFFFEF9C3);

  static Future<bool> show(
    BuildContext context, {
    required ClienteCreditoAlerta alerta,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x2E0F3460),
      builder: (ctx) => CreditoAlertDialog(
        alerta: alerta,
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final motivos = alerta.motivos;
    final situacao = alerta.situacao;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          decoration: BoxDecoration(
            color: _amberBg,
            border: Border.all(color: _amberBorder, width: 2),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: _amber.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: _amberBorder,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '!',
                      style: TextStyle(
                        color: Color(0xFF422006),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alerta.titulo,
                      style: const TextStyle(
                        color: _amberTitle,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onCancel,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _amberSoft,
                        border: Border.all(color: const Color(0xFFFACC15)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '×',
                        style: TextStyle(
                          color: Color(0xFF854D0E),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (motivos.isNotEmpty) ...[
                const SizedBox(height: 8),
                _block(
                  label: 'Motivos',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final m in motivos)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '• $m',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              _block(
                label: 'Situação',
                child: Column(
                  children: [
                    for (final row in situacao)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.label,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            Text(
                              row.valor,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF854D0E),
                        side: const BorderSide(color: _amberBorder),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: const Text(
                        'Não',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: _amber,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: const Text(
                        'Enviar',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                ClienteCreditoAlerta.hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF78716C),
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _block({required String label, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFFDE047)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: _amberTitle,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
