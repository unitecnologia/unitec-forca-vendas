import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Cliente HTTP da API Força de Vendas do ERP.
class ApiClient {
  ApiClient(this.config);

  final AppConfig config;
  final http.Client _http = http.Client();

  Duration timeout = const Duration(seconds: 20);

  Map<String, String> _headers({bool auth = false, Map<String, String>? extra}) {
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (config.deviceUuid.isNotEmpty) 'X-FV-Device': config.deviceUuid,
      if (auth && config.token.isNotEmpty) 'Authorization': 'Bearer ${config.token}',
    };
    if (extra != null) h.addAll(extra);
    return h;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${config.apiBase}/$path').replace(queryParameters: query);

  /// Testa se um endereço (base URL) responde como servidor do ERP.
  /// Usado na busca automática na rede e no IP digitado manualmente.
  static Future<bool> pingBase(String baseUrl, {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/forca-vendas/ping');
      final r = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
      if (r.statusCode != 200) return false;
      final body = jsonDecode(r.body);
      return body is Map && (body['ok'] == true || body['server_time'] != null);
    } catch (_) {
      return false;
    }
  }

  Future<bool> ping() async {
    try {
      final r = await _http.get(_uri('ping'), headers: _headers()).timeout(timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Registra o aparelho no ERP (status "pendente" até o admin autorizar).
  Future<Map<String, dynamic>> registerDevice({
    String? deviceName,
    String platform = 'android',
    String appVersion = '1.0.0',
  }) async {
    final r = await _http
        .post(
          _uri('devices/register'),
          headers: _headers(),
          body: jsonEncode({
            'device_uuid': config.deviceUuid,
            'device_name': deviceName ?? config.deviceName,
            'platform': platform,
            'app_version': appVersion,
          }),
        )
        .timeout(timeout);
    return _decode(r);
  }

  /// Consulta o status de autorização do aparelho.
  Future<Map<String, dynamic>> deviceStatus() async {
    final r = await _http
        .get(_uri('devices/status', {'device_uuid': config.deviceUuid}), headers: _headers())
        .timeout(timeout);
    return _decode(r);
  }

  Future<Map<String, dynamic>> info() async {
    final r = await _http.get(_uri('info'), headers: _headers()).timeout(timeout);
    return _decode(r);
  }

  Future<List<dynamic>> usuarios(int empresaId) async {
    final r = await _http
        .get(_uri('users', {'empresa_id': '$empresaId'}), headers: _headers())
        .timeout(timeout);
    final data = _decode(r);
    return (data['users'] as List<dynamic>? ?? []);
  }

  Future<Map<String, dynamic>> login({
    required int empresaId,
    required int userId,
    required String senha,
    required String deviceUuid,
    String? deviceName,
  }) async {
    final r = await _http
        .post(
          _uri('auth/login'),
          headers: _headers(),
          body: jsonEncode({
            'empresa_id': empresaId,
            'user_id': userId,
            'senha': senha,
            'device_uuid': deviceUuid,
            'device_name': deviceName,
            'platform': 'android',
            'app_version': '1.0.0',
          }),
        )
        .timeout(timeout);
    return _decode(r);
  }

  Future<void> logout() async {
    try {
      await _http
          .post(_uri('auth/logout'), headers: _headers(auth: true))
          .timeout(timeout);
    } catch (_) {}
  }

  /// PULL com suporte a ETag (304 quando nada mudou).
  /// Retorna null quando o servidor responde 304.
  Future<Map<String, dynamic>?> pull({String? since, String? etag}) async {
    final r = await _http
        .get(
          _uri('sync/pull', since != null ? {'since': since} : null),
          headers: _headers(auth: true, extra: etag != null ? {'If-None-Match': etag} : null),
        )
        .timeout(const Duration(seconds: 40));
    if (r.statusCode == 304) return null;
    final data = _decode(r);
    data['_etag'] = r.headers['etag'];
    return data;
  }

  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> orders) async {
    final r = await _http
        .post(
          _uri('sync/push'),
          headers: _headers(auth: true),
          body: jsonEncode({'orders': orders}),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(r);
  }

  Map<String, dynamic> _decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return {};
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    String msg = 'Erro ${r.statusCode}';
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['message'] != null) msg = body['message'].toString();
    } catch (_) {}
    throw ApiException(msg, statusCode: r.statusCode);
  }
}
