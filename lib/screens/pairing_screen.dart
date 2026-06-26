import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'manual_pairing_screen.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  bool _busy = false;
  String? _erro;
  int _scannerAttempt = 0;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    setState(() {
      _busy = true;
      _erro = null;
    });
    try {
      await context.read<AppState>().pairFromQr(raw);
      // O _Root reconstrói e leva para o login.
    } catch (e) {
      setState(() {
        _erro = 'QR inválido: $e';
        _busy = false;
      });
    }
  }

  void _abrirManual() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManualPairingScreen()),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    final detalhe = error.errorDetails?.message ?? error.errorCode.name;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, color: Colors.white70, size: 56),
          const SizedBox(height: 12),
          const Text(
            'Não foi possível abrir a câmera.',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            detalhe,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _scannerAttempt++),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
              FilledButton.icon(
                onPressed: _abrirManual,
                icon: const Icon(Icons.keyboard),
                label: const Text('Digitar manualmente'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parear com o servidor'),
        actions: [
          IconButton(
            tooltip: 'Digitar manualmente',
            icon: const Icon(Icons.keyboard),
            onPressed: _abrirManual,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  key: ValueKey(_scannerAttempt),
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _buildCameraError(error),
                ),
                IgnorePointer(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                if (_busy) const CircularProgressIndicator(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'No ERP, abra "App Força de Vendas" e aponte a câmera para o QR Code.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _abrirManual,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Não consegue ler? Digitar manualmente'),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 8),
                  Text(_erro!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
