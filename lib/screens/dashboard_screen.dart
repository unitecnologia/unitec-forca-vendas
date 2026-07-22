import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../ui/brand.dart';
import '../ui/format.dart';
import '../ui/meta_gauge.dart';

/// Dashboard online: meta, vendas e títulos — compacto e profissional.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _carregando = true;
  String? _erro;

  String? _vendedorNome;
  double _meta = 0;
  double _realizadoMes = 0;
  double _percentual = 0;
  double _vendidoHoje = 0;
  int _pedidosHoje = 0;
  double _vendidoMes = 0;
  int _pedidosMes = 0;
  double _ticketMes = 0;
  int _titulosQtd = 0;
  double _titulosValor = 0;
  int _vencidosQtd = 0;
  double _vencidosValor = 0;
  int _syncPendentes = 0;
  int _syncErro = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final state = context.read<AppState>();
      final data = await state.api.dashboard();

      final db = LocalDb.instance;
      final pe = await db.query("SELECT COUNT(*) c FROM outbox_orders WHERE status = 'pendente'");
      final er = await db.query("SELECT COUNT(*) c FROM outbox_orders WHERE status = 'erro'");

      if (!mounted) return;
      setState(() {
        final nomeApi = (data['vendedor_nome'] as String?)?.trim();
        _vendedorNome = (nomeApi != null && nomeApi.isNotEmpty) ? nomeApi : state.config.vendedorNome;
        _meta = (data['meta_mensal'] as num?)?.toDouble() ?? 0;
        _realizadoMes = (data['realizado_mes'] as num?)?.toDouble() ?? 0;
        _percentual = (data['percentual_meta'] as num?)?.toDouble() ?? 0;
        _vendidoHoje = (data['vendido_hoje'] as num?)?.toDouble() ?? 0;
        _pedidosHoje = (data['pedidos_hoje'] as num?)?.toInt() ?? 0;
        _vendidoMes = (data['vendido_mes'] as num?)?.toDouble() ?? 0;
        _pedidosMes = (data['pedidos_mes'] as num?)?.toInt() ?? 0;
        _ticketMes = (data['ticket_medio_mes'] as num?)?.toDouble() ?? 0;
        _titulosQtd = (data['titulos_aberto_qtd'] as num?)?.toInt() ?? 0;
        _titulosValor = (data['titulos_aberto_valor'] as num?)?.toDouble() ?? 0;
        _vencidosQtd = (data['titulos_vencidos_qtd'] as num?)?.toInt() ?? 0;
        _vencidosValor = (data['titulos_vencidos_valor'] as num?)?.toDouble() ?? 0;
        _syncPendentes = (pe.first['c'] as num?)?.toInt() ?? 0;
        _syncErro = (er.first['c'] as num?)?.toInt() ?? 0;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? _erroView()
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                    children: [
                      if (_syncPendentes > 0 || _syncErro > 0) ...[
                        _syncBanner(),
                        const SizedBox(height: 10),
                      ],
                      if (_meta > 0) ...[
                        MetaGaugeCard(
                          meta: _meta,
                          realizado: _realizadoMes,
                          percentual: _percentual,
                          nome: _vendedorNome,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _secao('Vendas'),
                      Row(
                        children: [
                          Expanded(
                            child: _mini(
                              'Hoje',
                              brMoney(_vendidoHoje),
                              '$_pedidosHoje ped.',
                              Brand.blue,
                              Icons.today_outlined,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _mini(
                              'Mês',
                              brMoney(_vendidoMes),
                              '$_pedidosMes ped.',
                              Brand.green,
                              Icons.calendar_month_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _mini(
                        'Ticket médio (mês)',
                        brMoney(_ticketMes),
                        null,
                        const Color(0xFF0D9488),
                        Icons.receipt_long_outlined,
                        wide: true,
                      ),
                      const SizedBox(height: 14),
                      _secao('Títulos da carteira'),
                      Row(
                        children: [
                          Expanded(
                            child: _mini(
                              'Em aberto',
                              brMoney(_titulosValor),
                              '$_titulosQtd título(s)',
                              Brand.blue,
                              Icons.request_quote_outlined,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _mini(
                              'Vencidos',
                              brMoney(_vencidosValor),
                              '$_vencidosQtd título(s)',
                              _vencidosQtd > 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                              Icons.warning_amber_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Dados online do ERP · puxe para atualizar',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.4)),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _erroView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 42, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            const Text(
              'Dashboard precisa de internet',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _erro ?? 'Não foi possível carregar.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _syncBanner() {
    final msg = [
      if (_syncPendentes > 0) '$_syncPendentes pendente(s)',
      if (_syncErro > 0) '$_syncErro com erro',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: Color(0xFFEA580C), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Fila do aparelho: $msg',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFF9A3412)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secao(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.2),
        ),
      );

  Widget _mini(
    String label,
    String valor,
    String? sub,
    Color cor,
    IconData icon, {
    bool wide = false,
  }) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x120F172A), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: cor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valor, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                ),
                if (sub != null)
                  Text(sub, style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
