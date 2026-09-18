import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../ui/brand.dart';
import '../ui/data_aparelho.dart';

/// Bloqueia o uso do app quando a data do aparelho mudou em relação à última aceita.
class DataAparelhoBloqueadaScreen extends StatelessWidget {
  const DataAparelhoBloqueadaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hoje = DataAparelho.formatBr(DataAparelho.hojeLocal());
    final ultima = state.config.lastKnownDate.isEmpty
        ? '—'
        : DataAparelho.formatBr(state.config.lastKnownDate);

    return Scaffold(
      backgroundColor: Brand.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: Brand.surfaceCard(radius: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Icon(
                        Icons.event_busy_rounded,
                        color: Color(0xFFDC2626),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Data do aparelho inválida',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Brand.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.dateBlockMessage.isEmpty
                          ? 'A data do aparelho mudou. Ajuste a data nas configurações do aparelho para continuar.'
                          : state.dateBlockMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _linha('Data do aparelho', hoje),
                    _linha('Última data aceita no app', ultima),
                    const SizedBox(height: 8),
                    const Text(
                      'Só a data é verificada (hora não importa). Sem uso de internet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => state.verificarDataAparelho(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Verificar novamente'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _linha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Text(
            valor,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Brand.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
