import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Configuração de conexão + autorização do aparelho + sessão, persistida.
class AppConfig {
  AppConfig({
    this.baseUrl = '',
    this.lastBaseUrl = '',
    this.deviceUuid = '',
    this.deviceName = '',
    this.pairingCode = '',
    this.deviceApproved = false,
    this.empresaId,
    this.empresaNome = '',
    this.token = '',
    this.userId,
    this.userName = '',
    this.vendedorId,
    this.vendedorNome = '',
    this.caixaNome = '',
    this.estoqueNome = '',
    this.tabelaVendaId,
    this.tabelaVendaCodigo = '',
    this.tabelaVendaDescricao = '',
    this.lastSyncIso,
    this.rememberUser = false,
    this.biometricEnabled = false,
    this.cachedToken = '',
    this.cachedEmpresasJson = '[]',
    this.cachedUsuariosJson = '{}',
  });

  String baseUrl;

  /// Último endereço que conectou com sucesso (mantido mesmo após desconectar,
  /// para oferecer "Reconectar" sem digitar de novo).
  String lastBaseUrl;
  String deviceUuid;
  String deviceName;
  String pairingCode;
  bool deviceApproved;
  int? empresaId;
  String empresaNome;
  String token;
  int? userId;
  String userName;
  int? vendedorId;
  String vendedorNome;
  String caixaNome;
  String estoqueNome;
  int? tabelaVendaId;
  String tabelaVendaCodigo;
  String tabelaVendaDescricao;
  String? lastSyncIso;

  /// Mantém empresa/usuário após sair (preenche o login automaticamente).
  bool rememberUser;

  /// Usa digital/biometria para entrar (exige [rememberUser] e senha guardada).
  bool biometricEnabled;

  /// Último token válido — permite reabrir sessão offline (mesmo após logout com lembrar usuário).
  String cachedToken;

  /// Cache JSON de empresas/usuários para montar o login sem servidor.
  String cachedEmpresasJson;
  String cachedUsuariosJson;

  bool get isConnected => baseUrl.isNotEmpty;
  bool get isApproved => deviceApproved;
  bool get isLoggedIn => token.isNotEmpty;

  /// Base completa da API de força de vendas.
  String get apiBase => '$baseUrl/api/v1/forca-vendas';

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'lastBaseUrl': lastBaseUrl,
        'deviceUuid': deviceUuid,
        'deviceName': deviceName,
        'pairingCode': pairingCode,
        'deviceApproved': deviceApproved,
        'empresaId': empresaId,
        'empresaNome': empresaNome,
        'token': token,
        'userId': userId,
        'userName': userName,
        'vendedorId': vendedorId,
        'vendedorNome': vendedorNome,
        'caixaNome': caixaNome,
        'estoqueNome': estoqueNome,
        'tabelaVendaId': tabelaVendaId,
        'tabelaVendaCodigo': tabelaVendaCodigo,
        'tabelaVendaDescricao': tabelaVendaDescricao,
        'lastSyncIso': lastSyncIso,
        'rememberUser': rememberUser,
        'biometricEnabled': biometricEnabled,
        'cachedToken': cachedToken,
        'cachedEmpresasJson': cachedEmpresasJson,
        'cachedUsuariosJson': cachedUsuariosJson,
      };

  static AppConfig fromJson(Map<String, dynamic> j) => AppConfig(
        baseUrl: j['baseUrl'] ?? '',
        lastBaseUrl: j['lastBaseUrl'] ?? '',
        deviceUuid: j['deviceUuid'] ?? '',
        deviceName: j['deviceName'] ?? '',
        pairingCode: j['pairingCode'] ?? '',
        deviceApproved: j['deviceApproved'] ?? false,
        empresaId: j['empresaId'],
        empresaNome: j['empresaNome'] ?? '',
        token: j['token'] ?? '',
        userId: j['userId'],
        userName: j['userName'] ?? '',
        vendedorId: j['vendedorId'],
        vendedorNome: j['vendedorNome'] ?? '',
        caixaNome: j['caixaNome'] ?? '',
        estoqueNome: j['estoqueNome'] ?? '',
        tabelaVendaId: j['tabelaVendaId'],
        tabelaVendaCodigo: j['tabelaVendaCodigo'] ?? '',
        tabelaVendaDescricao: j['tabelaVendaDescricao'] ?? '',
        lastSyncIso: j['lastSyncIso'],
        rememberUser: j['rememberUser'] == true,
        biometricEnabled: j['biometricEnabled'] == true,
        cachedToken: j['cachedToken'] ?? '',
        cachedEmpresasJson: j['cachedEmpresasJson'] ?? '[]',
        cachedUsuariosJson: j['cachedUsuariosJson'] ?? '{}',
      );

  static const _key = 'unitec_fv_config';

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return AppConfig();
    }
    try {
      return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppConfig();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }

  /// Limpa apenas a sessão (mantém a conexão e a autorização do aparelho).
  /// Com [rememberUser], empresa e usuário ficam para o próximo login.
  void clearSession() {
    token = '';
    vendedorId = null;
    vendedorNome = '';
    caixaNome = '';
    estoqueNome = '';
    tabelaVendaId = null;
    tabelaVendaCodigo = '';
    tabelaVendaDescricao = '';
    if (!rememberUser) {
      empresaId = null;
      empresaNome = '';
      userId = null;
      userName = '';
      biometricEnabled = false;
      cachedToken = '';
    }
  }
}
