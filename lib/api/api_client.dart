import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../config.dart';
import '../log/app_log.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Resultado detalhado de um teste de conexão (para a tela de diagnóstico).
class PingResult {
  PingResult({required this.ok, required this.message, this.ms, this.serverTime});

  final bool ok;
  final String message;
  final int? ms;
  final String? serverTime;
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
    final r = await pingDetailed(baseUrl, timeout: timeout);
    return r.ok;
  }

  /// Versão detalhada do ping: retorna motivo do erro e latência (diagnóstico).
  static Future<PingResult> pingDetailed(String baseUrl, {Duration timeout = const Duration(seconds: 5)}) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse('$baseUrl/api/v1/forca-vendas/ping');
      final r = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
      sw.stop();
      if (r.statusCode != 200) {
        return PingResult(ok: false, message: 'Respondeu HTTP ${r.statusCode}', ms: sw.elapsedMilliseconds);
      }
      final body = jsonDecode(r.body);
      final okBody = body is Map && (body['ok'] == true || body['server_time'] != null);
      return PingResult(
        ok: okBody,
        message: okBody ? 'OK' : 'Resposta inesperada do servidor',
        ms: sw.elapsedMilliseconds,
        serverTime: body is Map ? body['server_time']?.toString() : null,
      );
    } on TimeoutException {
      sw.stop();
      return PingResult(ok: false, message: 'Tempo esgotado (servidor não respondeu)', ms: sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      return PingResult(ok: false, message: _friendlyError(e), ms: sw.elapsedMilliseconds);
    }
  }

  static String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('refused')) {
      return 'Conexão recusada (o servidor não está ouvindo nessa porta)';
    }
    if (s.contains('unreachable') || s.contains('no route') || s.contains('host lookup')) {
      return 'Sem rota até o servidor (rede diferente ou IP errado?)';
    }
    if (s.contains('timed out') || s.contains('timeout')) {
      return 'Tempo esgotado (servidor não respondeu)';
    }
    return e.toString();
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
    String appVersion = kAppVersion,
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
            'app_version': kAppVersion,
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

  Future<Map<String, dynamic>> push(
    List<Map<String, dynamic>> orders, {
    List<Map<String, dynamic>> customers = const [],
    List<Map<String, dynamic>> visitasSemVenda = const [],
  }) async {
    final r = await _http
        .post(
          _uri('sync/push'),
          headers: _headers(auth: true),
          body: jsonEncode({
            'customers': customers,
            'orders': orders,
            'visitas_sem_venda': visitasSemVenda,
          }),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(r);
  }

  /// Cria uma cobrança Pix. origem: 'pedido' (ref = uuid, exige valor) ou
  /// 'titulo' (ref = id da conta a receber).
  Future<Map<String, dynamic>> criarPix({
    required String origem,
    required String ref,
    double? valor,
    String? payerEmail,
  }) async {
    final r = await _http
        .post(
          _uri('pix'),
          headers: _headers(auth: true),
          body: jsonEncode({
            'origem': origem,
            'ref': ref,
            if (valor != null) 'valor': valor,
            if (payerEmail != null && payerEmail.isNotEmpty) 'payer_email': payerEmail,
          }),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(r);
  }

  /// Consulta o status de uma cobrança Pix (usado no polling).
  Future<Map<String, dynamic>> pixStatus(int cobrancaId) async {
    final r = await _http
        .get(_uri('pix/$cobrancaId/status'), headers: _headers(auth: true))
        .timeout(timeout);
    return _decode(r);
  }

  Future<Map<String, dynamic>> cancelarPix(int cobrancaId) async {
    final r = await _http
        .post(_uri('pix/$cobrancaId/cancelar'), headers: _headers(auth: true))
        .timeout(timeout);
    return _decode(r);
  }

  /// Consulta CNPJ no ERP (mesma base do cadastro de pessoas) e retorna os campos preenchíveis.
  Future<Map<String, dynamic>> lookupCnpj(String cnpjDigits) async {
    final digits = cnpjDigits.replaceAll(RegExp(r'\D'), '');
    final r = await _http
        .get(_uri('cnpj/$digits'), headers: _headers(auth: true))
        .timeout(const Duration(seconds: 12));
    final data = _decode(r);
    return (data['data'] as Map<String, dynamic>? ?? {});
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
    AppLog.instance.error('api', '${r.request?.url.path ?? ''} → HTTP ${r.statusCode}: $msg');
    throw ApiException(msg, statusCode: r.statusCode);
  }
}
