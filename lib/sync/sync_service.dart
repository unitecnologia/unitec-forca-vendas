import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../db/local_db.dart';
import '../log/app_log.dart';
import '../media/produto_foto_cache.dart';

enum SyncStatus { idle, syncing, ok, offline, error }

/// Serviço de sincronização offline-first.
/// A cada ~30s (com jitter) faz PULL (delta + ETag) e PUSH (fila de pedidos).
class SyncService extends ChangeNotifier {
  SyncService(this.config, this.api);

  final AppConfig config;
  final ApiClient api;
  final LocalDb _db = LocalDb.instance;

  Timer? _timer;
  Future<void>? _inFlight;
  SyncStatus status = SyncStatus.idle;
  String? lastError;
  DateTime? lastSyncAt;
  int pendingCount = 0;

  void start() {
    stop();
    _restoreLastSync();
    // Primeira sync imediata, depois a cada 30s + jitter (0-5s) para os
    // aparelhos não baterem no servidor no mesmo instante.
    syncNow();
    _scheduleNext();
  }

  void _restoreLastSync() {
    final iso = config.lastSyncIso;
    if (iso == null || iso.isEmpty) return;
    lastSyncAt = DateTime.tryParse(iso);
    if (lastSyncAt != null) {
      status = SyncStatus.ok;
    }
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
    if (_inFlight != null) return _inFlight!;
    _inFlight = _syncNowInternal();
    try {
      await _inFlight;
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _syncNowInternal() async {
    final prev = status;
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      await _push().timeout(const Duration(seconds: 45));
      await _pull().timeout(const Duration(seconds: 60));
      pendingCount = await _db.pendingCount();
      lastSyncAt = DateTime.now();
      config.lastSyncIso = lastSyncAt!.toUtc().toIso8601String();
      await config.save();
      status = SyncStatus.ok;
      lastError = null;
      if (prev != SyncStatus.ok) {
        AppLog.instance.ok('sync', 'Sincronizado (pendentes: $pendingCount)');
      }
      // Completa cache local das fotos (funciona offline depois).
      unawaited(_cacheProdutoFotos());
    } on TimeoutException {
      status = SyncStatus.offline;
      lastError = 'Tempo esgotado — tente novamente';
      AppLog.instance.warn('sync', 'Timeout na sincronização');
    } on ApiException catch (e) {
      status = SyncStatus.error;
      lastError = e.message;
      AppLog.instance.error('sync', 'Falha: ${e.message}');
    } catch (e) {
      status = SyncStatus.offline;
      lastError = e.toString();
      AppLog.instance.warn('sync', 'Offline: ${e.toString()}');
    }
    notifyListeners();
  }

  Future<void> _pull() async {
    final etag = await _db.getMeta('pull_etag');
    final data = await api.pull(etag: etag);
    if (data == null) return; // 304 — nada mudou

    // Pull completo (sem `since`): o servidor manda o conjunto inteiro de
    // títulos em aberto, então substituímos a tabela para que os já quitados
    // (que somem da lista) também sumam do app.
    final fullPull = data['since'] == null;

    final prod = (data['products'] as List?)?.length ?? 0;
    final cli = (data['customers'] as List?)?.length ?? 0;
    AppLog.instance.info('sync', 'Catálogo atualizado (produtos: $prod, clientes: $cli)');

    final meta = data['meta'];
    if (meta is Map) {
      final pixOn = meta['pix_api_habilitada'] == true;
      if (config.pixApiHabilitada != pixOn) {
        config.pixApiHabilitada = pixOn;
        await config.save();
        AppLog.instance.info('sync', 'API PIX ${pixOn ? 'habilitada' : 'desabilitada'} (meta do pull)');
      }
    }

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
          'preco_especial': _d(r['preco_especial']),
          'qtd_atacado': _d(r['qtd_atacado']),
          'estoque': _d(r['estoque']),
          'estoque_reservado': _d(r['estoque_reservado']),
          'estoque_disponivel': _d(r['estoque_disponivel'] ?? r['estoque']),
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
          'rg_ie': r['rg_ie'],
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
          'forma_pagamento_id': r['forma_pagamento_id'],
          'tabela_prazo_id': r['tabela_prazo_id'],
          'tabela_prazo_dias': r['tabela_prazo_dias'],
          'price_table_id': r['price_table_id'],
          'vendedor_fv_id': r['vendedor_fv_id'],
          'vendedor_loja_id': r['vendedor_loja_id'],
          'ativo': _b(r['ativo']),
          'updated_at': r['updated_at'],
        });

