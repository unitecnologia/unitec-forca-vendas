import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../log/app_log.dart';

/// Tela de log: mostra os eventos do app (conexão, autorização, sincronização,
/// erros). Útil para o vendedor/suporte saber o que está acontecendo.
class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  Color _cor(LogLevel l) => switch (l) {
        LogLevel.ok => Colors.green,
        LogLevel.warn => Colors.orange,
        LogLevel.error => Colors.red,
        LogLevel.info => Colors.blueGrey,
      };

  IconData _icone(LogLevel l) => switch (l) {
        LogLevel.ok => Icons.check_circle,
        LogLevel.warn => Icons.warning_amber,
        LogLevel.error => Icons.error,
        LogLevel.info => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm:ss');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log do aplicativo'),
        actions: [
          IconButton(
            tooltip: 'Copiar tudo',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: AppLog.instance.exportText()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Log copiado.')),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Limpar log',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => AppLog.instance.clear(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: AppLog.instance,
        builder: (context, _) {
          final entries = AppLog.instance.entries;
          if (entries.isEmpty) {
            return const Center(child: Text('Sem registros ainda.'));
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = entries[i];
              return ListTile(
                dense: true,
                leading: Icon(_icone(e.level), color: _cor(e.level), size: 20),
                title: Text(e.message),
                subtitle: Text('${fmt.format(e.time)}  ·  ${e.tag}'),
              );
            },
          );
        },
      ),
    );
  }
}
