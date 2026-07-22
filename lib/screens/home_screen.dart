import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../db/local_db.dart';
import '../fv_carteira.dart';
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
import 'relatorios_screen.dart';
import 'rotas_screen.dart';
import 'visitas_sem_venda_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _produtos = 0;
  int _clientes = 0;
  int _pendentes = 0;
  SyncService? _sync;

  @override
  void initState() {
    super.initState();
    _atualizarContadores();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sync = context.read<AppState>().sync;
    if (!identical(_sync, sync)) {
      _sync?.removeListener(_onSyncChanged);
      _sync = sync;
      _sync!.addListener(_onSyncChanged);
    }
  }

  @override
  void dispose() {
    _sync?.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    final sync = _sync;
    if (sync == null || !mounted) return;
    // Após sync OK, o cartão "Sincronizado" já atualiza via ListenableBuilder,
    // mas os contadores (Pendentes / badge vermelho) precisam ser recarregados.
    if (sync.status == SyncStatus.ok) {
      setState(() => _pendentes = sync.pendingCount);
      _atualizarContadores();
    }
  }

  Future<void> _atualizarContadores() async {
    final db = LocalDb.instance;
    final vendedorId = context.read<AppState>().config.vendedorId;
    final pr = await db.count('products');
    final clRows = await db.query(
      'SELECT COUNT(*) AS c FROM customers WHERE ativo = 1 AND ${FvCarteira.sqlEquals(vendedorId)}',
      FvCarteira.args(vendedorId),
    );
    final cl = (clRows.first['c'] as num?)?.toInt() ?? 0;
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

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    final itens = <_MenuItem>[
      _MenuItem('Pedido/Orçamento', Icons.note_add_rounded, Brand.blue,
          onTap: () => _abrir(const NovoPedidoScreen(tipoInicial: 'pedido')), destaque: true),
      _MenuItem('Orçamentos', Icons.request_quote_rounded, const Color(0xFF6366F1),
          onTap: () => _abrir(const PedidosScreen(tipoFiltro: 'orcamento'))),
      _MenuItem('Rotas', Icons.alt_route_rounded, const Color(0xFF0891B2),
          onTap: () => _abrir(const RotasScreen())),
      _MenuItem('Pedidos', Icons.fact_check_rounded, Brand.blue,
          onTap: () => _abrir(const PedidosScreen()), badge: _pendentes > 0 ? '$_pendentes' : null),
      _MenuItem('Clientes', Icons.people_alt_rounded, const Color(0xFF0D9488),
          onTap: () => _abrir(const ClientesScreen())),
      _MenuItem('Produtos', Icons.inventory_2_rounded, const Color(0xFF2563EB),
          onTap: () => _abrir(const ProdutosScreen())),
      _MenuItem('Visitas sem Venda', Icons.location_off_rounded, const Color(0xFF64748B),
          onTap: () => _abrir(const VisitasSemVendaScreen())),
      _MenuItem('Dashboard', Icons.insights_rounded, const Color(0xFF7C3AED),
          onTap: () => _abrir(const DashboardScreen())),
      _MenuItem('Títulos', Icons.payments_rounded, const Color(0xFF059669),
          onTap: () => _abrir(const TitulosScreen())),
      _MenuItem('Relatórios', Icons.bar_chart_rounded, const Color(0xFF475569),
          onTap: () => _abrir(const RelatoriosScreen())),
      _MenuItem('Sincronizar', Icons.sync_rounded, Brand.blue, onTap: () async {
        await state.sync.syncNow();
        await _atualizarContadores();
      }),
      _MenuItem('Sair', Icons.logout_rounded, const Color(0xFFDC2626),
          onTap: () => _confirmarSair(state)),
    ];

    return Scaffold(
      backgroundColor: Brand.bg,
      body: RefreshIndicator(
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
                  childAspectRatio: 1.45,
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

class _Header extends StatefulWidget {
  const _Header({required this.state});

  final AppState state;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  String? _vendedorLocal;

  @override
  void initState() {
    super.initState();
    _resolverVendedorLocal();
  }

  Future<void> _resolverVendedorLocal() async {
    final id = widget.state.config.vendedorId;
    if (id == null || widget.state.config.vendedorNome.trim().isNotEmpty) return;
    final rows = await LocalDb.instance.query(
      'SELECT nome FROM vendedores WHERE id = ? LIMIT 1',
      [id],
    );
    if (!mounted || rows.isEmpty) return;
    setState(() => _vendedorLocal = (rows.first['nome'] ?? '').toString());
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final empresa = state.config.empresaNome.isEmpty
        ? 'UNITECNOLOGIA SISTEMAS'
        : state.config.empresaNome.toUpperCase();
    final usuario = state.config.userName.isEmpty ? 'Representante' : state.config.userName;
    final vendedor = state.config.vendedorNome.trim().isNotEmpty
        ? state.config.vendedorNome.trim()
        : (_vendedorLocal ?? '').trim();
    final caixa = state.config.caixaNome.trim();
    final estoque = state.config.estoqueNome.trim();

    return Container(
      decoration: const BoxDecoration(
        color: Brand.blue,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
                alignment: Alignment.center,
                child: const Text('U',
                    style: TextStyle(
                        color: Brand.blue, fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(empresa,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(usuario,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                        ),
                        Text(kAppVersionLabel,
                            style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
                      ],
                    ),
                    if (vendedor.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _metaLinha(Icons.badge_outlined, 'Vendedor', vendedor),
                    ],
                    if (caixa.isNotEmpty || estoque.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (caixa.isNotEmpty)
                            Expanded(child: _metaLinha(Icons.point_of_sale_outlined, 'Caixa', caixa)),
                          if (caixa.isNotEmpty && estoque.isNotEmpty) const SizedBox(width: 8),
                          if (estoque.isNotEmpty)
                            Expanded(child: _metaLinha(Icons.inventory_2_outlined, 'Estoque', estoque)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Log',
                icon: const Icon(Icons.article_outlined, color: Colors.white, size: 22),
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

  Widget _metaLinha(IconData icon, String label, String valor) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 13),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$label: $valor',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.2),
          ),
        ),
      ],
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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: Brand.surfaceCard(radius: 14),
        child: Column(
          children: [
            HomeMenuIconFlat(icon: icon, color: color, size: 36),
            const SizedBox(height: 6),
            Text('$value', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
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
          SyncStatus.idle => (Colors.grey, 'Preparando sincronização...'),
        };
        final last = sync.lastSyncAt != null
            ? DateFormat('dd/MM HH:mm:ss').format(sync.lastSyncAt!)
            : '—';
        return DecoratedBox(
          decoration: Brand.surfaceCard(radius: 14),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: sync.status == SyncStatus.syncing
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: color),
                    )
                  : Icon(Icons.sync_rounded, color: color, size: 22),
            ),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('Última sincronização: $last',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            trailing: IconButton(
              icon: Icon(Icons.refresh_rounded, color: color),
              onPressed: onSync,
            ),
          ),
        );
      },
    );
  }
}
