import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<dynamic> _empresas = [];
  List<dynamic> _usuarios = [];
  int? _empresaId;
  int? _userId;
  final _senha = TextEditingController();
  bool _loading = true;
  bool _carregandoUsuarios = false;
  bool _entrando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarEmpresas();
  }

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  Future<void> _carregarEmpresas() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final info = await context.read<AppState>().info();
      final empresas = (info['empresas'] as List<dynamic>? ?? []);
      setState(() {
        _empresas = empresas;
        _empresaId = empresas.isNotEmpty ? empresas.first['id'] as int? : null;
        _loading = false;
      });
      if (_empresaId != null) {
        await _carregarUsuarios();
      }
    } catch (e) {
      setState(() {
        _erro = 'Não foi possível carregar empresas: $e';
        _loading = false;
      });
    }
  }

  Future<void> _carregarUsuarios() async {
    if (_empresaId == null) return;
    setState(() {
      _carregandoUsuarios = true;
      _erro = null;
      _usuarios = [];
      _userId = null;
    });
    try {
      final users = await context.read<AppState>().usuariosDaEmpresa(_empresaId!);
      setState(() {
        _usuarios = users;
        _userId = users.isNotEmpty ? users.first['id'] as int? : null;
        _carregandoUsuarios = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Não foi possível carregar usuários: $e';
        _carregandoUsuarios = false;
      });
    }
  }

  String _empresaNome() {
    final e = _empresas.firstWhere(
      (e) => e['id'] == _empresaId,
      orElse: () => null,
    );
    return e != null ? (e['nome'] ?? '').toString() : '';
  }

  Future<void> _entrar() async {
    if (_empresaId == null || _userId == null) return;
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      await context.read<AppState>().login(
            _empresaId!,
            _userId!,
            _senha.text,
            empresaNome: _empresaNome(),
          );
    } catch (e) {
      setState(() {
        _erro = '$e';
        _entrando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrar'),
        actions: [
          IconButton(
            tooltip: 'Trocar servidor',
            icon: const Icon(Icons.lan_outlined),
            onPressed: () => context.read<AppState>().disconnect(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const Icon(Icons.point_of_sale, size: 64, color: Color(0xFF1565C0)),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<int>(
                    initialValue: _empresaId,
                    decoration: const InputDecoration(labelText: 'Empresa', border: OutlineInputBorder()),
                    items: _empresas
                        .map((e) => DropdownMenuItem<int>(
                              value: e['id'] as int?,
                              child: Text((e['nome'] ?? '').toString()),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _empresaId = v);
                      _carregarUsuarios();
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _userId,
                    decoration: InputDecoration(
                      labelText: 'Usuário',
                      border: const OutlineInputBorder(),
                      suffixIcon: _carregandoUsuarios
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                    items: _usuarios
                        .map((u) => DropdownMenuItem<int>(
                              value: u['id'] as int?,
                              child: Text((u['name'] ?? '').toString()),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _userId = v),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _senha,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha do app', border: OutlineInputBorder()),
                    onSubmitted: (_) => _entrar(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _entrando ? null : _entrar,
                    child: _entrando
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Entrar'),
                  ),
                  if (_erro != null) ...[
                    const SizedBox(height: 16),
                    Text(_erro!, style: const TextStyle(color: Colors.red)),
                  ],
                  const Spacer(),
                  Center(
                    child: Text(
                      '$kAppName • $kAppVersionLabel',
                      style: const TextStyle(color: Colors.black38, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
