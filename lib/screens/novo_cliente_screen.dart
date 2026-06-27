import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../db/local_db.dart';
import '../ui/brand.dart';

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

  bool _salvando = false;

  @override
  void dispose() {
    for (final c in [
      _nome, _fantasia, _cpfCnpj, _celular, _fone, _email,
      _endereco, _numero, _bairro, _cidade, _uf, _cep, _limite,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(TextEditingController c) => c.text.trim();

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);

    final agora = DateTime.now().toIso8601String();
    final localId = _db.newLocalId();
    final limite = double.tryParse(_t(_limite).replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;

    final row = <String, dynamic>{
      'id': localId,
      'codigo': '',
      'nome_razao': _t(_nome),
      'apelido_fantasia': _t(_fantasia),
      'cpf_cnpj': _t(_cpfCnpj),
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
            _campo(_cpfCnpj, 'CPF / CNPJ', teclado: TextInputType.number),
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

  Widget _secao(String titulo) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(titulo,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Brand.blue, letterSpacing: 0.3)),
      );

  Widget _campo(
    TextEditingController c,
    String label, {
    bool obrigatorio = false,
    bool capitalizar = false,
    TextInputType? teclado,
    int? maxLength,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        keyboardType: teclado,
        textCapitalization: capitalizar ? TextCapitalization.characters : TextCapitalization.none,
        maxLength: maxLength,
        inputFormatters: formatters,
        validator: obrigatorio
            ? (v) => (v == null || v.trim().isEmpty) ? 'Informe o $label.' : null
            : null,
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
