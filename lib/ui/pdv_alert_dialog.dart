import 'package:flutter/material.dart';

/// Aviso central no padrão PDV (borda vermelha, ícone !, título maiúsculo).
class PdvAlertDialog extends StatelessWidget {
  const PdvAlertDialog({
    super.key,
    required this.titulo,
    this.detalhe,
    this.hint,
    this.confirmLabel = 'OK',
    this.cancelLabel,
    this.onConfirm,
    this.onCancel,
  });

  final String titulo;
  final String? detalhe;
  final String? hint;
  final String confirmLabel;
  final String? cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  static const _red = Color(0xFFDC2626);
  static const _redTitle = Color(0xFFB91C1C);

  /// Exibe aviso com um botão (OK).
  static Future<void> showOk(
    BuildContext context, {
    required String titulo,
    String? detalhe,
    String? hint,
    String confirmLabel = 'OK',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x2E0F3460),
      builder: (ctx) => PdvAlertDialog(
        titulo: titulo,
        detalhe: detalhe,
        hint: hint,
        confirmLabel: confirmLabel,
        onConfirm: () => Navigator.pop(ctx),
      ),
    );
  }

  /// Exibe aviso com Sim / Não. Retorna `true` se liberou (Sim).
  static Future<bool> showSimNao(
    BuildContext context, {
    required String titulo,
    String? detalhe,
    String? hint,
    String confirmLabel = 'SIM, LIBERAR',
    String cancelLabel = 'NÃO',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PdvAlertDialog(
        titulo: titulo,
        detalhe: detalhe,
        hint: hint,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final doisBotoes = cancelLabel != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _red, width: 3),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _red.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: _red,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  '!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                titulo.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _redTitle,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  height: 1.2,
                ),
              ),
              if (detalhe != null && detalhe!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  detalhe!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (doisBotoes)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancel ?? () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                        child: Text(
                          cancelLabel!,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: onConfirm ?? () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                        child: Text(
                          confirmLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                )
              else
                FilledButton(
                  onPressed: onConfirm ?? () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(120, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  ),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              if (hint != null && hint!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
