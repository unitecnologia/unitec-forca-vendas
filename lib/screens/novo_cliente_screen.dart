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
  final _diaPgto = TextEditingController();

  List<Map<String, dynamic>> _formas = [];
  List<Map<String, dynamic>> _tabelas = [];
  int? _formaId;
  int? _tabelaPrazoId;
  String? _tabelaDias;

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
      _diaPgto,
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
    final diaPgto = int.tryParse(_t(_diaPgto));
    final vendedorId = context.read<AppState>().config.vendedorId;

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
      'dia_pgto': diaPgto,
      'forma_pagamento_id': _formaId,
      'tabela_prazo_id': _tabelaPrazoId,
      'tabela_prazo_dias': _tabelaDias,
      'vendedor_fv_id': vendedorId,
      'ativo': 1,
      'updated_at': agora,
    };

    try {
      await _db.upsertCustomer(row);

      final payload = Map<String, dynamic>.from(row)..remove('id');
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
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _secao('Identificação'),
            _campo(_nome, 'Nome / Razão social', obrigatorio: true, capitalizar: true),
            _campo(_fantasia, 'Apelido / Nome fantasia', capitalizar: true),
            _campoCpfCnpj(),
            _campo(_ie, 'IE (Inscrição Estadual)', capitalizar: true),
            _secao('Contato'),
            _campo(_celular, 'Celular / WhatsApp', teclado: TextInputType.phone),
            _campo(_fone, 'Telefone fixo', teclado: TextInputType.phone),
            _campo(_email, 'E-mail', teclado: TextInputType.emailAddress),
            _secao('Endereço'),
            _campo(_endereco, 'Endereço', capitalizar: true),
            Row(
              children: [
                Expanded(flex: 2, child: _campo(_numero, 'Número', teclado: TextInputType.text)),
                const SizedBox(width: 10),
                Expanded(flex: 3, child: _campo(_bairro, 'Bairro', capitalizar: true)),
              ],
            ),
            Row(
              children: [
                Expanded(flex: 3, child: _campo(_cidade, 'Cidade', capitalizar: true)),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: _campo(_uf, 'UF',
                      capitalizar: true,
                      maxLength: 2,
                      formatters: [LengthLimitingTextInputFormatter(2)]),
                ),
              ],
            ),
            _campo(_cep, 'CEP', teclado: TextInputType.number),
            _secao('Financeiro'),
            _campo(_limite, 'Limite de crédito (R\$)', teclado: const TextInputType.numberWithOptions(decimal: true)),
            _dropdownForma(),
            if (_tabelas.isNotEmpty) _dropdownTabela(),
            _campo(
              _diaPgto,
              'Dia de pagamento',
              teclado: TextInputType.number,
              maxLength: 2,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                if (n == null || n < 1 || n > 31) return 'Informe um dia entre 1 e 31.';
                return null;
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: Text(_salvando ? 'Salvando...' : 'Salvar cliente'),
            style: FilledButton.styleFrom(
              backgroundColor: Brand.green,
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ),
      ),
    );
  }

  Widget _campoCpfCnpj() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _cpfCnpj,
              keyboardType: TextInputType.number,
              inputFormatters: [CpfCnpjInputFormatter()],
              onFieldSubmitted: (_) => _pesquisarCnpj(),
              decoration: InputDecoration(
                labelText: 'CPF / CNPJ',
                helperText: 'CNPJ: toque em Pesquisar para buscar na Receita',
                helperMaxLines: 2,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton.tonalIcon(
              onPressed: _consultandoCnpj ? null : _pesquisarCnpj,
              icon: _consultandoCnpj
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(_consultandoCnpj ? '...' : 'Pesquisar'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownForma() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<int?>(
        value: _formaId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Forma de pagamento',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<int?>(
        value: _tabelaPrazoId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Tabela / Prazo',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
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

  Widget _secao(String titulo) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(titulo,
            style: TextStyle(
                fontSize: 13 + Brand.textBump01cm,
                fontWeight: FontWeight.w700,
                color: Brand.blue,
                letterSpacing: 0.3)),
      );

  Widget _campo(
    TextEditingController c,
    String label, {
    bool obrigatorio = false,
    bool capitalizar = false,
    TextInputType? teclado,
    int? maxLength,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        keyboardType: teclado,
        textCapitalization: capitalizar ? TextCapitalization.characters : TextCapitalization.none,
        maxLength: maxLength,
        inputFormatters: formatters,
        validator: validator ??
            (obrigatorio
                ? (v) => (v == null || v.trim().isEmpty) ? 'Informe o $label.' : null
                : null),
        decoration: InputDecoration(
          labelText: obrigatorio ? '$label *' : label,
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
