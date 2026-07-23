import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'log_screen.dart';
import 'network_test_screen.dart';

/// Tela de espera: o aparelho já se registrou no ERP e aguarda o
/// administrador autorizá-lo. Mostra o código de pareamento e fica
/// consultando o status periodicamente.
class WaitingApprovalScreen extends StatefulWidget {
  const WaitingApprovalScreen({super.key});

  @override
  State<WaitingApprovalScreen> createState() => _WaitingApprovalScreenState();
}

class _WaitingApprovalScreenState extends State<WaitingApprovalScreen> {
  Timer? _timer;
  bool _registrando = true;
  bool _editandoNome = false;
  String? _erro;
  String _status = 'pendente';
  final _nomeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _registrar();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _verificar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    setState(() {
      _registrando = true;
      _erro = null;
    });
    try {
      final state = context.read<AppState>();
      // Se o aparelho já estava autorizado, só confirma no servidor.
      if (state.config.deviceApproved && state.config.deviceUuid.isNotEmpty) {
        try {
          final status = await state.refreshApproval();
          if (state.isApproved) {
            _nomeCtrl.text = state.config.deviceName;
            if (mounted) setState(() => _status = status);
            return;
          }
        } catch (e) {
          // Servidor offline: mantém autorização local e segue para o login.
          if (state.config.deviceApproved) {
            _nomeCtrl.text = state.config.deviceName;
            if (mounted) {
              setState(() {
                _status = 'offline';
                _erro = null;
              });
            }
            return;
          }
          rethrow;
        }
      }
      await state.registerDevice();
      _nomeCtrl.text = state.config.deviceName;
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível registrar o aparelho: $e');
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  Future<void> _verificar() async {
    try {
      final status = await context.read<AppState>().refreshApproval();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // silencioso: tenta de novo no próximo ciclo
    }
  }

  Future<void> _salvarNome() async {
    final state = context.read<AppState>();
    await state.setDeviceName(_nomeCtrl.text);
    await state.registerDevice();
    if (mounted) setState(() => _editandoNome = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final code = state.config.pairingCode;
    final revogado = _status == 'revogado';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aguardando autorização'),
        actions: [
          IconButton(
            tooltip: 'Testar rede',
            icon: const Icon(Icons.troubleshoot),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NetworkTestScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Log',
            icon: const Icon(Icons.article_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Trocar servidor',
            icon: const Icon(Icons.lan_outlined),
            onPressed: () => context.read<AppState>().disconnect(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Icon(
              revogado ? Icons.gpp_bad : Icons.hourglass_top,
              size: 64,
              color: revogado ? Colors.red : const Color(0xFF1565C0),
            ),
            const SizedBox(height: 16),
            Text(
              revogado
                  ? 'Este aparelho foi revogado. Peça ao administrador para autorizar novamente.'
                  : 'Aguardando o administrador autorizar este aparelho no ERP.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 28),
            if (_registrando)
              const Center(child: CircularProgressIndicator())
            else ...[
              const Text('Código de autorização', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 6),
              Text(
                code.isEmpty ? '------' : code,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 6, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Nome do aparelho', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _editandoNome = !_editandoNome),
                            icon: Icon(_editandoNome ? Icons.close : Icons.edit, size: 18),
                            label: Text(_editandoNome ? 'Cancelar' : 'Editar'),
                          ),
                        ],
                      ),
                      if (_editandoNome) ...[
                        TextField(
                          controller: _nomeCtrl,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(onPressed: _salvarNome, child: const Text('Salvar nome')),
                      ] else
                        Text(state.config.deviceName, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No ERP, abra "Força de Vendas → Aparelhos", confira o código e pressione F2 para autorizar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              if (revogado)
                FilledButton.icon(
                  onPressed: _registrar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Solicitar novamente'),
                )
              else
                OutlinedButton.icon(
                  onPressed: _verificar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Verificar agora'),
                ),
            ],
            if (_erro != null) ...[
              const SizedBox(height: 20),
              Text(_erro!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
