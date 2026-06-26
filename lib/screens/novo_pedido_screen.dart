import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../db/local_db.dart';

class _ItemPedido {
  _ItemPedido({
    required this.productId,
    required this.descricao,
    required this.quantidade,
    required this.precoUnitario,
    this.desconto = 0,
  });

  final int productId;
  final String descricao;
  double quantidade;
  double precoUnitario;
  double desconto;

  double get total => (quantidade * precoUnitario) - desconto;
}

class NovoPedidoScreen extends StatefulWidget {
  const NovoPedidoScreen({super.key});

  @override
  State<NovoPedidoScreen> createState() => _NovoPedidoScreenState();
}

class _NovoPedidoScreenState extends State<NovoPedidoScreen> {
  final _db = LocalDb.instance;
  Map<String, dynamic>? _cliente;
  final List<_ItemPedido> _itens = [];
  final _obs = TextEditingController();
  bool _salvando = false;

  double get _total => _itens.fold(0.0, (s, i) => s + i.total);

  Future<void> _selecionarCliente() async {
    final escolhido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscaSheet(tabela: 'customers', titulo: 'Selecionar cliente', campoNome: 'nome_razao'),
    );
    if (escolhido != null) setState(() => _cliente = escolhido);
  }

  Future<void> _adicionarItem() async {
    final produto = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscaSheet(tabela: 'products', titulo: 'Selecionar produto', campoNome: 'descricao'),
    );
    if (produto == null) return;
    setState(() {
      _itens.add(_ItemPedido(
        productId: produto['id'] as int,
        descricao: (produto['descricao'] ?? '').toString(),
        quantidade: 1,
        precoUnitario: (produto['preco_venda'] as num?)?.toDouble() ?? 0.0,
      ));
    });
  }

  Future<(double?, double?)> _coletarGps() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (null, null);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _salvar() async {
    if (_cliente == null || _itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um cliente e ao menos um item.')),
      );
      return;
    }
    setState(() => _salvando = true);

    final (lat, lng) = await _coletarGps();
    final uuid = const Uuid().v4();
    final itensJson = jsonEncode(_itens
        .map((i) => {
              'product_id': i.productId,
              'quantidade': i.quantidade,
              'preco_unitario': i.precoUnitario,
              'desconto': i.desconto,
              'descricao': i.descricao,
            })
        .toList());

    await _db.insertOutbox({
      'uuid': uuid,
      'cliente_id': _cliente!['id'],
      'tipo': 'orcamento',
      'observacoes': _obs.text,
      'desconto_valor': 0,
      'total': _total,
      'latitude': lat,
      'longitude': lng,
      'itens_json': itensJson,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'pendente',
      'erro': null,
      'numero': null,
    });

    if (!mounted) return;
    // Dispara sync (sobe agora se houver internet; senão fica na fila).
    context.read<AppState>().sync.syncNow();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pedido salvo. Será sincronizado automaticamente.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo pedido')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(_cliente == null
                        ? 'Selecionar cliente'
                        : (_cliente!['nome_razao'] ?? '').toString()),
                    subtitle: _cliente == null ? null : Text((_cliente!['cidade_nome'] ?? '').toString()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _selecionarCliente,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Itens', style: Theme.of(context).textTheme.titleMedium),
                    TextButton.icon(
                      onPressed: _adicionarItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar'),
                    ),
                  ],
                ),
                ..._itens.asMap().entries.map((e) => _ItemTile(
                      item: e.value,
                      onChanged: () => setState(() {}),
                      onRemove: () => setState(() => _itens.removeAt(e.key)),
                    )),
                const SizedBox(height: 12),
                TextField(
                  controller: _obs,
                  decoration: const InputDecoration(labelText: 'Observações', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Total: R\$ ${_total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  FilledButton(
                    onPressed: _salvando ? null : _salvar,
                    child: _salvando
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Salvar pedido'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onChanged, required this.onRemove});

  final _ItemPedido item;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(item.descricao, maxLines: 2, overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: onRemove),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _NumField(
                    label: 'Qtd',
                    value: item.quantidade,
                    onChanged: (v) {
                      item.quantidade = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumField(
                    label: 'Preço',
                    value: item.precoUnitario,
                    onChanged: (v) {
                      item.precoUnitario = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('R\$ ${item.total.toStringAsFixed(2)}',
                      textAlign: TextAlign.end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (s) => onChanged(double.tryParse(s.replaceAll(',', '.')) ?? 0),
    );
  }
}

/// Sheet de busca genérica em uma tabela local (clientes/produtos).
class _BuscaSheet extends StatefulWidget {
  const _BuscaSheet({required this.tabela, required this.titulo, required this.campoNome});

  final String tabela;
  final String titulo;
  final String campoNome;

  @override
  State<_BuscaSheet> createState() => _BuscaSheetState();
}

class _BuscaSheetState extends State<_BuscaSheet> {
  final _db = LocalDb.instance;
  List<Map<String, dynamic>> _rows = [];
  String _termo = '';

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    final like = '%$_termo%';
    final rows = await _db.query(
      'SELECT * FROM ${widget.tabela} WHERE ${widget.campoNome} LIKE ? OR codigo LIKE ? ORDER BY ${widget.campoNome} LIMIT 60',
      [like, like],
    );
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.titulo,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (s) {
                  _termo = s;
                  _buscar();
                },
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: _rows.length,
                itemBuilder: (_, i) {
                  final r = _rows[i];
                  return ListTile(
                    title: Text((r[widget.campoNome] ?? '').toString()),
                    subtitle: Text('Cód. ${r['codigo'] ?? ''}'),
                    onTap: () => Navigator.pop(context, r),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