    // Rotas / dias de visita: substitui a lista da carteira a cada pull.
    if (data['visita_dias'] != null) {
      await _db.deleteAll('customer_visita_dias');
      await _db.upsertAll('customer_visita_dias', data['visita_dias'] ?? [], (r) => {
            'person_id': r['person_id'],
            'dia_semana': r['dia_semana'],
            'ordem': r['ordem'] ?? 1,
          });
    }

    // Formas de pagamento liberadas para o app: substitui a lista inteira para
    // refletir formas que deixaram de estar "Disponível Mobile".
    if (data['formas_pagamento'] != null) {
      await _db.deleteAll('formas_pagamento');
      await _db.upsertAll('formas_pagamento', data['formas_pagamento'] ?? [], (r) => {
            'id': r['id'],
            'codigo': r['codigo'],
            'descricao': r['descricao'],
            'tipo': r['tipo'],
            'nfce': _b(r['nfce']),
            'max_parcelas': r['max_parcelas'],
            'tabelas_json': jsonEncode(r['tabelas_prazo'] ?? []),
          });
    }

    // Transportadoras ativas: cache local para seleção offline no pedido.
    if (data['transportadoras'] != null) {
      await _db.ensureTransportadorasTable();
      await _db.deleteAll('transportadoras');
      await _db.upsertAll('transportadoras', data['transportadoras'] ?? [], (r) => {
            'id': r['id'],
            'codigo': (r['codigo'] ?? '').toString(),
            'nome': (r['nome'] ?? r['apelido'] ?? r['proprietario'] ?? '').toString(),
            'proprietario': (r['proprietario'] ?? '').toString(),
            'apelido': (r['apelido'] ?? '').toString(),
            'ativo': _b(r['ativo'] ?? true),
            'updated_at': r['updated_at'],
          });
    }

    // Grupos de produto (filtro na seleção de itens).
    if (data['grupos'] != null) {
      await _db.deleteAll('grupos');
      await _db.upsertAll('grupos', data['grupos'] ?? [], (r) => {
            'id': r['id'],
            'nome': r['nome'],
            'ativo': _b(r['ativo']),
            'mostrar_no_app': _b(r['mostrar_no_app'] ?? true),
            'updated_at': r['updated_at'],
          });
    }

    await _db.upsertAll('price_tables', data['price_tables'] ?? [], (r) => {
          'id': r['id'], 'codigo': r['codigo'], 'descricao': r['descricao'],
          'ativo': _b(r['ativo']), 'updated_at': r['updated_at'],
        });
    await _db.upsertAll('price_table_items', data['price_table_items'] ?? [], (r) => {
          'id': r['id'], 'product_id': r['product_id'], 'price_table_id': r['price_table_id'],
          'valor': _d(r['valor']), 'fator': _d(r['fator']), 'updated_at': r['updated_at'],
        });
    await _db.upsertAll('vendedores', data['vendedores'] ?? [], (r) => {
          'id': r['id'],
          'codigo': r['codigo'],
          'nome': r['nome'],
          'ativo': _b(r['ativo']),
          'tabela_venda_id': r['tabela_venda_id'],
        });
    if (fullPull) {
      await _db.deleteAll('financeiro');
    }
    await _db.upsertAll('financeiro', data['financeiro'] ?? [], (r) => {
          'id': r['id'], 'numero': r['numero'], 'documento': r['documento'],
          'cliente_id': r['cliente_id'], 'emissao': r['emissao'], 'vencimento': r['vencimento'],
          'valor': _d(r['valor']), 'saldo': _d(r['saldo']), 'forma': r['forma'],
        });
    if (fullPull) {
      await _db.deleteAll('historico_vendas');
      await _db.deleteAll('historico_orcamentos');
      await _db.deleteAll('pedidos_fv_cache');
    }
    await _db.upsertAll('historico_vendas', data['historico_vendas'] ?? [], (r) => {
          'id': r['id'], 'numero': r['numero'], 'numero_orcamento': r['numero_orcamento'],
          'data': r['data'], 'cliente_id': r['cliente_id'],
          'total': _d(r['total']), 'status': r['status'], 'tipo': r['tipo'],
        });
    await _db.upsertAll('historico_orcamentos', data['historico_orcamentos'] ?? [], (r) => {
          'id': r['id'], 'numero': r['numero'], 'data': r['data'], 'cliente_id': r['cliente_id'],
          'total': _d(r['total']), 'status': r['status'],
        });
    // Orçamentos do ERP com itens → cache local (abre / transforma em pedido).
    for (final row in (data['historico_orcamentos'] as List?) ?? const []) {
      final m = Map<String, dynamic>.from(row as Map);
      if ((m['uuid'] ?? '').toString().isEmpty) {
        final id = m['id'];
        if (id != null) m['uuid'] = 'erp-orc-$id';
      }
      m['tipo'] = 'orcamento';
      m['situacao'] = m['situacao'] ?? m['status'];
      await _db.upsertPedidoFvCache(_mapPedidoFvCacheRow(m));
    }

