import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
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
  }

  Future<void> _carregar() async {
    final tipo = widget.tipoFiltro;
    final whereOutbox = tipo != null ? 'WHERE o.tipo = ?' : '';
    final whereHist = tipo != null ? 'WHERE h.tipo = ?' : '';
    final args = tipo != null ? [tipo] : <Object?>[];

    // Pedidos lançados neste aparelho (outbox).
    final outbox = await _db.query(
      'SELECT o.uuid, o.numero, o.total, o.status, o.erro, o.created_at, c.nome_razao '
      'FROM outbox_orders o LEFT JOIN customers c ON c.id = o.cliente_id '
      '$whereOutbox ORDER BY o.created_at DESC LIMIT 300',
      args,
    );

    // Histórico de vendas do vendedor logado (vindo do ERP). Sobrevive a
    // reinstalação porque é baixado a cada sync completo.
    final historico = await _db.query(
      'SELECT h.numero, h.total, h.data, c.nome_razao '
      'FROM historico_vendas h LEFT JOIN customers c ON c.id = h.cliente_id '
      '$whereHist ORDER BY h.data DESC LIMIT 500',
      args,
    );

    final numerosOutbox = <String>{
      for (final o in outbox)
        if ((o['numero'] ?? '').toString().isNotEmpty) (o['numero']).toString(),
    };

    final unified = <Map<String, dynamic>>[];
    for (final o in outbox) {
      unified.add({
        'fonte': 'outbox',
        'nome_razao': o['nome_razao'],
        'numero': o['numero'],
        'total': o['total'],
        'status': o['status'],
        'erro': o['erro'],
        'created_at': o['created_at'],
      });
    }
    for (final h in historico) {
      final numero = (h['numero'] ?? '').toString();
      // Evita duplicar uma venda que também está no outbox (já enviada).
      if (numero.isNotEmpty && numerosOutbox.contains(numero)) continue;
      unified.add({
        'fonte': 'erp',
        'nome_razao': h['nome_razao'],
        'numero': h['numero'],
        'total': h['total'],
        'status': 'faturado',
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

  Future<void> _sincronizar() async {
    await context.read<AppState>().sync.syncNow();
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final ehOrcamento = widget.tipoFiltro == 'orcamento';
    final titulo = ehOrcamento ? 'Orçamentos' : 'Pedidos';
    final vazio = ehOrcamento
        ? 'Nenhum orçamento feito no app ainda.'
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
                    itemBuilder: (_, i) => _PedidoCard(p: _rows[i]),
                  ),
                ),
    );
  }
}

class _PedidoCard extends StatelessWidget {
  const _PedidoCard({required this.p});

  final Map<String, dynamic> p;

  (Color, String, IconData) _status() {
    switch ((p['status'] ?? '').toString()) {
      case 'enviado':
        return (Brand.green, 'Enviado', Icons.cloud_done_outlined);
      case 'erro':
        return (Colors.red, 'Erro', Icons.error_outline);
      case 'faturado':
        return (Brand.blue, 'ERP', Icons.receipt_long_outlined);
      default:
        return (Colors.orange, 'Pendente', Icons.cloud_upload_outlined);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (cor, label, icon) = _status();
    final numero = (p['numero'] ?? '').toString();
    final erro = (p['erro'] ?? '').toString();
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
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(numero.isEmpty ? brDate(p['created_at'] as String?) : 'Nº $numero  •  ${brDate(p['created_at'] as String?)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
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
