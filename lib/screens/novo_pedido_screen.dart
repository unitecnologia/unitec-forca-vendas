import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../ui/brand.dart';
import '../ui/format.dart';
import 'pedidos_screen.dart';

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

  double get bruto => quantidade * precoUnitario;
  double get total => bruto - desconto;
}

const List<String> _formasPagamento = [
  'Dinheiro',
  'Pix',
  'Boleto',
  'Cartão',
  'Crediário',
  'A prazo',
];

class NovoPedidoScreen extends StatefulWidget {
  const NovoPedidoScreen({super.key, this.clienteInicial});

  /// Cliente pré-selecionado (ex.: ao iniciar o pedido pela tela de Clientes).
  final Map<String, dynamic>? clienteInicial;

  @override
  State<NovoPedidoScreen> createState() => _NovoPedidoScreenState();
}

class _NovoPedidoScreenState extends State<NovoPedidoScreen> {
  final _db = LocalDb.instance;

  Map<String, dynamic>? _cliente;
  final List<_ItemPedido> _itens = [];
  final _obs = TextEditingController();
  final _condicao = TextEditingController();
  final _frete = TextEditingController(text: '0,00');
  final _descPct = TextEditingController(text: '0,00');
  final _descValor = TextEditingController(text: '0,00');

  String _tipo = 'pedido';
  String _forma = 'Boleto';
  Map<String, dynamic>? _listaPreco;
  List<Map<String, dynamic>> _listasPreco = [];
  bool _enviarNaSync = true;
  bool _salvando = false;
  bool _sincDesconto = false;

  @override
  void initState() {
    super.initState();
    _cliente = widget.clienteInicial;
    _carregarListasPreco();
  }

  @override
  void dispose() {
    _obs.dispose();
    _condicao.dispose();
    _frete.dispose();
    _descPct.dispose();
    _descValor.dispose();
    super.dispose();
  }

  Future<void> _carregarListasPreco() async {
    final rows = await _db.query('SELECT * FROM price_tables WHERE ativo = 1 ORDER BY descricao');
    if (mounted) setState(() => _listasPreco = rows);
  }

  // ---- Cálculos ----------------------------------------------------------
  double get _subtotalItens => _itens.fold(0.0, (s, i) => s + i.total);
  double get _brutoItens => _itens.fold(0.0, (s, i) => s + i.bruto);
  double get _descontoItens => _itens.fold(0.0, (s, i) => s + i.desconto);
  double get _freteValor => _parseNum(_frete.text);
  double get _descontoPedido => _parseNum(_descValor.text);
  double get _total => (_subtotalItens - _descontoPedido + _freteValor).clamp(0, double.infinity);

  double _parseNum(String s) =>
      double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;

