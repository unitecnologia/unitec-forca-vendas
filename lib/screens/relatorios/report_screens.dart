import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../reports/report_data.dart';
import '../../ui/brand.dart';
import '../../ui/format.dart';
import '../../ui/report_widgets.dart';
import '../../ui/uppercase_input.dart';

class MinhasVendasReportScreen extends StatefulWidget {
  const MinhasVendasReportScreen({super.key});

  @override
  State<MinhasVendasReportScreen> createState() => _MinhasVendasReportScreenState();
}

enum _PeriodoVendas { hoje, semana, mes, personalizado }

class _MinhasVendasReportScreenState extends State<MinhasVendasReportScreen> {
  MinhasVendasResumo? _dados;
  bool _carregando = true;
  _PeriodoVendas _periodo = _PeriodoVendas.mes;
  late DateTime _inicio;
  late DateTime _fim;

  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _aplicarPreset(_PeriodoVendas.mes);
    _carregar();
  }

  void _aplicarPreset(_PeriodoVendas p) {
    final agora = DateTime.now();
    _periodo = p;
    switch (p) {
      case _PeriodoVendas.hoje:
        _inicio = ReportData.startOfDay(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoVendas.semana:
        _inicio = ReportData.startOfWeek(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoVendas.mes:
        _inicio = ReportData.startOfMonth(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoVendas.personalizado:
        // mantém _inicio/_fim já escolhidos
        break;
    }
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final d = await ReportData.minhasVendas(inicio: _inicio, fim: _fim);
    if (mounted) {
      setState(() {
        _dados = d;
        _carregando = false;
      });
    }
  }

  Future<void> _escolherPeriodo() async {
    final de = await showDatePicker(
      context: context,
      initialDate: _inicio,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Data inicial',
    );
    if (de == null || !mounted) return;
    final ate = await showDatePicker(
      context: context,
      initialDate: _fim.isBefore(de) ? de : _fim,
      firstDate: de,
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Data final',
    );
    if (ate == null || !mounted) return;
    setState(() {
      _periodo = _PeriodoVendas.personalizado;
      _inicio = ReportData.startOfDay(de);
      _fim = ReportData.startOfDay(ate);
    });
    await _carregar();
  }

  String get _rotuloPeriodo {
    if (_periodo == _PeriodoVendas.hoje) return 'Hoje · ${_fmt.format(_inicio)}';
    if (_inicio.year == _fim.year && _inicio.month == _fim.month && _inicio.day == _fim.day) {
      return _fmt.format(_inicio);
    }
    return '${_fmt.format(_inicio)} — ${_fmt.format(_fim)}';
  }

  Widget _chip(_PeriodoVendas p, String label) {
    final sel = _periodo == p;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        selectedColor: Brand.blue.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: sel ? Brand.blue : Colors.black87,
          fontSize: 13,
        ),
        onSelected: (_) {
          setState(() => _aplicarPreset(p));
          _carregar();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportScaffold(
      title: 'Minhas vendas',
      onRefresh: _carregar,
      body: _carregando
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Vendas faturadas no ERP (histórico sincronizado).',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip(_PeriodoVendas.hoje, 'Hoje'),
                      _chip(_PeriodoVendas.semana, 'Semana'),
                      _chip(_PeriodoVendas.mes, 'Mês'),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Icon(
                            Icons.calendar_month_outlined,
                            size: 18,
                            color: _periodo == _PeriodoVendas.personalizado ? Brand.blue : Colors.black54,
                          ),
                          label: Text(
                            'Período',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _periodo == _PeriodoVendas.personalizado ? Brand.blue : Colors.black87,
                            ),
                          ),
                          backgroundColor: _periodo == _PeriodoVendas.personalizado
                              ? Brand.blue.withValues(alpha: 0.14)
                              : null,
                          onPressed: _escolherPeriodo,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Brand.blue.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range_outlined, size: 18, color: Brand.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _rotuloPeriodo,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Brand.textPrimary),
                        ),
                      ),
                      if (_periodo == _PeriodoVendas.personalizado)
                        TextButton(
                          onPressed: _escolherPeriodo,
                          child: const Text('Alterar'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ReportStatGrid(items: [
                  ReportStatItem('Vendido no período', brMoney(_dados!.total), Icons.payments_outlined, Brand.blue),
                  ReportStatItem('Pedidos no período', '${_dados!.qtd}', Icons.receipt_long_outlined, Brand.green),
                ]),
                const SizedBox(height: 12),
                ReportListCard(
                  title: 'Ticket médio',
                  subtitle: Text(
                    brMoney(_dados!.ticketMedio),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.blue),
                  ),
                ),
              ],
            ),
    );
  }
}

