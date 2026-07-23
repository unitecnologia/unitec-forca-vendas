import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'api/api_client.dart';
import 'auth/credential_store.dart';
import 'config.dart';
import 'log/app_log.dart';
import 'sync/sync_service.dart';

class AppState extends ChangeNotifier {
  AppState(this.config) : api = ApiClient(config) {
    sync = SyncService(config, api);
  }

  /// Restaura sessão persistida (sync periódica após reabrir o app).
  Future<void> initialize() async {
    // Sem ping: se já conectou antes, reabre o endereço para login/vendas offline.
    if (config.baseUrl.isEmpty && config.lastBaseUrl.isNotEmpty) {
      config.baseUrl = config.lastBaseUrl;
      await config.save();
      notifyListeners();
      AppLog.instance.info('conexão', 'Restaurada offline: ${config.baseUrl}');
    }
    if (config.isLoggedIn) {
      sync.start();
    }
  }

  final AppConfig config;
  final ApiClient api;
  late final SyncService sync;

  bool get isConnected => config.isConnected;
  bool get isApproved => config.isApproved;
  bool get isLoggedIn => config.isLoggedIn;

  static bool isNetworkError(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is http.ClientException) return true;
    if (e is ApiException) {
      final m = e.message.toLowerCase();
      return m.contains('socket') ||
          m.contains('timed out') ||
          m.contains('timeout') ||
          m.contains('connection') ||
          m.contains('failed host') ||
          m.contains('network') ||
          m.contains('conexão') ||
          m.contains('conectar');
    }
    final m = e.toString().toLowerCase();
    return m.contains('socket') ||
        m.contains('timed out') ||
        m.contains('timeout') ||
        m.contains('connection refused') ||
        m.contains('failed host') ||
        m.contains('network is unreachable') ||
        m.contains('clientexception');
  }

  /// Continua com o último servidor sem testar a rede (modo offline).
  Future<void> continueOffline() async {
    final url = config.lastBaseUrl.trim();
    if (url.isEmpty) {
      throw Exception('Nenhum servidor anterior. Conecte online pelo menos uma vez.');
    }
    if (!config.deviceApproved) {
      throw Exception('Aparelho ainda não autorizado. Conecte online para liberar.');
    }
    config.baseUrl = url;
    await ensureDeviceIdentity();
    await config.save();
    AppLog.instance.warn('conexão', 'Modo offline com $url');
    notifyListeners();
  }

  /// Garante um identificador único e um nome padrão (modelo do aparelho).
  Future<void> ensureDeviceIdentity() async {
    var changed = false;
    if (config.deviceUuid.isEmpty) {
      config.deviceUuid = const Uuid().v4();
      changed = true;
    }
    if (config.deviceName.isEmpty) {
      config.deviceName = await _defaultDeviceName();
      changed = true;
    }
    if (changed) {
      await config.save();
      notifyListeners();
    }
  }

  Future<String> _defaultDeviceName() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final brand = info.brand.isNotEmpty
          ? '${info.brand[0].toUpperCase()}${info.brand.substring(1)}'
          : '';
      final name = '$brand ${info.model}'.trim();
      return name.isEmpty ? 'Aparelho Android' : name;
    } catch (_) {
      return 'Aparelho Android';
    }
  }

  String _normalizarUrl(String input, {int defaultPort = 8765}) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    s = s.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(s);
    if (uri != null && !uri.hasPort) {
      s = '${uri.scheme}://${uri.host}:$defaultPort';
    }
    return s;
  }

  /// Conecta a um endereço (IP/porta) digitado manualmente.
  Future<void> connectManual(String url) async {
    final clean = _normalizarUrl(url);
    if (clean.isEmpty) {
      throw Exception('Informe o endereço do servidor.');
    }
    AppLog.instance.info('conexão', 'Testando $clean');
    final r = await ApiClient.pingDetailed(clean, timeout: const Duration(seconds: 5));
    if (!r.ok) {
      AppLog.instance.error('conexão', 'Falhou em $clean: ${r.message}');
      throw Exception('Não foi possível conectar em $clean: ${r.message}');
    }
    AppLog.instance.ok('conexão', 'Conectado a $clean (${r.ms} ms)');
    await _applyConnection(clean);
  }

  Future<void> _applyConnection(String baseUrl) async {
    config.baseUrl = baseUrl;
    config.lastBaseUrl = baseUrl;
    await ensureDeviceIdentity();
    await config.save();
    notifyListeners();
  }

  Future<void> connectFound(String baseUrl) async {
    AppLog.instance.ok('conexão', 'Servidor encontrado na rede: $baseUrl');
    await _applyConnection(baseUrl);
  }

  Future<void> setDeviceName(String name) async {
    config.deviceName = name.trim();
    await config.save();
    notifyListeners();
  }

  Future<String> registerDevice() async {
    await ensureDeviceIdentity();
    final resp = await api.registerDevice(deviceName: config.deviceName);
    config.pairingCode = (resp['pairing_code'] ?? '').toString();
    config.deviceApproved = resp['approved'] == true;
    await config.save();
    AppLog.instance.info('aparelho',
        'Registrado "${config.deviceName}" — código ${config.pairingCode} (status: ${resp['status'] ?? '-'})');
    notifyListeners();
    return config.pairingCode;
  }

  Future<String> refreshApproval() async {
    final resp = await api.deviceStatus();
    final status = (resp['status'] ?? 'desconhecido').toString();
    final approved = resp['approved'] == true;
    if (resp['pairing_code'] != null) {
      config.pairingCode = resp['pairing_code'].toString();
    }
    if (approved != config.deviceApproved) {
      config.deviceApproved = approved;
      await config.save();
      if (approved) {
        AppLog.instance.ok('aparelho', 'Autorizado pelo administrador');
      } else {
        AppLog.instance.warn('aparelho', 'Status mudou para: $status');
      }
      notifyListeners();
    }
    return status;
  }

  Future<bool> syncDeviceApprovalFromError(Object e) async {
    final blocked = e is ApiException
        ? e.isDeviceBlocked
        : e.toString().toLowerCase().contains('aguardando autorização');
    if (!blocked) return false;
    if (config.deviceApproved) {
      config.deviceApproved = false;
      await config.save();
      AppLog.instance.warn('aparelho', 'Autorização local invalidada: $e');
      notifyListeners();
    }
    return true;
  }

  Future<Map<String, dynamic>> info() async => api.info();

  Future<List<dynamic>> usuariosDaEmpresa(int empresaId) async => api.usuarios(empresaId);

  Future<void> cacheEmpresas(List<dynamic> empresas) async {
    config.cachedEmpresasJson = jsonEncode(empresas);
    await config.save();
  }

  Future<void> cacheUsuarios(int empresaId, List<dynamic> users) async {
    Map<String, dynamic> map = {};
    try {
      map = jsonDecode(config.cachedUsuariosJson) as Map<String, dynamic>? ?? {};
    } catch (_) {}
    map['$empresaId'] = users;
    config.cachedUsuariosJson = jsonEncode(map);
    await config.save();
  }

  List<dynamic> empresasEmCache() {
    try {
      final list = jsonDecode(config.cachedEmpresasJson);
      return list is List ? List<dynamic>.from(list) : [];
    } catch (_) {
      return [];
    }
  }

  List<dynamic> usuariosEmCache(int empresaId) {
    try {
      final map = jsonDecode(config.cachedUsuariosJson) as Map<String, dynamic>?;
      final list = map?['$empresaId'];
      return list is List ? List<dynamic>.from(list) : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> login(
    int empresaId,
    int userId,
    String senha, {
    String? empresaNome,
    bool rememberUser = false,
    bool biometricEnabled = false,
  }) async {
    try {
      final resp = await api.login(
        empresaId: empresaId,
        userId: userId,
        senha: senha,
        deviceUuid: config.deviceUuid,
        deviceName: config.deviceName,
      );
      await _aplicarLoginOnline(
        resp,
        empresaId: empresaId,
        empresaNome: empresaNome,
        rememberUser: rememberUser,
        biometricEnabled: biometricEnabled,
        senha: senha,
      );
    } catch (e) {
      if (isNetworkError(e)) {
        final ok = await _loginOffline(
          empresaId: empresaId,
          userId: userId,
          senha: senha,
          empresaNome: empresaNome,
          rememberUser: rememberUser,
          biometricEnabled: biometricEnabled,
        );
        if (ok) return;
      }
      rethrow;
    }
  }

  Future<void> _aplicarLoginOnline(
    Map<String, dynamic> resp, {
    required int empresaId,
    String? empresaNome,
    required bool rememberUser,
    required bool biometricEnabled,
    required String senha,
  }) async {
    config.token = (resp['token'] ?? '').toString();
    config.cachedToken = config.token;
    config.empresaId = empresaId;
    if (empresaNome != null) config.empresaNome = empresaNome;
    final user = resp['user'] as Map<String, dynamic>?;
    if (user != null) {
      config.userId = user['id'];
      config.userName = (user['name'] ?? '').toString();
      config.vendedorId = user['vendedor_id'];
      config.vendedorNome = (user['vendedor_nome'] ?? '').toString();
      config.caixaNome = (user['caixa_nome'] ?? '').toString();
      config.estoqueNome = (user['estoque_nome'] ?? '').toString();
      config.tabelaVendaId = user['tabela_venda_id'] is int
          ? user['tabela_venda_id'] as int
          : int.tryParse('${user['tabela_venda_id'] ?? ''}');
      config.tabelaVendaCodigo = (user['tabela_venda_codigo'] ?? '').toString();
      config.tabelaVendaDescricao = (user['tabela_venda_descricao'] ?? '').toString();

      // Garante vendedor no cache de usuários para restaurar no login offline.
      try {
        final cached = usuariosEmCache(empresaId).map((e) {
          if (e is! Map) return e;
          final m = Map<String, dynamic>.from(e);
          if (_asInt(m['id']) == config.userId) {
            m['vendedor_id'] = config.vendedorId;
            m['vendedor_nome'] = config.vendedorNome;
            m['name'] = config.userName;
          }
          return m;
        }).toList();
        if (cached.isNotEmpty) {
          await cacheUsuarios(empresaId, cached);
        }
      } catch (_) {}
    }
    config.rememberUser = rememberUser;
    config.biometricEnabled = rememberUser && biometricEnabled;
    if (rememberUser) {
      await CredentialStore.saveSenha(senha);
    } else {
      await CredentialStore.clearSenha();
    }
    await config.save();
    AppLog.instance.ok('login', 'Entrou como ${config.userName} (empresa ${config.empresaNome})');
    sync.start();
    notifyListeners();
  }

  Future<bool> _loginOffline({
    required int empresaId,
    required int userId,
    required String senha,
    String? empresaNome,
    required bool rememberUser,
    required bool biometricEnabled,
  }) async {
    final saved = await CredentialStore.readSenha();
    final token = config.cachedToken.trim();
    if (saved == null || saved.isEmpty || saved != senha) {
      return false;
    }
    if (token.isEmpty) return false;
    if (config.empresaId != null && config.empresaId != empresaId) return false;
    if (config.userId != null && config.userId != userId) return false;

    config.token = token;
    config.empresaId = empresaId;
    if (empresaNome != null && empresaNome.isNotEmpty) {
      config.empresaNome = empresaNome;
    }
    config.userId = userId;
    // Restaura nome/vendedor do cache de usuários se a sessão limpa perdeu o vínculo.
    if (config.userName.isEmpty || config.vendedorId == null) {
      for (final raw in usuariosEmCache(empresaId)) {
        if (raw is! Map) continue;
        final u = Map<String, dynamic>.from(raw);
        if (_asInt(u['id']) != userId) continue;
        if (config.userName.isEmpty) {
          config.userName = (u['name'] ?? '').toString();
        }
        final vid = _asInt(u['vendedor_id']);
        if (config.vendedorId == null && vid != null) {
          config.vendedorId = vid;
          config.vendedorNome = (u['vendedor_nome'] ?? '').toString();
        }
        break;
      }
    }
    config.rememberUser = rememberUser;
    config.biometricEnabled = rememberUser && biometricEnabled;
    await config.save();
    AppLog.instance.warn(
      'login',
      'Entrou OFFLINE como ${config.userName.isEmpty ? userId : config.userName}'
      '${config.vendedorId != null ? ' (vendedor ${config.vendedorId})' : ' (sem vendedor)'}',
    );
    sync.start();
    notifyListeners();
    return true;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  Future<void> logout() async {
    sync.stop();
    try {
      await api.logout();
    } catch (_) {}
    if (!config.rememberUser) {
      await CredentialStore.clearSenha();
      config.biometricEnabled = false;
      config.cachedToken = '';
    }
    config.clearSession();
    await config.save();
    AppLog.instance.info('login', 'Sessão encerrada');
    notifyListeners();
  }

  Future<void> disconnect() async {
    sync.stop();
    await CredentialStore.clearSenha();
    config
      ..baseUrl = ''
      ..pairingCode = ''
      ..rememberUser = false
      ..biometricEnabled = false
      ..empresaId = null
      ..empresaNome = ''
      ..cachedToken = ''
      ..clearSession();
    await config.save();
    notifyListeners();
  }
}
