import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../log/app_log.dart';
import 'api_client.dart';

/// Consulta CNPJ com fallback direto nas APIs públicas.
///
/// No Wi‑Fi o app costuma usar o ERP local; em 4G/5G o ERP (LAN) pode ficar
/// inacessível e a tela “girava” até o timeout. Aqui tentamos o ERP rápido e,
/// se falhar, consultamos BrasilAPI/OpenCNPJ direto do aparelho.
class CnpjLookup {
  CnpjLookup(this.api, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final ApiClient api;
  final http.Client _http;

  static const Duration erpTimeout = Duration(seconds: 12);
  static const Duration publicTimeout = Duration(seconds: 12);

  Future<Map<String, dynamic>> lookup(String cnpjDigits) async {
    final digits = cnpjDigits.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 14) {
      throw ApiException('Informe um CNPJ completo com 14 dígitos.');
    }

    try {
      final fromErp = await api.lookupCnpj(digits).timeout(erpTimeout);
      if ((fromErp['nome_razao'] ?? '').toString().trim().isNotEmpty) {
        return fromErp;
      }
    } on TimeoutException {
      AppLog.instance.warn('cnpj', 'ERP demorou demais; tentando API pública.');
    } on ApiException catch (e) {
      AppLog.instance.warn('cnpj', 'ERP: ${e.message}; tentando API pública.');
    } catch (e) {
      AppLog.instance.warn('cnpj', 'ERP indisponível ($e); tentando API pública.');
    }

    final fromPublic = await _lookupPublic(digits);
    if ((fromPublic['nome_razao'] ?? '').toString().trim().isEmpty) {
      throw ApiException(
        'Não foi possível consultar o CNPJ. Verifique a internet (4G/Wi‑Fi) e tente de novo.',
      );
    }
    return fromPublic;
  }

  Future<Map<String, dynamic>> _lookupPublic(String digits) async {
    final brasil = await _fetchBrasilApi(digits);
    if ((brasil['nome_razao'] ?? '').toString().trim().isNotEmpty) {
      return brasil;
    }
    return _fetchOpenCnpj(digits);
  }

  Future<Map<String, dynamic>> _fetchBrasilApi(String digits) async {
    try {
      final r = await _http
          .get(
            Uri.parse('https://brasilapi.com.br/api/cnpj/v1/$digits'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(publicTimeout);
      if (r.statusCode == 404 || r.statusCode >= 400) return {};
      final data = jsonDecode(r.body);
      if (data is! Map) return {};
      return _mapBrasilApi(Map<String, dynamic>.from(data));
    } catch (e) {
      AppLog.instance.warn('cnpj', 'BrasilAPI falhou: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> _fetchOpenCnpj(String digits) async {
    try {
      final r = await _http
          .get(
            Uri.parse('https://api.opencnpj.org/$digits'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(publicTimeout);
      if (r.statusCode == 404 || r.statusCode >= 400) return {};
      final data = jsonDecode(r.body);
      if (data is! Map) return {};
      return _mapOpenCnpj(Map<String, dynamic>.from(data));
    } catch (e) {
      AppLog.instance.warn('cnpj', 'OpenCNPJ falhou: $e');
      return {};
    }
  }

  Map<String, dynamic> _mapBrasilApi(Map<String, dynamic> data) {
    final tipo = (data['descricao_tipo_de_logradouro'] ?? '').toString().trim();
    final log = (data['logradouro'] ?? '').toString().trim();
    final endereco = [tipo, log].where((e) => e.isNotEmpty).join(' ');

    final out = <String, dynamic>{
      'cpf_cnpj': _fmtCnpj(digitsOr(data['cnpj'])),
      'nome_razao': _up(data['razao_social']),
      'apelido_fantasia': _up(data['nome_fantasia']),
      'cep': _fmtCep(digitsOr(data['cep'])),
      'endereco': _up(endereco),
      'numero': (data['numero'] ?? '').toString().trim(),
      'bairro': _up(data['bairro']),
      'cidade_nome': _up(data['municipio']),
      'uf': _up(data['uf']),
      'email': (data['email'] ?? '').toString().trim().toLowerCase(),
      'fone1': _fmtPhone(data['ddd_telefone_1']),
      'fone2': _fmtPhone(data['ddd_telefone_2']),
      'rg_ie': _extractIe(data),
    };
    out.removeWhere((_, v) => v == null || (v is String && v.trim().isEmpty));
    return out;
  }

  Map<String, dynamic> _mapOpenCnpj(Map<String, dynamic> data) {
    final tipo = (data['tipo_logradouro'] ?? '').toString().trim();
    final log = (data['logradouro'] ?? '').toString().trim();
    final endereco = [tipo, log].where((e) => e.isNotEmpty).join(' ');

    String? fone1;
    String? fone2;
    final telefones = data['telefones'];
    if (telefones is List) {
      final phones = telefones
          .whereType<Map>()
          .where((p) => p['is_fax'] != true)
          .map((p) => _fmtPhoneParts(p['ddd']?.toString(), p['numero']?.toString()))
          .whereType<String>()
          .toList();
      if (phones.isNotEmpty) fone1 = phones[0];
      if (phones.length > 1) fone2 = phones[1];
    }

    final out = <String, dynamic>{
      'cpf_cnpj': _fmtCnpj(digitsOr(data['cnpj'])),
      'nome_razao': _up(data['razao_social']),
      'apelido_fantasia': _up(data['nome_fantasia']),
      'cep': _fmtCep(digitsOr(data['cep'])),
      'endereco': _up(endereco),
      'numero': (data['numero'] ?? '').toString().trim(),
      'bairro': _up(data['bairro']),
      'cidade_nome': _up(data['municipio']),
      'uf': _up(data['uf']),
      'email': (data['email'] ?? '').toString().trim().toLowerCase(),
      'fone1': fone1,
      'fone2': fone2,
    };
    out.removeWhere((_, v) => v == null || (v is String && v.trim().isEmpty));
    return out;
  }

  String? _extractIe(Map<String, dynamic> data) {
    for (final key in ['inscricao_estadual', 'inscricao_estadual_1', 'rg_ie']) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v.toUpperCase();
    }
    return null;
  }

  String digitsOr(dynamic v) => (v ?? '').toString().replaceAll(RegExp(r'\D'), '');

  String _up(dynamic v) => (v ?? '').toString().trim().toUpperCase();

  String? _fmtCnpj(String d) {
    if (d.length != 14) return d.isEmpty ? null : d;
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12)}';
  }

  String? _fmtCep(String d) {
    if (d.length != 8) return d.isEmpty ? null : d;
    return '${d.substring(0, 5)}-${d.substring(5)}';
  }

  String? _fmtPhone(dynamic raw) {
    final d = digitsOr(raw);
    if (d.length < 10) return null;
    return d;
  }

  String? _fmtPhoneParts(String? ddd, String? numero) {
    final d = digitsOr('$ddd$numero');
    if (d.length < 10) return null;
    return d;
  }
}
