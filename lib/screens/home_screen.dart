import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../sync/sync_service.dart';
import 'log_screen.dart';
import 'novo_pedido_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(state.config.userName.isEmpty ? 'Unitec Força de Vendas' : state.config.userName),
        actions: [
          IconButton(
            tooltip: 'Log',
            icon: const Icon(Icons.article_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AppState>().logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await state.sync.syncNow();
          await _atualizarContadores();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SyncCard(sync: state.sync, onSync: () async {
              await state.sync.syncNow();
              await _atualizarContadores();
            }),
            const SizedBox(height: 16),
            Row(
              children: [
                _CountTile(label: 'Produtos', value: _produtos, icon: Icons.inventory_2),
                const SizedBox(width: 12),
                _CountTile(label: 'Clientes', value: _clientes, icon: Icons.people),
                const SizedBox(width: 12),
                _CountTile(label: 'Pendentes', value: _pendentes, icon: Icons.cloud_upload),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const NovoPedidoScreen()));
                await _atualizarContadores();
              },
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Novo pedido / orçamento'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
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
          SyncStatus.ok => (Colors.green, 'Sincronizado'),
          SyncStatus.offline => (Colors.orange, 'Offline (dados salvos no aparelho)'),
          SyncStatus.error => (Colors.red, 'Erro: ${sync.lastError ?? ''}'),
          SyncStatus.idle => (Colors.grey, 'Aguardando...'),
        };
        final last = sync.lastSyncAt != null
            ? DateFormat('dd/MM HH:mm:ss').format(sync.lastSyncAt!)
            : '—';
        return Card(
          child: ListTile(
            leading: Icon(Icons.sync, color: color),
            title: Text(label),
            subtitle: Text('Última sincronização: $last'),
            trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: onSync),
          ),
        );
      },
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.value, required this.icon});

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF1565C0)),
              const SizedBox(height: 8),
              Text('$value', style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
