import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../fv_carteira.dart';
import '../ui/brand.dart';
import '../ui/format.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = LocalDb.instance;
  bool _carregando = true;

  int _produtos = 0;
  int _clientes = 0;
  int _pedPendentes = 0;
  int _pedEnviados = 0;
  int _pedErro = 0;
  double _pedTotal = 0;
  int _titulos = 0;
  double _titulosTotal = 0;
  int _titulosVencidos = 0;
  double _titulosVencidosTotal = 0;
  int _vendas = 0;
  double _vendasTotal = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<int> _scalarInt(String sql, [List<Object?>? args]) async {
    final r = await _db.query(sql, args);
    final v = r.first.values.first;
    return (v is int) ? v : (v is num ? v.toInt() : 0);
  }

  Future<double> _scalarDouble(String sql, [List<Object?>? args]) async {
    final r = await _db.query(sql, args);
    final v = r.first.values.first;
    return (v is num) ? v.toDouble() : 0.0;
  }

  Future<void> _carregar() async {
    final hoje = DateTime.now();
    final hojeStr =
        '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
    final vendedorId = context.read<AppState>().config.vendedorId;

    _produtos = await _scalarInt('SELECT COUNT(*) FROM products WHERE ativo = 1');
    _clientes = await _scalarInt(
      'SELECT COUNT(*) FROM customers WHERE ativo = 1 AND ${FvCarteira.sqlEquals(vendedorId)}',
      FvCarteira.args(vendedorId),
    );
    _pedPendentes = await _scalarInt("SELECT COUNT(*) FROM outbox_orders WHERE status = 'pendente'");
    _pedEnviados = await _scalarInt("SELECT COUNT(*) FROM outbox_orders WHERE status = 'enviado'");
    _pedErro = await _scalarInt("SELECT COUNT(*) FROM outbox_orders WHERE status = 'erro'");
    _pedTotal = await _scalarDouble('SELECT COALESCE(SUM(total),0) FROM outbox_orders');
    _titulos = await _scalarInt('SELECT COUNT(*) FROM financeiro WHERE saldo > 0');
    _titulosTotal = await _scalarDouble('SELECT COALESCE(SUM(saldo),0) FROM financeiro WHERE saldo > 0');
    _titulosVencidos = await _scalarInt('SELECT COUNT(*) FROM financeiro WHERE saldo > 0 AND vencimento < ?', [hojeStr]);
    _titulosVencidosTotal = await _scalarDouble('SELECT COALESCE(SUM(saldo),0) FROM financeiro WHERE saldo > 0 AND vencimento < ?', [hojeStr]);
    _vendas = await _scalarInt('SELECT COUNT(*) FROM historico_vendas');
    _vendasTotal = await _scalarDouble('SELECT COALESCE(SUM(total),0) FROM historico_vendas');

    if (mounted) setState(() => _carregando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(title: const Text('Dashboard'), backgroundColor: Brand.blue, foregroundColor: Colors.white),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _secao('Pedidos do aparelho'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [
                      _card('Pendentes', '$_pedPendentes', Icons.cloud_upload_outlined, Colors.orange),
                      _card('Enviados', '$_pedEnviados', Icons.cloud_done_outlined, Brand.green),
                      _card('Com erro', '$_pedErro', Icons.error_outline, Colors.red),
                      _card('Valor total', brMoney(_pedTotal), Icons.payments_outlined, Brand.blue),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _secao('Títulos (a receber)'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [
                      _card('Em aberto', '$_titulos', Icons.request_quote_outlined, Brand.blue),
                      _card('Total aberto', brMoney(_titulosTotal), Icons.account_balance_outlined, Brand.green),
                      _card('Vencidos', '$_titulosVencidos', Icons.event_busy_outlined, Colors.red),
                      _card('Valor vencido', brMoney(_titulosVencidosTotal), Icons.warning_amber_outlined, Colors.red),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _secao('Catálogo e histórico'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [
                      _card('Produtos', '$_produtos', Icons.inventory_2_outlined, Brand.blue),
                      _card('Clientes', '$_clientes', Icons.people_alt_outlined, Brand.green),
                      _card('Vendas (hist.)', '$_vendas', Icons.receipt_long_outlined, Brand.blue),
                      _card('Total vendas', brMoney(_vendasTotal), Icons.trending_up_outlined, Brand.green),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _secao(String titulo) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF455A64))),
      );

  Widget _card(String label, String valor, IconData icon, Color cor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: cor, size: 22),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
        ],
      ),
    );
  }
}