  String _fmtInput(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  void _recalcDescontoDeValor() {
    if (_sincDesconto) return;
    _sincDesconto = true;
    final base = _subtotalItens;
    final pct = base > 0 ? (_descontoPedido / base * 100) : 0.0;
    _descPct.text = _fmtInput(pct);
    _sincDesconto = false;
    setState(() {});
  }

  void _recalcDescontoDePct() {
    if (_sincDesconto) return;
    _sincDesconto = true;
    final base = _subtotalItens;
    final pct = _parseNum(_descPct.text);
    _descValor.text = _fmtInput(base * pct / 100);
    _sincDesconto = false;
    setState(() {});
  }

  // ---- Ações -------------------------------------------------------------
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
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
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

    final extra = <String, dynamic>{
      'percentual_desconto': _parseNum(_descPct.text),
      'forma_pagamento': _forma,
      'condicao_pagamento': _condicao.text.trim(),
      'price_table_id': _listaPreco?['id'],
      'lista_preco_nome': _listaPreco?['descricao'],
      'frete': _freteValor,
    };

    await _db.insertOutbox({
      'uuid': uuid,
      'cliente_id': _cliente!['id'],
      'tipo': _tipo,
      'observacoes': _obs.text,
      'desconto_valor': _descontoPedido,
      'total': _total,
      'latitude': lat,
      'longitude': lng,
      'itens_json': itensJson,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'status': _enviarNaSync ? 'pendente' : 'rascunho',
      'erro': null,
      'numero': null,
      'extra_json': jsonEncode(extra),
    });

    if (!mounted) return;
    if (_enviarNaSync) {
      context.read<AppState>().sync.syncNow();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_enviarNaSync
          ? 'Pedido salvo. Será sincronizado automaticamente.'
          : 'Pedido salvo como rascunho (não será enviado).')),
    );

    // Após salvar, vai para a lista de pedidos.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PedidosScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Brand.bg,
        appBar: AppBar(
          title: const Text('Cadastro de Pedido'),
          backgroundColor: Brand.blue,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.assignment_outlined), text: 'Dados'),
              Tab(icon: Icon(Icons.list_alt_outlined), text: 'Itens'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Resumo'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _abaDados(),
            _abaItens(),
            _abaResumo(),
          ],
        ),
        bottomNavigationBar: _barraAcoes(),
      ),
    );
  }

  // ---- Aba 1: Dados ------------------------------------------------------
  Widget _abaDados() {
    final limite = (_cliente?['limite_credito'] as num?)?.toDouble();
    final endereco = _cliente == null
        ? null
        : [_cliente!['endereco'], _cliente!['numero'], _cliente!['bairro'], _cliente!['cidade_nome'], _cliente!['uf']]
            .where((e) => (e ?? '').toString().trim().isNotEmpty)
            .join(', ');
    final empresa = context.read<AppState>().config.empresaNome;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _enviarNaSync,
          onChanged: (v) => setState(() => _enviarNaSync = v),
          activeColor: Brand.green,
          title: const Text('Enviar pedido na próxima sincronização',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Desmarque para salvar como rascunho (não envia).'),
        ),
        _label('Número do Pedido'),
        _readonlyBox('(gerado no ERP ao sincronizar)'),
        _label('Tipo de Pedido *'),
        _dropdown<String>(
          value: _tipo,
          items: const {'pedido': '1 - Pedido', 'orcamento': '2 - Orçamento'},
          onChanged: (v) => setState(() => _tipo = v ?? 'pedido'),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _label('Cliente *'),
            if (limite != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text('Limite de crédito: ${brMoney(limite)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
          ],
        ),
        _selectorBox(
          texto: _cliente == null ? 'Selecionar cliente' : (_cliente!['nome_razao'] ?? '').toString(),
          icon: Icons.person_search_outlined,
          onTap: _selecionarCliente,
          destaque: _cliente != null,
        ),
        _label('Filial / Unidade'),
        _readonlyBox(empresa.isEmpty ? 'Empresa padrão' : empresa),
        _label('Lista de Preço'),
        _dropdown<int?>(
          value: _listaPreco?['id'] as int?,
          items: {
            for (final l in _listasPreco)
              (l['id'] as int): '${l['codigo'] ?? ''} - ${l['descricao'] ?? ''}'.trim()
          },
          hint: 'Padrão',
          onChanged: (id) => setState(() =>
              _listaPreco = _listasPreco.cast<Map<String, dynamic>?>().firstWhere(
                    (l) => l?['id'] == id,
                    orElse: () => null,
                  )),
        ),
        _label('Condição de Pagamento'),
        _campoTexto(_condicao, hint: 'Ex.: 30/60'),
        _label('Forma de Pagamento *'),
        _dropdown<String>(
          value: _forma,
          items: {for (final f in _formasPagamento) f: f},
          onChanged: (v) => setState(() => _forma = v ?? 'Boleto'),
        ),
        _label('Data de Emissão'),
        _readonlyBox(_dataHoraAgora()),
        _label('Endereço de entrega'),
        _readonlyBox((endereco == null || endereco.isEmpty) ? 'Selecione o cliente' : endereco),
        _label('Valor do Frete'),
        _campoTexto(_frete,
            teclado: const TextInputType.numberWithOptions(decimal: true),
            prefix: 'R\$ ',
            onChanged: (_) => setState(() {})),
      ],
    );
  }

  // ---- Aba 2: Itens ------------------------------------------------------
  Widget _abaItens() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              _resumoRow('Total de itens', '${_itens.length}'),
              _resumoRow('Valor dos produtos', brMoney(_subtotalItens)),
              _resumoRow('Frete', brMoney(_freteValor)),
              _resumoRow('Desconto', brMoney(_descontoPedido)),
              const Divider(),
              _resumoRow('Valor total', brMoney(_total), destaque: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _adicionarItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar Item'),
                  style: FilledButton.styleFrom(backgroundColor: Brand.blue),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _itens.isEmpty
              ? const Center(child: Text('Nenhum item adicionado.', style: TextStyle(color: Colors.black54)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: _itens.length,
                  itemBuilder: (_, i) => _ItemTile(
                    indice: i + 1,
                    item: _itens[i],
                    onChanged: () {
                      _recalcDescontoDePct();
                      setState(() {});
                    },
                    onRemove: () {
                      setState(() => _itens.removeAt(i));
                      _recalcDescontoDePct();
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ---- Aba 3: Resumo -----------------------------------------------------
  Widget _abaResumo() {
    final pctItens = _brutoItens > 0 ? (_descontoItens / _brutoItens * 100) : 0.0;
    final descTotal = _descontoItens + _descontoPedido;
    final pctTotal = _brutoItens > 0 ? (descTotal / _brutoItens * 100) : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _tituloSecao('Dados dos itens'),
        _resumoRow('Preço de tabela dos produtos', brMoney(_brutoItens)),
        _resumoRow('Desconto nos itens', '${brMoney(_descontoItens)} (${pctItens.toStringAsFixed(2)}%)'),
        _resumoRow('R\$ produtos com desconto', brMoney(_subtotalItens)),
        const SizedBox(height: 16),
        _tituloSecao('Desconto a nível de pedido'),
        Row(
          children: [
            Expanded(
              child: _campoTexto(_descPct,
                  label: 'Desconto (%)',
                  teclado: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _recalcDescontoDePct()),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _campoTexto(_descValor,
                  label: 'Desconto (R\$)',
                  teclado: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _recalcDescontoDeValor()),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _resumoRow('Descontos totais', '${brMoney(descTotal)} (${pctTotal.toStringAsFixed(2)}%)'),
        const SizedBox(height: 16),
        _tituloSecao('Totais do Pedido'),
        _resumoRow('Valor dos produtos', brMoney(_subtotalItens)),
        _resumoRow('Frete', brMoney(_freteValor)),
        const Divider(),
        _resumoRow('Valor total do pedido', brMoney(_total), destaque: true),
      ],
    );
  }

  // ---- Barra de ações ----------------------------------------------------
  Widget _barraAcoes() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 11, color: Colors.black54)),
                  Text(brMoney(_total),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.green)),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _salvando ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: _salvando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(_salvando ? 'Salvando...' : 'Salvar'),
              style: FilledButton.styleFrom(backgroundColor: Brand.green),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Widgets utilitários ----------------------------------------------
  String _dataHoraAgora() {
    final n = DateTime.now();
    String d(int v) => v.toString().padLeft(2, '0');
    return '${d(n.day)}/${d(n.month)}/${n.year} ${d(n.hour)}:${d(n.minute)}';
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF37474F))),
      );

  Widget _tituloSecao(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Brand.blue)),
      );

  Widget _readonlyBox(String texto) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF1F5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(texto, style: const TextStyle(color: Colors.black87)),
      );

  Widget _selectorBox({
    required String texto,
    required IconData icon,
    required VoidCallback onTap,
    bool destaque = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(texto,
                    style: TextStyle(
                        fontWeight: destaque ? FontWeight.w700 : FontWeight.w400,
                        color: destaque ? Colors.black87 : Colors.black54)),
              ),
              Icon(icon, color: Brand.blue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) {
    final values = items.keys.toList();
    final safeValue = values.contains(value) ? value : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: safeValue,
          isExpanded: true,
          hint: Text(hint ?? 'Selecione'),
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _campoTexto(
    TextEditingController c, {
    String? label,
    String? hint,
    String? prefix,
    TextInputType? teclado,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: c,
      keyboardType: teclado,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _resumoRow(String label, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: destaque ? FontWeight.w700 : FontWeight.w500,
                  fontSize: destaque ? 16 : 14)),
          Text(valor,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: destaque ? 17 : 14,
                  color: destaque ? Brand.green : const Color(0xFF263238))),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.indice, required this.item, required this.onChanged, required this.onRemove});

  final int indice;
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
                Text('$indice. ', style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.blue)),
                Expanded(child: Text(item.descricao, maxLines: 2, overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.delete_outline), color: Colors.redAccent, onPressed: onRemove),
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
                  child: _NumField(
                    label: 'Desc.',
                    value: item.desconto,
                    onChanged: (v) {
                      item.desconto = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Total do item: ${brMoney(item.total)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
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
