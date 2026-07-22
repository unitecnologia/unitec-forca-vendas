import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../documents/pedido_document_actions.dart';
import '../fv_carteira.dart';
import '../sync/sync_service.dart';
import '../ui/brand.dart';
import '../ui/barcode_scan.dart';
import '../ui/cliente_credito_check.dart';
import '../ui/format.dart';
import '../ui/pedido_envio_dialog.dart';
import '../ui/pdv_alert_dialog.dart';
import '../ui/produto_busca.dart';
import '../ui/produto_list_card.dart';
import '../ui/produto_foto_viewer.dart';
import '../ui/uppercase_input.dart';
import '../pricing/product_preco.dart';
import 'pix_qr_screen.dart';

class _ItemPedido {
  _ItemPedido({
    required this.productId,
    required this.descricao,
    required this.quantidade,
    required this.precoUnitario,
    double desconto = 0,
    double? descontoPercentual,
  })  : _descontoValor = desconto,
        _descontoPercentual = descontoPercentual;

  final int productId;
  final String descricao;
  double quantidade;
  final double precoUnitario;

  double? _descontoPercentual;
  double _descontoValor;

  double get bruto => quantidade * precoUnitario;

  double get desconto {
    if (_descontoPercentual != null && _descontoPercentual! > 0) {
      return (bruto * _descontoPercentual! / 100).clamp(0.0, bruto).toDouble();
    }
    return _descontoValor.clamp(0.0, bruto).toDouble();
  }

  double get descontoPercentualExibicao {
    if (_descontoPercentual != null) return _descontoPercentual!;
    if (bruto <= 0) return 0;
    return desconto / bruto * 100;
  }

  double get descontoValorExibicao => desconto;

  void aplicarDescontoPercentual(double pct) {
    final p = pct.clamp(0.0, 100.0).toDouble();
    _descontoPercentual = p > 0 ? p : null;
    if (p <= 0) _descontoValor = 0;
  }

  void aplicarDescontoValor(double valor) {
    _descontoPercentual = null;
    _descontoValor = valor.clamp(0.0, bruto).toDouble();
  }

  double get total => bruto - desconto;
}

class NovoPedidoScreen extends StatefulWidget {
  const NovoPedidoScreen({
    super.key,
    this.clienteInicial,
    this.tipoInicial = 'pedido',
    this.documentoUuid,
    this.converterParaPedido = false,
  });

  /// Cliente pré-selecionado (ex.: ao iniciar o pedido pela tela de Clientes).
  final Map<String, dynamic>? clienteInicial;

  /// Tipo do documento: 'pedido' (vai para o Monitor de Vendas e baixa estoque
  /// ao faturar) ou 'orcamento' (vai para Orçamentos recebidos, sem baixa).
  final String tipoInicial;

  /// UUID de orçamento/pedido local (outbox ou cache) para reabrir.
  final String? documentoUuid;

  /// Se true, abre o documento como pedido (conversão de orçamento).
  final bool converterParaPedido;

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
  String? _orcamentoOrigemUuid;
  String? _orcamentoOrigemNumero;

  // Forma de pagamento e prazo vêm sincronizados do ERP (flag "Disponível Mobile").
  List<Map<String, dynamic>> _formas = [];
  int? _formaId;
  String _forma = '';
  List<Map<String, dynamic>> _tabelas = [];
  int? _tabelaPrazoId;
  String? _tabelaDias;

