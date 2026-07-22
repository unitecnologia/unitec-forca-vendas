import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../fv_carteira.dart';
import '../ui/brand.dart';
import 'novo_pedido_screen.dart';

/// Rota do dia: clientes marcados no ERP (Força de Vendas → Rotas).
class RotasScreen extends StatefulWidget {
  const RotasScreen({super.key});

  @override
  State<RotasScreen> createState() => _RotasScreenState();
}

class _RotasScreenState extends State<RotasScreen> {
  final _db = LocalDb.instance;

  static const _dias = <int, String>{
    1: 'Seg',
    2: 'Ter',
    3: 'Qua',
    4: 'Qui',
    5: 'Sex',
    6: 'Sáb',
    7: 'Dom',
  };

  static const _diasLongos = <int, String>{
    1: 'Segunda',
    2: 'Terça',
    3: 'Quarta',
    4: 'Quinta',
    5: 'Sexta',
    6: 'Sábado',
    7: 'Domingo',
  };

  late int _diaSemana;
  List<Map<String, dynamic>> _rows = [];
  /// person_id → `venda` | `visita`
  Map<int, String> _atendidos = {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _diaSemana = _diaHoje();
    _buscar();
  }

  int _diaHoje() {
    // DateTime: 1=Seg ... 7=Dom — igual ao ERP.
    return DateTime.now().weekday;
  }

  /// Data civil da semana corrente correspondente ao dia selecionado.
  DateTime _dataDoDiaSelecionado() {
    final now = DateTime.now();
    final hoje = DateTime(now.year, now.month, now.day);
    return hoje.subtract(Duration(days: hoje.weekday - _diaSemana));
  }

  Future<void> _buscar() async {
    setState(() => _carregando = true);
    final vendedorId = context.read<AppState>().config.vendedorId;
    final rows = await _db.query(
      'SELECT c.*, v.ordem AS visita_ordem '
      'FROM customer_visita_dias v '
      'INNER JOIN customers c ON c.id = v.person_id '
      'WHERE v.dia_semana = ? AND c.ativo = 1 AND ${FvCarteira.sqlEquals(vendedorId)} '
      'ORDER BY v.ordem ASC, c.nome_razao ASC',
      [_diaSemana, ...FvCarteira.args(vendedorId)],
    );
    final atendidos = await _db.clientesAtendidosNoDia(_dataDoDiaSelecionado());
    if (mounted) {
      setState(() {
        _rows = rows;
        _atendidos = atendidos;
        _carregando = false;
      });
    }
  }

