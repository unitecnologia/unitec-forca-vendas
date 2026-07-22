import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../auth/credential_store.dart';
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
  bool _salvarUsuario = false;
  bool _usarDigital = false;
  bool _biometriaDisponivel = false;
  bool _temSenhaSalva = false;
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
    _preparar();
  }

  Future<void> _preparar() async {
    final config = context.read<AppState>().config;
    _salvarUsuario = config.rememberUser;
    _usarDigital = config.biometricEnabled;
    _biometriaDisponivel = await CredentialStore.canUseBiometrics();
    _temSenhaSalva = (await CredentialStore.readSenha())?.isNotEmpty == true;
    if (!mounted) return;
    await _carregarEmpresas();
    if (mounted &&
        _salvarUsuario &&
        _usarDigital &&
        _biometriaDisponivel &&
        _temSenhaSalva &&
        _empresaId != null &&
        _userId != null) {
      // Oferece a digital assim que a tela estiver pronta.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entrarComDigital();
      });
    }
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
    final state = context.read<AppState>();
    try {
      // Confere no servidor se o aparelho ainda está autorizado.
      await state.refreshApproval();
      if (!mounted) return;
      if (!state.isApproved) {
        setState(() => _loading = false);
        return;
      }
      final info = await state.info();
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
      final voltouEspera = await state.syncDeviceApprovalFromError(e);
      if (!mounted) return;
      setState(() {
        _erro = voltouEspera
            ? null
            : 'Não foi possível carregar empresas: $e';
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
    final state = context.read<AppState>();
    try {
      final users = _ordenarUsuarios(await state.usuariosDaEmpresa(_empresaId!));
      if (!mounted) return;
      final lastUser = state.config.userId;
      setState(() {
        _usuarios = users;
        _userId = lastUser != null && users.any((u) => u['id'] == lastUser)
            ? lastUser
            : (users.isNotEmpty ? users.first['id'] as int? : null);
        _carregandoUsuarios = false;
      });
    } catch (e) {
      final voltouEspera = await state.syncDeviceApprovalFromError(e);
      if (!mounted) return;
      setState(() {
        _erro = voltouEspera ? null : 'Não foi possível carregar usuários: $e';
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

  Future<void> _entrar({String? senhaOverride}) async {
    if (_empresaId == null || _userId == null) return;
    final senha = senhaOverride ?? _senha.text;
    if (senha.isEmpty) {
      setState(() => _erro = 'Informe a senha do app.');
      return;
    }
    setState(() {
      _entrando = true;
      _erro = null;
    });
    final state = context.read<AppState>();
    try {
      await state.login(
        _empresaId!,
        _userId!,
        senha,
        empresaNome: _empresaNome(),
        rememberUser: _salvarUsuario,
        biometricEnabled: _salvarUsuario && _usarDigital,
      );
    } catch (e) {
      await state.syncDeviceApprovalFromError(e);
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _entrando = false;
      });
    }
  }

  Future<void> _entrarComDigital() async {
    if (_entrando || _empresaId == null || _userId == null) return;
    final ok = await CredentialStore.authenticate(
      reason: 'Entre no Força de Vendas com a digital',
    );
    if (!ok) {
      if (mounted) setState(() => _erro = 'Digital não reconhecida. Digite a senha.');
      return;
    }
    final senha = await CredentialStore.readSenha();
    if (senha == null || senha.isEmpty) {
      if (mounted) {
        setState(() {
          _erro = 'Senha não encontrada. Entre com a senha e ative a digital de novo.';
          _usarDigital = false;
          _temSenhaSalva = false;
        });
      }
      return;
    }
    await _entrar(senhaOverride: senha);
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
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final tecladoAberto = teclado > 0;

    return Scaffold(
      backgroundColor: Brand.bg,
      resizeToAvoidBottomInset: true,
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
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
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
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Column(
                          children: [
                            if (!tecladoAberto) ...[
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
                              const SizedBox(height: 20),
                            ],
                            Container(
                              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
                                  const SizedBox(height: 14),
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
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: _senha,
                                    obscureText: true,
                                    textInputAction: TextInputAction.done,
                                    decoration: _fieldDecoration(
                                      'Senha do app',
                                      suffixIcon: (_usarDigital && _temSenhaSalva && _biometriaDisponivel)
                                          ? IconButton(
                                              tooltip: 'Entrar com digital',
                                              icon: const Icon(Icons.fingerprint, color: Brand.blue),
                                              onPressed: _entrando ? null : _entrarComDigital,
                                            )
                                          : null,
                                    ),
                                    onSubmitted: (_) => _entrar(),
                                  ),
                                  const SizedBox(height: 4),
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    value: _salvarUsuario,
                                    title: const Text('Salvar usuário', style: TextStyle(fontSize: 14)),
                                    subtitle: const Text(
                                      'Mantém empresa e usuário ao sair',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    onChanged: (v) {
                                      setState(() {
                                        _salvarUsuario = v ?? false;
                                        if (!_salvarUsuario) _usarDigital = false;
                                      });
                                    },
                                  ),
                                  if (_biometriaDisponivel)
                                    CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      value: _usarDigital && _salvarUsuario,
                                      title: const Text('Usar digital do aparelho', style: TextStyle(fontSize: 14)),
                                      subtitle: const Text(
                                        'Próximo acesso com biometria',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      onChanged: !_salvarUsuario
                                          ? null
                                          : (v) => setState(() => _usarDigital = v ?? false),
                                    ),
                                  if (_erro != null) ...[
                                    const SizedBox(height: 8),
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
                    // Botão fixo acima do teclado — não some ao digitar a senha.
                    Material(
                      color: Colors.transparent,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 4, 20, tecladoAberto ? 8 : 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                            if (_salvarUsuario &&
                                _usarDigital &&
                                _temSenhaSalva &&
                                _biometriaDisponivel) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _entrando ? null : _entrarComDigital,
                                icon: const Icon(Icons.fingerprint),
                                label: const Text('Entrar com digital'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Brand.blue,
                                  minimumSize: const Size.fromHeight(44),
                                  side: BorderSide(color: Brand.blue.withValues(alpha: 0.45)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ],
                            if (!tecladoAberto) ...[
                              const SizedBox(height: 8),
                              Text(
                                '$kAppName • $kAppVersionLabel',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black.withValues(alpha: 0.38), fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