  Map<String, dynamic>? _listaPreco;
  List<Map<String, dynamic>> _listasPreco = [];
  int? _vendedorTabelaId;
  List<Map<String, dynamic>> _transportadoras = [];
  int? _transportadoraId;
  bool _salvando = false;
  bool _sincDesconto = false;
  bool _creditoLiberado = false;
  /// true se o vendedor alterou a lista manualmente (não sobrescrever até trocar cliente).
  bool _listaPrecoManual = false;
  SyncService? _sync;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync = context.read<AppState>().sync;
      _sync!.addListener(_onSyncChanged);
    });
  }

  void _onSyncChanged() {
    if (_sync?.status != SyncStatus.ok) return;
    _carregarTransportadoras();
  }

  Future<void> _init() async {
    await _carregarListasPreco();
    await _carregarFormas();
    await _carregarTransportadoras();
    if (widget.documentoUuid != null && widget.documentoUuid!.isNotEmpty) {
      await _carregarDocumento(widget.documentoUuid!);
    } else if (_cliente != null && mounted) {
      setState(() {
        _preselecionarDoCliente();
        _aplicarListaPrecoPreferida(forcar: true);
      });
    }
  }

  Future<void> _carregarDocumento(String uuid) async {
    final doc = await _db.orderForPdf(uuid);
    if (!mounted) return;
    if (doc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir este orçamento. Sincronize e tente de novo.')),
      );
      return;
    }

    final clienteId = _asInt(doc['cliente_id']);
    Map<String, dynamic>? cliente;
    if (clienteId != null) {
      final rows = await _db.query('SELECT * FROM customers WHERE id = ? LIMIT 1', [clienteId]);
      if (rows.isNotEmpty) cliente = rows.first;
    }

    final itens = <_ItemPedido>[];
    try {
      final decoded = jsonDecode((doc['itens_json'] ?? '[]').toString());
      if (decoded is List) {
        for (final raw in decoded) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final pid = _asInt(m['product_id']);
          if (pid == null) continue;
          itens.add(_ItemPedido(
            productId: pid,
            descricao: (m['descricao'] ?? '').toString(),
            quantidade: (m['quantidade'] as num?)?.toDouble() ?? 1,
            precoUnitario: (m['preco_unitario'] as num?)?.toDouble() ?? 0,
            desconto: (m['desconto'] as num?)?.toDouble() ?? 0,
          ));
        }
      }
    } catch (_) {}

    Map<String, dynamic> extra = {};
    try {
      final decoded = jsonDecode((doc['extra_json'] ?? '{}').toString());
      if (decoded is Map) extra = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    final converter = widget.converterParaPedido;
    final tipoDoc = (doc['tipo'] ?? '').toString();
    if (converter || tipoDoc == 'orcamento') {
      _orcamentoOrigemUuid = uuid;
      final numOrc = (doc['numero'] ?? '').toString();
      _orcamentoOrigemNumero = numOrc.isNotEmpty ? numOrc : null;
    }

    final frete = (extra['frete'] as num?)?.toDouble() ?? 0;
    final condicao = (extra['condicao_pagamento'] ?? '').toString();
    final descPedido = (doc['desconto_valor'] as num?)?.toDouble() ?? 0;
    final pctExtra = (extra['percentual_desconto'] as num?)?.toDouble();
    final obs = (doc['observacoes'] ?? '').toString();

    setState(() {
      _tipo = converter ? 'pedido' : (tipoDoc.isNotEmpty ? tipoDoc : widget.tipoInicial);
      _cliente = cliente;
      _itens
        ..clear()
        ..addAll(itens);
      _obs.text = obs;
      _descValor.text = _fmtInput(descPedido);
      if (pctExtra != null && pctExtra > 0) {
        _descPct.text = _fmtInput(pctExtra);
      } else {
        final base = _itens.fold(0.0, (s, i) => s + i.total);
        final pct = base > 0 ? (descPedido / base * 100) : 0.0;
        _descPct.text = _fmtInput(pct);
      }
      _frete.text = _fmtInput(frete);
      _condicao.text = condicao;

      _transportadoraId = _asInt(extra['transportadora_id']);
      if (_cliente != null) {
        _preselecionarDoCliente();
      }

      // Dados do orçamento prevalecem sobre o padrão do cliente.
      final formaId = _asInt(extra['forma_pagamento_id']);
      if (formaId != null && _formaById(formaId) != null) {
        _aplicarForma(formaId);
        final tid = _asInt(extra['tabela_prazo_id']);
        if (tid != null && _tabelaById(tid) != null) {
          _tabelaPrazoId = tid;
          _tabelaDias = (extra['tabela_prazo_dias'] ?? _tabelaById(tid)?['dias'])?.toString();
        }
      }

      final priceTableId = _asInt(extra['price_table_id']);
      final lista = _listaPrecoById(priceTableId);
      if (lista != null) {
        _listaPreco = lista;
        _listaPrecoManual = true;
      } else if (_cliente != null) {
        _aplicarListaPrecoPreferida(forcar: true);
      }
    });
  }

  Future<void> _carregarTransportadoras() async {
    try {
      await _db.ensureTransportadorasTable();
      final rows = await _db.query(
        'SELECT * FROM transportadoras WHERE COALESCE(ativo, 1) = 1 '
        'ORDER BY CAST(codigo AS INTEGER), nome',
      );
      if (!mounted) return;
      setState(() {
        _transportadoras = rows;
        if (_transportadoraId != null &&
            !_transportadoras.any((t) => _asInt(t['id']) == _transportadoraId)) {
          _transportadoraId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _transportadoras = []);
    }
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  void dispose() {
    _sync?.removeListener(_onSyncChanged);
    _tabController.dispose();
    _obs.dispose();
    _condicao.dispose();
    _frete.dispose();
    _descPct.dispose();
    _descValor.dispose();
    super.dispose();
  }

  Future<void> _carregarListasPreco() async {
    final rows = await _db.query(
      'SELECT * FROM price_tables WHERE ativo = 1 '
      'ORDER BY CAST(codigo AS INTEGER), descricao',
    );
    if (!mounted) return;

    final config = context.read<AppState>().config;
    var vendedorTid = config.tabelaVendaId;
    if (vendedorTid == null && config.vendedorId != null) {
      final vs = await _db.query(
        'SELECT tabela_venda_id FROM vendedores WHERE id = ? LIMIT 1',
        [config.vendedorId],
      );
      if (vs.isNotEmpty) {
        vendedorTid = _asInt(vs.first['tabela_venda_id']);
      }
    }

    if (!mounted) return;
    setState(() {
      _listasPreco = rows;
      _vendedorTabelaId = vendedorTid;
      // Ao abrir o pedido: sempre a tabela padrão do vendedor (não a 1ª da lista).
      _listaPrecoManual = false;
      _aplicarListaPrecoPreferida(forcar: true);
    });
  }

  Map<String, dynamic>? _listaPrecoById(int? id) {
    if (id == null) return null;
    for (final r in _listasPreco) {
      if (r['id'] == id || _asInt(r['id']) == id) return r;
    }
    return null;
  }

  Map<String, dynamic>? _listaPadraoVendedor() {
    final config = context.read<AppState>().config;
    var preferida = _listaPrecoById(_vendedorTabelaId ?? config.tabelaVendaId);
    if (preferida != null) return preferida;

    if (config.tabelaVendaDescricao.isNotEmpty) {
      final alvo = config.tabelaVendaDescricao.toUpperCase();
      for (final r in _listasPreco) {
        if ((r['descricao'] ?? '').toString().toUpperCase() == alvo) {
          return r;
        }
      }
    }
    if (config.tabelaVendaCodigo.isNotEmpty) {
      final cod = config.tabelaVendaCodigo.trim();
      for (final r in _listasPreco) {
        if ((r['codigo'] ?? '').toString().trim() == cod) {
          return r;
        }
      }
    }

    // Fallback seguro: VAREJO / código 1 — nunca a 1ª alfabética (ATACADO).
    for (final r in _listasPreco) {
      final desc = (r['descricao'] ?? '').toString().toUpperCase();
      final cod = (r['codigo'] ?? '').toString().trim();
      if (desc.contains('VAREJO') || desc.contains('PADRAO') || desc.contains('PADRÃO') || cod == '1') {
        return r;
      }
    }
    return _listasPreco.isNotEmpty ? _listasPreco.first : null;
  }

  /// Sem cliente: tabela do vendedor. Com cliente + price_table_id: tabela do cliente.
  /// Alteração manual do dropdown é respeitada até trocar o cliente.
  void _aplicarListaPrecoPreferida({bool forcar = false}) {
    if (_listasPreco.isEmpty) return;

    final doCliente = _listaPrecoById(_asInt(_cliente?['price_table_id']));
    if (doCliente != null) {
      _listaPreco = doCliente;
      _listaPrecoManual = false;
      return;
    }

    if (!forcar && _listaPrecoManual && _listaPreco != null) return;

    _listaPreco = _listaPadraoVendedor();
    _listaPrecoManual = false;
  }

  Future<double> _precoDoProduto(Map<String, dynamic> produto, {double quantidade = 1}) {
    return ProductPreco.resolve(
      produto,
      listaPreco: _listaPreco,
      quantidade: quantidade,
      db: _db,
    );
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

  Map<String, dynamic>? _transportadoraById(int? id) {
    for (final t in _transportadoras) {
      if (_asInt(t['id']) == id) return t;
    }
    return null;
  }

  String _transportadoraItemLabel(Map<String, dynamic> t) {
    final codigo = (t['codigo'] ?? '').toString().trim();
    final nome = (t['nome'] ?? t['apelido'] ?? t['proprietario'] ?? '').toString().trim();
    if (codigo.isEmpty) return nome.isEmpty ? 'Transportadora' : nome;
    if (nome.isEmpty) return codigo;
    return '$codigo - $nome';
  }

  String? _transportadoraLabel(int? id) {
    final t = _transportadoraById(id);
    if (t == null) return null;
    return _transportadoraItemLabel(t);
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
  double get _total => (_subtotalItens - _descontoPedido + _freteValor).clamp(0.0, double.infinity).toDouble();

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

  void _alterarDescPedidoPct(double delta) {
    final nova = (_parseNum(_descPct.text) + delta).clamp(0.0, 100.0).toDouble();
    _descPct.text = _fmtInput(nova);
    _recalcDescontoDePct();
  }

  void _alterarDescPedidoValor(double delta) {
    final nova = (_parseNum(_descValor.text) + delta).clamp(0.0, _subtotalItens).toDouble();
    _descValor.text = _fmtInput(nova);
    _recalcDescontoDeValor();
  }

  Widget _stepBtnPedido(IconData icon, VoidCallback onTap) {
    return Material(
      color: Brand.blue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 34,
          height: 42,
          child: Icon(icon, size: 18, color: Brand.blue),
        ),
      ),
    );
  }

  Widget _campoDescontoStepper({
    required TextEditingController controller,
    required String label,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required ValueChanged<String> onChanged,
    String? suffix,
  }) {
    return Row(
      children: [
        _stepBtnPedido(Icons.remove_rounded, onMinus),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13 + Brand.textBump01cm, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Brand.blue, width: 1.4),
              ),
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 4),
        _stepBtnPedido(Icons.add_rounded, onPlus),
      ],
    );
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
        _creditoLiberado = false;
        _preselecionarDoCliente();
        _aplicarListaPrecoPreferida(forcar: true);
      });
    }
  }

  Future<void> _adicionarItem() async {
    if (_cliente == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o cliente antes de adicionar itens.')),
      );
      return;
    }
    final produto = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BuscaSheet(tabela: 'products', titulo: 'Selecionar produto', campoNome: 'descricao'),
    );
    if (produto == null || !mounted) return;

    final preco = await _precoDoProduto(produto);
    if (!mounted) return;
    final item = await showModalBottomSheet<_ItemPedido>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemFormSheet(
        descricao: (produto['descricao'] ?? '').toString(),
        precoUnitario: preco,
        productId: produto['id'] as int,
        produto: produto,
        listaPreco: _listaPreco,
      ),
    );
    if (item == null) return;

    setState(() {
      _itens.insert(0, item);
      _recalcDescontoDePct();
    });
  }

  Future<void> _editarItem(int indice) async {
    final item = _itens[indice];
    final atualizado = await showModalBottomSheet<_ItemPedido>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemFormSheet(
        productId: item.productId,
        descricao: item.descricao,
        precoUnitario: item.precoUnitario,
        quantidadeInicial: item.quantidade,
        descontoPctInicial: item.descontoPercentualExibicao,
        descontoValorInicial: item.descontoValorExibicao,
        confirmLabel: 'Salvar alterações',
      ),
    );
    if (atualizado == null || !mounted) return;

    setState(() {
      _itens[indice] = atualizado;
      _recalcDescontoDePct();
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

  /// Boletos vencidos e/ou limite de crédito — padrão PDV com Sim/Não.
  Future<bool> _confirmarCreditoCliente() async {
    if (_tipo != 'pedido') return true;

    final clienteId = (_cliente?['id'] as num?)?.toInt();
    if (clienteId == null) return true;

    final alerta = await ClienteCreditoCheck.verificar(
      clienteId: clienteId,
      totalPedido: _total,
    );
    if (alerta == null) {
      _creditoLiberado = false;
      return true;
    }

    if (!mounted) return false;

    final liberar = await PdvAlertDialog.showSimNao(
      context,
      titulo: alerta.titulo,
      detalhe: alerta.detalhe,
      hint: ClienteCreditoAlerta.hint,
    );

    if (liberar) _creditoLiberado = true;
    return liberar;
  }

  Future<void> _salvar() async {
    if (_cliente == null || _itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um cliente e ao menos um item.')),
      );
      return;
    }

    if (!await _confirmarCreditoCliente()) return;

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
      'transportadora_id': _transportadoraId,
      'transportadora_nome': _transportadoraLabel(_transportadoraId),
      if (_creditoLiberado) 'credito_liberado': true,
      if (_orcamentoOrigemUuid != null) 'orcamento_origem_uuid': _orcamentoOrigemUuid,
      if (_orcamentoOrigemNumero != null) 'orcamento_origem_numero': _orcamentoOrigemNumero,
      if (pixExtra != null) ...pixExtra,
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
      'status': 'pendente',
      'erro': null,
      'numero': null,
      'extra_json': jsonEncode(extra),
    });

    if (!mounted) return;
    context.read<AppState>().sync.syncNow();

    setState(() => _salvando = false);

    final tipoLabel = _tipo == 'orcamento' ? 'orçamento' : 'pedido';
    final clienteNome = (_cliente?['nome_razao'] ?? 'Cliente').toString();
    final whats = _telefoneWhatsAppCliente(_cliente);
    final email = (_cliente?['email'] ?? '').toString().trim();
    final msgPadrao = _tipo == 'orcamento'
        ? 'Segue orçamento ($clienteNome).'
        : 'Segue pedido ($clienteNome).';

    final envio = await showPedidoEnvioDialog(
      context,
      tipoLabel: tipoLabel,
      clienteNome: clienteNome,
      whatsappInicial: whats,
      emailInicial: email,
      mensagemInicial: msgPadrao,
    );

    if (!mounted) return;

    if (envio != null) {
      if (envio.canal == PedidoEnvioCanal.whatsapp) {
        await PedidoDocumentActions.enviarWhatsApp(
          context,
          uuid,
          telefone: envio.whatsapp,
          mensagem: envio.mensagem,
        );
      } else {
        await PedidoDocumentActions.enviarEmail(
          context,
          uuid,
          email: envio.email,
          mensagem: envio.mensagem,
        );
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          envio == null
              ? 'Pedido salvo. Será sincronizado automaticamente.'
              : 'Pedido salvo e enviado. Será sincronizado automaticamente.',
        ),
      ),
    );

    // Após salvar (e eventual envio), volta à tela inicial do app.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String _telefoneWhatsAppCliente(Map<String, dynamic>? c) {
    if (c == null) return '';
    for (final key in ['whatsapp', 'celular1', 'fone1']) {
      final raw = (c[key] ?? '').toString().trim();
      if (raw.isNotEmpty) return raw;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: Text(
          _orcamentoOrigemUuid != null && _tipo == 'pedido'
              ? 'Pedido (do orçamento${_orcamentoOrigemNumero != null ? ' $_orcamentoOrigemNumero' : ''})'
              : (_tipo == 'orcamento' ? 'Cadastro de Orçamento' : 'Cadastro de Pedido'),
          style: TextStyle(fontSize: 17 + Brand.textBump01cm, fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        toolbarHeight: 48,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicatorWeight: 2.5,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelPadding: EdgeInsets.zero,
              labelStyle: TextStyle(fontSize: 13 + Brand.textBump01cm, fontWeight: FontWeight.w700, letterSpacing: 0.3),
              unselectedLabelStyle: TextStyle(fontSize: 13 + Brand.textBump01cm, fontWeight: FontWeight.w500),
              tabs: [
                Tab(height: 36, child: _tabLabel(1, 'Dados')),
                Tab(height: 36, child: _tabLabel(2, 'Itens')),
                Tab(height: 36, child: _tabLabel(3, 'Resumo')),
              ],
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

  Widget _tabLabel(int n, String label) {
    final i = n - 1;
    final active = _tabController.index == i;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white24,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$n',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: active ? Brand.blue : Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  // ---- Aba 1: Dados ------------------------------------------------------
  Widget _abaDados() {
    final limite = (_cliente?['limite_credito'] as num?)?.toDouble();
    final empresa = context.read<AppState>().config.empresaNome;

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      children: [
        _filialCard(empresa.isEmpty ? 'Empresa padrão' : empresa),
        _section(icon: Icons.person_outline, titulo: 'Cliente', filhos: [
          _clienteCard(limite: limite),
        ]),
        _section(icon: Icons.description_outlined, titulo: 'Dados do Pedido', filhos: [
          _pedidoNumeroCard(),
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
            hint: 'Tabela do vendedor',
            onChanged: (id) => setState(() {
              _listaPreco = _listaPrecoById(id);
              _listaPrecoManual = true;
            }),
          )),
          _infoTile(icon: Icons.event_outlined, label: 'Data de Emissão', value: _dataHoraAgora()),
        ]),
        _section(icon: Icons.local_shipping_outlined, titulo: 'Entrega', filhos: [
          _enderecoCard(),
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
        _section(icon: Icons.local_shipping_outlined, titulo: 'Transportadora', filhos: [
          _field(
            'Transportadora',
            _dropdown<int?>(
              value: _transportadoraId,
              items: {
                for (final t in _transportadoras)
                  if (_asInt(t['id']) case final int id)
                    id: _transportadoraItemLabel(t),
              },
              hint: _transportadoras.isEmpty ? 'Sincronize para carregar' : 'Selecione',
              onChanged: (id) => setState(() => _transportadoraId = id),
            ),
          ),
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
          margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color.lerp(Colors.white, Brand.blue, 0.04)!],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Brand.blue.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(color: Brand.blue.withValues(alpha: 0.07), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _resumoCompacto('Itens', '${_itens.length}')),
                  Expanded(child: _resumoCompacto('Bruto', brMoney(_brutoItens))),
                  Expanded(child: _resumoCompacto('Produtos', brMoney(_subtotalItens))),
                ],
              ),
              if (_descontoItens > 0 || _descontoPedido > 0 || _freteValor > 0) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (_descontoItens > 0)
                      _chipResumo('Desc. itens', brMoney(_descontoItens), Colors.orange.shade800),
                    if (_descontoPedido > 0)
                      _chipResumo('Desc. pedido', brMoney(_descontoPedido), Colors.orange.shade800),
                    if (_freteValor > 0) _chipResumo('Frete', brMoney(_freteValor), const Color(0xFF475569)),
                  ],
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1),
              ),
              _resumoRow('Valor total', brMoney(_total), destaque: true, compacto: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: FilledButton.icon(
            onPressed: _adicionarItem,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text('Adicionar item',
                style: TextStyle(fontSize: 14 + Brand.textBump01cm, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: Brand.blue,
              minimumSize: const Size.fromHeight(42),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Expanded(
          child: _itens.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 6),
                      Text('Nenhum item.', style: TextStyle(color: Colors.black.withValues(alpha: 0.45), fontSize: 13 + Brand.textBump01cm)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  itemCount: _itens.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _ItemListaTile(
                    key: ValueKey('item-$i-${_itens[i].productId}-${_itens[i].quantidade}'),
                    indice: i + 1,
                    item: _itens[i],
                    onTap: () => _editarItem(i),
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

  Widget _resumoCompacto(String label, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11 + Brand.textBump01cm, color: Colors.black.withValues(alpha: 0.45))),
        const SizedBox(height: 2),
        Text(valor, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13 + Brand.textBump01cm, color: Color(0xFF263238))),
      ],
    );
  }

  Widget _chipResumo(String label, String valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $valor', style: TextStyle(fontSize: 11 + Brand.textBump01cm, fontWeight: FontWeight.w600, color: color)),
    );
  }

  // ---- Aba 3: Resumo -----------------------------------------------------
  Widget _abaResumo() {
    final pctItens = _brutoItens > 0 ? (_descontoItens / _brutoItens * 100) : 0.0;
    final descTotal = _descontoItens + _descontoPedido;
    final pctTotal = _brutoItens > 0 ? (descTotal / _brutoItens * 100) : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      children: [
        _section(icon: Icons.inventory_2_outlined, titulo: 'Dados dos itens', filhos: [
          _resumoRow('Preço de tabela', brMoney(_brutoItens), compacto: true),
          _resumoRow('Desconto nos itens', '${brMoney(_descontoItens)} (${pctItens.toStringAsFixed(2)}%)', compacto: true),
          _resumoRow('Produtos c/ desconto', brMoney(_subtotalItens), compacto: true),
        ]),
        _section(icon: Icons.percent_outlined, titulo: 'Desconto do pedido', filhos: [
          Row(
            children: [
              Expanded(
                child: _campoDescontoStepper(
                  controller: _descPct,
                  label: 'Desc. %',
                  suffix: '%',
                  onMinus: () => _alterarDescPedidoPct(-1),
                  onPlus: () => _alterarDescPedidoPct(1),
                  onChanged: (_) => _recalcDescontoDePct(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _campoDescontoStepper(
                  controller: _descValor,
                  label: 'Desc. R\$',
                  onMinus: () => _alterarDescPedidoValor(-1),
                  onPlus: () => _alterarDescPedidoValor(1),
                  onChanged: (_) => _recalcDescontoDeValor(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _resumoRow('Descontos totais', '${brMoney(descTotal)} (${pctTotal.toStringAsFixed(2)}%)', compacto: true),
        ]),
        _section(icon: Icons.receipt_long_outlined, titulo: 'Totais do pedido', filhos: [
          _resumoRow('Valor dos produtos', brMoney(_subtotalItens), compacto: true),
          _resumoRow('Frete', brMoney(_freteValor), compacto: true),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),
          _resumoRow('Valor total', brMoney(_total), destaque: true, compacto: true),
        ]),
        _section(icon: Icons.calendar_month_outlined, titulo: 'Parcelas', filhos: [
          _parcelasResumo(),
        ]),
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
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${i + 1}ª — ${_fmtData(venc)}',
                      style: TextStyle(
                          fontSize: 12 + Brand.textBump01cm,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                          height: 1.2)),
                  Text(forma,
                      style: TextStyle(
                          fontSize: 10 + Brand.textBump01cm,
                          color: Color(0xFF94A3B8),
                          height: 1.2)),
                ],
              ),
            ),
            Text(brMoney(valor),
                style: TextStyle(
                    fontSize: 13 + Brand.textBump01cm, fontWeight: FontWeight.w700, color: Brand.green)),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('$n parcela${n > 1 ? 's' : ''}',
              style: TextStyle(
                  fontSize: 10 + Brand.textBump01cm,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: Color(0xFF64748B))),
        ),
        ...linhas,
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
                  const Text('Total', style: TextStyle(fontSize: 11 + Brand.textBump01cm, color: Colors.black54)),
                  Text(brMoney(_total),
                      style: TextStyle(fontSize: 18 + Brand.textBump01cm, fontWeight: FontWeight.w800, color: Brand.green)),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -Brand.textBump01cm), // sobe ~0,10 cm
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
          style: TextStyle(
              fontSize: 13 + Brand.textBump01cm, fontWeight: FontWeight.w600, color: Color(0xFF37474F))));
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
                  style: TextStyle(fontSize: 11 + Brand.textBump01cm, fontWeight: FontWeight.w700, color: Brand.blue)),
            ),
            ...linhas,
          ],
        ),
      ),
    );
  }

  // ---- Componentes do redesign (cards / campos / info tiles) -------------
  Widget _filialCard(String nome) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Brand.blue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('Filial',
              style: TextStyle(
                  fontSize: 11 + Brand.textBump01cm,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13 + Brand.textBump01cm,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.1)),
          ),
        ],
      ),
    );
  }

  Widget _pedidoNumeroCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(Icons.tag_outlined, size: 16, color: Brand.blue.withValues(alpha: 0.85)),
          const SizedBox(width: 8),
          Text('Nº do pedido',
              style: TextStyle(
                  fontSize: 12 + Brand.textBump01cm,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B))),
          const Spacer(),
          Flexible(
            child: Text('Gerado na sincronização',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12 + Brand.textBump01cm,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                    fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  Widget _clienteCard({double? limite}) {
    if (_cliente == null) {
      return _field(
        'Cliente *',
        _selectorBox(
          texto: 'Selecionar cliente',
          icon: Icons.person_add_alt_1_rounded,
          onTap: _selecionarCliente,
        ),
      );
    }

    final nome = (_cliente!['nome_razao'] ?? 'Cliente').toString();
    final doc = (_cliente!['cpf_cnpj'] ?? '').toString().trim();
    final rua = [
      _cliente!['endereco'],
      _cliente!['numero'],
    ].where((e) => (e ?? '').toString().trim().isNotEmpty).join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _selecionarCliente,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome,
                          style: TextStyle(
                              fontSize: 14 + Brand.textBump01cm,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                              height: 1.15)),
                      if (doc.isNotEmpty)
                        Text(doc,
                            style: TextStyle(
                                fontSize: 12 + Brand.textBump01cm,
                                color: Color(0xFF64748B),
                                height: 1.25)),
                      if (rua.isNotEmpty)
                        Text(rua,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11 + Brand.textBump01cm,
                                color: Color(0xFF94A3B8),
                                height: 1.25)),
                      if (limite != null)
                        Text('Limite ${brMoney(limite)}',
                            style: TextStyle(
                                fontSize: 11 + Brand.textBump01cm,
                                fontWeight: FontWeight.w600,
                                color: Brand.blue,
                                height: 1.3)),
                    ],
                  ),
                ),
                const Icon(Icons.edit_outlined, color: Color(0xFF94A3B8), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _enderecoCard() {
    if (_cliente == null) {
      return _infoTile(
        icon: Icons.place_outlined,
        label: 'Endereço de entrega',
        value: 'Selecione o cliente',
        muted: true,
      );
    }

    final rua = [
      _cliente!['endereco'],
      _cliente!['numero'],
    ].where((e) => (e ?? '').toString().trim().isNotEmpty).join(', ');
    final bairro = (_cliente!['bairro'] ?? '').toString().trim();
    final cidade = (_cliente!['cidade_nome'] ?? '').toString().trim();
    final uf = (_cliente!['uf'] ?? '').toString().trim().toUpperCase();
    final linhas = <String>[
      if (rua.isNotEmpty) rua,
      if (bairro.isNotEmpty) bairro,
      if (cidade.isNotEmpty || uf.isNotEmpty) [cidade, uf].where((e) => e.isNotEmpty).join(' — '),
    ];

    if (linhas.isEmpty) {
      return _infoTile(
        icon: Icons.place_outlined,
        label: 'Endereço de entrega',
        value: 'Sem endereço cadastrado',
        muted: true,
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.place_outlined, size: 16, color: Color(0xFF64748B)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < linhas.length; i++)
                  Text(linhas[i],
                      style: TextStyle(
                          fontSize: (i == 0 ? 13 : 12) + Brand.textBump01cm,
                          fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                          color: i == 0 ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                          height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required IconData icon, required String titulo, required List<Widget> filhos}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Brand.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(titulo.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11 + Brand.textBump01cm,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Color(0xFF334155))),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: filhos,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldCaption(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(t,
            style: TextStyle(
                fontSize: 11 + Brand.textBump01cm,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B))),
      );

  Widget _field(String caption, Widget control, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          trailing == null
              ? _fieldCaption(caption)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [_fieldCaption(caption), Padding(padding: const EdgeInsets.only(bottom: 3), child: trailing)],
                ),
          control,
        ],
      ),
    );
  }

  Widget _infoTile({required IconData icon, required String label, required String value, bool muted = false}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: muted ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10 + Brand.textBump01cm,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF94A3B8))),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13 + Brand.textBump01cm,
                        fontWeight: FontWeight.w600,
                        color: muted ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                        height: 1.15)),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _tituloSecao(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 11 + Brand.textBump01cm,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Color(0xFF334155))),
      );

  Widget _selectorBox({
    required String texto,
    required IconData icon,
    required VoidCallback onTap,
    bool destaque = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14 + Brand.textBump01cm,
                        fontWeight: destaque ? FontWeight.w700 : FontWeight.w400,
                        color: destaque ? Colors.black87 : Colors.black54)),
              ),
              Icon(icon, color: Brand.blue, size: 22),
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
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: safeValue,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 22),
          style: TextStyle(
            fontSize: 14 + Brand.textBump01cm,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E293B),
          ),
          hint: Text(hint ?? 'Selecione',
              style: TextStyle(fontSize: 14 + Brand.textBump01cm, color: Colors.black.withValues(alpha: 0.45))),
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
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
    bool caixaAlta = true,
  }) {
    final isNumeric = teclado == TextInputType.number ||
        teclado == const TextInputType.numberWithOptions(decimal: true) ||
        teclado == const TextInputType.numberWithOptions(decimal: true, signed: true);
    return TextField(
      controller: c,
      keyboardType: teclado,
      onChanged: onChanged,
      enabled: enabled,
      textCapitalization: caixaAlta && !isNumeric ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: caixaAlta && !isNumeric ? withUpperCase() : null,
      style: TextStyle(fontSize: 14 + Brand.textBump01cm, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        isDense: true,
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Brand.blue, width: 1.4),
        ),
      ),
    );
  }

  Widget _resumoRow(String label, String valor, {bool destaque = false, Color? valorColor, bool compacto = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compacto ? 1.5 : 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: destaque ? FontWeight.w700 : FontWeight.w500,
                    fontSize: (destaque ? (compacto ? 13 : 14) : (compacto ? 12 : 13)) + Brand.textBump01cm,
                    color: destaque ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                    height: 1.2)),
          ),
          const SizedBox(width: 8),
          Text(valor,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: (destaque ? (compacto ? 14 : 15) : (compacto ? 12 : 13)) + Brand.textBump01cm,
                  color: valorColor ?? (destaque ? Brand.green : const Color(0xFF0F172A)),
                  height: 1.2)),
        ],
      ),
    );
  }
}