enum _PeriodoClientes { hoje, semana, mes, personalizado }

class ClientesAtendidosReportScreen extends StatefulWidget {
  const ClientesAtendidosReportScreen({super.key});

  @override
  State<ClientesAtendidosReportScreen> createState() => _ClientesAtendidosReportScreenState();
}

class _ClientesAtendidosReportScreenState extends State<ClientesAtendidosReportScreen> {
  List<ClienteAtendido> _lista = [];
  bool _carregando = true;
  String _termo = '';
  _PeriodoClientes _periodo = _PeriodoClientes.mes;
  late DateTime _inicio;
  late DateTime _fim;

  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _aplicarPreset(_PeriodoClientes.mes);
    _carregar();
  }

  void _aplicarPreset(_PeriodoClientes p) {
    final agora = DateTime.now();
    _periodo = p;
    switch (p) {
      case _PeriodoClientes.hoje:
        _inicio = ReportData.startOfDay(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoClientes.semana:
        _inicio = ReportData.startOfWeek(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoClientes.mes:
        _inicio = ReportData.startOfMonth(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoClientes.personalizado:
        break;
    }
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final vendedorId = context.read<AppState>().config.vendedorId;
    final rows = await ReportData.clientesAtendidos(
      vendedorId,
      inicio: _inicio,
      fim: _fim,
    );
    if (mounted) {
      setState(() {
        _lista = rows;
        _carregando = false;
      });
    }
  }

  Future<void> _escolherPeriodo() async {
    final de = await showDatePicker(
      context: context,
      initialDate: _inicio,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Data inicial',
    );
    if (de == null || !mounted) return;
    final ate = await showDatePicker(
      context: context,
      initialDate: _fim.isBefore(de) ? de : _fim,
      firstDate: de,
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Data final',
    );
    if (ate == null || !mounted) return;
    setState(() {
      _periodo = _PeriodoClientes.personalizado;
      _inicio = ReportData.startOfDay(de);
      _fim = ReportData.startOfDay(ate);
    });
    await _carregar();
  }

  String get _rotuloPeriodo {
    if (_periodo == _PeriodoClientes.hoje) return 'Hoje · ${_fmt.format(_inicio)}';
    if (_inicio.year == _fim.year && _inicio.month == _fim.month && _inicio.day == _fim.day) {
      return _fmt.format(_inicio);
    }
    return '${_fmt.format(_inicio)} — ${_fmt.format(_fim)}';
  }

  List<ClienteAtendido> get _filtrados {
    final t = _termo.trim().toLowerCase();
    if (t.isEmpty) return _lista;
    return _lista.where((c) => c.nome.toLowerCase().contains(t)).toList();
  }

  Color _corStatus(String s) => switch (s) {
        'Inadimplente' => Colors.red,
        'Parado' => const Color(0xFFEA580C),
        'Só visita' => const Color(0xFF64748B),
        _ => Brand.green,
      };

  Widget _chip(_PeriodoClientes p, String label) {
    final sel = _periodo == p;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        selectedColor: Brand.blue.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: sel ? Brand.blue : Colors.black87,
          fontSize: 13,
        ),
        onSelected: (_) {
          setState(() => _aplicarPreset(p));
          _carregar();
        },
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color ?? const Color(0xFF64748B)),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color ?? const Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return ReportScaffold(
      title: 'Clientes atendidos',
      onRefresh: _carregar,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip(_PeriodoClientes.hoje, 'Hoje'),
                      _chip(_PeriodoClientes.semana, 'Semana'),
                      _chip(_PeriodoClientes.mes, 'Mês'),
                      ActionChip(
                        avatar: Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                          color: _periodo == _PeriodoClientes.personalizado ? Brand.blue : Colors.black54,
                        ),
                        label: Text(
                          'Período',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _periodo == _PeriodoClientes.personalizado ? Brand.blue : Colors.black87,
                          ),
                        ),
                        backgroundColor: _periodo == _PeriodoClientes.personalizado
                            ? Brand.blue.withValues(alpha: 0.14)
                            : null,
                        onPressed: _escolherPeriodo,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Brand.blue.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range_outlined, size: 16, color: Brand.blue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _rotuloPeriodo,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Brand.textPrimary),
                        ),
                      ),
                      Text(
                        '${lista.length} cliente${lista.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: withUpperCase(),
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, color: Brand.blue, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: (s) => setState(() => _termo = s),
                ),
              ],
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : lista.isEmpty
                    ? const ReportEmpty(message: 'Nenhum cliente atendido no período.\nAjuste o filtro ou sincronize.')
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          itemCount: lista.length,
                          itemBuilder: (_, i) {
                            final c = lista[i];
                            final compra = c.ultimaCompra != null
                                ? brDate(ReportData.isoDate(c.ultimaCompra!))
                                : (c.ultimaVisita != null ? 'visita' : '—');
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: Brand.surfaceCard(radius: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.nome,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _corStatus(c.status).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          c.status,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: _corStatus(c.status),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      _meta(Icons.event_outlined, compra),
                                      _meta(Icons.payments_outlined, brMoney(c.totalComprado), color: Brand.blue),
                                      _meta(Icons.receipt_long_outlined, '${c.qtdPedidos} ped.'),
                                      _meta(
                                        Icons.account_balance_wallet_outlined,
                                        brMoney(c.valorAberto),
                                        color: c.valorAberto > 0 ? const Color(0xFFEA580C) : null,
                                      ),
                                      if (c.whatsapp.isNotEmpty) _meta(Icons.chat_outlined, c.whatsapp),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class ClientesSemCompraReportScreen extends StatefulWidget {
  const ClientesSemCompraReportScreen({super.key});

  @override
  State<ClientesSemCompraReportScreen> createState() => _ClientesSemCompraReportScreenState();
}

class _ClientesSemCompraReportScreenState extends State<ClientesSemCompraReportScreen> {
  int _dias = 30;
  List<ClienteSemCompra> _lista = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final vendedorId = context.read<AppState>().config.vendedorId;
    final rows = await ReportData.clientesSemCompra(_dias, vendedorId);
    if (mounted) setState(() {
      _lista = rows;
      _carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ReportScaffold(
      title: 'Clientes sem compra',
      onRefresh: _carregar,
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [15, 30, 60, 90].map((d) {
                final sel = _dias == d;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$d dias'),
                    selected: sel,
                    onSelected: (_) {
                      setState(() => _dias = d);
                      _carregar();
                    },
                    selectedColor: Brand.blue,
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _lista.isEmpty
                    ? ReportEmpty(message: 'Nenhum cliente sem compra há $_dias dias ou mais.')
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _lista.length,
                          itemBuilder: (_, i) {
                            final c = _lista[i];
                            return ReportListCard(
                              title: c.nome,
                              badge: '${c.diasSemCompra} dias',
                              badgeColor: const Color(0xFFEA580C),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _linha('Última compra', brDate(ReportData.isoDate(c.ultimaCompra))),
                                  if (c.whatsapp.isNotEmpty) _linha('WhatsApp', c.whatsapp),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _linha(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            children: [
              TextSpan(text: '$k: '),
              TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF334155))),
            ],
          ),
        ),
      );
}

class ContasAbertoReportScreen extends StatefulWidget {
  const ContasAbertoReportScreen({super.key});

  @override
  State<ContasAbertoReportScreen> createState() => _ContasAbertoReportScreenState();
}

class _ContasAbertoReportScreenState extends State<ContasAbertoReportScreen> {
  List<ContaAbertoCliente> _lista = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final vendedorId = context.read<AppState>().config.vendedorId;
    final rows = await ReportData.contasAbertoCarteira(vendedorId);
    if (mounted) {
      setState(() {
        _lista = rows;
        _carregando = false;
      });
    }
  }

  Widget _meta(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color ?? const Color(0xFF64748B)),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color ?? const Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportScaffold(
      title: 'Contas em aberto',
      onRefresh: _carregar,
      body: _carregando
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())],
            )
          : _lista.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80),
                    ReportEmpty(message: 'Nenhum título em aberto nos clientes da sua carteira.'),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _lista.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Somente clientes da sua carteira Força de Vendas.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        );
                      }
                      final c = _lista[i - 1];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: Brand.surfaceCard(radius: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.nome,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                if (c.maxDiasAtraso > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${c.maxDiasAtraso}d atraso',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                _meta(
                                  Icons.warning_amber_rounded,
                                  'Venc. ${brMoney(c.valorVencido)}',
                                  color: c.valorVencido > 0 ? Colors.red : const Color(0xFF64748B),
                                ),
                                _meta(
                                  Icons.schedule_outlined,
                                  'A vencer ${brMoney(c.valorAVencer)}',
                                  color: Brand.blue,
                                ),
                                _meta(
                                  Icons.event_outlined,
                                  c.ultimaCompra != null
                                      ? brDate(ReportData.isoDate(c.ultimaCompra!))
                                      : '—',
                                ),
                                if (c.whatsapp.isNotEmpty) _meta(Icons.chat_outlined, c.whatsapp),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

enum _PeriodoVisitas { hoje, semana, mes, personalizado }

class VisitasReportScreen extends StatefulWidget {
  const VisitasReportScreen({super.key});

  @override
  State<VisitasReportScreen> createState() => _VisitasReportScreenState();
}

class _VisitasReportScreenState extends State<VisitasReportScreen> {
  List<VisitaRegistro> _lista = [];
  bool _carregando = true;
  _PeriodoVisitas _periodo = _PeriodoVisitas.mes;
  late DateTime _inicio;
  late DateTime _fim;

  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _aplicarPreset(_PeriodoVisitas.mes);
    _carregar();
  }

  void _aplicarPreset(_PeriodoVisitas p) {
    final agora = DateTime.now();
    _periodo = p;
    switch (p) {
      case _PeriodoVisitas.hoje:
        _inicio = ReportData.startOfDay(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoVisitas.semana:
        _inicio = ReportData.startOfWeek(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoVisitas.mes:
        _inicio = ReportData.startOfMonth(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoVisitas.personalizado:
        break;
    }
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final vendedorId = context.read<AppState>().config.vendedorId;
    final rows = await ReportData.visitasRealizadas(
      vendedorId,
      inicio: _inicio,
      fim: _fim,
    );
    if (mounted) {
      setState(() {
        _lista = rows;
        _carregando = false;
      });
    }
  }

  Future<void> _escolherPeriodo() async {
    final de = await showDatePicker(
      context: context,
      initialDate: _inicio,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Data inicial',
    );
    if (de == null || !mounted) return;
    final ate = await showDatePicker(
      context: context,
      initialDate: _fim.isBefore(de) ? de : _fim,
      firstDate: de,
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Data final',
    );
    if (ate == null || !mounted) return;
    setState(() {
      _periodo = _PeriodoVisitas.personalizado;
      _inicio = ReportData.startOfDay(de);
      _fim = ReportData.startOfDay(ate);
    });
    await _carregar();
  }

  String get _rotuloPeriodo {
    if (_periodo == _PeriodoVisitas.hoje) return 'Hoje · ${_fmt.format(_inicio)}';
    if (_inicio.year == _fim.year && _inicio.month == _fim.month && _inicio.day == _fim.day) {
      return _fmt.format(_inicio);
    }
    return '${_fmt.format(_inicio)} — ${_fmt.format(_fim)}';
  }

  Widget _chip(_PeriodoVisitas p, String label) {
    final sel = _periodo == p;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        selectedColor: Brand.blue.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: sel ? Brand.blue : Colors.black87,
          fontSize: 13,
        ),
        onSelected: (_) {
          setState(() => _aplicarPreset(p));
          _carregar();
        },
      ),
    );
  }

  String _fmtData(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return ReportScaffold(
      title: 'Visitas realizadas',
      onRefresh: _carregar,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip(_PeriodoVisitas.hoje, 'Hoje'),
                      _chip(_PeriodoVisitas.semana, 'Semana'),
                      _chip(_PeriodoVisitas.mes, 'Mês'),
                      ActionChip(
                        avatar: Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                          color: _periodo == _PeriodoVisitas.personalizado ? Brand.blue : Colors.black54,
                        ),
                        label: Text(
                          'Período',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _periodo == _PeriodoVisitas.personalizado ? Brand.blue : Colors.black87,
                          ),
                        ),
                        backgroundColor: _periodo == _PeriodoVisitas.personalizado
                            ? Brand.blue.withValues(alpha: 0.14)
                            : null,
                        onPressed: _escolherPeriodo,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Brand.blue.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range_outlined, size: 16, color: Brand.blue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _rotuloPeriodo,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Brand.textPrimary),
                        ),
                      ),
                      Text(
                        '${_lista.length} visita${_lista.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _lista.isEmpty
                    ? const ReportEmpty(message: 'Nenhuma visita no período selecionado.')
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _lista.length,
                          itemBuilder: (_, i) {
                            final v = _lista[i];
                            return ReportListCard(
                              title: v.clienteNome,
                              badge: v.status == 'enviado' ? 'Enviada' : v.status,
                              badgeColor: v.status == 'enviado' ? Brand.green : Colors.orange,
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _linha('Data', _fmtData(v.createdAt)),
                                  _linha('Motivo', v.motivo),
                                  if (v.temGps)
                                    _linha(
                                      'GPS',
                                      '${v.latitude!.toStringAsFixed(5)}, ${v.longitude!.toStringAsFixed(5)}',
                                    ),
                                  if (v.telefone.isNotEmpty) _linha('Telefone', v.telefone),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _linha(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            children: [
              TextSpan(text: '$k: '),
              TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF334155))),
            ],
          ),
        ),
      );
}

