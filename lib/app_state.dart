import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
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
    // Se não tiver porta explícita, usa a padrão do ERP.
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

  /// Salva a conexão encontrada (manual ou automática).
  Future<void> _applyConnection(String baseUrl) async {
    config.baseUrl = baseUrl;
    config.lastBaseUrl = baseUrl;
    await ensureDeviceIdentity();
    // Não zera autorização aqui: o status real vem do ERP (register/refresh).
    await config.save();
    notifyListeners();
  }

  Future<void> connectFound(String baseUrl) async {
    AppLog.instance.ok('conexão', 'Servidor encontrado na rede: $baseUrl');
    await _applyConnection(baseUrl);
  }

  /// Atualiza o nome do aparelho (mostrado ao admin).
  Future<void> setDeviceName(String name) async {
    config.deviceName = name.trim();
    await config.save();
    notifyListeners();
  }

  /// Registra o aparelho no ERP (cria a solicitação de autorização).
  /// Retorna o código de pareamento para o vendedor conferir no ERP.
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

  /// Consulta o status de autorização. Retorna o status textual do servidor.
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

  /// Se a API indicar aparelho pendente/revogado, alinha o flag local
  /// (volta à tela de autorização).
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

  Future<Map<String, dynamic>> info() async {
    return api.info();
  }

  Future<List<dynamic>> usuariosDaEmpresa(int empresaId) async {
    return api.usuarios(empresaId);
  }

  Future<void> login(
    int empresaId,
    int userId,
    String senha, {
    String? empresaNome,
    bool rememberUser = false,
    bool biometricEnabled = false,
  }) async {
    final resp = await api.login(
      empresaId: empresaId,
      userId: userId,
      senha: senha,
      deviceUuid: config.deviceUuid,
      deviceName: config.deviceName,
    );
    config.token = (resp['token'] ?? '').toString();
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
    }
    config.rememberUser = rememberUser;
    config.biometricEnabled = rememberUser && biometricEnabled;
    if (config.biometricEnabled) {
      await CredentialStore.saveSenha(senha);
    } else {
      await CredentialStore.clearSenha();
    }
    await config.save();
    AppLog.instance.ok('login', 'Entrou como ${config.userName} (empresa ${config.empresaNome})');
    sync.start();
    notifyListeners();
  }

  Future<void> logout() async {
    sync.stop();
    await api.logout();
    if (!config.rememberUser) {
      await CredentialStore.clearSenha();
      config.biometricEnabled = false;
    }
    config.clearSession();
    await config.save();
    AppLog.instance.info('login', 'Sessão encerrada');
    notifyListeners();
  }

  /// Desconecta do servidor (volta à tela de conexão). Mantém o device_uuid
  /// e a autorização local — ao reconectar, o ERP confirma o mesmo aparelho.
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
      ..clearSession();
    // Mantém deviceApproved + deviceUuid: não pede autorização de novo.
    await config.save();
    notifyListeners();
  }
}
