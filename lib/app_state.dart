import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api/api_client.dart';
import 'config.dart';
import 'sync/sync_service.dart';

class AppState extends ChangeNotifier {
  AppState(this.config) : api = ApiClient(config) {
    sync = SyncService(config, api);
  }

  final AppConfig config;
  final ApiClient api;
  late final SyncService sync;

  bool get isPaired => config.isPaired;
  bool get isLoggedIn => config.isLoggedIn;

  /// Lê o conteúdo de um QR de pareamento e salva a configuração.
  /// Espera JSON: {"v":1,"url":"http://ip:8765","secret":"...","empresa_id":1,"empresa":"..."}
  Future<void> pairFromQr(String raw) async {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['app'] != 'unitec-forca-vendas') {
      throw Exception('QR Code inválido para este aplicativo.');
    }
    config.baseUrl = (data['url'] ?? '').toString();
    config.pairingSecret = (data['secret'] ?? '').toString();
    config.empresaId = data['empresa_id'] is int ? data['empresa_id'] : int.tryParse('${data['empresa_id']}');
    config.empresaNome = (data['empresa'] ?? '').toString();
    if (config.deviceUuid.isEmpty) {
      config.deviceUuid = const Uuid().v4();
    }
    await config.save();
    notifyListeners();
  }

  /// Pareamento manual (quando a câmera não funciona): o vendedor digita o
  /// endereço do servidor + segredo (mostrados na tela do ERP) e escolhe a empresa.
  Future<void> pairManual({
    required String url,
    required String secret,
    required int empresaId,
    String empresaNome = '',
  }) async {
    final cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleanUrl.isEmpty) {
      throw Exception('Informe o endereço do servidor.');
    }
    if (secret.trim().isEmpty) {
      throw Exception('Informe o segredo de pareamento.');
    }
    config.baseUrl = cleanUrl;
    config.pairingSecret = secret.trim();
    config.empresaId = empresaId;
    config.empresaNome = empresaNome.trim();
    if (config.deviceUuid.isEmpty) {
      config.deviceUuid = const Uuid().v4();
    }
    await config.save();
    notifyListeners();
  }

  Future<List<dynamic>> usuariosDaEmpresa() async {
    return api.usuarios(config.empresaId ?? 0);
  }

  Future<void> login(int userId, String senha, {String? deviceName}) async {
    final resp = await api.login(
      empresaId: config.empresaId ?? 0,
      userId: userId,
      senha: senha,
      deviceUuid: config.deviceUuid,
      deviceName: deviceName,
    );
    config.token = (resp['token'] ?? '').toString();
    final user = resp['user'] as Map<String, dynamic>?;
    if (user != null) {
      config.userId = user['id'];
      config.userName = (user['name'] ?? '').toString();
      config.vendedorId = user['vendedor_id'];
    }
    await config.save();
    sync.start();
    notifyListeners();
  }

  Future<void> logout() async {
    sync.stop();
    await api.logout();
    config.clearSession();
    await config.save();
    notifyListeners();
  }

  /// Remove o pareamento (volta à tela inicial de configuração).
  Future<void> unpair() async {
    sync.stop();
    config
      ..baseUrl = ''
      ..pairingSecret = ''
      ..empresaId = null
      ..empresaNome = ''
      ..clearSession();
    await config.save();
    notifyListeners();
  }
}