enum _PeriodoComissao { hoje, semana, mes, personalizado }

/// Relatório online: comissão do vendedor (alíquotas do cadastro × vendas).
class ComissoesReportScreen extends StatefulWidget {
  const ComissoesReportScreen({super.key});

  @override
  State<ComissoesReportScreen> createState() => _ComissoesReportScreenState();
}

class _ComissoesReportScreenState extends State<ComissoesReportScreen> {
  bool _carregando = true;
  String? _erro;
  _PeriodoComissao _periodo = _PeriodoComissao.mes;
  late DateTime _inicio;
  late DateTime _fim;

  double _pctAv = 0;
  double _pctAp = 0;
  int _qtd = 0;
  double _totalAvista = 0;
  double _totalAprazo = 0;
  double _totalGeral = 0;
  double _comAvista = 0;
  double _comAprazo = 0;
  double _comTotal = 0;
  List<Map<String, dynamic>> _itens = [];
  int? _vendaExpandida;

  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _aplicarPreset(_PeriodoComissao.mes);
    _carregar();
  }

  void _aplicarPreset(_PeriodoComissao p) {
    final agora = DateTime.now();
    _periodo = p;
    switch (p) {
      case _PeriodoComissao.hoje:
        _inicio = ReportData.startOfDay(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoComissao.semana:
        _inicio = ReportData.startOfWeek(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoComissao.mes:
        _inicio = ReportData.startOfMonth(agora);
        _fim = ReportData.startOfDay(agora);
      case _PeriodoComissao.personalizado:
        break;
    }
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final api = context.read<AppState>().api;
      final data = await api.comissao(de: _iso(_inicio), ate: _iso(_fim));
      if (!mounted) return;
      setState(() {
        _pctAv = (data['comissao_av'] as num?)?.toDouble() ?? 0;
        _pctAp = (data['comissao_ap'] as num?)?.toDouble() ?? 0;
        _qtd = (data['qtd'] as num?)?.toInt() ?? 0;
        _totalAvista = (data['total_avista'] as num?)?.toDouble() ?? 0;
        _totalAprazo = (data['total_aprazo'] as num?)?.toDouble() ?? 0;
        _totalGeral = (data['total_geral'] as num?)?.toDouble() ?? 0;
        _comAvista = (data['comissao_avista'] as num?)?.toDouble() ?? 0;
        _comAprazo = (data['comissao_aprazo'] as num?)?.toDouble() ?? 0;
        _comTotal = (data['comissao_total'] as num?)?.toDouble() ?? 0;
        final raw = data['itens'];
        _itens = raw is List
            ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
        _vendaExpandida = null;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e.toString();
      });
    }
  }

  Future<void> _escolherPeriodo() async {
    final de = await showDatePicker(
      context: context,
      initialDate: _inicio,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Data inicial',
    );
    if (de == null || !mounted) return;
    final ate = await showDatePicker(
      context: context,
      initialDate: _fim.isBefore(de) ? de : _fim,
      firstDate: de,
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Data final',
    );
    if (ate == null || !mounted) return;
    setState(() {
      _periodo = _PeriodoComissao.personalizado;
      _inicio = ReportData.startOfDay(de);
      _fim = ReportData.startOfDay(ate);
    });
    await _carregar();
  }

  String get _rotuloPeriodo {
    if (_periodo == _PeriodoComissao.hoje) return 'Hoje · ${_fmt.format(_inicio)}';
    if (_inicio.year == _fim.year && _inicio.month == _fim.month && _inicio.day == _fim.day) {
      return _fmt.format(_inicio);
    }
    return '${_fmt.format(_inicio)} — ${_fmt.format(_fim)}';
  }

  Widget _chip(_PeriodoComissao p, String label) {
    final sel = _periodo == p;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        visualDensity: VisualDensity.compact,
        label: Text(label),
        selected: sel,
        selectedColor: Brand.blue.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: sel ? Brand.blue : Colors.black87,
          fontSize: 12.5,
        ),
        onSelected: (_) {
          setState(() => _aplicarPreset(p));
          _carregar();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportScaffold(
      title: 'Minhas comissões',
      onRefresh: _carregando ? null : _carregar,
      body: _carregando
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())],
            )
          : _erro != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 40),
                    Icon(Icons.wifi_off_rounded, size: 48, color: Colors.black.withValues(alpha: 0.25)),
                    const SizedBox(height: 12),
                    const Text(
                      'Não foi possível carregar as comissões',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Este relatório funciona somente online.\n$_erro',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: FilledButton.icon(
                        onPressed: _carregar,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar de novo'),
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                  children: [
                    const Text(
                      'Online · % à vista / a prazo do cadastro do colaborador.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _chip(_PeriodoComissao.hoje, 'Hoje'),
                          _chip(_PeriodoComissao.semana, 'Semana'),
                          _chip(_PeriodoComissao.mes, 'Mês'),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(
                                Icons.calendar_month_outlined,
                                size: 16,
                                color: _periodo == _PeriodoComissao.personalizado ? Brand.blue : Colors.black54,
                              ),
                              label: Text(
                                'Período',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: _periodo == _PeriodoComissao.personalizado ? Brand.blue : Colors.black87,
                                ),
                              ),
                              backgroundColor: _periodo == _PeriodoComissao.personalizado
                                  ? Brand.blue.withValues(alpha: 0.14)
                                  : null,
                              onPressed: _escolherPeriodo,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Brand.blue.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range_outlined, size: 16, color: Brand.blue),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _rotuloPeriodo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: Brand.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: Brand.surfaceCard(radius: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Comissão do período',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black.withValues(alpha: 0.45),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      brMoney(_comTotal),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF7C3AED),
                                        letterSpacing: -0.4,
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '$_qtd venda(s)',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _resumoMini('À vista', brMoney(_comAvista), Brand.blue),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _resumoMini('A prazo', brMoney(_comAprazo), const Color(0xFFEA580C)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Base AV ${brMoney(_totalAvista)} · AP ${brMoney(_totalAprazo)}'
                            ' · total ${brMoney(_totalGeral)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), height: 1.25),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Alíquotas AV ${_pctAv.toStringAsFixed(2)}% · AP ${_pctAp.toStringAsFixed(2)}%',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                    if (_itens.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Vendas (${_itens.length}) · toque para detalhe',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 4, offset: Offset(0, 1))],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < _itens.length && i < 120; i++) ...[
                              if (i > 0) const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                              _linhaVenda(i, _itens[i]),
                            ],
                          ],
                        ),
                      ),
                      if (_itens.length > 120) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Mostrando 120 de ${_itens.length}.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10.5, color: Colors.black.withValues(alpha: 0.4)),
                        ),
                      ],
                    ],
                  ],
                ),
    );
  }

  Widget _resumoMini(String label, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cor)),
          const SizedBox(height: 1),
          Text(valor, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  /// Linha compacta; toque expande data, forma, AV/AP e comissão.
  Widget _linhaVenda(int index, Map<String, dynamic> item) {
    final expandida = _vendaExpandida == index;
    final aPrazo = item['tipo'] == 'aprazo';
    final data = (item['data'] ?? '').toString();
    final dt = DateTime.tryParse(data);
    final dataCurta = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}'
        : data;
    final dataFull = dt != null ? _fmt.format(dt) : data;
    final forma = (item['forma'] ?? '—').toString();
    final cliente = (item['cliente'] ?? '—').toString();
    final venda = brMoney((item['total'] as num?)?.toDouble() ?? 0);
    final comissao = brMoney((item['comissao'] as num?)?.toDouble() ?? 0);
    final cor = aPrazo ? const Color(0xFFEA580C) : Brand.blue;

    return Material(
      color: expandida ? const Color(0xFFF8FAFC) : (index.isOdd ? const Color(0xFFFAFBFC) : Colors.white),
      child: InkWell(
        onTap: () => setState(() => _vendaExpandida = expandida ? null : index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: cliente,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                          ),
                          TextSpan(
                            text: ' · $dataCurta',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    venda,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    expandida ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 18,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
              if (expandida) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _detalheRow('Tipo', aPrazo ? 'A prazo' : 'À vista', cor),
                      _detalheRow('Data', dataFull),
                      _detalheRow('Forma', forma),
                      _detalheRow('Venda', venda),
                      _detalheRow('Comissão', comissao, cor),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detalheRow(String label, String valor, [Color? valorCor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: valorCor ?? const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

