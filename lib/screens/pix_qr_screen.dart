import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../ui/brand.dart';
import '../ui/format.dart';

/// Tela de pagamento Pix: mostra o QR (imagem + copia-e-cola), faz polling do
/// status no ERP (que consulta o Mercado Pago) e retorna `true` quando pago.
class PixQrScreen extends StatefulWidget {
  const PixQrScreen({super.key, required this.cobranca});

  /// Mapa retornado por ApiClient.criarPix: id, status, valor,
  /// qr_copia_cola, qr_imagem_base64, expira_em.
  final Map<String, dynamic> cobranca;

  @override
  State<PixQrScreen> createState() => _PixQrScreenState();
}

class _PixQrScreenState extends State<PixQrScreen> {
  late final int _id;
  late final String _copiaCola;
  String? _imgBase64;
  late final double _valor;
  DateTime? _expiraEm;
  String _status = 'pendente';

  Timer? _poll;
  Timer? _tick;
  int _restante = 0;
  bool _encerrando = false;

  @override
  void initState() {
    super.initState();
    final c = widget.cobranca;
    _id = (c['id'] as num).toInt();
    _copiaCola = (c['qr_copia_cola'] ?? '').toString();
    _imgBase64 = c['qr_imagem_base64'] as String?;
    _valor = (c['valor'] as num?)?.toDouble() ?? 0;
    _status = (c['status'] ?? 'pendente').toString();
    _expiraEm = DateTime.tryParse((c['expira_em'] ?? '').toString());
    _recalcRestante();

    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _recalcRestante());
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _consultar());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _recalcRestante() {
    if (_expiraEm == null) return;
    final s = _expiraEm!.difference(DateTime.now()).inSeconds;
    if (mounted) setState(() => _restante = s < 0 ? 0 : s);
  }

  Future<void> _consultar() async {
    if (_encerrando) return;
    try {
      final api = context.read<AppState>().api;
      final r = await api.pixStatus(_id);
      final st = (r['status'] ?? 'pendente').toString();
      if (!mounted) return;
      setState(() => _status = st);
      if (st == 'pago') {
        _finalizar(true);
      } else if (st == 'expirado' || st == 'cancelado') {
        _poll?.cancel();
      }
    } catch (_) {
      // mantém pendente em falha transitória de rede
    }
  }

  void _finalizar(bool pago) {
    if (_encerrando) return;
    _encerrando = true;
    _poll?.cancel();
    _tick?.cancel();
    if (mounted) Navigator.pop(context, pago);
  }

  Future<void> _cancelar() async {
    _poll?.cancel();
    try {
      await context.read<AppState>().api.cancelarPix(_id);
    } catch (_) {}
    _finalizar(false);
  }

  void _copiar() {
    Clipboard.setData(ClipboardData(text: _copiaCola));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código Pix copiado.')),
    );
  }

  String get _restanteFmt {
    final m = (_restante ~/ 60).toString().padLeft(2, '0');
    final s = (_restante % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pago = _status == 'pago';
    final encerrado = _status == 'expirado' || _status == 'cancelado' || (_restante == 0 && _expiraEm != null);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finalizar(false);
      },
      child: Scaffold(
        backgroundColor: Brand.bg,
        appBar: AppBar(
          title: const Text('Pagamento Pix'),
          backgroundColor: Brand.blue,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: pago
              ? _sucesso()
              : (encerrado ? _expirado() : _aguardando()),
        ),
      ),
    );
  }

  Widget _aguardando() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Center(
          child: Text('Valor a receber',
              style: TextStyle(color: Colors.black54, fontSize: 13)),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(brMoney(_valor),
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: Brand.blue)),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              if (_imgBase64 != null && _imgBase64!.isNotEmpty)
                Image.memory(
                  base64Decode(_imgBase64!),
                  width: 230,
                  height: 230,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                )
              else
                const SizedBox(
                  height: 230,
                  child: Center(child: Icon(Icons.qr_code_2, size: 120, color: Colors.black26)),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined, size: 16, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text('Expira em $_restanteFmt',
                      style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('Pix copia e cola',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12)),
          child: Text(_copiaCola,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _copiar,
          icon: const Icon(Icons.copy),
          label: const Text('Copiar código Pix'),
          style: FilledButton.styleFrom(backgroundColor: Brand.blue),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Aguardando pagamento...', style: TextStyle(color: Colors.black54)),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _cancelar,
          icon: const Icon(Icons.close),
          label: const Text('Cancelar cobrança'),
        ),
      ],
    );
  }

  Widget _sucesso() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Brand.green, size: 90),
          const SizedBox(height: 10),
          const Text('Pagamento confirmado!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Brand.green)),
          const SizedBox(height: 4),
          Text(brMoney(_valor),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _expirado() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_off_outlined, color: Colors.redAccent, size: 80),
          const SizedBox(height: 10),
          Text(_status == 'cancelado' ? 'Cobrança cancelada' : 'Cobrança expirada',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'O pagamento não foi confirmado. Você pode tentar novamente ou escolher outra forma de pagamento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _finalizar(false),
            style: FilledButton.styleFrom(backgroundColor: Brand.blue),
            child: const Text('Voltar'),
          ),
        ],
      ),
    );
  }
}
