import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../db/local_db.dart';
import '../ui/brand.dart';
import '../ui/cnpj_lookup.dart';
import '../ui/cpf_cnpj_formatter.dart';
import '../ui/uppercase_input.dart';

/// Cadastro rápido de um novo cliente direto no aparelho.
///
/// O cliente é salvo na base local (já aparece na lista e pode ser usado num
/// pedido) e fica enfileirado em `outbox_customers` para subir ao ERP na próxima
/// sincronização.
class NovoClienteScreen extends StatefulWidget {
  const NovoClienteScreen({super.key});

  @override
  State<NovoClienteScreen> createState() => _NovoClienteScreenState();
}

class _NovoClienteScreenState extends State<NovoClienteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = LocalDb.instance;

  final _nome = TextEditingController();
  final _fantasia = TextEditingController();
  final _cpfCnpj = TextEditingController();
  final _ie = TextEditingController();
  final _celular = TextEditingController();
  final _fone = TextEditingController();
  final _email = TextEditingController();
  final _endereco = TextEditingController();
  final _numero = TextEditingController();
  final _bairro = TextEditingController();
  final _cidade = TextEditingController();
  final _uf = TextEditingController();
  final _cep = TextEditingController();
  final _limite = TextEditingController();

  List<Map<String, dynamic>> _formas = [];
  List<Map<String, dynamic>> _tabelas = [];
  int? _formaId;
  int? _tabelaPrazoId;
  String? _tabelaDias;

  /// Dias de visita (1=Seg … 7=Dom), alinhado ao ERP.
  final Set<int> _visitaDias = {};

  static const _abrevDias = <int, String>{
    1: 'Seg',
    2: 'Ter',
    3: 'Qua',
    4: 'Qui',
    5: 'Sex',
    6: 'Sáb',
    7: 'Dom',
  };

  bool _salvando = false;
  bool _consultandoCnpj = false;

  @override
  void initState() {
    super.initState();
    _carregarFormas();
  }

  @override
  void dispose() {
    for (final c in [
      _nome,
      _fantasia,
      _cpfCnpj,
      _ie,
      _celular,
      _fone,
      _email,
      _endereco,
      _numero,
      _bairro,
      _cidade,
      _uf,
      _cep,
      _limite,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(TextEditingController c) => c.text.trim();

  void _setIfFilled(TextEditingController c, dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) {
      c.text = text;
    }
  }

  Future<void> _carregarFormas() async {
    final rows = await _db.query('SELECT * FROM formas_pagamento ORDER BY codigo');
    if (!mounted) return;
    setState(() => _formas = rows);
  }

  Map<String, dynamic>? _formaById(int? id) {
    for (final f in _formas) {
      if (f['id'] == id) return f;
    }
    return null;
  }

  Map<String, dynamic>? _tabelaById(int? id) {
    for (final t in _tabelas) {
      if (t['id'] == id) return t;
    }
    return null;
  }

  List<Map<String, dynamic>> _parseTabelas(dynamic json) {
    try {
      final decoded = jsonDecode((json ?? '[]').toString());
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  void _aplicarForma(int? id) {
    final f = _formaById(id);
    _formaId = id;
    _tabelas = _parseTabelas(f?['tabelas_json']);
    if (_tabelaById(_tabelaPrazoId) == null) {
      _tabelaPrazoId = null;
      _tabelaDias = null;
    }
  }

  void _aplicarTelefone(String? phone, {String? fallback}) {
    for (final raw in [phone, fallback]) {
      if (raw == null || raw.trim().isEmpty) continue;
      final digits = CpfCnpjInputFormatter.onlyDigits(raw);
      if (digits.length < 10) continue;

      final isCelular = digits.length >= 11 && digits[2] == '9';
      if (isCelular) {
        if (_t(_celular).isEmpty) _celular.text = raw.trim();
      } else if (_t(_fone).isEmpty) {
        _fone.text = raw.trim();
      } else if (_t(_celular).isEmpty) {
        _celular.text = raw.trim();
      }
    }
  }

  Future<void> _pesquisarCnpj() async {
    final digits = CpfCnpjInputFormatter.onlyDigits(_cpfCnpj.text);

    if (digits.length != 14) {
      _avisa('Informe um CNPJ completo com 14 dígitos para pesquisar.');
      return;
    }

    final state = context.read<AppState>();
    if (!state.isLoggedIn) {
      _avisa('Faça login no ERP para consultar o CNPJ.');
      return;
    }

    setState(() => _consultandoCnpj = true);

    try {
      final data = await CnpjLookup(state.api).lookup(digits);
      _aplicarConsultaCnpj(data);
      if (!mounted) return;
      _avisa('Dados da empresa preenchidos automaticamente.', sucesso: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _avisa(e.message);
    } on TimeoutException {
      if (!mounted) return;
      _avisa('A consulta demorou demais. Verifique a internet e tente novamente.');
    } catch (e) {
      if (!mounted) return;
      _avisa('Não foi possível consultar o CNPJ: $e');
    } finally {
      if (mounted) setState(() => _consultandoCnpj = false);
    }
  }

  void _aplicarConsultaCnpj(Map<String, dynamic> data) {
    _setIfFilled(_cpfCnpj, data['cpf_cnpj']);
    _setIfFilled(_nome, data['nome_razao']);
    _setIfFilled(_fantasia, data['apelido_fantasia']);
    _setIfFilled(_ie, data['rg_ie'] ?? data['inscricao_estadual']);
    _setIfFilled(_cep, data['cep']);
    _setIfFilled(_endereco, data['endereco']);
    _setIfFilled(_numero, data['numero']);
    _setIfFilled(_bairro, data['bairro']);
    _setIfFilled(_cidade, data['cidade_nome']);
    _setIfFilled(_uf, data['uf']);
    _setIfFilled(_email, data['email']);
    _aplicarTelefone(data['fone1']?.toString(), fallback: data['fone2']?.toString());
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

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);

    final agora = DateTime.now().toIso8601String();
    final localId = _db.newLocalId();
    final limite = double.tryParse(_t(_limite).replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
    final vendedorId = context.read<AppState>().config.vendedorId;
    final visitaDias = (_visitaDias.toList()..sort());

    final row = <String, dynamic>{
      'id': localId,
      'codigo': '',
      'nome_razao': _t(_nome),
      'apelido_fantasia': _t(_fantasia),
      'cpf_cnpj': _t(_cpfCnpj),
      'rg_ie': _t(_ie).isEmpty ? null : _t(_ie).toUpperCase(),
      'endereco': _t(_endereco),
      'numero': _t(_numero),
      'bairro': _t(_bairro),
      'cidade_nome': _t(_cidade),
      'uf': _t(_uf).toUpperCase(),
      'cep': _t(_cep),
      'email': _t(_email),
      'fone1': _t(_fone),
      'celular1': _t(_celular),
      'whatsapp': _t(_celular),
      'limite_credito': limite,
      'dia_pgto': null,
      'forma_pagamento_id': _formaId,
      'tabela_prazo_id': _tabelaPrazoId,
      'tabela_prazo_dias': _tabelaDias,
      'vendedor_fv_id': vendedorId,
      'ativo': 1,
      'updated_at': agora,
    };

    try {
      await _db.upsertCustomer(row);
      await _db.replaceCustomerVisitaDias(localId, visitaDias);

      final payload = Map<String, dynamic>.from(row)
        ..remove('id')
        ..['visita_dias'] = visitaDias;
      await _db.insertOutboxCustomer({
        'uuid': const Uuid().v4(),
        'local_id': localId,
        'payload_json': jsonEncode(payload),
        'created_at': agora,
        'status': 'pendente',
        'erro': null,
        'server_id': null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Cliente salvo. Será enviado ao ERP na sincronização.'),
          behavior: SnackBarBehavior.floating,
        ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: const Text('Novo Cliente'),
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
          children: [
            _bloco(
              icon: Icons.badge_outlined,
              titulo: 'Identificação',
              filhos: [
                _campo(_nome, 'Nome / Razão social', obrigatorio: true, capitalizar: true),
                _campo(_fantasia, 'Apelido / Nome fantasia', capitalizar: true),
                _campoCpfCnpj(),
                _campo(_ie, 'IE (Inscrição Estadual)', capitalizar: true),
              ],
            ),
            _bloco(
              icon: Icons.phone_outlined,
              titulo: 'Contato',
              filhos: [
                Row(
                  children: [
                    Expanded(child: _campo(_celular, 'Celular / WhatsApp', teclado: TextInputType.phone)),
                    const SizedBox(width: 8),
                    Expanded(child: _campo(_fone, 'Telefone fixo', teclado: TextInputType.phone)),
                  ],
                ),
                _campo(_email, 'E-mail', teclado: TextInputType.emailAddress),
              ],
            ),
            _bloco(
              icon: Icons.location_on_outlined,
              titulo: 'Endereço',
              filhos: [
                _campo(_endereco, 'Endereço', capitalizar: true),
                Row(
                  children: [
                    Expanded(flex: 2, child: _campo(_numero, 'Número', teclado: TextInputType.text)),
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: _campo(_bairro, 'Bairro', capitalizar: true)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(flex: 3, child: _campo(_cidade, 'Cidade', capitalizar: true)),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: _campo(_uf, 'UF',
                          capitalizar: true,
                          maxLength: 2,
                          formatters: [LengthLimitingTextInputFormatter(2)]),
                    ),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: _campo(_cep, 'CEP', teclado: TextInputType.number)),
                  ],
                ),
              ],
            ),
            _bloco(
              icon: Icons.payments_outlined,
              titulo: 'Financeiro',
              filhos: [
                _campo(_limite, 'Limite de crédito (R\$)',
                    teclado: const TextInputType.numberWithOptions(decimal: true)),
                _dropdownForma(),
                if (_tabelas.isNotEmpty) _dropdownTabela(),
              ],
            ),
            _bloco(
              icon: Icons.calendar_month_outlined,
              titulo: 'Dias de visita',
              filhos: [_chipsVisitaDias()],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
          ),
          child: FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 20),
            label: Text(_salvando ? 'Salvando...' : 'Salvar cliente'),
            style: FilledButton.styleFrom(
              backgroundColor: Brand.green,
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _deco(String label, {String? helper, int helperMaxLines = 1}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: helperMaxLines,
      isDense: true,
      counterText: '',
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Brand.blue, width: 1.4),
      ),
    );
  }

  Widget _bloco({required IconData icon, required String titulo, required List<Widget> filhos}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Brand.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    titulo.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11 + Brand.textBump01cm,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: const Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: filhos,
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoCpfCnpj() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _cpfCnpj,
              keyboardType: TextInputType.number,
              inputFormatters: [CpfCnpjInputFormatter()],
              onFieldSubmitted: (_) => _pesquisarCnpj(),
              decoration: _deco(
                'CPF / CNPJ',
                helper: 'CNPJ: Pesquisar busca na Receita',
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: FilledButton.tonalIcon(
              onPressed: _consultandoCnpj ? null : _pesquisarCnpj,
              icon: _consultandoCnpj
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search_rounded, size: 18),
              label: Text(_consultandoCnpj ? '...' : 'Pesquisar'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownForma() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<int?>(
        value: _formaId,
        isExpanded: true,
        isDense: true,
        decoration: _deco('Forma de pagamento'),
        hint: Text(_formas.isEmpty ? 'Sincronize para carregar' : 'Selecione'),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Nenhuma')),
          for (final f in _formas)
            DropdownMenuItem<int?>(
              value: f['id'] as int?,
              child: Text('${f['codigo'] ?? ''} - ${f['descricao'] ?? ''}'.trim(),
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (id) => setState(() => _aplicarForma(id)),
      ),
    );
  }

  Widget _dropdownTabela() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<int?>(
        value: _tabelaPrazoId,
        isExpanded: true,
        isDense: true,
        decoration: _deco('Tabela / Prazo'),
        hint: const Text('Selecione'),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('À vista / nenhuma')),
          for (final t in _tabelas)
            DropdownMenuItem<int?>(
              value: t['id'] as int?,
              child: Text('${t['dias'] ?? ''} dias'.trim(), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (id) => setState(() {
          _tabelaPrazoId = id;
          _tabelaDias = _tabelaById(id)?['dias']?.toString();
        }),
      ),
    );
  }

  Widget _campo(
    TextEditingController c,
    String label, {
    bool obrigatorio = false,
    bool capitalizar = true,
    TextInputType? teclado,
    int? maxLength,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: c,
        keyboardType: teclado,
        textCapitalization: capitalizar ? TextCapitalization.characters : TextCapitalization.none,
        maxLength: maxLength,
        inputFormatters: capitalizar ? withUpperCase(formatters) : formatters,
        style: TextStyle(fontSize: 14 + Brand.textBump01cm, color: Brand.textPrimary),
        validator: validator ??
            (obrigatorio
                ? (v) => (v == null || v.trim().isEmpty) ? 'Informe o $label.' : null
                : null),
        decoration: _deco(obrigatorio ? '$label *' : label),
      ),
    );
  }

  /// Flags compactas Seg–Dom (mesmo modelo do ERP).
  Widget _chipsVisitaDias() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in _abrevDias.entries)
            FilterChip(
              label: Text(entry.value),
              selected: _visitaDias.contains(entry.key),
              onSelected: (sel) => setState(() {
                if (sel) {
                  _visitaDias.add(entry.key);
                } else {
                  _visitaDias.remove(entry.key);
                }
              }),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              selectedColor: Brand.blue.withValues(alpha: 0.16),
              checkmarkColor: Brand.blue,
              labelStyle: TextStyle(
                fontSize: 12.5 + Brand.textBump01cm,
                fontWeight: FontWeight.w600,
                color: _visitaDias.contains(entry.key) ? Brand.blue : const Color(0xFF475569),
              ),
              side: BorderSide(
                color: _visitaDias.contains(entry.key) ? Brand.blue : const Color(0xFFE2E8F0),
              ),
            ),
        ],
      ),
    );
  }
}
