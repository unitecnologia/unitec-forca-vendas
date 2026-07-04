import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../fv_carteira.dart';
import '../ui/brand.dart';
import '../ui/format.dart';

/// Registra visita ao cliente sem venda (motivo mínimo 10 caracteres).
class VisitasSemVendaScreen extends StatefulWidget {
  const VisitasSemVendaScreen({super.key});

  @override
  State<VisitasSemVendaScreen> createState() => _VisitasSemVendaScreenState();
}

class _VisitasSemVendaScreenState extends State<VisitasSemVendaScreen> {
  final _db = LocalDb.instance;
  final _motivo = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _cliente;
  List<Map<String, dynamic>> _historico = [];
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final rows = await _db.query(
      'SELECT v.uuid, v.motivo, v.created_at, v.status, v.erro, c.nome_razao '
      'FROM visitas_sem_venda v LEFT JOIN customers c ON c.id = v.cliente_id '
      'ORDER BY v.created_at DESC LIMIT 200',
    );
    if (mounted) {
      setState(() {
        _historico = rows;
        _carregando = false;
      });
    }
  }

  Future<void> _selecionarCliente() async {
    final termo = ValueNotifier<String>('');
    final escolhido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return _ClienteBuscaSheet(
              termo: termo,
              onBuscar: () => setModal(() {}),
            );
          },
        );
      },
    );
    if (escolhido != null) {
      setState(() => _cliente = escolhido);
    }
  }

  Future<(double?, double?)> _coletarGps() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return (null, null);
      }
      final pos = await Geolocator.getCurrentPosition();
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _salvar() async {
    if (_cliente == null) {
      _avisa('Selecione o cliente visitado.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    final (lat, lng) = await _coletarGps();
    final agora = DateTime.now().toUtc().toIso8601String();
    final uuid = const Uuid().v4();

    await _db.insertVisitaSemVenda({
      'uuid': uuid,
      'cliente_id': _cliente!['id'],
      'motivo': _motivo.text.trim(),
      'latitude': lat,
      'longitude': lng,
      'created_at': agora,
      'status': 'pendente',
      'erro': null,
    });

    if (!mounted) return;

    await context.read<AppState>().sync.syncNow();

    if (!mounted) return;
    setState(() {
      _salvando = false;
      _cliente = null;
      _motivo.clear();
    });

    _avisa('Visita registrada. Será enviada ao ERP na sincronização.', sucesso: true);
    await _carregar();
  }

  void _avisa(String msg, {bool sucesso = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: sucesso ? Brand.green : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: const Text('Visitas sem Venda'),
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            icon: const Icon(Icons.sync_rounded),
            onPressed: () async {
              await context.read<AppState>().sync.syncNow();
              await _carregar();
            },
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await context.read<AppState>().sync.syncNow();
                await _carregar();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Registrar visita sem venda',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Brand.blue),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _selecionarCliente,
                          icon: const Icon(Icons.person_search_rounded),
                          label: Text(
                            _cliente == null
                                ? 'Selecionar cliente *'
                                : (_cliente!['nome_razao'] ?? 'Cliente').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _motivo,
                          minLines: 3,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Motivo (mínimo 10 caracteres) *',
                            hintText: 'Ex.: Cliente sem verba, estoque cheio, fechado...',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                          ),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.length < 10) {
                              return 'Informe o motivo com pelo menos 10 caracteres.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _salvando ? null : _salvar,
                          icon: _salvando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_salvando ? 'Salvando...' : 'Registrar visita'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Brand.green,
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_historico.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Histórico recente',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Brand.blue),
                    ),
                    const SizedBox(height: 8),
                    ..._historico.map(_VisitaCard.new),
                  ],
                ],
              ),
            ),
    );
  }
}

class _VisitaCard extends StatelessWidget {
  const _VisitaCard(this.v);

  final Map<String, dynamic> v;

  (Color, String) _status() {
    switch ((v['status'] ?? '').toString()) {
      case 'enviado':
        return (Brand.green, 'Enviado');
      case 'erro':
        return (Colors.red, 'Erro');
      default:
        return (Colors.orange, 'Pendente');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (cor, label) = _status();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (v['nome_razao'] ?? 'Cliente').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(label, style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(brDate(v['created_at'] as String?), style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 6),
          Text((v['motivo'] ?? '').toString(), style: const TextStyle(height: 1.3)),
          if (((v['erro'] ?? '').toString()).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(v['erro'].toString(), style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _ClienteBuscaSheet extends StatefulWidget {
  const _ClienteBuscaSheet({required this.termo, required this.onBuscar});

  final ValueNotifier<String> termo;
  final VoidCallback onBuscar;

  @override
  State<_ClienteBuscaSheet> createState() => _ClienteBuscaSheetState();
}

class _ClienteBuscaSheetState extends State<_ClienteBuscaSheet> {
  final _db = LocalDb.instance;
  List<Map<String, dynamic>> _rows = [];
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    widget.termo.addListener(_buscar);
    _buscar();
  }

  @override
  void dispose() {
    widget.termo.removeListener(_buscar);
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() => _buscando = true);
    final like = '%${widget.termo.value.trim()}%';
    final vendedorId = context.read<AppState>().config.vendedorId;
    final rows = await _db.query(
      "SELECT * FROM customers WHERE ativo = 1 AND ${FvCarteira.sqlEquals(vendedorId)} "
      "AND (nome_razao LIKE ? OR apelido_fantasia LIKE ? OR codigo LIKE ? OR cpf_cnpj LIKE ?) "
      'ORDER BY nome_razao LIMIT 80',
      [...FvCarteira.args(vendedorId), like, like, like, like],
    );
    if (mounted) {
      setState(() {
        _rows = rows;
        _buscando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.75,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Selecionar cliente', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Nome, código ou CPF/CNPJ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                onChanged: (v) => widget.termo.value = v,
              ),
            ),
            Expanded(
              child: _buscando
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final c = _rows[i];
                        return ListTile(
                          title: Text((c['nome_razao'] ?? '').toString()),
                          subtitle: Text((c['cpf_cnpj'] ?? c['codigo'] ?? '').toString()),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
