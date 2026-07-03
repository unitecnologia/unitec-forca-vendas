import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../ui/brand.dart';

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

  static String _empresaLabel(dynamic e) {
    final nome = (e['nome'] ?? '').toString().trim();
    if (nome.isNotEmpty) return nome;
    final codigo = e['codigo'];
    if (codigo != null && '$codigo'.trim().isNotEmpty) return 'Empresa $codigo';
    return 'Empresa #${e['id']}';
  }

  static List<dynamic> _ordenarEmpresas(List<dynamic> empresas) {
    final sorted = List<dynamic>.from(empresas);
    sorted.sort(
      (a, b) => _empresaLabel(a).toUpperCase().compareTo(_empresaLabel(b).toUpperCase()),
    );
    return sorted;
  }

  static List<dynamic> _ordenarUsuarios(List<dynamic> usuarios) {
    final sorted = List<dynamic>.from(usuarios);
    sorted.sort(
      (a, b) => ((a['name'] ?? '') as String).toUpperCase().compareTo(
            ((b['name'] ?? '') as String).toUpperCase(),
          ),
    );
    return sorted;
  }

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

  int? _empresaPreferida(List<dynamic> empresas) {
    final config = context.read<AppState>().config;
    final lastId = config.empresaId;
    if (lastId != null && empresas.any((e) => e['id'] == lastId)) {
      return lastId;
    }
    return empresas.isNotEmpty ? empresas.first['id'] as int? : null;
  }

  Future<void> _carregarEmpresas() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final info = await context.read<AppState>().info();
      final empresas = _ordenarEmpresas(info['empresas'] as List<dynamic>? ?? []);
      setState(() {
        _empresas = empresas;
        _empresaId = _empresaPreferida(empresas);
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
      final users = _ordenarUsuarios(
        await context.read<AppState>().usuariosDaEmpresa(_empresaId!),
      );
      final config = context.read<AppState>().config;
      final lastUser = config.userId;
      setState(() {
        _usuarios = users;
        _userId = lastUser != null && users.any((u) => u['id'] == lastUser)
            ? lastUser
            : (users.isNotEmpty ? users.first['id'] as int? : null);
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
    for (final e in _empresas) {
      if (e['id'] == _empresaId) return _empresaLabel(e);
    }
    return '';
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

  InputDecoration _fieldDecoration(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Brand.blue.withValues(alpha: 0.22)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.blue, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE3ECF5), Color(0xFFF1F4F8), Color(0xFFE8EEF5)],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Brand.blue))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(
                        children: [
                          const SizedBox(width: 4),
                          const Text(
                            'Entrar',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Trocar servidor',
                            icon: const Icon(Icons.lan_outlined, color: Brand.blue),
                            onPressed: () => context.read<AppState>().disconnect(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Column(
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: const LinearGradient(
                                  colors: [Brand.blue, Brand.green],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Brand.blue.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 40),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Força de Vendas',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A237E),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Selecione empresa e usuário para continuar',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 13),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white,
                                    Color.lerp(Colors.white, Brand.blue, 0.04)!,
                                  ],
                                ),
                                border: Border.all(color: Brand.blue.withValues(alpha: 0.12)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Brand.blue.withValues(alpha: 0.12),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DropdownButtonFormField<int>(
                                    value: _empresaId,
                                    decoration: _fieldDecoration('Empresa'),
                                    items: _empresas
                                        .map(
                                          (e) => DropdownMenuItem<int>(
                                            value: e['id'] as int?,
                                            child: Text(_empresaLabel(e)),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      setState(() => _empresaId = v);
                                      _carregarUsuarios();
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<int>(
                                    value: _userId,
                                    decoration: _fieldDecoration(
                                      'Usuário',
                                      suffixIcon: _carregandoUsuarios
                                          ? const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: SizedBox(
                                                height: 16,
                                                width: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Brand.blue),
                                              ),
                                            )
                                          : null,
                                    ),
                                    items: _usuarios
                                        .map(
                                          (u) => DropdownMenuItem<int>(
                                            value: u['id'] as int?,
                                            child: Text((u['name'] ?? '').toString()),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: _carregandoUsuarios ? null : (v) => setState(() => _userId = v),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _senha,
                                    obscureText: true,
                                    decoration: _fieldDecoration('Senha do app'),
                                    onSubmitted: (_) => _entrar(),
                                  ),
                                  const SizedBox(height: 22),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: const LinearGradient(
                                        colors: [Brand.blue, Color(0xFF1976D2)],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Brand.blue.withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        minimumSize: const Size.fromHeight(48),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      onPressed: _entrando ? null : _entrar,
                                      child: _entrando
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Text(
                                              'Entrar',
                                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                            ),
                                    ),
                                  ),
                                  if (_erro != null) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.red.shade200),
                                      ),
                                      child: Text(
                                        _erro!,
                                        style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '$kAppName • $kAppVersionLabel',
                        style: TextStyle(color: Colors.black.withValues(alpha: 0.38), fontSize: 12),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
