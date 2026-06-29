import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../ui/brand.dart';
import '../ui/format.dart';
import 'pix_qr_screen.dart';

class TitulosScreen extends StatefulWidget {
  const TitulosScreen({super.key});

  @override
  State<TitulosScreen> createState() => _TitulosScreenState();
}

class _TitulosScreenState extends State<TitulosScreen> {
  final _db = LocalDb.instance;
  List<_GrupoCliente> _grupos = [];
  int _qtdTitulos = 0;
  final Set<String> _expandidos = {};
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
      'SELECT f.*, c.nome_razao, c.limite_credito FROM financeiro f '
      'LEFT JOIN customers c ON c.id = f.cliente_id '
      'WHERE f.saldo > 0 AND (c.nome_razao LIKE ? OR f.documento LIKE ? OR f.numero LIKE ?) '
      'ORDER BY c.nome_razao, f.vencimento',
      [like, like, like],
    );

    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final mapa = <String, _GrupoCliente>{};

    for (final r in rows) {
      final id = r['cliente_id'];
      final chave = id?.toString() ?? 'sem-cliente';
      final grupo = mapa.putIfAbsent(
        chave,
        () => _GrupoCliente(
          chave: chave,
          nome: (r['nome_razao'] ?? 'Cliente').toString(),
          limite: (r['limite_credito'] as num?)?.toDouble() ?? 0,
        ),
      );
      grupo.titulos.add(r);
    }

    for (final g in mapa.values) {
      g.titulos.sort((a, b) {
        final va = _vencido(a['vencimento']?.toString(), inicioHoje);
        final vb = _vencido(b['vencimento']?.toString(), inicioHoje);
        if (va != vb) return va ? -1 : 1; // atrasados primeiro
        final da = DateTime.tryParse((a['vencimento'] ?? '').toString());
        final db = DateTime.tryParse((b['vencimento'] ?? '').toString());
        if (da == null || db == null) return 0;
        return da.compareTo(db);
      });
    }

    if (mounted) {
      setState(() {
        _grupos = mapa.values.toList();
        _qtdTitulos = rows.length;
        _carregando = false;
      });
    }
  }

  bool _vencido(String? venc, DateTime inicioHoje) {
    if (venc == null || venc.isEmpty) return false;
    final d = DateTime.tryParse(venc);
    if (d == null) return false;
    return d.isBefore(inicioHoje);
  }

  double get _totalAberto =>
      _grupos.fold(0.0, (s, g) => s + g.totalAberto);

  @override
  Widget build(BuildContext context) {
    final inicioHoje = () {
      final h = DateTime.now();
      return DateTime(h.year, h.month, h.day);
    }();

    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: const Text('Títulos'),
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
      ),
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
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: (s) {
                _termo = s;
                _carregar();
              },
            ),
          ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_grupos.isEmpty)
            const Expanded(child: Center(child: Text('Nenhum título em aberto.')))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _grupos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) =>
                    _grupoCard(_grupos[i], inicioHoje),
              ),
            ),
          _Rodape(
            total: _totalAberto,
            clientes: _grupos.length,
            titulos: _qtdTitulos,
          ),
        ],
      ),
    );
  }

  Widget _grupoCard(_GrupoCliente g, DateTime inicioHoje) {
    final aberto = _expandidos.contains(g.chave);
    final temAtraso = g.temAtraso(inicioHoje);

    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              if (aberto) {
                _expandidos.remove(g.chave);
              } else {
                _expandidos.add(g.chave);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: temAtraso ? Colors.red : Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        '${g.titulos.length}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black45),
                      ),
                      AnimatedRotation(
                        turns: aberto ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.expand_more,
                            color: Colors.black45),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _resumo(g, inicioHoje),
                ],
              ),
            ),
          ),
          if (aberto) ...[
            const Divider(height: 1),
            ...g.titulos.map((t) => _tituloLinha(t, inicioHoje)),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _resumo(_GrupoCliente g, DateTime inicioHoje) {
    final disponivel = g.limite - g.totalAberto;
    final atraso = g.totalAtraso(inicioHoje);
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        _resumoItem('Títulos', brMoney(g.totalValor)),
        _resumoItem('Aberto', brMoney(g.totalAberto)),
        _resumoItem('Limite', brMoney(g.limite)),
        _resumoItem('Disponível', brMoney(disponivel),
            valorColor: disponivel < 0 ? Colors.red : null),
        if (atraso > 0)
          _resumoItem('Atrasado', brMoney(atraso),
              valorColor: Colors.red, destaque: true),
      ],
    );
  }

  Widget _resumoItem(String label, String valor,
      {Color? valorColor, bool destaque = false}) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 11, color: Colors.black54),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: valor,
            style: TextStyle(
              fontSize: 11,
              fontWeight: destaque ? FontWeight.w800 : FontWeight.w700,
              color: valorColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tituloLinha(Map<String, dynamic> t, DateTime inicioHoje) {
    final venc = (t['vencimento'] ?? '').toString();
    final vencido = _vencido(venc, inicioHoje);
    final cor = vencido ? Colors.red : Colors.black87;
    final doc = (t['documento'] ?? t['numero'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        children: [
          Icon(vencido ? Icons.error_outline : Icons.event_outlined,
              size: 15, color: vencido ? Colors.red : Colors.black45),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Venc. ${brDate(venc)}${vencido ? '  ·  VENCIDO' : ''}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cor,
                    fontWeight: vencido ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (doc.isNotEmpty)
                  Text('Doc. $doc',
                      style: TextStyle(
                          fontSize: 11,
                          color: vencido
                              ? Colors.red.shade300
                              : Colors.black45)),
              ],
            ),
          ),
          Text(
            brMoney(t['saldo'] as num?),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: vencido ? Colors.red : Brand.blue),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Receber via Pix',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.qr_code_2, color: Brand.green),
            onPressed: () => _cobrarPixTitulo(t),
          ),
        ],
      ),
    );
  }

  Future<void> _cobrarPixTitulo(Map<String, dynamic> t) async {
    final id = (t['id'] as num?)?.toInt();
    if (id == null) return;

    Map<String, dynamic> cobranca;
    try {
      cobranca = await context.read<AppState>().api.criarPix(
            origem: 'titulo',
            ref: id.toString(),
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar o Pix: $e')),
      );
      return;
    }

    if (!mounted) return;
    final pago = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PixQrScreen(cobranca: cobranca)),
    );

    if (!mounted) return;
    if (pago == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Título recebido via Pix!')),
      );
      // O título é baixado no ERP; sincroniza para sumir da lista.
      await context.read<AppState>().sync.syncNow();
      await _carregar();
    }
  }
}