    for (final row in (data['pedidos_fv'] as List?) ?? const []) {
      final m = Map<String, dynamic>.from(row as Map);
      await _db.upsertPedidoFvCache(_mapPedidoFvCacheRow(m));
      await _db.applyPedidoFvSync(m);
    }

    if (data['_etag'] != null) {
      await _db.setMeta('pull_etag', data['_etag'] as String);
    }
  }

  Future<void> _cacheProdutoFotos() async {
    if (config.baseUrl.isEmpty) return;
    try {
      final rows = await _db.query(
        "SELECT id, foto_url FROM products WHERE IFNULL(foto_url, '') != ''",
      );
      if (rows.isEmpty) return;
      await ProdutoFotoCache.instance.syncAfterPull(
        baseUrl: config.baseUrl,
        products: rows,
      );
    } catch (e) {
      AppLog.instance.warn('sync', 'Cache de fotos: $e');
    }
  }

  Future<void> _push() async {
    final pendingCustomers = await _db.pendingCustomers();
    final pending = await _db.pendingOrders();
    final visitasPendentes = await _db.pendingVisitasSemVenda();

    if (pendingCustomers.isEmpty && pending.isEmpty && visitasPendentes.isEmpty) return;

    final customers = pendingCustomers.map((c) {
      final payload = _parseMap((c['payload_json'] as String?) ?? '');
      return <String, dynamic>{
        'uuid': c['uuid'],
        'local_id': c['local_id'],
        'device_uuid': config.deviceUuid,
        ...payload,
      };
    }).toList();

    if (customers.isNotEmpty) {
      AppLog.instance.info('sync', 'Enviando ${customers.length} cliente(s)...');
    }

    if (visitasPendentes.isNotEmpty) {
      AppLog.instance.info('sync', 'Enviando ${visitasPendentes.length} visita(s) sem venda...');
    }

    if (customers.isNotEmpty) {
      final customerResp = await api.push([], customers: customers);
      await _applyCustomerResults(customerResp, pendingCustomers);
    }

    final ordersAfterCustomers = await _db.pendingOrders();
    final visitasAfterCustomers = await _db.pendingVisitasSemVenda();

    if (ordersAfterCustomers.isEmpty && visitasAfterCustomers.isEmpty) return;

    final ordersPayload = ordersAfterCustomers.map((o) {
      final itens = (o['itens_json'] as String?) ?? '[]';
      final extra = _parseMap((o['extra_json'] as String?) ?? '');
      return <String, dynamic>{
        'uuid': o['uuid'],
        'tipo': o['tipo'] ?? 'orcamento',
        'cliente_id': o['cliente_id'],
        'observacoes': o['observacoes'],
        'desconto_valor': o['desconto_valor'] ?? 0,
        'percentual_desconto': extra['percentual_desconto'] ?? 0,
        'forma_pagamento': extra['forma_pagamento'],
        'forma_pagamento_id': extra['forma_pagamento_id'],
        'caixa_id': extra['caixa_id'],
        'caixa_nome': extra['caixa_nome'],
        'tabela_prazo_id': extra['tabela_prazo_id'],
        'tabela_prazo_dias': extra['tabela_prazo_dias'],
        'condicao_pagamento': extra['condicao_pagamento'],
        'price_table_id': extra['price_table_id'],
        'lista_preco_nome': extra['lista_preco_nome'],
        'frete': extra['frete'] ?? 0,
        'transportadora_id': extra['transportadora_id'],
        'transportadora_nome': extra['transportadora_nome'],
        'restricao_financeira': extra['restricao_financeira'] == true,
        'credito_liberado': extra['credito_liberado'] == true,
        'credito_titulos_vencidos': extra['credito_titulos_vencidos'] == true,
        'credito_titulos_vencidos_saldo': extra['credito_titulos_vencidos_saldo'],
        'credito_boleto_atrasado': extra['credito_boleto_atrasado'] == true,
        'credito_boleto_saldo': extra['credito_boleto_saldo'],
        'credito_limite_excedido': extra['credito_limite_excedido'] == true,
        'credito_limite': extra['credito_limite'],
        'credito_total_aberto': extra['credito_total_aberto'],
        'credito_disponivel': extra['credito_disponivel'],
        'credito_total_pedido': extra['credito_total_pedido'],
        'credito_aberto_apos_pedido': extra['credito_aberto_apos_pedido'],
        'credito_disponivel_apos_pedido': extra['credito_disponivel_apos_pedido'],
        'credito_cliente_em_debito': extra['credito_cliente_em_debito'] == true,
        'credito_motivo': extra['credito_motivo'],
        'latitude': o['latitude'],
        'longitude': o['longitude'],
        'created_at': o['created_at'],
        'device_uuid': config.deviceUuid,
        'itens': _parseItens(itens),
      };
    }).toList();

    final visitasPayload = visitasAfterCustomers
        .map((v) => <String, dynamic>{
              'uuid': v['uuid'],
              'cliente_id': v['cliente_id'],
              'motivo': v['motivo'],
              'latitude': v['latitude'],
              'longitude': v['longitude'],
              'created_at': v['created_at'],
              'device_uuid': config.deviceUuid,
            })
        .toList();

    if (ordersPayload.isNotEmpty) {
      AppLog.instance.info('sync', 'Enviando ${ordersPayload.length} pedido(s)...');
    }

    final resp = await api.push(ordersPayload, visitasSemVenda: visitasPayload);
    final results = (resp['results'] as List<dynamic>? ?? []);
    var enviados = 0;
    var comErro = 0;
    for (final res in results) {
      final m = Map<String, dynamic>.from(res as Map);
      final uuid = m['uuid']?.toString();
      if (uuid == null || uuid.isEmpty) continue;
      final st = (m['status'] ?? '').toString();
      // ERP confirma com "importado"; "duplicado" também significa que já está no servidor.
      if (st == 'importado' || m['duplicado'] == true) {
        final situacao = (m['situacao'] ?? '').toString();
        final localStatus = situacao == 'financeiro' ? 'financeiro' : 'enviado';
        await _db.markOrder(
          uuid,
          localStatus,
          numero: m['numero']?.toString(),
          numeroPedido: m['numero_pedido']?.toString(),
        );
        enviados++;
      } else if (st == 'erro') {
        await _db.markOrder(uuid, 'erro', erro: m['erro']?.toString());
        comErro++;
      }
    }
    if (comErro > 0) {
      AppLog.instance.warn('sync', 'Pedidos: $enviados enviado(s), $comErro com erro');
    } else if (enviados > 0) {
      AppLog.instance.ok('sync', 'Pedidos: $enviados enviado(s)');
    }

    final visitaResults = (resp['visita_results'] as List<dynamic>? ?? []);
    var visitasOk = 0;
    var visitasErro = 0;
    for (final res in visitaResults) {
      final m = Map<String, dynamic>.from(res as Map);
      final uuid = m['uuid']?.toString();
      if (uuid == null) continue;
      if (m['status'] == 'importado') {
        await _db.markVisitaSemVenda(uuid, 'enviado');
        visitasOk++;
      } else if (m['status'] == 'erro') {
        await _db.markVisitaSemVenda(uuid, 'erro', erro: m['erro']?.toString());
        visitasErro++;
      }
    }
    if (visitasErro > 0) {
      AppLog.instance.warn('sync', 'Visitas: $visitasOk enviada(s), $visitasErro com erro');
    } else if (visitasOk > 0) {
      AppLog.instance.ok('sync', 'Visitas: $visitasOk enviada(s)');
    }
  }

  Future<void> _applyCustomerResults(
    Map<String, dynamic> resp,
    List<Map<String, dynamic>> pendingCustomers,
  ) async {
    final customerResults = (resp['customer_results'] as List<dynamic>? ?? []);
    var clientesOk = 0;
    var clientesErro = 0;

    for (final res in customerResults) {
      final m = Map<String, dynamic>.from(res as Map);
      final uuid = m['uuid']?.toString();
      if (uuid == null) continue;

      if (m['status'] == 'importado') {
        final serverId = (m['person_id'] as num?)?.toInt();
        final localId = (m['local_id'] as num?)?.toInt();
        if (serverId != null && localId != null) {
          Map<String, dynamic>? outbox;
          for (final c in pendingCustomers) {
            if (c['uuid'] == uuid) {
              outbox = c;
              break;
            }
          }
          if (outbox != null) {
            final payload = _parseMap((outbox['payload_json'] as String?) ?? '');
            final row = Map<String, dynamic>.from(payload)
              ..['codigo'] = m['codigo']?.toString() ?? payload['codigo'] ?? '';
            await _db.remapCustomerId(localId, serverId, row);
          }
        }
        await _db.markCustomer(uuid, 'enviado', serverId: serverId);
        clientesOk++;
      } else if (m['status'] == 'erro') {
        await _db.markCustomer(uuid, 'erro', erro: m['erro']?.toString());
        clientesErro++;
      }
    }

    if (clientesErro > 0) {
      AppLog.instance.warn('sync', 'Clientes: $clientesOk enviado(s), $clientesErro com erro');
    } else if (clientesOk > 0) {
      AppLog.instance.ok('sync', 'Clientes: $clientesOk enviado(s)');
    }
  }

  static Map<String, dynamic> mapPedidoFvCacheRow(Map<String, dynamic> row) {
    final situacao = (row['situacao'] ?? '').toString();
    var status = (row['status'] ?? '').toString();
    if (situacao == 'faturado') {
      status = 'faturado';
    } else if (situacao == 'cancelado') {
      status = 'cancelado';
    } else if (situacao == 'financeiro') {
      status = 'financeiro';
    } else if (status == 'importado') {
      status = 'enviado';
    }

    final extra = <String, dynamic>{
      if (row['forma_pagamento'] != null) 'forma_pagamento': row['forma_pagamento'],
      if (row['condicao_pagamento'] != null) 'condicao_pagamento': row['condicao_pagamento'],
      if (row['percentual_desconto'] != null) 'percentual_desconto': row['percentual_desconto'],
    };

    return {
      'uuid': row['uuid'],
      'cliente_id': row['cliente_id'],
      'tipo': row['tipo'] ?? 'pedido',
      'numero': row['numero'],
      'numero_pedido': row['numero_pedido'],
      'total': _d(row['total']),
      'observacoes': row['observacoes'],
      'desconto_valor': _d(row['desconto_valor']),
      'itens_json': jsonEncode(row['itens'] ?? []),
      'extra_json': jsonEncode(extra),
      'created_at': row['created_at'] ?? row['data'],
      'status': status,
      'situacao': situacao,
    };
  }

  // Compatível com chamadas internas antigas.
  static Map<String, dynamic> _mapPedidoFvCacheRow(Map<String, dynamic> row) =>
      mapPedidoFvCacheRow(row);

  static List<dynamic> _parseItens(String json) {
    try {
      if (json.trim().isEmpty) return [];
      final decoded = jsonDecode(json);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _parseMap(String json) {
    try {
      if (json.trim().isEmpty) return {};
      final decoded = jsonDecode(json);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  static double _d(dynamic v) => v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
  static int _b(dynamic v) => (v == true || v == 1 || v == '1') ? 1 : 0;
}
