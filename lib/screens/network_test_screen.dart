import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../log/app_log.dart';
import '../net/discovery.dart';
import 'log_screen.dart';

/// Diagnóstico de rede: mostra o IP do aparelho, o tipo de conexão, testa
/// um endereço (ping detalhado) e faz a varredura da rede.
class NetworkTestScreen extends StatefulWidget {
  const NetworkTestScreen({super.key});

  @override
  State<NetworkTestScreen> createState() => _NetworkTestScreenState();
}

class _NetworkTestScreenState extends State<NetworkTestScreen> {
  final _ipCtrl = TextEditingController();

  List<String> _ips = [];
  String _conexao = '—';
  bool _carregandoInfo = true;

  bool _testando = false;
  String? _resultadoTeste;
  bool _testeOk = false;

  bool _varrendo = false;
  String? _resultadoVarredura;
  String? _encontrado;

  @override
  void initState() {
    super.initState();
    final base = context.read<AppState>().config.baseUrl;
    if (base.isNotEmpty) {
      final host = Uri.tryParse(base)?.host ?? '';
      if (host.isNotEmpty) _ipCtrl.text = host;
    }
    _carregarInfo();
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarInfo() async {
    setState(() => _carregandoInfo = true);
    final ips = <String>[];
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          ips.add('${iface.name}: ${addr.address}');
        }
      }
    } catch (_) {}

    var conexao = 'desconhecida';
    try {
      final result = await Connectivity().checkConnectivity();
      final tipos = result
          .map((r) => switch (r) {
                ConnectivityResult.wifi => 'Wi-Fi',
                ConnectivityResult.mobile => 'Dados móveis',
                ConnectivityResult.ethernet => 'Cabo',
                ConnectivityResult.vpn => 'VPN',
                ConnectivityResult.none => 'Sem rede',
                _ => 'outra',
              })
          .toList();
      conexao = tipos.isEmpty ? 'desconhecida' : tipos.join(', ');
    } catch (_) {}

    if (mounted) {
      setState(() {
        _ips = ips;
        _conexao = conexao;
        _carregandoInfo = false;
      });
    }
  }

  String _normalizar(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    s = s.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(s);
    if (uri != null && !uri.hasPort) s = '${uri.scheme}://${uri.host}:8765';
    return s;
  }

  Future<void> _testarEndereco() async {
    final url = _normalizar(_ipCtrl.text);
    if (url.isEmpty) {
      setState(() => _resultadoTeste = 'Informe o IP do servidor.');
      return;
    }
    setState(() {
      _testando = true;
      _resultadoTeste = null;
    });
    final r = await ApiClient.pingDetailed(url, timeout: const Duration(seconds: 5));
    AppLog.instance.info('rede', 'Teste $url → ${r.ok ? 'OK' : 'FALHOU'}: ${r.message} (${r.ms} ms)');
    if (mounted) {
      setState(() {
        _testando = false;
        _testeOk = r.ok;
        _resultadoTeste = r.ok
            ? 'Conectou em $url\nLatência: ${r.ms} ms\nHora do servidor: ${r.serverTime ?? '-'}'
            : 'Não conectou em $url\nMotivo: ${r.message}\nTempo: ${r.ms} ms';
      });
    }
  }

  Future<void> _varrer() async {
    setState(() {
      _varrendo = true;
      _resultadoVarredura = 'Procurando na rede...';
      _encontrado = null;
    });
    final found = await ServerDiscovery.find(
      onProgress: (done, total) {
        if (mounted) setState(() => _resultadoVarredura = 'Procurando... ($done/$total)');
      },
    );
    AppLog.instance.info('rede', found == null ? 'Varredura: nenhum servidor nas portas 8765/8000' : 'Varredura encontrou: $found');
    if (mounted) {
      setState(() {
        _varrendo = false;
        _encontrado = found;
        _resultadoVarredura = found == null
            ? 'Nenhum servidor respondeu nas portas 8765 ou 8000. Verifique se o ERP está ligado, publicado na rede (host 0.0.0.0) e na mesma rede do celular.'
            : 'Servidor encontrado: $found';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Testar rede'),
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Meu aparelho', style: TextStyle(fontWeight: FontWeight.bold))),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: _carregandoInfo ? null : _carregarInfo,
                      ),
                    ],
                  ),
                  Text('Conexão: $_conexao'),
                  const SizedBox(height: 4),
                  if (_carregandoInfo)
                    const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
                  else if (_ips.isEmpty)
                    const Text('Sem IP detectado (aparelho sem rede?)', style: TextStyle(color: Colors.red))
                  else
                    ..._ips.map((ip) => Text(ip, style: const TextStyle(fontFamily: 'monospace'))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Testar um endereço', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _ipCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'IP do servidor',
              hintText: '192.168.0.10  (porta 8765 é o padrão)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lan),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _testando ? null : _testarEndereco,
            icon: _testando
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.network_check),
            label: const Text('Testar conexão'),
          ),
          if (_resultadoTeste != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testeOk ? Colors.green : Colors.red).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _testeOk ? Colors.green : Colors.red),
              ),
              child: Text(_resultadoTeste!),
            ),
          ],
          const SizedBox(height: 24),
          const Text('Procurar na rede', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _varrendo ? null : _varrer,
            icon: _varrendo
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_find),
            label: const Text('Varrer a rede agora'),
          ),
          if (_resultadoVarredura != null) ...[
            const SizedBox(height: 12),
            Text(_resultadoVarredura!),
            if (_encontrado != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  await context.read<AppState>().connectFound(_encontrado!);
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.check),
                label: Text('Usar $_encontrado'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
