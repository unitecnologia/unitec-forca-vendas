import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../ui/brand.dart';
import '../ui/format.dart';

class TitulosScreen extends StatefulWidget {
  const TitulosScreen({super.key});

  @override
  State<TitulosScreen> createState() => _TitulosScreenState();
}

class _TitulosScreenState extends State<TitulosScreen> {
  final _db = LocalDb.instance;
  List<Map<String, dynamic>> _rows = [];
  String _termo = '';
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final like = '%${_termo.trim()}%';
    final rows = await _db.query(
      'SELECT f.*, c.nome_razao FROM financeiro f LEFT JOIN customers c ON c.id = f.cliente_id '
      'WHERE f.saldo > 0 AND (c.nome_razao LIKE ? OR f.documento LIKE ? OR f.numero LIKE ?) '
      'ORDER BY f.vencimento',
      [like, like, like],
    );
    if (mounted) {
      setState(() {
        _rows = rows;
        _carregando = false;
      });
    }
  }

  double get _totalAberto =>
      _rows.fold(0.0, (s, r) => s + ((r['saldo'] as num?)?.toDouble() ?? 0));

  bool _vencido(String? venc) {
    if (venc == null || venc.isEmpty) return false;
    final d = DateTime.tryParse(venc);
    if (d == null) return false;
    final hoje = DateTime.now();
    return d.isBefore(DateTime(hoje.year, hoje.month, hoje.day));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(title: const Text('Títulos'), backgroundColor: Brand.blue, foregroundColor: Colors.white),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por cliente ou documento',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (s) {
                _termo = s;
                _carregar();
              },
            ),
          ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_rows.isEmpty)
            const Expanded(child: Center(child: Text('Nenhum título em aberto.')))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final t = _rows[i];
                  final venc = (t['vencimento'] ?? '').toString();
                  final vencido = _vencido(venc);
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text((t['nome_razao'] ?? 'Cliente').toString(),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Text(brMoney(t['saldo'] as num?),
                                style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.blue)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.event_outlined, size: 15, color: vencido ? Colors.red : Colors.black54),
                            const SizedBox(width: 4),
                            Text('Venc. ${brDate(venc)}',
                                style: TextStyle(
                                    color: vencido ? Colors.red : Colors.black54,
                                    fontWeight: vencido ? FontWeight.w700 : FontWeight.w400,
                                    fontSize: 13)),
                            const Spacer(),
                            Text('Doc. ${t['documento'] ?? t['numero'] ?? ''}',
                                style: const TextStyle(color: Colors.black45, fontSize: 12)),
                          ],
                        ),
                        if (vencido)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text('VENCIDO', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          _Rodape(total: _totalAberto, qtd: _rows.length),
        ],
      ),
    );
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape({required this.total, required this.qtd});

  final double total;
  final int qtd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$qtd título(s) em aberto', style: const TextStyle(color: Colors.black54)),
            Text('Total: ${brMoney(total)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Brand.green)),
          ],
        ),
      ),
    );
  }
}
