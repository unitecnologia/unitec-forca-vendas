import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../documents/pedido_document_actions.dart';
import '../sync/sync_service.dart';
import '../ui/brand.dart';
import '../ui/format.dart';
import 'novo_pedido_screen.dart';

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
        'SELECT h.id, h.numero, h.total, h.data, h.status, c.nome_razao '
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
        'orcamento_id': h['id'],
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

  Future<void> _abrirOrcamento(Map<String, dynamic> p) async {
    var uuid = (p['uuid'] ?? '').toString();
    if (uuid.isEmpty) {
      final orcId = p['orcamento_id'];
      final id = orcId is int ? orcId : int.tryParse('$orcId');
      if (id == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este orçamento não tem detalhes no aparelho. Sincronize e tente de novo.',
            ),
          ),
        );
        return;
      }

      // Busca online os itens e grava no cache local.
      try {
        final api = context.read<AppState>().api;
        final data = await api.orcamentoDetalhe(id);
        uuid = (data['uuid'] ?? 'erp-orc-$id').toString();
        final mapped = SyncService.mapPedidoFvCacheRow({
          ...data,
          'uuid': uuid,
          'tipo': 'orcamento',
        });
        await _db.upsertPedidoFvCache(mapped);
        p = {...p, 'uuid': uuid};
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o orçamento online: $e')),
        );
        return;
      }
      if (!mounted) return;
    }

    final status = (p['status'] ?? '').toString();
    final escolha = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Brand.green.withValues(alpha: 0.12),
                  child: const Icon(Icons.shopping_cart_checkout_rounded, color: Brand.green),
                ),
                title: const Text('Transformar em pedido', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  status == 'cancelado'
                      ? 'Orçamento cancelado — não recomendado'
                      : 'Abre com os itens para salvar como pedido',
                ),
                onTap: () => Navigator.pop(ctx, 'pedido'),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Brand.blue.withValues(alpha: 0.12),
                  child: const Icon(Icons.edit_note_rounded, color: Brand.blue),
                ),
                title: const Text('Abrir orçamento', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Revisa e salva de novo como orçamento'),
                onTap: () => Navigator.pop(ctx, 'orcamento'),
              ),
              if (uuid.isNotEmpty)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Brand.blue.withValues(alpha: 0.08),
                    child: const Icon(Icons.picture_as_pdf_outlined, color: Brand.blue),
                  ),
                  title: const Text('PDF / imprimir'),
                  onTap: () => Navigator.pop(ctx, 'pdf'),
                ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || escolha == null) return;

    if (escolha == 'pdf') {
      _menuDocumentos(context, uuid);
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NovoPedidoScreen(
          documentoUuid: uuid,
          converterParaPedido: escolha == 'pedido',
          tipoInicial: escolha == 'pedido' ? 'pedido' : 'orcamento',
        ),
      ),
    );
    if (mounted) await _carregar();
  }

  void _menuDocumentos(BuildContext context, String uuid) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: Brand.blue),
              title: Text('Compartilhar PDF',
                  style: TextStyle(fontSize: 16 + Brand.textBump01cm, fontWeight: FontWeight.w500)),
              subtitle: Text('WhatsApp, e-mail, etc.',
                  style: TextStyle(fontSize: 14 + Brand.textBump01cm)),
              onTap: () {
                Navigator.pop(ctx);
                PedidoDocumentActions.compartilhar(context, uuid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined, color: Brand.blue),
              title: Text('Imprimir',
                  style: TextStyle(fontSize: 16 + Brand.textBump01cm, fontWeight: FontWeight.w500)),
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
    final ehOrcamento = widget.tipoFiltro == 'orcamento';
    final titulo = ehOrcamento ? 'Orçamentos' : 'Pedidos';
    final vazio = ehOrcamento
        ? 'Nenhum orçamento neste aparelho nem nos últimos 30 dias do ERP.\nToque em sincronizar após reinstalar o app.'
        : 'Nenhum pedido neste aparelho nem venda no histórico.';
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontSizeDelta: Brand.textBump01cm),
        primaryTextTheme: theme.primaryTextTheme.apply(fontSizeDelta: Brand.textBump01cm),
      ),
      child: Scaffold(
        backgroundColor: Brand.bg,
        appBar: AppBar(
          title: Text(titulo, style: TextStyle(fontSize: 20 + Brand.textBump01cm, fontWeight: FontWeight.w600)),
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        vazio,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14 + Brand.textBump01cm, color: Colors.black54),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _sincronizar,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _PedidoCard(
                        p: _rows[i],
                        ehOrcamento: ehOrcamento,
                        onTap: ehOrcamento ? () => _abrirOrcamento(_rows[i]) : null,
                        onMenuPdf: () {
                          final uuid = (_rows[i]['uuid'] ?? '').toString();
                          if (uuid.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Este pedido não possui dados para PDF. Sincronize novamente.'),
                              ),
                            );
                            return;
                          }
                          _menuDocumentos(context, uuid);
                        },
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _PedidoCard extends StatelessWidget {
  const _PedidoCard({
    required this.p,
    required this.ehOrcamento,
    this.onTap,
    required this.onMenuPdf,
  });

  final Map<String, dynamic> p;
  final bool ehOrcamento;
  final VoidCallback? onTap;
  final VoidCallback onMenuPdf;

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

  @override
  Widget build(BuildContext context) {
    final (cor, label, icon) = _status();
    final erro = (p['erro'] ?? '').toString();
    final uuid = (p['uuid'] ?? '').toString();
    final temPdf = uuid.isNotEmpty;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
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
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14 + Brand.textBump01cm),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            color: cor, fontWeight: FontWeight.w700, fontSize: 12 + Brand.textBump01cm)),
                  ),
                  if (temPdf) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'PDF / imprimir',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.more_vert, size: 20, color: Brand.blue),
                      onPressed: onMenuPdf,
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
                      style: TextStyle(color: Colors.black54, fontSize: 13 + Brand.textBump01cm),
                    ),
                  ),
                  Text(brMoney(p['total'] as num?),
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: Brand.blue, fontSize: 14 + Brand.textBump01cm)),
                ],
              ),
              if (ehOrcamento && onTap != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Toque para abrir / transformar em pedido',
                  style: TextStyle(
                    fontSize: 11.5 + Brand.textBump01cm,
                    color: Brand.blue.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (erro.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(erro, style: TextStyle(color: Colors.red, fontSize: 12 + Brand.textBump01cm)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
