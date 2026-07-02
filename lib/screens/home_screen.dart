import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../db/local_db.dart';
import '../sync/sync_service.dart';
import '../ui/brand.dart';
import '../ui/home_menu_card.dart';
import 'clientes_screen.dart';
import 'dashboard_screen.dart';
import 'log_screen.dart';
import 'novo_pedido_screen.dart';
import 'pedidos_screen.dart';
import 'produtos_screen.dart';
import 'titulos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _produtos = 0;
  int _clientes = 0;
  int _pendentes = 0;

  @override
  void initState() {
    super.initState();
    _atualizarContadores();
  }

  Future<void> _atualizarContadores() async {
    final db = LocalDb.instance;
    final pr = await db.count('products');
    final cl = await db.count('customers');
    final pe = await db.pendingCount();
    if (mounted) {
      setState(() {
        _produtos = pr;
        _clientes = cl;
        _pendentes = pe;
      });
    }
  }

  Future<void> _abrir(Widget tela) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    await _atualizarContadores();
  }

  void _emDesenvolvimento(String nome) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$nome — em desenvolvimento'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    final itens = <_MenuItem>[
      _MenuItem('Pedido/Orçamento', Icons.note_add_rounded, Brand.green,
          onTap: () => _abrir(const NovoPedidoScreen(tipoInicial: 'pedido')), destaque: true),
      _MenuItem('Orçamentos', Icons.request_quote_rounded, Brand.blue,
          onTap: () => _abrir(const PedidosScreen(tipoFiltro: 'orcamento'))),
      _MenuItem('Rotas', Icons.alt_route_rounded, Brand.blue,
          onTap: () => _emDesenvolvimento('Rotas'), emDesenvolvimento: true),
      _MenuItem('Pedidos', Icons.fact_check_rounded, Brand.blue,
          onTap: () => _abrir(const PedidosScreen()), badge: _pendentes > 0 ? '$_pendentes' : null),
      _MenuItem('Clientes', Icons.people_alt_rounded, Brand.green,
          onTap: () => _abrir(const ClientesScreen())),
      _MenuItem('Produtos', Icons.inventory_2_rounded, Brand.blue,
          onTap: () => _abrir(const ProdutosScreen())),
      _MenuItem('Expectativa de Vendas', Icons.track_changes_rounded, Brand.green,
          onTap: () => _emDesenvolvimento('Expectativa de Vendas'), emDesenvolvimento: true),
      _MenuItem('Saldo Flex', Icons.account_balance_wallet_rounded, Brand.blue,
          onTap: () => _emDesenvolvimento('Saldo Flex'), emDesenvolvimento: true),
      _MenuItem('Visitas sem Venda', Icons.location_off_rounded, Brand.green,
          onTap: () => _emDesenvolvimento('Visitas sem Venda'), emDesenvolvimento: true),
      _MenuItem('Dashboard', Icons.insights_rounded, Brand.blue,
          onTap: () => _abrir(const DashboardScreen()), novo: true),
      _MenuItem('Títulos', Icons.payments_rounded, Brand.green,
          onTap: () => _abrir(const TitulosScreen())),
      _MenuItem('Relatórios', Icons.bar_chart_rounded, Brand.blue,
          onTap: () => _emDesenvolvimento('Relatórios'), emDesenvolvimento: true),
      _MenuItem('Sincronizar', Icons.sync_rounded, Brand.green, onTap: () async {
        await state.sync.syncNow();
        await _atualizarContadores();
      }),
      _MenuItem('Sair', Icons.logout_rounded, const Color(0xFFD32F2F),
          onTap: () => _confirmarSair(state)),
    ];

    return Scaffold(
      backgroundColor: Brand.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE3ECF5), Color(0xFFF1F4F8), Color(0xFFE8EEF5)],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: () async {
            await state.sync.syncNow();
            await _atualizarContadores();
          },
          child: CustomScrollView(
            slivers: [
            SliverToBoxAdapter(child: _Header(state: state)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _SyncCard(
                  sync: state.sync,
                  onSync: () async {
                    await state.sync.syncNow();
                    await _atualizarContadores();
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    _MiniStat(label: 'Produtos', value: _produtos, icon: Icons.inventory_2_rounded, color: Brand.blue),
                    const SizedBox(width: 10),
                    _MiniStat(label: 'Clientes', value: _clientes, icon: Icons.people_alt_rounded, color: Brand.green),
                    const SizedBox(width: 10),
                    _MiniStat(label: 'Pendentes', value: _pendentes, icon: Icons.cloud_upload_rounded, color: const Color(0xFF00838F)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => HomeMenuCard(
                    label: itens[i].label,
                    icon: itens[i].icon,
                    color: itens[i].color,
                    onTap: itens[i].onTap,
                    destaque: itens[i].destaque,
                    emDesenvolvimento: itens[i].emDesenvolvimento,
                    novo: itens[i].novo,
                    badge: itens[i].badge,
                  ),
                  childCount: itens.length,
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmarSair(AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Deseja encerrar a sessão?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
        ],
      ),
    );
    if (ok == true) {
      await state.logout();
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final empresa = state.config.empresaNome.isEmpty
        ? 'UNITECNOLOGIA SISTEMAS'
        : state.config.empresaNome.toUpperCase();
    final usuario = state.config.userName.isEmpty ? 'Representante' : state.config.userName;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Brand.blue, Brand.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFE3F2FD)],
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4)),
                    BoxShadow(color: Color(0x66FFFFFF), blurRadius: 2, offset: Offset(-1, -1)),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('U',
                    style: TextStyle(
                        color: Brand.blue, fontSize: 30, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(empresa,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, color: Colors.white70, size: 15),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(usuario,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                        Text(kAppVersionLabel,
                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Log',
                icon: const Icon(Icons.article_outlined, color: Colors.white),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  _MenuItem(
    this.label,
    this.icon,
    this.color, {
    required this.onTap,
    this.destaque = false,
    this.emDesenvolvimento = false,
    this.novo = false,
    this.badge,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool destaque;
  final bool emDesenvolvimento;
  final bool novo;
  final String? badge;
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.icon, required this.color});

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(Colors.white, color, 0.08)!,
              Color.lerp(const Color(0xFFEEF2F7), color, 0.14)!,
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            HomeMenuIcon3D(icon: icon, color: color, size: 36),
            const SizedBox(height: 6),
            Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.sync, required this.onSync});

  final SyncService sync;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final (color, label) = switch (sync.status) {
          SyncStatus.syncing => (Colors.blue, 'Sincronizando...'),
          SyncStatus.ok => (Brand.green, 'Sincronizado'),
          SyncStatus.offline => (Colors.orange, 'Offline (dados salvos no aparelho)'),
          SyncStatus.error => (Colors.red, 'Erro: ${sync.lastError ?? ''}'),
          SyncStatus.idle => (Colors.grey, 'Aguardando...'),
        };
        final last = sync.lastSyncAt != null
            ? DateFormat('dd/MM HH:mm:ss').format(sync.lastSyncAt!)
            : '—';
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                Color.lerp(Colors.white, color, 0.06)!,
                Color.lerp(const Color(0xFFEEF2F7), color, 0.12)!,
              ],
            ),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: ListTile(
            leading: HomeMenuIcon3D(icon: Icons.sync_rounded, color: color, size: 40),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Última sincronização: $last'),
            trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: onSync),
          ),
        );
      },
    );
  }
}
