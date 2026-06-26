import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../ui/brand.dart';
import '../ui/format.dart';

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
    final rows = await _db.query(
      "SELECT * FROM customers WHERE ativo = 1 AND (nome_razao LIKE ? OR apelido_fantasia LIKE ? OR codigo LIKE ? OR cpf_cnpj LIKE ?) "
      'ORDER BY nome_razao LIMIT 200',
      [like, like, like, like],
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
      appBar: AppBar(title: const Text('Clientes'), backgroundColor: Brand.blue, foregroundColor: Colors.white),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por nome, código ou CPF/CNPJ',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = _rows[i];
                  final cidade = [c['cidade_nome'], c['uf']].where((e) => (e ?? '').toString().isNotEmpty).join(' - ');
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: CircleAvatar(
                        backgroundColor: Brand.blue.withValues(alpha: 0.12),
                        child: const Icon(Icons.person, color: Brand.blue),
                      ),
                      title: Text((c['nome_razao'] ?? '').toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(cidade.isEmpty ? 'Cód. ${c['codigo'] ?? ''}' : cidade),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _detalhe(c),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _detalhe(Map<String, dynamic> c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        final endereco = [
          c['endereco'],
          c['numero'],
          c['bairro'],
        ].where((e) => (e ?? '').toString().isNotEmpty).join(', ');
        final cidade = [c['cidade_nome'], c['uf']].where((e) => (e ?? '').toString().isNotEmpty).join(' - ');
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((c['nome_razao'] ?? '').toString(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if ((c['apelido_fantasia'] ?? '').toString().isNotEmpty)
                  Text(c['apelido_fantasia'].toString(), style: const TextStyle(color: Colors.black54)),
                const Divider(height: 24),
                _linha(Icons.badge_outlined, 'Código', (c['codigo'] ?? '—').toString()),
                _linha(Icons.assignment_ind_outlined, 'CPF/CNPJ', (c['cpf_cnpj'] ?? '—').toString()),
                _linha(Icons.location_on_outlined, 'Endereço', endereco.isEmpty ? '—' : endereco),
                _linha(Icons.location_city_outlined, 'Cidade', cidade.isEmpty ? '—' : cidade),
                _linha(Icons.phone_outlined, 'Telefone',
                    [(c['celular1'] ?? ''), (c['fone1'] ?? '')].where((e) => e.toString().isNotEmpty).join(' / ').isEmpty
                        ? '—'
                        : [(c['celular1'] ?? ''), (c['fone1'] ?? '')].where((e) => e.toString().isNotEmpty).join(' / ')),
                _linha(Icons.email_outlined, 'E-mail', (c['email'] ?? '—').toString()),
                _linha(Icons.credit_score_outlined, 'Limite de crédito', brMoney(c['limite_credito'] as num?)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _linha(IconData icon, String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Brand.blue),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}
