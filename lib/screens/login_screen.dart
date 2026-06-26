import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<dynamic> _usuarios = [];
  int? _userId;
  final _senha = TextEditingController();
  bool _loading = true;
  bool _entrando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarUsuarios();
  }

  Future<void> _carregarUsuarios() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final users = await context.read<AppState>().usuariosDaEmpresa();
      setState(() {
        _usuarios = users;
        _userId = users.isNotEmpty ? users.first['id'] as int? : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Não foi possível carregar usuários: $e';
        _loading = false;
      });
    }
  }

  Future<void> _entrar() async {
    if (_userId == null) return;
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      await context.read<AppState>().login(_userId!, _senha.text);
    } catch (e) {
      setState(() {
        _erro = '$e';
        _entrando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(state.config.empresaNome.isEmpty ? 'Entrar' : state.config.empresaNome),
        actions: [
          IconButton(
            tooltip: 'Refazer pareamento',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => context.read<AppState>().unpair(),
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
                    initialValue: _userId,
                    decoration: const InputDecoration(labelText: 'Usuário', border: OutlineInputBorder()),
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
                ],
              ),
            ),
    );
  }
}