  Future<void> _fazerPedido(Map<String, dynamic> cliente) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NovoPedidoScreen(
          tipoInicial: 'pedido',
          clienteInicial: cliente,
        ),
      ),
    );
    if (mounted) await _buscar();
  }

  /// Mesmo formato do ERP (`endereco_lista`).
  String _enderecoCompleto(Map<String, dynamic> c) {
    final numero = (c['numero'] ?? '').toString().trim();
    final partes = <String>[
      (c['endereco'] ?? '').toString().trim(),
      if (numero.isNotEmpty) 'nº $numero',
      (c['bairro'] ?? '').toString().trim(),
      (c['cidade_nome'] ?? '').toString().trim(),
      (c['uf'] ?? '').toString().trim(),
    ].where((e) => e.isNotEmpty).toList();
    return partes.join(', ');
  }

  Future<void> _abrirMapa(Map<String, dynamic> c) async {
    final endereco = _enderecoCompleto(c);
    if (endereco.isEmpty) {
      _snack('Cliente sem endereço cadastrado.');
      return;
    }

    final escolha = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const Text('Abrir no mapa', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                endereco,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8F0FE),
                  child: Icon(Icons.map_outlined, color: Brand.blue),
                ),
                title: const Text('Google Maps'),
                onTap: () => Navigator.pop(ctx, 'google'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.navigation_outlined, color: Color(0xFF33CCFF)),
                ),
                title: const Text('Waze'),
                onTap: () => Navigator.pop(ctx, 'waze'),
              ),
            ],
          ),
        ),
      ),
    );

    if (escolha == null || !mounted) return;

    final uri = escolha == 'waze'
        ? Uri.parse('https://waze.com/ul?q=${Uri.encodeComponent(endereco)}&navigate=yes')
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}');

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _snack('Não foi possível abrir o aplicativo de mapas.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  int? _clienteId(Map<String, dynamic> c) {
    final id = c['id'];
    if (id is int) return id;
    return int.tryParse('$id');
  }

  @override
  Widget build(BuildContext context) {
    final diaLabel = _diasLongos[_diaSemana] ?? '';
    final total = _rows.length;
    final feitos = _rows.where((c) {
      final id = _clienteId(c);
      return id != null && _atendidos.containsKey(id);
    }).length;

    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: const Text('Rotas'),
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _buscar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Clientes de $diaLabel',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    if (!_carregando && total > 0)
                      Text(
                        '$feitos de $total',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: feitos == total ? Brand.green : Brand.blue,
                        ),
                      ),
                  ],
                ),
                if (!_carregando && total > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : feitos / total,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE2E8F0),
                      color: feitos == total ? Brand.green : Brand.blue,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry in _dias.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(entry.value),
                            selected: _diaSemana == entry.key,
                            selectedColor: Brand.blue.withValues(alpha: 0.18),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _diaSemana == entry.key ? Brand.blue : Colors.black87,
                            ),
                            onSelected: (_) {
                              setState(() => _diaSemana = entry.key);
                              _buscar();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_rows.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Nenhum cliente na rota de $diaLabel.\n'
                    'Marque no ERP em Força de Vendas → Rotas de Vendedores e sincronize.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, height: 1.4),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = _rows[i];
                  final id = _clienteId(c);
                  final status = id == null ? null : _atendidos[id];
                  final passou = status != null;
                  final foiVenda = status == 'venda';
                  final ordem = c['visita_ordem'] ?? (i + 1);
                  final cidade = [c['cidade_nome'], c['uf']]
                      .where((e) => (e ?? '').toString().isNotEmpty)
                      .join(' / ');
                  final endereco = _enderecoCompleto(c);
                  final temMapa = endereco.isNotEmpty;

                  final accent = passou ? Brand.green : Brand.blue;
                  final cardBg = passou
                      ? const Color(0xFFECFDF5)
                      : Colors.white;
                  final borderColor = passou
                      ? Brand.green.withValues(alpha: 0.35)
                      : Brand.blue.withValues(alpha: 0.10);

                  return Material(
                    color: cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: borderColor),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _fazerPedido(c),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(width: 4, color: accent),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: accent.withValues(alpha: 0.14),
                                      child: passou
                                          ? Icon(Icons.check_rounded, color: accent, size: 22)
                                          : Text(
                                              '$ordem',
                                              style: TextStyle(
                                                color: accent,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            (c['nome_razao'] ?? '').toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: passou
                                                  ? const Color(0xFF14532D)
                                                  : Brand.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              if (cidade.isNotEmpty) cidade,
                                              'Cód. ${c['codigo'] ?? ''}',
                                            ].join(' · '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          if (passou) ...[
                                            const SizedBox(height: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Brand.green.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                foiVenda ? 'Atendido · venda' : 'Visitado · sem venda',
                                                style: const TextStyle(
                                                  color: Brand.green,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: temMapa ? 'Abrir no mapa' : 'Sem endereço',
                                      onPressed: temMapa ? () => _abrirMapa(c) : null,
                                      icon: Icon(
                                        Icons.map_outlined,
                                        color: temMapa
                                            ? (passou ? Brand.green : Brand.blue)
                                            : Colors.black26,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: passou ? 'Novo pedido' : 'Fazer pedido',
                                      icon: Icon(
                                        passou
                                            ? Icons.check_circle_rounded
                                            : Icons.add_shopping_cart,
                                        color: Brand.green,
                                      ),
                                      onPressed: () => _fazerPedido(c),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