class _GrupoCliente {
  _GrupoCliente({
    required this.chave,
    required this.nome,
    required this.limite,
  });

  final String chave;
  final String nome;
  final double limite;
  final List<Map<String, dynamic>> titulos = [];

  double get totalValor =>
      titulos.fold(0.0, (s, t) => s + ((t['valor'] as num?)?.toDouble() ?? 0));

  double get totalAberto =>
      titulos.fold(0.0, (s, t) => s + ((t['saldo'] as num?)?.toDouble() ?? 0));

  bool _venc(Map<String, dynamic> t, DateTime inicioHoje) {
    final v = (t['vencimento'] ?? '').toString();
    if (v.isEmpty) return false;
    final d = DateTime.tryParse(v);
    return d != null && d.isBefore(inicioHoje);
  }

  bool temAtraso(DateTime inicioHoje) =>
      titulos.any((t) => _venc(t, inicioHoje));

  double totalAtraso(DateTime inicioHoje) => titulos
      .where((t) => _venc(t, inicioHoje))
      .fold(0.0, (s, t) => s + ((t['saldo'] as num?)?.toDouble() ?? 0));
}

class _Rodape extends StatelessWidget {
  const _Rodape({
    required this.total,
    required this.clientes,
    required this.titulos,
  });

  final double total;
  final int clientes;
  final int titulos;

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
            Text('$clientes cliente(s) · $titulos título(s)',
                style: const TextStyle(color: Colors.black54)),
            Text('Total: ${brMoney(total)}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Brand.green)),
          ],
        ),
      ),
    );
  }
}
