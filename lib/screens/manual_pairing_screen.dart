import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../config.dart';

/// Pareamento manual: alternativa quando a câmera não lê o QR Code.
/// O vendedor digita o endereço do servidor e o segredo (mostrados na tela
/// do ERP em "App Força de Vendas") e escolhe a empresa numa lista.
class ManualPairingScreen extends StatefulWidget {
  const ManualPairingScreen({super.key});

  @override
  State<ManualPairingScreen> createState() => _ManualPairingScreenState();
}

class _ManualPairingScreenState extends State<ManualPairingScreen> {
  final _serverCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();

  List<dynamic> _empresas = [];
  int? _empresaId;
  bool _conectando = false;
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  String _normalizarUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _conectar() async {
    final url = _normalizarUrl(_serverCtrl.text);
    final secret = _secretCtrl.text.trim();
    if (url.isEmpty || secret.isEmpty) {
      setState(() => _erro = 'Preencha o endereço do servidor e o segredo.');
      return;
    }
    setState(() {
      _conectando = true;
      _erro = null;
      _empresas = [];
      _empresaId = null;
    });
    try {
      final deviceUuid = context.read<AppState>().config.deviceUuid;
      final temp = AppConfig(baseUrl: url, pairingSecret: secret, deviceUuid: deviceUuid);
      final info = await ApiClient(temp).info();
      final empresas = (info['empresas'] as List<dynamic>? ?? []);
      if (empresas.isEmpty) {
        setState(() {
          _erro = 'Conectado, mas nenhuma empresa ativa foi encontrada.';
          _conectando = false;
        });
        return;
      }
      setState(() {
        _empresas = empresas;
        _empresaId = empresas.first['id'] as int?;
        _conectando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Não foi possível conectar: $e';
        _conectando = false;
      });
    }
  }

  Future<void> _concluir() async {
    if (_empresaId == null) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final empresa = _empresas.firstWhere(
        (e) => e['id'] == _empresaId,
        orElse: () => null,
      );
      final nome = empresa != null ? (empresa['nome'] ?? '').toString() : '';
      await context.read<AppState>().pairManual(
            url: _normalizarUrl(_serverCtrl.text),
            secret: _secretCtrl.text.trim(),
            empresaId: _empresaId!,
            empresaNome: nome,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _erro = '$e';
        _salvando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conectado = _empresas.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar manualmente')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'No ERP, abra "App Força de Vendas". O endereço do servidor e o '
              'segredo aparecem escritos ali, abaixo do QR Code.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _serverCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enabled: !conectado,
              decoration: const InputDecoration(
                labelText: 'Endereço do servidor',
                hintText: 'http://192.168.0.10:8765',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _secretCtrl,
              autocorrect: false,
              enabled: !conectado,
              decoration: const InputDecoration(
                labelText: 'Segredo de pareamento',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            if (!conectado)
              FilledButton.icon(
                onPressed: _conectando ? null : _conectar,
                icon: _conectando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Conectar'),
              ),
            if (conectado) ...[
              DropdownButtonFormField<int>(
                initialValue: _empresaId,
                decoration: const InputDecoration(labelText: 'Empresa', border: OutlineInputBorder()),
                items: _empresas
                    .map((e) => DropdownMenuItem<int>(
                          value: e['id'] as int?,
                          child: Text((e['nome'] ?? '').toString()),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _empresaId = v),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _salvando ? null : _concluir,
                child: _salvando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Concluir pareamento'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _salvando
                    ? null
                    : () => setState(() {
                          _empresas = [];
                          _empresaId = null;
                        }),
                child: const Text('Editar endereço/segredo'),
              ),
            ],
            if (_erro != null) ...[
              const SizedBox(height: 16),
              Text(_erro!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
