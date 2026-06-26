import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Configuração de pareamento + sessão, persistida no aparelho.
class AppConfig {
  AppConfig({
    this.baseUrl = '',
    this.pairingSecret = '',
    this.empresaId,
    this.empresaNome = '',
    this.token = '',
    this.userId,
    this.userName = '',
    this.vendedorId,
    this.deviceUuid = '',
    this.lastSyncIso,
  });

  String baseUrl;
  String pairingSecret;
  int? empresaId;
  String empresaNome;
  String token;
  int? userId;
  String userName;
  int? vendedorId;
  String deviceUuid;
  String? lastSyncIso;

  bool get isPaired => baseUrl.isNotEmpty && pairingSecret.isNotEmpty;
  bool get isLoggedIn => token.isNotEmpty;

  /// Base completa da API de força de vendas.
  String get apiBase => '$baseUrl/api/v1/forca-vendas';

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'pairingSecret': pairingSecret,
        'empresaId': empresaId,
        'empresaNome': empresaNome,
        'token': token,
        'userId': userId,
        'userName': userName,
        'vendedorId': vendedorId,
        'deviceUuid': deviceUuid,
        'lastSyncIso': lastSyncIso,
      };

  static AppConfig fromJson(Map<String, dynamic> j) => AppConfig(
        baseUrl: j['baseUrl'] ?? '',
        pairingSecret: j['pairingSecret'] ?? '',
        empresaId: j['empresaId'],
        empresaNome: j['empresaNome'] ?? '',
        token: j['token'] ?? '',
        userId: j['userId'],
        userName: j['userName'] ?? '',
        vendedorId: j['vendedorId'],
        deviceUuid: j['deviceUuid'] ?? '',
        lastSyncIso: j['lastSyncIso'],
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

  /// Limpa apenas a sessão (mantém o pareamento).
  void clearSession() {
    token = '';
    userId = null;
    userName = '';
    vendedorId = null;
  }
}
