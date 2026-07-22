import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../fv_carteira.dart';
import '../ui/brand.dart';
import '../ui/format.dart';
import '../ui/uppercase_input.dart';
import 'novo_cliente_screen.dart';
import 'novo_pedido_screen.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  final _db = LocalDb.instance;
  List<Map<String, dynamic>> _rows = [];
  String _termo = '';
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    final like = '%${_termo.trim()}%';
    final vendedorId = context.read<AppState>().config.vendedorId;
    final rows = await _db.query(
      "SELECT * FROM customers WHERE ativo = 1 AND ${FvCarteira.sqlEquals(vendedorId)} "
      "AND (nome_razao LIKE ? OR apelido_fantasia LIKE ? OR codigo LIKE ? OR cpf_cnpj LIKE ?) "
      'ORDER BY nome_razao LIMIT 200',
      [...FvCarteira.args(vendedorId), like, like, like, like],
    );
    if (mounted) {
      setState(() {
        _rows = rows;
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: const Text('Clientes'),
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novoCliente,
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1, size: 20),
        label: const Text('Novo cliente'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: TextField(
              style: const TextStyle(fontSize: 14),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: withUpperCase(),
              decoration: InputDecoration(
                hintText: 'Buscar por nome, código ou CPF/CNPJ',
                hintStyle: const TextStyle(fontSize: 13.5),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              onChanged: (s) {
                _termo = s;
                _buscar();
              },
            ),
          ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_rows.isEmpty)
            const Expanded(child: Center(child: Text('Nenhum cliente encontrado.')))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 72),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 5),
                itemBuilder: (_, i) {
                  final c = _rows[i];
                  final cidade = [c['cidade_nome'], c['uf']]
                      .where((e) => (e ?? '').toString().isNotEmpty)
                      .join(' - ');
                  final codigo = (c['codigo'] ?? '').toString();
                  final subtitulo = [
                    if (cidade.isNotEmpty) cidade,
                    if (codigo.isNotEmpty) 'Cód. $codigo',
                  ].join(' · ');
                  final temMapa = _enderecoCompleto(c).isNotEmpty;

                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _detalhe(c),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Brand.blue.withValues(alpha: 0.12),
                              child: const Icon(Icons.person, size: 18, color: Brand.blue),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (c['nome_razao'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitulo.isEmpty ? '—' : subtitulo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: temMapa ? 'Abrir no mapa' : 'Sem endereço',
                              onPressed: temMapa ? () => _abrirMapa(c) : null,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              icon: Icon(
                                Icons.map_outlined,
                                size: 20,
                                color: temMapa ? Brand.blue : Colors.black26,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Fazer pedido',
                              onPressed: () => _fazerPedido(c),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              icon: const Icon(Icons.add_shopping_cart, size: 20, color: Brand.green),
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

  Future<void> _novoCliente() async {
    final criado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NovoClienteScreen()),
    );
    if (criado == true) {
      _termo = '';
      await _buscar();
    }
  }

  Future<void> _fazerPedido(Map<String, dynamic> c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NovoPedidoScreen(clienteInicial: c)),
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

  String _digitos(String? raw) => (raw ?? '').replaceAll(RegExp(r'\D'), '');

  String _telefoneExibicao(Map<String, dynamic> c) {
    final parts = [
      c['celular1'],
      c['fone1'],
      c['whatsapp'],
    ].map((e) => (e ?? '').toString().trim()).where((e) => e.isNotEmpty).toSet().toList();
    return parts.isEmpty ? '—' : parts.join(' / ');
  }

  String? _telefoneWhatsApp(Map<String, dynamic> c) {
    for (final key in ['whatsapp', 'celular1', 'fone1']) {
      final d = _digitos(c[key]?.toString());
      if (d.length >= 10) return d;
    }
    return null;
  }

  Future<void> _abrirWhatsApp(Map<String, dynamic> c) async {
    var digits = _telefoneWhatsApp(c);
    if (digits == null) {
      _snack('Informe o celular do cliente antes de abrir o WhatsApp.');
      return;
    }
    // Brasil: 10/11 dígitos → prefixa 55
    if (digits.length == 10 || digits.length == 11) {
      digits = '55$digits';
    }
    final uri = Uri.parse('https://wa.me/$digits');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _snack('Não foi possível abrir o WhatsApp.');
    }
  }

  Future<void> _editarTelefone(Map<String, dynamic> c, void Function(void Function()) setSheet) async {
    final celularCtrl = TextEditingController(text: (c['celular1'] ?? c['whatsapp'] ?? '').toString());
    final foneCtrl = TextEditingController(text: (c['fone1'] ?? '').toString());

    final salvos = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar telefone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: celularCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s()\-+]'))],
              decoration: const InputDecoration(
                labelText: 'Celular / WhatsApp',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: foneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s()\-+]'))],
              decoration: const InputDecoration(
                labelText: 'Telefone fixo',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Brand.green),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    final celular = celularCtrl.text.trim();
    final fone = foneCtrl.text.trim();
    celularCtrl.dispose();
    foneCtrl.dispose();

    if (salvos != true) return;

    final id = c['id'] as int?;
    if (id == null) return;

    await _db.updateCustomerPhones(
      id,
      celular1: celular,
      fone1: fone,
      whatsapp: celular,
    );

    setSheet(() {
      c['celular1'] = celular;
      c['fone1'] = fone;
      c['whatsapp'] = celular;
    });
    await _buscar();
    if (mounted) _snack('Telefone atualizado.', sucesso: true);
  }

  void _snack(String msg, {bool sucesso = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: sucesso ? Brand.green : null,
      ));
  }

  void _detalhe(Map<String, dynamic> c) {
    // Cópia mutável para refletir edição de telefone no sheet.
    final cliente = Map<String, dynamic>.from(c);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final endereco = [
              cliente['endereco'],
              cliente['numero'],
              cliente['bairro'],
            ].where((e) => (e ?? '').toString().isNotEmpty).join(', ');
            final cidade = [cliente['cidade_nome'], cliente['uf']]
                .where((e) => (e ?? '').toString().isNotEmpty)
                .join(' - ');
            final temWhats = _telefoneWhatsApp(cliente) != null;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text((cliente['nome_razao'] ?? '').toString(),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    if ((cliente['apelido_fantasia'] ?? '').toString().isNotEmpty)
                      Text(cliente['apelido_fantasia'].toString(),
                          style: const TextStyle(color: Colors.black54, fontSize: 13)),
                    const Divider(height: 20),
                    _linha(Icons.badge_outlined, 'Código', (cliente['codigo'] ?? '—').toString()),
                    _linha(Icons.assignment_ind_outlined, 'CPF/CNPJ', (cliente['cpf_cnpj'] ?? '—').toString()),
                    _linha(Icons.location_on_outlined, 'Endereço', endereco.isEmpty ? '—' : endereco),
                    _linha(Icons.location_city_outlined, 'Cidade', cidade.isEmpty ? '—' : cidade),
                    _linhaTelefone(
                      valor: _telefoneExibicao(cliente),
                      onEditar: () => _editarTelefone(cliente, setSheet),
                      onWhatsApp: () => _abrirWhatsApp(cliente),
                      whatsEnabled: temWhats,
                    ),
                    _linha(Icons.email_outlined, 'E-mail', (cliente['email'] ?? '—').toString()),
                    _linha(Icons.credit_score_outlined, 'Limite de crédito',
                        brMoney(cliente['limite_credito'] as num?)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _fazerPedido(cliente);
                        },
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Fazer pedido'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Brand.green,
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _linha(IconData icon, String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Brand.blue),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }

  Widget _linhaTelefone({
    required String valor,
    required VoidCallback onEditar,
    required VoidCallback onWhatsApp,
    required bool whatsEnabled,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.phone_outlined, size: 18, color: Brand.blue),
          const SizedBox(width: 10),
          const Text('Telefone: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 13.5))),
          IconButton(
            tooltip: 'Editar telefone',
            onPressed: onEditar,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.edit_outlined, size: 20, color: Brand.blue),
          ),
          IconButton(
            tooltip: whatsEnabled ? 'Chamar no WhatsApp' : 'Cadastre um celular para o WhatsApp',
            onPressed: onWhatsApp,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              Icons.chat,
              size: 20,
              color: whatsEnabled ? const Color(0xFF25D366) : Colors.black26,
            ),
          ),
        ],
      ),
    );
  }
}
