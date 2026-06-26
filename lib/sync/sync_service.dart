import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../db/local_db.dart';

enum SyncStatus { idle, syncing, ok, offline, error }

/// Serviço de sincronização offline-first.
/// A cada ~30s (com jitter) faz PULL (delta + ETag) e PUSH (fila de pedidos).
class SyncService extends ChangeNotifier {
  SyncService(this.config, this.api);

  final AppConfig config;
  final ApiClient api;
  final LocalDb _db = LocalDb.instance;

  Timer? _timer;
  SyncStatus status = SyncStatus.idle;
  String? lastError;
  DateTime? lastSyncAt;
  int pendingCount = 0;

  void start() {
    stop();
    // Primeira sync imediata, depois a cada 30s + jitter (0-5s) para os
    // aparelhos não baterem no servidor no mesmo instante.
    syncNow();
    _scheduleNext();
  }

  void _scheduleNext() {
    final jitter = Duration(milliseconds: Random().nextInt(5000));
    _timer = Timer(const Duration(seconds: 30) + jitter, () async {
      await syncNow();
      _scheduleNext();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> syncNow() async {
    if (!config.isLoggedIn) return;
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      await _push();
      await _pull();
      pendingCount = await _db.pendingCount();
      lastSyncAt = DateTime.now();
      config.lastSyncIso = lastSyncAt!.toUtc().toIso8601String();
      await config.save();
      status = SyncStatus.ok;
      lastError = null;
    } on ApiException catch (e) {
      status = SyncStatus.error;
      lastError = e.message;
    } catch (e) {
      status = SyncStatus.offline;
      lastError = e.toString();
    }
    notifyListeners();
  }

  Future<void> _pull() async {
    final etag = await _db.getMeta('pull_etag');
    final data = await api.pull(etag: etag);
    if (data == null) return; // 304 — nada mudou

    await _db.upsertAll('products', data['products'] ?? [], (r) => {
          'id': r['id'],
          'codigo': r['codigo'],
          'codigo_barras': r['codigo_barras'],
          'descricao': r['descricao'],
          'unidade': r['unidade'],
          'marca': r['marca'],
          'grupo': r['grupo'],
          'preco_venda': _d(r['preco_venda']),
          'preco_venda_prazo': _d(r['preco_venda_prazo']),
          'preco_atacado': _d(r['preco_atacado']),
          'qtd_atacado': _d(r['qtd_atacado']),
          'estoque': _d(r['estoque']),
          'usa_tab_preco': _b(r['usa_tab_preco']),
          'mostrar_no_app': _b(r['mostrar_no_app']),
          'promo_preco_venda': _d(r['promo_preco_venda']),
          'foto_url': r['foto_url'],
          'ativo': _b(r['ativo']),
          'updated_at': r['updated_at'],
        });

    await _db.upsertAll('customers', data['customers'] ?? [], (r) => {
          'id': r['id'],
          'codigo': r['codigo'],
          'nome_razao': r['nome_razao'],
          'apelido_fantasia': r['apelido_fantasia'],
          'cpf_cnpj': r['cpf_cnpj'],
          'endereco': r['endereco'],
          'numero': r['numero'],
          'bairro': r['bairro'],
          'cidade_nome': r['cidade_nome'],
          'uf': r['uf'],
          'cep': r['cep'],
          'email': r['email'],
          'fone1': r['fone1'],
          'celular1': r['celular1'],
          'whatsapp': r['whatsapp'],
          'limite_credito': _d(r['limite_credito']),
          'dia_pgto': r['dia_pgto'],
          'ativo': _b(r['ativo']),
          'updated_at': r['updated_at'],
        });

    await _db.upsertAll('price_tables', data['price_tables'] ?? [], (r) => {
          'id': r['id'], 'codigo': r['codigo'], 'descricao': r['descricao'],
          'ativo': _b(r['ativo']), 'updated_at': r['updated_at'],
        });
    await _db.upsertAll('price_table_items', data['price_table_items'] ?? [], (r) => {
          'id': r['id'], 'product_id': r['product_id'], 'price_table_id': r['price_table_id'],
          'valor': _d(r['valor']), 'fator': _d(r['fator']), 'updated_at': r['updated_at'],
        });
    await _db.upsertAll('vendedores', data['vendedores'] ?? [], (r) => {
          'id': r['id'], 'codigo': r['codigo'], 'nome': r['nome'], 'ativo': _b(r['ativo']),
        });
    await _db.upsertAll('financeiro', data['financeiro'] ?? [], (r) => {
          'id': r['id'], 'numero': r['numero'], 'documento': r['documento'],
          'cliente_id': r['cliente_id'], 'emissao': r['emissao'], 'vencimento': r['vencimento'],
          'valor': _d(r['valor']), 'saldo': _d(r['saldo']), 'forma': r['forma'],
        });
    await _db.upsertAll('historico_vendas', data['historico_vendas'] ?? [], (r) => {
          'id': r['id'], 'numero': r['numero'], 'data': r['data'], 'cliente_id': r['cliente_id'],
          'total': _d(r['total']), 'status': r['status'], 'tipo': r['tipo'],
        });

    if (data['_etag'] != null) {
      await _db.setMeta('pull_etag', data['_etag'] as String);
    }
  }

  Future<void> _push() async {
    final pending = await _db.pendingOrders();
    if (pending.isEmpty) return;

    final orders = pending.map((o) {
      final itens = (o['itens_json'] as String?) ?? '[]';
      return <String, dynamic>{
        'uuid': o['uuid'],
        'tipo': o['tipo'] ?? 'orcamento',
        'cliente_id': o['cliente_id'],
        'observacoes': o['observacoes'],
        'desconto_valor': o['desconto_valor'] ?? 0,
        'latitude': o['latitude'],
        'longitude': o['longitude'],
        'created_at': o['created_at'],
        'device_uuid': config.deviceUuid,
        'itens': _parseItens(itens),
      };
    }).toList();

    final resp = await api.push(orders);
    final results = (resp['results'] as List<dynamic>? ?? []);
    for (final res in results) {
      final m = Map<String, dynamic>.from(res as Map);
      final uuid = m['uuid']?.toString();
      if (uuid == null) continue;
      if (m['status'] == 'importado') {
        await _db.markOrder(uuid, 'enviado', numero: m['numero']?.toString());
      } else if (m['status'] == 'erro') {
        await _db.markOrder(uuid, 'erro', erro: m['erro']?.toString());
      }
    }
  }

  static List<dynamic> _parseItens(String json) {
    try {
      if (json.trim().isEmpty) return [];
      final decoded = jsonDecode(json);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  static double _d(dynamic v) => v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
  static int _b(dynamic v) => (v == true || v == 1 || v == '1') ? 1 : 0;
}
