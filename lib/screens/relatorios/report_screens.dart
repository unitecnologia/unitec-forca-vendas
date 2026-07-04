import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../reports/report_data.dart';
import '../../ui/brand.dart';
import '../../ui/format.dart';
import '../../ui/report_widgets.dart';

class MinhasVendasReportScreen extends StatefulWidget {
  const MinhasVendasReportScreen({super.key});

  @override
  State<MinhasVendasReportScreen> createState() => _MinhasVendasReportScreenState();
}

class _MinhasVendasReportScreenState extends State<MinhasVendasReportScreen> {
  MinhasVendasResumo? _dados;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final d = await ReportData.minhasVendas();
    if (mounted) setState(() {
      _dados = d;
      _carregando = false;
    });
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
                ReportStatGrid(items: [
                  ReportStatItem('Vendido hoje', brMoney(_dados!.totalHoje), Icons.today_outlined, Brand.blue),
                  ReportStatItem('Pedidos hoje', '${_dados!.qtdHoje}', Icons.receipt_outlined, Brand.green),
                  ReportStatItem('Vendido na semana', brMoney(_dados!.totalSemana), Icons.date_range_outlined, Brand.blue),
                  ReportStatItem('Pedidos na semana', '${_dados!.qtdSemana}', Icons.list_alt_outlined, Brand.green),
                  ReportStatItem('Vendido no mês', brMoney(_dados!.totalMes), Icons.calendar_month_outlined, const Color(0xFF7C3AED)),
                  ReportStatItem('Pedidos no mês', '${_dados!.qtdMes}', Icons.shopping_bag_outlined, const Color(0xFF7C3AED)),
                ]),
                const SizedBox(height: 12),
                ReportListCard(
                  title: 'Ticket médio (mês)',
                  subtitle: Text(
                    brMoney(_dados!.ticketMedioMes),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.blue),
                  ),
                ),
              ],
            ),
    );
  }
}

class ClientesAtendidosReportScreen extends StatefulWidget {
  const ClientesAtendidosReportScreen({super.key});

  @override
  State<ClientesAtendidosReportScreen> createState() => _ClientesAtendidosReportScreenState();
}

class _ClientesAtendidosReportScreenState extends State<ClientesAtendidosReportScreen> {
  List<ClienteAtendido> _lista = [];
  bool _carregando = true;
  String _termo = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final rows = await ReportData.clientesAtendidos();
    if (mounted) setState(() {
      _lista = rows;
      _carregando = false;
    });
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
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar cliente...',
                prefixIcon: const Icon(Icons.search, color: Brand.blue),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (s) => setState(() => _termo = s),
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : lista.isEmpty
                    ? const ReportEmpty(message: 'Nenhum cliente atendido ainda.\nSincronize ou registre pedidos/visitas.')
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: lista.length,
                          itemBuilder: (_, i) {
                            final c = lista[i];
                            return ReportListCard(
                              title: c.nome,
                              badge: c.status,
                              badgeColor: _corStatus(c.status),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _linha('Última compra', c.ultimaCompra != null ? brDate(ReportData.isoDate(c.ultimaCompra!)) : '—'),
                                  _linha('Total comprado', brMoney(c.totalComprado)),
                                  _linha('Pedidos', '${c.qtdPedidos}'),
                                  _linha('Em aberto', brMoney(c.valorAberto)),
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
    final rows = await ReportData.clientesSemCompra(_dias);
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
    final rows = await ReportData.contasAbertoCarteira();
    if (mounted) setState(() {
      _lista = rows;
      _carregando = false;
    });
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
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Somente clientes que você vendeu, pediu ou visitou.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ),
                      ..._lista.map((c) => ReportListCard(
                            title: c.nome,
                            badge: c.maxDiasAtraso > 0 ? '${c.maxDiasAtraso}d atraso' : null,
                            badgeColor: Colors.red,
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _linha('Vencido', brMoney(c.valorVencido), cor: Colors.red),
                                _linha('A vencer', brMoney(c.valorAVencer)),
                                _linha('Última compra', c.ultimaCompra != null ? brDate(ReportData.isoDate(c.ultimaCompra!)) : '—'),
                                if (c.whatsapp.isNotEmpty) _linha('WhatsApp', c.whatsapp),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
    );
  }

  Widget _linha(String k, String v, {Color? cor}) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            children: [
              TextSpan(text: '$k: '),
              TextSpan(
                text: v,
                style: TextStyle(fontWeight: FontWeight.w700, color: cor ?? const Color(0xFF334155)),
              ),
            ],
          ),
        ),
      );
}

class VisitasReportScreen extends StatefulWidget {
  const VisitasReportScreen({super.key});

  @override
  State<VisitasReportScreen> createState() => _VisitasReportScreenState();
}

class _VisitasReportScreenState extends State<VisitasReportScreen> {
  List<VisitaRegistro> _lista = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final rows = await ReportData.visitasRealizadas();
    if (mounted) setState(() {
      _lista = rows;
      _carregando = false;
    });
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
                    ReportEmpty(message: 'Nenhuma visita registrada neste aparelho.'),
                  ],
                )
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
                              _linha('GPS', '${v.latitude!.toStringAsFixed(5)}, ${v.longitude!.toStringAsFixed(5)}'),
                            if (v.telefone.isNotEmpty) _linha('Telefone', v.telefone),
                          ],
                        ),
                      );
                    },
                  ),
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
