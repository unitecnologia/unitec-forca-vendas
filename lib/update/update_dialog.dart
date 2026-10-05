import 'package:flutter/material.dart';

import '../app_info.dart';
import '../ui/brand.dart';
import 'app_updater.dart';

enum _Etapa { oferta, baixando, permissao, instalador, erro }

/// Modal "Nova versão disponível": baixa, valida (SHA-256) e abre o instalador.
Future<void> mostrarAtualizacaoDisponivel(BuildContext context, AppRelease release) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(release: release),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release});

  final AppRelease release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> with WidgetsBindingObserver {
  final _updater = AppUpdater.instance;
  _Etapa _etapa = _Etapa.oferta;
  int _recebido = 0;
  int _total = 0;
  String? _arquivo;
  String _erro = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou da tela "Permitir desta fonte": segue para o instalador se liberou.
    if (state == AppLifecycleState.resumed && _etapa == _Etapa.permissao) {
      _instalar();
    }
  }

  Future<void> _atualizar() async {
    if (_updater.baixando && _etapa == _Etapa.baixando) return;
    setState(() {
      _etapa = _Etapa.baixando;
      _recebido = 0;
      _total = widget.release.apkSize;
    });
    try {
      _arquivo = await _updater.baixar(widget.release, progresso: (recebido, total) {
        if (!mounted) return;
        setState(() {
          _recebido = recebido;
          _total = total;
        });
      });
      await _instalar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is AtualizacaoException ? e.message : 'Não foi possível baixar a atualização. Tente novamente.';
        _etapa = _Etapa.erro;
      });
    }
  }

  Future<void> _instalar() async {
    final arquivo = _arquivo;
    if (arquivo == null) return;
    try {
      if (!await _updater.podeInstalar()) {
        if (mounted) setState(() => _etapa = _Etapa.permissao);
        return;
      }
      await _updater.instalar(arquivo);
      if (mounted) setState(() => _etapa = _Etapa.instalador);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível abrir o instalador do Android.';
        _etapa = _Etapa.erro;
      });
    }
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _etapa != _Etapa.baixando,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        title: Row(
          children: [
            Icon(
              _etapa == _Etapa.erro ? Icons.error_outline : Icons.system_update,
              color: _etapa == _Etapa.erro ? const Color(0xFFD32F2F) : Brand.blue,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Nova versão disponível',
                style: TextStyle(fontWeight: FontWeight.w700, color: Brand.textPrimary),
              ),
            ),
          ],
        ),
        content: _conteudo(),
        actions: [_botoes()],
      ),
    );
  }

  Widget _versoes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Versão instalada: $kAppVersion', style: TextStyle(fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          'Nova versão: ${widget.release.versionName}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Brand.blue),
        ),
      ],
    );
  }

  Widget _conteudo() {
    switch (_etapa) {
      case _Etapa.oferta:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _versoes(),
            const SizedBox(height: 12),
            Text(
              'Seus dados, pedidos e login continuam no aparelho.',
              style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700),
            ),
          ],
        );
      case _Etapa.baixando:
        final fracao = _total > 0 ? (_recebido / _total).clamp(0.0, 1.0) : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _versoes(),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: fracao, minHeight: 8, color: Brand.blue),
            ),
            const SizedBox(height: 8),
            Text(
              fracao == null
                  ? 'Baixando… ${_mb(_recebido)} MB'
                  : 'Baixando… ${(fracao * 100).toStringAsFixed(0)}%  (${_mb(_recebido)} de ${_mb(_total)} MB)',
              style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700),
            ),
          ],
        );
      case _Etapa.permissao:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _versoes(),
            const SizedBox(height: 12),
            const Text(
              'Para atualizar, o Android precisa liberar a instalação por este app.\n\n'
              'Toque em "Abrir configuração", ative "Permitir desta fonte" e volte ao app.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        );
      case _Etapa.instalador:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _versoes(),
            const SizedBox(height: 12),
            const Text(
              'Confirme a atualização na tela do Android. '
              'Se fechou sem atualizar, toque em "Instalar".',
              style: TextStyle(fontSize: 14),
            ),
          ],
        );
      case _Etapa.erro:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _versoes(),
            const SizedBox(height: 12),
            Text(_erro, style: const TextStyle(fontSize: 14, color: Color(0xFFD32F2F))),
          ],
        );
    }
  }

  Widget _botoes() {
    final fechar = _botaoSecundario(
      _etapa == _Etapa.oferta ? 'Mais tarde' : 'Fechar',
      () => Navigator.of(context).pop(),
    );
    switch (_etapa) {
      case _Etapa.oferta:
        return _linha(fechar, _botaoPrimario('Atualizar agora', Icons.download, _atualizar));
      case _Etapa.baixando:
        return const SizedBox.shrink();
      case _Etapa.permissao:
        return _linha(
          fechar,
          _botaoPrimario('Abrir configuração', Icons.settings, _updater.abrirPermissaoInstalacao),
        );
      case _Etapa.instalador:
        return _linha(fechar, _botaoPrimario('Instalar', Icons.install_mobile, _instalar));
      case _Etapa.erro:
        return _linha(fechar, _botaoPrimario('Tentar de novo', Icons.refresh, _atualizar));
    }
  }

  /// Ação principal em cima (largura total); secundária embaixo.
  Widget _linha(Widget secundario, Widget principal) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          principal,
          const SizedBox(height: 10),
          secundario,
        ],
      );

  Widget _botaoSecundario(String texto, VoidCallback onPressed) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.blue,
          side: const BorderSide(color: Brand.blue, width: 1.6),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: Text(texto),
      );

  Widget _botaoPrimario(String texto, IconData icone, VoidCallback onPressed) => FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Brand.blue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        icon: Icon(icone, size: 20),
        label: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}
