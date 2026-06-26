import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../net/discovery.dart';
import 'log_screen.dart';
import 'network_test_screen.dart';

/// Primeira tela: conecta ao servidor do ERP na rede local.
/// Busca automática + opção de digitar o IP/porta manualmente.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _ipCtrl = TextEditingController();
  bool _buscando = false;
  bool _conectando = false;
  String? _erro;
  String? _progresso;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().ensureDeviceIdentity();
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarNaRede() async {
    setState(() {
      _buscando = true;
      _erro = null;
      _progresso = 'Procurando na rede...';
    });
    try {
      final found = await ServerDiscovery.find(
        onProgress: (done, total) {
          if (mounted) setState(() => _progresso = 'Procurando na rede... ($done/$total)');
        },
      );
      if (!mounted) return;
      if (found == null) {
        setState(() {
          _erro = 'Servidor não encontrado na rede. Digite o IP manualmente.';
          _buscando = false;
          _progresso = null;
        });
        return;
      }
      await context.read<AppState>().connectFound(found);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Falha na busca: $e';
          _buscando = false;
          _progresso = null;
        });
      }
    }
  }

  Future<void> _conectarManual() async {
    final url = _ipCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _erro = 'Informe o IP do servidor (ex.: 192.168.0.10).');
      return;
    }
    setState(() {
      _conectando = true;
      _erro = null;
    });
    try {
      await context.read<AppState>().connectManual(url);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = '$e';
          _conectando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ocupado = _buscando || _conectando;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar ao servidor'),
        actions: [
          IconButton(
            tooltip: 'Ver log',
            icon: const Icon(Icons.article_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Icon(Icons.dns, size: 64, color: Color(0xFF1565C0)),
            const SizedBox(height: 16),
            const Text(
              'Conecte o aparelho ao servidor do ERP que está na rede da loja.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: ocupado ? null : _buscarNaRede,
              icon: _buscando
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.wifi_find),
              label: Text(_buscando ? 'Procurando...' : 'Procurar servidor na rede'),
            ),
            if (_progresso != null) ...[
              const SizedBox(height: 8),
              Text(_progresso!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            ],
            const SizedBox(height: 24),
            const Row(children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('ou')),
              Expanded(child: Divider()),
            ]),
            const SizedBox(height: 24),
            TextField(
              controller: _ipCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enabled: !ocupado,
              decoration: const InputDecoration(
                labelText: 'IP do servidor',
                hintText: '192.168.0.10  (porta 8765 é o padrão)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lan),
              ),
              onSubmitted: (_) => ocupado ? null : _conectarManual(),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: ocupado ? null : _conectarManual,
              icon: _conectando
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Text('Conectar por IP'),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 20),
              Text(_erro!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: ocupado
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NetworkTestScreen()),
                      ),
              icon: const Icon(Icons.troubleshoot),
              label: const Text('Testar rede / diagnóstico'),
            ),
          ],
        ),
      ),
    );
  }
}
