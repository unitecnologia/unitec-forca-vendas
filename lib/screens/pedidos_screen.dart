import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../documents/pedido_document_actions.dart';
import '../ui/brand.dart';
import '../ui/format.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key, this.tipoFiltro});

  /// Quando definido (ex.: 'orcamento'), lista apenas os registros desse tipo.
  final String? tipoFiltro;

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  final _db = LocalDb.instance;
  List<Map<String, dynamic>> _rows = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizar());
  }

  Future<void> _carregar() async {
    final tipo = widget.tipoFiltro;
    final ehOrcamento = tipo == 'orcamento';
    final whereOutbox = tipo != null ? 'WHERE o.tipo = ?' : '';
    final args = tipo != null ? [tipo] : <Object?>[];

    final outbox = await _db.query(
      'SELECT o.uuid, o.numero, o.numero_pedido, o.total, o.status, o.erro, o.created_at, c.nome_razao '
      'FROM outbox_orders o LEFT JOIN customers c ON c.id = o.cliente_id '
      '$whereOutbox ORDER BY o.created_at DESC LIMIT 300',
      args,
    );

    final List<Map<String, dynamic>> pedidosFvCache;
    if (ehOrcamento) {
      pedidosFvCache = await _db.query(
        'SELECT p.uuid, p.numero, p.numero_pedido, p.total, p.status, p.situacao, p.created_at, c.nome_razao '
        'FROM pedidos_fv_cache p LEFT JOIN customers c ON c.id = p.cliente_id '
        "WHERE p.tipo = 'orcamento' ORDER BY p.created_at DESC LIMIT 500",
      );
    } else {
      pedidosFvCache = await _db.query(
        'SELECT p.uuid, p.numero, p.numero_pedido, p.total, p.status, p.situacao, p.created_at, c.nome_razao '
        'FROM pedidos_fv_cache p LEFT JOIN customers c ON c.id = p.cliente_id '
        "WHERE p.tipo IS NULL OR p.tipo = 'pedido' ORDER BY p.created_at DESC LIMIT 500",
      );
    }

    final List<Map<String, dynamic>> historico;
    if (ehOrcamento) {
      historico = await _db.query(
        'SELECT h.numero, h.total, h.data, h.status, c.nome_razao '
        'FROM historico_orcamentos h LEFT JOIN customers c ON c.id = h.cliente_id '
        'ORDER BY h.data DESC LIMIT 500',
      );
    } else {
      final whereHist = tipo != null ? 'WHERE h.tipo = ?' : '';
      historico = await _db.query(
        'SELECT h.numero, h.numero_orcamento, h.total, h.data, h.status, c.nome_razao '
        'FROM historico_vendas h LEFT JOIN customers c ON c.id = h.cliente_id '
        '$whereHist ORDER BY h.data DESC LIMIT 500',
        args,
      );
    }

    final chavesOutbox = <String>{
      for (final o in outbox) _chaveDedup(o['numero'], o['numero_pedido']),
    };
    final uuidsOutbox = <String>{
      for (final o in outbox)
        if ((o['uuid'] ?? '').toString().isNotEmpty) (o['uuid']).toString(),
    };

    final unified = <Map<String, dynamic>>[];
    for (final o in outbox) {
      unified.add({
        'fonte': 'outbox',
        'uuid': o['uuid'],
        'nome_razao': o['nome_razao'],
        'numero': o['numero'],
        'numero_pedido': o['numero_pedido'],
        'total': o['total'],
        'status': o['status'],
        'erro': o['erro'],
        'created_at': o['created_at'],
      });
    }
    for (final p in pedidosFvCache) {
      final uuid = (p['uuid'] ?? '').toString();
      if (uuid.isNotEmpty && uuidsOutbox.contains(uuid)) continue;
      final chave = _chaveDedup(p['numero'], p['numero_pedido']);
      if (chave.isNotEmpty && chavesOutbox.contains(chave)) continue;
      unified.add({
        'fonte': 'erp',
        'uuid': p['uuid'],
        'nome_razao': p['nome_razao'],
        'numero': p['numero'],
        'numero_pedido': p['numero_pedido'],
        'total': p['total'],
        'status': _statusFromPedidoFv(p),
        'erro': '',
        'created_at': p['created_at'],
      });
      if (chave.isNotEmpty) chavesOutbox.add(chave);
    }
    for (final h in historico) {
      final numeroPedido = ehOrcamento ? null : h['numero'];
      final numeroDav = ehOrcamento ? h['numero'] : h['numero_orcamento'];
      final chave = _chaveDedup(numeroDav, numeroPedido);
      if (chave.isNotEmpty && chavesOutbox.contains(chave)) continue;
      unified.add({
        'fonte': 'erp',
        'uuid': null,
        'nome_razao': h['nome_razao'],
        'numero': numeroDav,
        'numero_pedido': numeroPedido,
        'total': h['total'],
        'status': (h['status'] ?? 'erp').toString(),
        'erro': '',
        'created_at': h['data'],
      });
    }

    unified.sort((a, b) {
      final da = DateTime.tryParse((a['created_at'] ?? '').toString()) ?? DateTime(1900);
      final dbt = DateTime.tryParse((b['created_at'] ?? '').toString()) ?? DateTime(1900);
      return dbt.compareTo(da);
    });

    if (mounted) {
      setState(() {
        _rows = unified;
        _carregando = false;
      });
    }
  }

  static String _statusFromPedidoFv(Map<String, dynamic> p) {
    final situacao = (p['situacao'] ?? '').toString();
    if (situacao == 'faturado') return 'faturado';
    if (situacao == 'cancelado') return 'cancelado';
    final status = (p['status'] ?? '').toString();
    if (status == 'importado') return 'enviado';
    return status.isNotEmpty ? status : 'fechado';
  }

  static String _chaveDedup(Object? numeroDav, Object? numeroPedido) {
    final dav = (numeroDav ?? '').toString();
    final ped = (numeroPedido ?? '').toString();
    if (ped.isNotEmpty) return 'ped:$ped';
    if (dav.isNotEmpty) return 'dav:$dav';
    return '';
  }

  Future<void> _sincronizar() async {
    await context.read<AppState>().sync.syncNow();
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final ehOrcamento = widget.tipoFiltro == 'orcamento';
    final titulo = ehOrcamento ? 'Orçamentos' : 'Pedidos';
    final vazio = ehOrcamento
        ? 'Nenhum orçamento neste aparelho nem nos últimos 30 dias do ERP.\nToque em sincronizar após reinstalar o app.'
        : 'Nenhum pedido neste aparelho nem venda no histórico.';
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: Text(titulo),
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            icon: const Icon(Icons.sync),
            onPressed: _sincronizar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? Center(child: Text(vazio))
              : RefreshIndicator(
                  onRefresh: _sincronizar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _PedidoCard(p: _rows[i], ehOrcamento: ehOrcamento),
                  ),
                ),
    );
  }
}

