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
  final _senhaFocus = FocusNode();
  bool _loading = true;
  bool _carregandoUsuarios = false;
  bool _entrando = false;
  bool _salvarUsuario = false;
  bool _usarDigital = false;
  bool _biometriaDisponivel = false;
  bool _temSenhaSalva = false;
  bool _modoOffline = false;
  String? _erro;

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

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
      (a, b) => ((a['name'] ?? '').toString()).toUpperCase().compareTo(
            ((b['name'] ?? '').toString()).toUpperCase(),
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
    // NÃ£o abre biometria sozinha: atrapalha o teclado da senha.
  }

  @override
  void dispose() {
    _senha.dispose();
    _senhaFocus.dispose();
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
      _modoOffline = false;
    });
    final state = context.read<AppState>();
    try {
      // Confere no servidor se o aparelho ainda estÃ¡ autorizado.
      await state.refreshApproval();
      if (!mounted) return;
      if (!state.isApproved) {
        setState(() => _loading = false);
        return;
      }
      final info = await state.info();
      final empresas = _ordenarEmpresas(info['empresas'] as List<dynamic>? ?? []);
      await state.cacheEmpresas(empresas);
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
      if (voltouEspera) {
        setState(() => _loading = false);
        return;
      }
      // Offline: usa cache local para ainda permitir digitar senha e vender.
      final cached = _ordenarEmpresas(state.empresasEmCache());
      if (cached.isNotEmpty && state.config.deviceApproved) {
        setState(() {
          _empresas = cached;
          _empresaId = _empresaPreferida(cached);
          _modoOffline = true;
          _erro = 'Servidor offline â€” usando dados salvos no aparelho.';
          _loading = false;
        });
        if (_empresaId != null) {
          await _carregarUsuarios(offline: true);
        }
        return;
      }
      setState(() {
        _erro = 'NÃ£o foi possÃ­vel carregar empresas: $e';
        _loading = false;
      });
    }
  }

  Future<void> _carregarUsuarios({bool offline = false}) async {
    if (_empresaId == null) return;
    setState(() {
      _carregandoUsuarios = true;
      if (!_modoOffline) _erro = null;
      _usuarios = [];
      _userId = null;
    });
    final state = context.read<AppState>();
    try {
      List<dynamic> users;
      if (offline) {
        users = _ordenarUsuarios(state.usuariosEmCache(_empresaId!));
      } else {
        users = _ordenarUsuarios(await state.usuariosDaEmpresa(_empresaId!));
        await state.cacheUsuarios(_empresaId!, users);
      }
      if (!mounted) return;
      final lastUser = state.config.userId;
      setState(() {
        _usuarios = users;
        _userId = lastUser != null && users.any((u) => _asInt(u['id']) == lastUser)
            ? lastUser
            : (users.isNotEmpty ? _asInt(users.first['id']) : null);
        _carregandoUsuarios = false;
      });
    } catch (e) {
      final voltouEspera = await state.syncDeviceApprovalFromError(e);
      if (!mounted) return;
      final cached = _ordenarUsuarios(state.usuariosEmCache(_empresaId!));
      if (cached.isNotEmpty) {
        final lastUser = state.config.userId;
        setState(() {
          _usuarios = cached;
          _userId = lastUser != null && cached.any((u) => _asInt(u['id']) == lastUser)
              ? lastUser
              : (cached.isNotEmpty ? _asInt(cached.first['id']) : null);
          _modoOffline = true;
          _erro = voltouEspera ? null : 'Servidor offline â€” usuÃ¡rios do cache.';
          _carregandoUsuarios = false;
        });
        return;
      }
      setState(() {
        _erro = voltouEspera ? null : 'NÃ£o foi possÃ­vel carregar usuÃ¡rios: $e';
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
      reason: 'Entre no ForÃ§a de Vendas com a digital',
    );
    if (!ok) {
      if (mounted) {
        setState(() => _erro = 'Digital nÃ£o reconhecida. Digite a senha.');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _senhaFocus.requestFocus();
        });
      }
      return;
    }
    final senha = await CredentialStore.readSenha();
    if (senha == null || senha.isEmpty) {
      if (mounted) {
        setState(() {
          _erro = 'Senha nÃ£o encontrada. Entre com a senha e ative a digital de novo.';
          _usarDigital = false;
          _temSenhaSalva = false;
        });
        _senhaFocus.requestFocus();
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
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        // manual: onDrag fechava o teclado e parecia que "nao digita"
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            const Text(
                              'Força de Vendas',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A237E),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                color: Colors.white,
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
                                        .map((e) {
                                          final id = _asInt(e['id']);
                                          if (id == null) return null;
                                          return DropdownMenuItem<int>(
                                            value: id,
                                            child: Text(_empresaLabel(e)),
                                          );
                                        })
                                        .whereType<DropdownMenuItem<int>>()
                                        .toList(),
                                    onChanged: (v) {
                                      setState(() => _empresaId = v);
                                      _carregarUsuarios(offline: _modoOffline);
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
                                        .map((u) {
                                          final id = _asInt(u['id']);
                                          if (id == null) return null;
                                          return DropdownMenuItem<int>(
                                            value: id,
                                            child: Text((u['name'] ?? '').toString()),
                                          );
                                        })
                                        .whereType<DropdownMenuItem<int>>()
                                        .toList(),
                                    onChanged: _carregandoUsuarios
                                        ? null
                                        : (v) {
                                            setState(() => _userId = v);
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              if (mounted) _senhaFocus.requestFocus();
                                            });
                                          },
                                  ),
                                  if (!_carregandoUsuarios && _empresaId != null && _usuarios.isEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Nenhum usuário com senha do app nesta empresa.\nNo ERP: Usuários → editar → “Senha app força de vendas”.',
                                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  TextField(
                                    key: const ValueKey('login_senha'),
                                    controller: _senha,
                                    focusNode: _senhaFocus,
                                    obscureText: true,
                                    keyboardType: TextInputType.text,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    smartDashesType: SmartDashesType.disabled,
                                    smartQuotesType: SmartQuotesType.disabled,
                                    textInputAction: TextInputAction.done,
                                    enableInteractiveSelection: true,
                                    decoration: _fieldDecoration('Senha do app'),
                                    onTap: () {
                                      if (!_senhaFocus.hasFocus) {
                                        _senhaFocus.requestFocus();
                                      }
                                    },
                                    onSubmitted: (_) => _entrar(),
                                  ),
                                  if (_modoOffline) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Modo offline: marque “Salvar usuário” no próximo login online para liberar vendas sem servidor.',
                                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                                    ),
                                  ],
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
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Brand.blue,
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
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '$kAppName • $kAppVersionLabel',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black.withValues(alpha: 0.38), fontSize: 12),
                            ),
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