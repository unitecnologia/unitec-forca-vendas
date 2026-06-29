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
import 'pix_qr_screen.dart';

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

class NovoPedidoScreen extends StatefulWidget {
  const NovoPedidoScreen({super.key, this.clienteInicial, this.tipoInicial = 'pedido'});

  /// Cliente pré-selecionado (ex.: ao iniciar o pedido pela tela de Clientes).
  final Map<String, dynamic>? clienteInicial;

  /// Tipo do documento: 'pedido' (vai para o Monitor de Vendas e baixa estoque
  /// ao faturar) ou 'orcamento' (vai para Orçamentos recebidos, sem baixa).
  final String tipoInicial;

  @override
  State<NovoPedidoScreen> createState() => _NovoPedidoScreenState();
}

class _NovoPedidoScreenState extends State<NovoPedidoScreen>
    with SingleTickerProviderStateMixin {
  final _db = LocalDb.instance;

  late final TabController _tabController;

  Map<String, dynamic>? _cliente;
  final List<_ItemPedido> _itens = [];
  final _obs = TextEditingController();
  final _condicao = TextEditingController();
  final _frete = TextEditingController(text: '0,00');
  final _descPct = TextEditingController(text: '0,00');
  final _descValor = TextEditingController(text: '0,00');

  late String _tipo = widget.tipoInicial;

  // Forma de pagamento e prazo vêm sincronizados do ERP (flag "Disponível Mobile").
  List<Map<String, dynamic>> _formas = [];
  int? _formaId;
  String _forma = '';
  List<Map<String, dynamic>> _tabelas = [];
  int? _tabelaPrazoId;
  String? _tabelaDias;

  Map<String, dynamic>? _listaPreco;
  List<Map<String, dynamic>> _listasPreco = [];
  bool _enviarNaSync = true;
  bool _salvando = false;
  bool _sincDesconto = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Atualiza a tela ao trocar de aba para mostrar a barra só no Resumo.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _cliente = widget.clienteInicial;
    _init();
  }

  Future<void> _init() async {
    await _carregarListasPreco();
    await _carregarFormas();
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  Future<void> _carregarFormas() async {
    final rows = await _db.query('SELECT * FROM formas_pagamento ORDER BY codigo');
    if (!mounted) return;
    setState(() {
      _formas = rows;
      // Pré-seleciona a forma/prazo amarrados ao cliente; senão, a primeira forma.
      if (!_preselecionarDoCliente() && _formaId == null && rows.isNotEmpty) {
        _aplicarForma(rows.first['id'] as int?);
      }
    });
  }

  Map<String, dynamic>? _formaById(int? id) {
    for (final f in _formas) {
      if (f['id'] == id) return f;
    }
    return null;
  }

  Map<String, dynamic>? _tabelaById(int? id) {
    for (final t in _tabelas) {
      if (t['id'] == id) return t;
    }
    return null;
  }

  List<Map<String, dynamic>> _parseTabelas(dynamic json) {
    try {
      final decoded = jsonDecode((json ?? '[]').toString());
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Define a forma selecionada e recarrega as tabelas de prazo dela.
  void _aplicarForma(int? id) {
    final f = _formaById(id);
    _formaId = id;
    _forma = (f?['descricao'] ?? '').toString();
    _tabelas = _parseTabelas(f?['tabelas_json']);
    if (_tabelaById(_tabelaPrazoId) == null) {
      _tabelaPrazoId = null;
      _tabelaDias = null;
    }
    // Quando o Prazo Avulso some (dinheiro/pix) ou fica bloqueado (cliente com
    // forma definida), limpa para não enviar prazo inválido ao ERP.
    if (_avulsoOculto || _avulsoBloqueado) {
      _condicao.clear();
    }
  }

  /// Aplica a forma/prazo pré-fixados no cadastro do cliente. Retorna true
  /// quando conseguiu pré-selecionar a forma.
  bool _preselecionarDoCliente() {
    final fid = _cliente?['forma_pagamento_id'] as int?;
    if (fid == null || _formaById(fid) == null) return false;
    _aplicarForma(fid);
    final tid = _cliente?['tabela_prazo_id'] as int?;
    if (tid != null && _tabelaById(tid) != null) {
      _tabelaPrazoId = tid;
      _tabelaDias = (_cliente?['tabela_prazo_dias'] ?? _tabelaById(tid)?['dias'])?.toString();
    }
    return true;
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
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BuscaSheet(tabela: 'customers', titulo: 'Selecionar cliente', campoNome: 'nome_razao'),
    );
    if (escolhido != null) {
      setState(() {
        _cliente = escolhido;
        _preselecionarDoCliente();
      });
    }
  }

  Future<void> _adicionarItem() async {
    final produto = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
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

  String _formaTipo() => (_formaById(_formaId)?['tipo'] ?? '').toString();

  bool _isFormaPix() => _formaTipo() == 'pix';

  /// Cliente já tem forma de pagamento amarrada no cadastro.
  bool get _clienteComFormaDefinida => _cliente?['forma_pagamento_id'] != null;

  /// Regra 2: Prazo Avulso some em formas à vista (dinheiro/pix).
  bool get _avulsoOculto => _formaTipo() == 'dinheiro' || _formaTipo() == 'pix';

  /// Regra 1: Prazo Avulso bloqueado quando o cliente já tem forma definida.
  bool get _avulsoBloqueado => _clienteComFormaDefinida;

  /// Regra 3: havendo Prazo Avulso preenchido, o Prazo/Parcelamento some.
  bool get _avulsoPreenchido => _condicao.text.trim().isNotEmpty;

  Future<void> _salvar() async {
    if (_cliente == null || _itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um cliente e ao menos um item.')),
      );
      return;
    }

    // Pedido pago no Pix: gera a cobrança e só persiste após confirmar.
    if (_tipo == 'pedido' && _isFormaPix()) {
      await _fluxoPix();
      return;
    }

    await _persistirPedido(uuid: const Uuid().v4());
  }

  /// Gera a cobrança Pix, abre o QR e — se pago — persiste/envia o pedido.
  /// Se falhar/expirar, o pedido continua na tela para o vendedor decidir.
  Future<void> _fluxoPix() async {
    setState(() => _salvando = true);
    final uuid = const Uuid().v4();

    Map<String, dynamic> cobranca;
    try {
      cobranca = await context.read<AppState>().api.criarPix(
            origem: 'pedido',
            ref: uuid,
            valor: _total,
            payerEmail: (_cliente?['email'] ?? '').toString(),
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar o Pix: $e')),
      );
      return;
    }

    if (!mounted) return;
    final pago = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PixQrScreen(cobranca: cobranca)),
    );

    if (!mounted) return;
    if (pago == true) {
      await _persistirPedido(
        uuid: uuid,
        forcarEnvio: true,
        pixExtra: {'pix_pago': true, 'pix_cobranca_id': cobranca['id']},
      );
    } else {
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Pix não confirmado. Tente novamente ou troque a forma de pagamento.')),
      );
    }
  }

  Future<void> _persistirPedido({
    required String uuid,
    Map<String, dynamic>? pixExtra,
    bool forcarEnvio = false,
  }) async {
    setState(() => _salvando = true);

    final (lat, lng) = await _coletarGps();
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
      'forma_pagamento_id': _formaId,
      'tabela_prazo_id': _tabelaPrazoId,
      'tabela_prazo_dias': _tabelaDias,
      'condicao_pagamento': _condicao.text.trim(),
      'price_table_id': _listaPreco?['id'],
      'lista_preco_nome': _listaPreco?['descricao'],
      'frete': _freteValor,
      if (pixExtra != null) ...pixExtra,
    };

    final enviar = _enviarNaSync || forcarEnvio;

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
      'status': enviar ? 'pendente' : 'rascunho',
      'erro': null,
      'numero': null,
      'extra_json': jsonEncode(extra),
    });

    if (!mounted) return;
    if (enviar) {
      context.read<AppState>().sync.syncNow();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(enviar
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
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: Text(_tipo == 'orcamento' ? 'Cadastro de Orçamento' : 'Cadastro de Pedido'),
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0x26FFFFFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                splashBorderRadius: BorderRadius.circular(9),
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                labelColor: Brand.blue,
                unselectedLabelColor: Colors.white,
                labelPadding: EdgeInsets.zero,
                labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(height: 38, child: _TabContent(icon: Icons.assignment_outlined, text: 'Dados')),
                  Tab(height: 38, child: _TabContent(icon: Icons.list_alt_outlined, text: 'Itens')),
                  Tab(height: 38, child: _TabContent(icon: Icons.receipt_long_outlined, text: 'Resumo')),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _abaDados(),
          _abaItens(),
          _abaResumo(),
        ],
      ),
      // Barra com Total + Salvar/Cancelar aparece apenas na aba Resumo.
      bottomNavigationBar: _tabController.index == 2 ? _barraAcoes() : null,
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: [
        _envioCard(),
        _infoTile(icon: Icons.store_outlined, label: 'Filial / Unidade', value: empresa.isEmpty ? 'Empresa padrão' : empresa),
        _section(icon: Icons.description_outlined, titulo: 'Dados do Pedido', filhos: [
          _infoTile(
            icon: Icons.tag,
            label: 'Número do Pedido',
            value: 'Gerado no ERP ao sincronizar',
            muted: true,
          ),
          _field('Tipo de Pedido *', _dropdown<String>(
            value: _tipo,
            items: const {'pedido': '1 - Pedido', 'orcamento': '2 - Orçamento'},
            onChanged: (v) => setState(() => _tipo = v ?? 'pedido'),
          )),
          _field('Lista de Preço', _dropdown<int?>(
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
          )),
          _infoTile(icon: Icons.event_outlined, label: 'Data de Emissão', value: _dataHoraAgora()),
        ]),
        _section(icon: Icons.person_outline, titulo: 'Cliente & Entrega', filhos: [
          _field(
            'Cliente *',
            _selectorBox(
              texto: _cliente == null ? 'Selecionar cliente' : (_cliente!['nome_razao'] ?? '').toString(),
              icon: Icons.person_search_outlined,
              onTap: _selecionarCliente,
              destaque: _cliente != null,
            ),
            trailing: limite != null
                ? Text('Limite: ${brMoney(limite)}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54))
                : null,
          ),
          _infoTile(
            icon: Icons.local_shipping_outlined,
            label: 'Endereço de entrega',
            value: (endereco == null || endereco.isEmpty) ? 'Selecione o cliente' : endereco,
            muted: endereco == null || endereco.isEmpty,
          ),
        ]),
        _section(icon: Icons.payments_outlined, titulo: 'Pagamento', filhos: [
          _field('Forma de Pagamento *', _dropdown<int?>(
            value: _formaId,
            items: {
              for (final f in _formas)
                (f['id'] as int): '${f['codigo'] ?? ''} - ${f['descricao'] ?? ''}'.trim()
            },
            hint: _formas.isEmpty ? 'Sincronize para carregar' : 'Selecione',
            onChanged: (id) => setState(() => _aplicarForma(id)),
          )),
          if (!_avulsoOculto)
            _field('Prazo Avulso',
                _campoTexto(_condicao,
                    hint: _avulsoBloqueado ? 'Definido no cadastro do cliente' : 'Ex.: 30,60,90',
                    enabled: !_avulsoBloqueado,
                    onChanged: (v) => setState(() {
                          // Regra 3: ao usar prazo avulso, zera o parcelamento.
                          if (v.trim().isNotEmpty) {
                            _tabelaPrazoId = null;
                            _tabelaDias = null;
                          }
                        }))),
          if (_tabelas.isNotEmpty && !_avulsoPreenchido)
            _field('Prazo / Parcelamento', _dropdown<int?>(
              value: _tabelaPrazoId,
              items: {
                for (final t in _tabelas) (t['id'] as int): '${t['dias'] ?? ''} dias'.trim()
              },
              hint: 'À vista',
              onChanged: (id) => setState(() {
                _tabelaPrazoId = id;
                _tabelaDias = _tabelaById(id)?['dias']?.toString();
              }),
            )),
          _vencimentosPreview(),
        ]),
        _section(icon: Icons.attach_money, titulo: 'Valores', filhos: [
          _field('Valor do Frete', _campoTexto(_frete,
              teclado: const TextInputType.numberWithOptions(decimal: true),
              prefix: 'R\$ ',
              onChanged: (_) => setState(() {}))),
        ]),
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
        const SizedBox(height: 16),
        _tituloSecao('Parcelas'),
        _parcelasResumo(),
      ],
    );
  }

  /// Prévia detalhada das parcelas: nº, vencimento, forma de pagamento e valor.
  /// Quando não há prazo (à vista), mostra uma única parcela com vencimento hoje.
  /// Converte uma string "30,60,90" em lista de dias [30, 60, 90].
  List<int> _diasDe(String s) => s
      .split(',')
      .map((d) => int.tryParse(d.trim()))
      .whereType<int>()
      .toList();

  /// Dias de prazo efetivos para gerar os vencimentos. O "Prazo Avulso"
  /// (campo livre) tem prioridade sobre a tabela de prazo da forma de
  /// pagamento; se estiver vazio, usa a tabela da forma.
  List<int> _diasEfetivos() {
    final avulso = _diasDe(_condicao.text);
    if (avulso.isNotEmpty) return avulso;
    return _diasDe(_tabelaDias ?? '');
  }

  Widget _parcelasResumo() {
    final dias = _diasEfetivos();
    final base = dias.isEmpty ? <int>[0] : dias;
    final n = base.length;
    final total = _total;
    final forma = _forma.trim().isEmpty ? '—' : _forma.trim();
    final hoje = DateTime.now();

    // Divide o total em centavos para evitar diferença de arredondamento;
    // a última parcela recebe o eventual resto.
    final parcelaBase = (total / n * 100).floorToDouble() / 100;

    final linhas = <Widget>[];
    for (var i = 0; i < n; i++) {
      final valor = i == n - 1
          ? double.parse((total - parcelaBase * (n - 1)).toStringAsFixed(2))
          : parcelaBase;
      final venc = hoje.add(Duration(days: base[i]));
      linhas.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${i + 1}ª — ${_fmtData(venc)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF37474F))),
                  Text(forma,
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
            Text(brMoney(valor),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: Brand.green)),
          ],
        ),
      ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('$n parcela${n > 1 ? 's' : ''}',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: Brand.blue)),
          ),
          ...linhas,
        ],
      ),
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
                  : Icon(_tipo == 'pedido' && _isFormaPix() ? Icons.qr_code_2 : Icons.save_outlined),
              label: Text(_salvando
                  ? 'Salvando...'
                  : (_tipo == 'pedido' && _isFormaPix() ? 'Gerar Pix' : 'Salvar')),
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

  String _fmtData(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }

  /// Prévia dos vencimentos a partir da tabela de prazo selecionada
  /// (hoje + cada dia), exibidos de 2 em 2: "1ª — 27/08/2026   2ª — ...".
  Widget _vencimentosPreview() {
    final dias = _diasEfetivos();
    if (dias.isEmpty) return const SizedBox.shrink();

    final hoje = DateTime.now();
    final itens = <Widget>[];
    for (var i = 0; i < dias.length; i++) {
      final venc = hoje.add(Duration(days: dias[i]));
      itens.add(Text('${i + 1}ª — ${_fmtData(venc)}',
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF37474F))));
    }

    final linhas = <Widget>[];
    for (var i = 0; i < itens.length; i += 2) {
      linhas.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(child: itens[i]),
            Expanded(child: i + 1 < itens.length ? itens[i + 1] : const SizedBox()),
          ],
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F6FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Vencimentos',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.blue)),
            ),
            ...linhas,
          ],
        ),
      ),
    );
  }

  // ---- Componentes do redesign (cards / campos / info tiles) -------------
  Widget _section({required IconData icon, required String titulo, required List<Widget> filhos}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x0F1E293B), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: Brand.blue),
              ),
              const SizedBox(width: 8),
              Text(titulo,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Brand.blue)),
            ],
          ),
          const SizedBox(height: 12),
          ...filhos,
        ],
      ),
    );
  }

  Widget _fieldCaption(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: Color(0xFF64748B))),
      );

  Widget _field(String caption, Widget control, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          trailing == null
              ? _fieldCaption(caption)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [_fieldCaption(caption), Padding(padding: const EdgeInsets.only(bottom: 5), child: trailing)],
                ),
          control,
        ],
      ),
    );
  }

  Widget _infoTile({required IconData icon, required String label, required String value, bool muted = false}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: Color(0xFF94A3B8))),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: muted ? const Color(0xFF94A3B8) : const Color(0xFF1E293B))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _envioCard() {
    final on = _enviarNaSync;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: on ? const Color(0xFFE9F7EC) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? const Color(0xFFB7E1C0) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: on ? Brand.green : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(on ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enviar na próxima sincronização',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                Text(on ? 'Será enviado ao ERP.' : 'Salvar como rascunho (não envia).',
                    style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
              ],
            ),
          ),
          Switch(
            value: on,
            activeColor: Brand.green,
            onChanged: (v) => setState(() => _enviarNaSync = v),
          ),
        ],
      ),
    );
  }

  Widget _tituloSecao(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Brand.blue)),
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
    bool enabled = true,
  }) {
    return TextField(
      controller: c,
      keyboardType: teclado,
      onChanged: onChanged,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        isDense: true,
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF1F5F9),
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

/// Conteúdo compacto de cada aba (ícone + texto numa linha).
class _TabContent extends StatelessWidget {
  const _TabContent({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(text),
      ],
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
  List<String> _grupos = [];
  String _termo = '';
  String? _grupoSel; // null = Todos

  bool get _isProdutos => widget.tabela == 'products';

  @override
  void initState() {
    super.initState();
    if (_isProdutos) _carregarGrupos();
    _buscar();
  }

  Future<void> _carregarGrupos() async {
    final rows = await _db.query(
      "SELECT DISTINCT grupo FROM products WHERE ativo = 1 AND mostrar_no_app = 1 "
      "AND grupo IS NOT NULL AND TRIM(grupo) <> '' ORDER BY grupo",
    );
    if (mounted) {
      setState(() => _grupos =
          rows.map((r) => (r['grupo'] ?? '').toString()).where((g) => g.isNotEmpty).toList());
    }
  }

  Future<void> _buscar() async {
    final like = '%$_termo%';
    List<Map<String, dynamic>> rows;
    if (_isProdutos) {
      final where = StringBuffer(
          'ativo = 1 AND mostrar_no_app = 1 AND (descricao LIKE ? OR codigo LIKE ? OR codigo_barras LIKE ?)');
      final args = <Object?>[like, like, like];
      if (_grupoSel != null) {
        where.write(' AND grupo = ?');
        args.add(_grupoSel);
      }
      rows = await _db.query('SELECT * FROM products WHERE $where ORDER BY descricao LIMIT 100', args);
    } else {
      rows = await _db.query(
        'SELECT * FROM ${widget.tabela} WHERE ${widget.campoNome} LIKE ? OR codigo LIKE ? ORDER BY ${widget.campoNome} LIMIT 60',
        [like, like],
      );
    }
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 1.0,
      minChildSize: 0.6,
      maxChildSize: 1.0,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Brand.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 2),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(widget.titulo,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    autofocus: false,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (s) {
                      _termo = s;
                      _buscar();
                    },
                  ),
                ),
                if (_isProdutos && _grupos.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        _chip('Todos', _grupoSel == null, () => setState(() {
                              _grupoSel = null;
                              _buscar();
                            })),
                        for (final g in _grupos)
                          _chip(g, _grupoSel == g, () => setState(() {
                                _grupoSel = g;
                                _buscar();
                              })),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(child: Text('Nada encontrado.'))
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) =>
                              _isProdutos ? _produtoItem(_rows[i]) : _clienteItem(_rows[i]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onTap(),
        selectedColor: Brand.blue,
        labelStyle: TextStyle(
            color: sel ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 12.5),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE2E8F0))),
      ),
    );
  }

  Widget _clienteItem(Map<String, dynamic> r) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text((r[widget.campoNome] ?? '').toString()),
        subtitle: Text('Cód. ${r['codigo'] ?? ''}'),
        onTap: () => Navigator.pop(context, r),
      ),
    );
  }

  Widget _produtoItem(Map<String, dynamic> r) {
    final base = context.read<AppState>().config.baseUrl;
    final fotoUrl = _fotoBuscaUrl(base, r['foto_url']);
    final estoque = (r['estoque'] as num?)?.toDouble() ?? 0;
    final preco = (r['preco_venda'] as num?)?.toDouble() ?? 0;
    final descricao = (r['descricao'] ?? '').toString();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(context, r),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _MiniFoto(url: fotoUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    const SizedBox(height: 3),
                    Text(
                        'Cód. ${r['codigo'] ?? ''}  •  Estoque: ${_fmtEstoque(estoque)} ${r['unidade'] ?? ''}',
                        style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(brMoney(preco),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.blue)),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtEstoque(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
}

/// Monta a URL completa da foto a partir do caminho relativo vindo do ERP.
String? _fotoBuscaUrl(String base, dynamic fotoUrl) {
  final f = (fotoUrl ?? '').toString().trim();
  if (f.isEmpty) return null;
  if (f.startsWith('http://') || f.startsWith('https://')) return f;
  final b = base.replaceFirst(RegExp(r'/+$'), '');
  final path = f.startsWith('/') ? f : '/$f';
  return '$b$path';
}

class _MiniFoto extends StatelessWidget {
  const _MiniFoto({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const double size = 46;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Brand.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.inventory_2_outlined, color: Brand.green, size: 22),
    );
    if (url == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