class _ItemListaTile extends StatelessWidget {
  const _ItemListaTile({
    super.key,
    required this.indice,
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final int indice;
  final _ItemPedido item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  String _fmtQtd(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final temDesconto = item.desconto > 0;

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Brand.blue.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Brand.blue.withValues(alpha: 0.18), Brand.blue.withValues(alpha: 0.08)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$indice',
                    style: TextStyle(fontWeight: FontWeight.w800, color: Brand.blue, fontSize: 11 + Brand.textBump01cm)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13 + Brand.textBump01cm, height: 1.2)),
                    const SizedBox(height: 3),
                    Text(
                      '${_fmtQtd(item.quantidade)} × ${brMoney(item.precoUnitario)}'
                      '${temDesconto ? '  •  desc. ${brMoney(item.desconto)}' : ''}',
                      style: TextStyle(fontSize: 11 + Brand.textBump01cm, color: Colors.black.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(brMoney(item.total),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14 + Brand.textBump01cm, color: Brand.green)),
                  if (temDesconto)
                    Text(brMoney(item.bruto),
                        style: TextStyle(
                            fontSize: 10 + Brand.textBump01cm,
                            color: Colors.black.withValues(alpha: 0.35),
                            decoration: TextDecoration.lineThrough)),
                ],
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: Colors.black.withValues(alpha: 0.25)),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: Colors.redAccent,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemFormSheet extends StatefulWidget {
  const _ItemFormSheet({
    required this.productId,
    required this.descricao,
    required this.precoUnitario,
    this.quantidadeInicial = 1,
    this.descontoPctInicial = 0,
    this.descontoValorInicial = 0,
    this.confirmLabel = 'Incluir item',
    this.produto,
    this.listaPreco,
  });

  final int productId;
  final String descricao;
  final double precoUnitario;
  final double quantidadeInicial;
  final double descontoPctInicial;
  final double descontoValorInicial;
  final String confirmLabel;
  final Map<String, dynamic>? produto;
  final Map<String, dynamic>? listaPreco;

  @override
  State<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<_ItemFormSheet> {
  late final TextEditingController _qtd;
  late final TextEditingController _descPct;
  late final TextEditingController _descValor;
  late double _precoUnitario;
  bool _sincDesc = false;

  String _fmtNum(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  String _fmtQtd(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void initState() {
    super.initState();
    _precoUnitario = widget.precoUnitario;
    _qtd = TextEditingController(text: _fmtQtd(widget.quantidadeInicial));
    _descPct = TextEditingController(text: _fmtNum(widget.descontoPctInicial));
    _descValor = TextEditingController(text: _fmtNum(widget.descontoValorInicial));
  }

  @override
  void dispose() {
    _qtd.dispose();
    _descPct.dispose();
    _descValor.dispose();
    super.dispose();
  }

  double _parseNum(String s) =>
      double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;

  double get _quantidade => _parseNum(_qtd.text).clamp(0.001, 999999.0).toDouble();

  double get _bruto => _quantidade * _precoUnitario;

  Future<void> _atualizarPrecoPorQtd() async {
    final produto = widget.produto;
    if (produto == null) return;
    final novo = await ProductPreco.resolve(
      produto,
      listaPreco: widget.listaPreco,
      quantidade: _quantidade,
    );
    if (!mounted) return;
    if ((novo - _precoUnitario).abs() > 0.0001) {
      setState(() => _precoUnitario = novo);
      _syncFromPct();
    }
  }

  double get _desconto {
    final pct = _parseNum(_descPct.text);
    if (pct > 0) return (_bruto * pct / 100).clamp(0.0, _bruto).toDouble();
    return _parseNum(_descValor.text).clamp(0.0, _bruto).toDouble();
  }

  void _syncFromPct() {
    if (_sincDesc) return;
    _sincDesc = true;
    final pct = _parseNum(_descPct.text);
    _descValor.text = _fmtNum((pct > 0 ? _bruto * pct / 100 : 0.0).toDouble());
    _sincDesc = false;
    setState(() {});
  }

  void _syncFromValor() {
    if (_sincDesc) return;
    _sincDesc = true;
    final valor = _parseNum(_descValor.text);
    final pct = _bruto > 0 ? valor / _bruto * 100.0 : 0.0;
    _descPct.text = _fmtNum(pct);
    _sincDesc = false;
    setState(() {});
  }

  void _alterarQtd(double delta) {
    final nova = (_parseNum(_qtd.text) + delta).clamp(0.001, 999999.0).toDouble();
    _qtd.text = _fmtQtd(nova);
    _syncFromPct();
    setState(() {});
    _atualizarPrecoPorQtd();
  }

  void _alterarDescPct(double delta) {
    final nova = (_parseNum(_descPct.text) + delta).clamp(0.0, 100.0).toDouble();
    _descPct.text = _fmtNum(nova);
    _syncFromPct();
    setState(() {});
  }

  void _alterarDescValor(double delta) {
    final nova = (_parseNum(_descValor.text) + delta).clamp(0.0, _bruto).toDouble();
    _descValor.text = _fmtNum(nova);
    _syncFromValor();
    setState(() {});
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Brand.blue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 48,
          child: Icon(icon, size: 20, color: Brand.blue),
        ),
      ),
    );
  }

  void _confirmar() {
    final qtd = _quantidade;
    if (qtd <= 0) return;

    final pct = _parseNum(_descPct.text);
    final item = _ItemPedido(
      productId: widget.productId,
      descricao: widget.descricao,
      quantidade: qtd,
      precoUnitario: _precoUnitario,
      descontoPercentual: pct > 0 ? pct : null,
      desconto: pct > 0 ? 0 : _parseNum(_descValor.text),
    );

    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(widget.descricao,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15 + Brand.textBump01cm)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Preço unitário (bloqueado)', style: TextStyle(color: Colors.black54)),
                      Text(brMoney(_precoUnitario),
                          style: TextStyle(fontWeight: FontWeight.w800, color: Brand.blue)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _stepBtn(Icons.remove_rounded, () => _alterarQtd(-1)),
                    Expanded(
                      child: TextField(
                        controller: _qtd,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Quantidade',
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        ),
                        onChanged: (_) {
                          _syncFromPct();
                          setState(() {});
                          _atualizarPrecoPorQtd();
                        },
                      ),
                    ),
                    _stepBtn(Icons.add_rounded, () => _alterarQtd(1)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _stepBtn(Icons.remove_rounded, () => _alterarDescPct(-1)),
                          Expanded(
                            child: TextField(
                              controller: _descPct,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                labelText: 'Desconto %',
                                suffixText: '%',
                                filled: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                              ),
                              onChanged: (_) => _syncFromPct(),
                            ),
                          ),
                          _stepBtn(Icons.add_rounded, () => _alterarDescPct(1)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          _stepBtn(Icons.remove_rounded, () => _alterarDescValor(-1)),
                          Expanded(
                            child: TextField(
                              controller: _descValor,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                labelText: 'Desconto R\$',
                                filled: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                              ),
                              onChanged: (_) => _syncFromValor(),
                            ),
                          ),
                          _stepBtn(Icons.add_rounded, () => _alterarDescValor(1)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total do item: ${brMoney(_bruto - _desconto)}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Brand.green)),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _confirmar,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(widget.confirmLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.green,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
  final _buscaCtrl = TextEditingController();
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

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _escanearBarras() async {
    final codigo = await escanearCodigoBarras(context);
    if (!mounted || codigo == null || codigo.isEmpty) return;

    _buscaCtrl.text = codigo;
    _termo = codigo;
    await _buscar();

    // Match exato de código de barras → seleciona direto.
    Map<String, dynamic>? exato;
    for (final r in _rows) {
      final barras = (r['codigo_barras'] ?? '').toString().trim();
      final cod = (r['codigo'] ?? '').toString().trim();
      if (barras == codigo || cod == codigo) {
        exato = r;
        break;
      }
    }
    if (exato != null && mounted) {
      Navigator.pop(context, exato);
    }
  }

  Future<void> _carregarGrupos() async {
    // Fonte oficial: cadastro de Grupos do ERP (sincronizado).
    // Fallback: DISTINCT nos produtos (sem tabela local / sync antigo).
    var nomes = <String>[];

    try {
      final rows = await _db.query(
        "SELECT nome FROM grupos WHERE (ativo = 1 OR ativo IS NULL) "
        "AND (mostrar_no_app = 1 OR mostrar_no_app IS NULL) "
        "AND nome IS NOT NULL AND TRIM(nome) <> '' ORDER BY nome",
      );
      nomes = rows
          .map((r) => (r['nome'] ?? '').toString().trim())
          .where((g) => g.isNotEmpty)
          .toList();
    } catch (_) {
      // Tabela grupos ausente — usa fallback abaixo.
    }

    if (nomes.isEmpty) {
      try {
        final rows = await _db.query(
          "SELECT DISTINCT grupo AS nome FROM products WHERE ativo = 1 AND mostrar_no_app = 1 "
          "AND grupo IS NOT NULL AND TRIM(grupo) <> '' ORDER BY grupo",
        );
        nomes = rows
            .map((r) => (r['nome'] ?? '').toString().trim())
            .where((g) => g.isNotEmpty)
            .toList();
      } catch (_) {
        nomes = [];
      }
    }

    if (!mounted) return;
    setState(() {
      _grupos = nomes;
      if (_grupoSel != null && !_grupos.contains(_grupoSel)) {
        _grupoSel = null;
      }
    });
  }

  Future<void> _buscar() async {
    List<Map<String, dynamic>> rows;
    if (_isProdutos) {
      final f = ProdutoBusca.filtro(_termo, grupo: _grupoSel);
      rows = await _db.query(
        'SELECT * FROM products WHERE ${f.whereExtra} ORDER BY ${f.orderBy} LIMIT 100',
        f.args,
      );
    } else {
      final like = '%${_termo.trim().toUpperCase()}%';
      final vendedorId = context.read<AppState>().config.vendedorId;
      if (widget.tabela == 'customers') {
        rows = await _db.query(
          "SELECT * FROM customers WHERE ativo = 1 AND ${FvCarteira.sqlEquals(vendedorId)} "
          "AND (${widget.campoNome} LIKE ? OR codigo LIKE ? OR apelido_fantasia LIKE ? OR cpf_cnpj LIKE ?) "
          'ORDER BY ${widget.campoNome} LIMIT 60',
          [...FvCarteira.args(vendedorId), like, like, like, like],
        );
      } else {
        rows = await _db.query(
          'SELECT * FROM ${widget.tabela} WHERE ${widget.campoNome} LIKE ? OR codigo LIKE ? ORDER BY ${widget.campoNome} LIMIT 60',
          [like, like],
        );
      }
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.titulo,
                                style: TextStyle(fontSize: 16 + Brand.textBump01cm, fontWeight: FontWeight.w700)),
                            if (_isProdutos) ...[
                              const SizedBox(height: 2),
                              Builder(
                                builder: (context) {
                                  final estoque = context.read<AppState>().config.estoqueNome.trim();
                                  final label = estoque.isEmpty ? 'Estoque não definido' : estoque;
                                  return Row(
                                    children: [
                                      Icon(
                                        Icons.inventory_2_outlined,
                                        size: 13,
                                        color: estoque.isEmpty ? Colors.black38 : Brand.blue,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'Estoque: $label',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12 + Brand.textBump01cm,
                                            fontWeight: FontWeight.w600,
                                            color: estoque.isEmpty ? Colors.black45 : Brand.blue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _buscaCtrl,
                    autofocus: false,
                    textInputAction: TextInputAction.search,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: withUpperCase(),
                    decoration: InputDecoration(
                      hintText: 'Buscar...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isProdutos
                          ? IconButton(
                              tooltip: 'Escanear código de barras',
                              onPressed: _escanearBarras,
                              icon: const Icon(Icons.qr_code_scanner, color: Brand.blue),
                            )
                          : null,
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
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
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
            color: sel ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 12.5 + Brand.textBump01cm),
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
    final fotoUrl = produtoFotoUrl(base, r['foto_url']);
    final productId = (r['id'] as num?)?.toInt();
    final descricao = (r['descricao'] ?? '').toString();
    return ProdutoListCard(
      produto: r,
      baseUrl: base,
      onTap: () => Navigator.pop(context, r),
      onFotoTap: () => abrirProdutoFoto(
        context,
        productId: productId,
        url: fotoUrl,
        titulo: descricao,
      ),
    );
  }
}