class _PedidoCard extends StatelessWidget {
  const _PedidoCard({required this.p, required this.ehOrcamento});

  final Map<String, dynamic> p;
  final bool ehOrcamento;

  (Color, String, IconData) _status() {
    switch ((p['status'] ?? '').toString()) {
      case 'enviado':
        return (Brand.green, 'Enviado', Icons.cloud_done_outlined);
      case 'erro':
        return (Colors.red, 'Erro', Icons.error_outline);
      case 'faturado':
        return (Brand.blue, 'Faturado', Icons.receipt_long_outlined);
      case 'aberto':
        return (Brand.blue, 'Aberto', Icons.description_outlined);
      case 'fechado':
        return (Brand.green, 'Fechado', Icons.check_circle_outline);
      case 'cancelado':
        return (Colors.red, 'Cancelado', Icons.cancel_outlined);
      case 'importado':
        return (const Color(0xFF00838F), 'Importado', Icons.cloud_download_outlined);
      default:
        return (Colors.orange, 'Pendente', Icons.cloud_upload_outlined);
    }
  }

  String _linhaNumeros() {
    final dav = (p['numero'] ?? '').toString();
    final pedido = (p['numero_pedido'] ?? '').toString();
    final data = brDate(p['created_at'] as String?);
    final partes = <String>[];
    if (dav.isNotEmpty) {
      partes.add(ehOrcamento ? 'Nº $dav' : 'DAV $dav');
    }
    if (!ehOrcamento && pedido.isNotEmpty) {
      partes.add('Ped. $pedido');
    }
    if (partes.isEmpty) return data;
    return '${partes.join('  •  ')}  •  $data';
  }

  void _menuDocumentos(BuildContext context) {
    final uuid = (p['uuid'] ?? '').toString();
    if (uuid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este pedido não possui dados para PDF. Sincronize novamente.')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: Brand.blue),
              title: const Text('Compartilhar PDF'),
              subtitle: const Text('WhatsApp, e-mail, etc.'),
              onTap: () {
                Navigator.pop(ctx);
                PedidoDocumentActions.compartilhar(context, uuid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined, color: Brand.blue),
              title: const Text('Imprimir'),
              onTap: () {
                Navigator.pop(ctx);
                PedidoDocumentActions.imprimir(context, uuid);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (cor, label, icon) = _status();
    final erro = (p['erro'] ?? '').toString();
    final uuid = (p['uuid'] ?? '').toString();
    final temPdf = uuid.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (p['nome_razao'] ?? 'Cliente').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(label, style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              if (temPdf) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'PDF / imprimir',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.more_vert, size: 20, color: Brand.blue),
                  onPressed: () => _menuDocumentos(context),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _linhaNumeros(),
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ),
              Text(brMoney(p['total'] as num?),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.blue)),
            ],
          ),
          if (erro.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(erro, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
