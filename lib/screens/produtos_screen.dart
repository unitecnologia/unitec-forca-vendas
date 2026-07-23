import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../pricing/product_preco.dart';
import '../ui/barcode_scan.dart';
import '../ui/brand.dart';
import '../ui/estoque_chips.dart';
import '../ui/format.dart';
import '../ui/produto_busca.dart';
import '../ui/produto_foto_image.dart';
import '../ui/produto_foto_viewer.dart';
import '../ui/produto_list_card.dart';
import '../ui/uppercase_input.dart';

/// Monta a URL completa da foto a partir do caminho relativo vindo do ERP.
String? _fotoFullUrl(String base, dynamic fotoUrl) => produtoFotoUrl(base, fotoUrl);

class ProdutosScreen extends StatefulWidget {
  const ProdutosScreen({super.key});

  @override
  State<ProdutosScreen> createState() => _ProdutosScreenState();
}

class _ProdutosScreenState extends State<ProdutosScreen> {
  final _db = LocalDb.instance;
  final _buscaCtrl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  List<String> _grupos = [];
  String _termo = '';
  String? _grupoSel; // null = Todos
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarGrupos();
    _buscar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarGrupos() async {
    // Mesma regra da tela de vendas: grupos com flag App no ERP.
    var nomes = <String>[];

    try {
      final rows = await _db.query(
        "SELECT nome FROM grupos WHERE (ativo = 1 OR ativo IS NULL) "
        "AND (mostrar_no_app = 1 OR mostrar_no_app IS NULL) "
        "AND nome IS NOT NULL AND TRIM(nome) <> '' ORDER BY nome",
      );
      nomes = rows
          .map((r) => (r['nome'] ?? '').toString().trim())
          .where((g) => g.isNotEmpty)
          .toList();
    } catch (_) {}

    if (nomes.isEmpty) {
      try {
        final rows = await _db.query(
          "SELECT DISTINCT grupo AS nome FROM products WHERE ativo = 1 AND mostrar_no_app = 1 "
          "AND grupo IS NOT NULL AND TRIM(grupo) <> '' ORDER BY grupo",
        );
        nomes = rows
            .map((r) => (r['nome'] ?? '').toString().trim())
            .where((g) => g.isNotEmpty)
            .toList();
      } catch (_) {
        nomes = [];
      }
    }

    if (!mounted) return;
    setState(() {
      _grupos = nomes;
      if (_grupoSel != null && !_grupos.contains(_grupoSel)) {
        _grupoSel = null;
      }
    });
  }

  Future<void> _escanearBarras() async {
    final codigo = await escanearCodigoBarras(context);
    if (!mounted || codigo == null || codigo.isEmpty) return;
    _buscaCtrl.text = codigo;
    _termo = codigo;
    await _buscar();
  }

  Future<void> _buscar() async {
    final f = ProdutoBusca.filtro(_termo, grupo: _grupoSel);
    final rows = await _db.query(
      'SELECT * FROM products WHERE ${f.whereExtra} ORDER BY ${f.orderBy} LIMIT 200',
      f.args,
    );
    if (mounted) {
      setState(() {
        _rows = rows;
        _carregando = false;
      });
    }
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onTap(),
        selectedColor: Brand.blue,
        labelStyle: TextStyle(
          color: sel ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = context.read<AppState>().config;
    final base = config.baseUrl;
    final estoque = config.estoqueNome.trim();
    final estoqueLabel = estoque.isEmpty ? 'Estoque não definido' : estoque;

    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Produtos'),
            const SizedBox(height: 1),
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 12,
                  color: estoque.isEmpty ? Colors.white54 : Colors.white70,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    estoqueLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: estoque.isEmpty ? Colors.white54 : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: const BoxDecoration(
              color: Brand.blue,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
            ),
            child: TextField(
              controller: _buscaCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: withUpperCase(),
              decoration: InputDecoration(
                hintText: 'Buscar por descrição, código ou marca',
                prefixIcon: const Icon(Icons.search, color: Brand.blue),
                suffixIcon: IconButton(
                  tooltip: 'Escanear código de barras',
                  onPressed: _escanearBarras,
                  icon: const Icon(Icons.qr_code_scanner, color: Brand.blue),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (s) {
                _termo = s;
                _buscar();
              },
            ),
          ),
          if (_grupos.isNotEmpty)
            Container(
              width: double.infinity,
              color: Brand.bg,
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _chip('Todos', _grupoSel == null, () {
                      setState(() => _grupoSel = null);
                      _buscar();
                    }),
                    for (final g in _grupos)
                      _chip(g, _grupoSel == g, () {
                        setState(() => _grupoSel = g);
                        _buscar();
                      }),
                  ],
                ),
              ),
            ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_rows.isEmpty)
            const Expanded(child: Center(child: Text('Nenhum produto encontrado.')))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => ProdutoListCard(
                  produto: _rows[i],
                  baseUrl: base,
                  onTap: () => _detalhe(_rows[i]),
                  onFotoTap: () {
                    final url = _fotoFullUrl(base, _rows[i]['foto_url']);
                    final id = (_rows[i]['id'] as num?)?.toInt();
                    if (url != null || id != null) {
                      abrirProdutoFoto(
                        context,
                        productId: id,
                        url: url,
                        titulo: (_rows[i]['descricao'] ?? '').toString(),
                      );
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _detalhe(Map<String, dynamic> p) {
    final promo = (p['promo_preco_venda'] as num?)?.toDouble() ?? 0;
    final base = context.read<AppState>().config.baseUrl;
    final fotoUrl = _fotoFullUrl(base, p['foto_url']);
    final productId = (p['id'] as num?)?.toInt();
    final descricao = (p['descricao'] ?? '').toString();
    final temFoto = fotoUrl != null || productId != null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (temFoto && fotoUrl != null)
                Center(
                  child: GestureDetector(
                    onTap: () => abrirProdutoFoto(
                      sheetCtx,
                      productId: productId,
                      url: fotoUrl,
                      titulo: descricao,
                    ),
                    child: Container(
                      width: double.infinity,
                      height: 160,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ProdutoFotoImage(
                        productId: productId,
                        networkUrl: fotoUrl,
                        height: 160,
                        fit: BoxFit.contain,
                        borderRadius: 14,
                        placeholderIconSize: 40,
                      ),
                    ),
                  ),
                ),
              if (temFoto && fotoUrl != null) const SizedBox(height: 14),
              Text(descricao,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Cód. ${p['codigo'] ?? ''}  •  ${p['marca'] ?? ''}',
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              EstoquePainel(produto: p),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: productId == null
                      ? null
                      : () => _consultarEstoqueFiliais(sheetCtx, p),
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text('Consultar estoque nas filiais'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Brand.blue,
                    side: BorderSide(color: Brand.blue.withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              _linhaPreco('Preço varejo', brMoney(ProductPreco.precoVarejo(p)), Brand.precoVarejo),
              _linhaPreco('Preço atacado', brMoney(ProductPreco.precoAtacado(p)), Brand.precoAtacado),
              _linhaPreco('Preço especial', brMoney(ProductPreco.precoEspecial(p)), Brand.precoEspecial),
              if (promo > 0)
                _linhaPreco('Promoção', brMoney(promo), Brand.precoEspecial),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _consultarEstoqueFiliais(BuildContext context, Map<String, dynamic> p) async {
    final productId = (p['id'] as num?)?.toInt();
    if (productId == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final data = await context.read<AppState>().api.estoqueFiliais(productId);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // loading

      final filiais = (data['filiais'] as List?) ?? const [];
      final unidade = (data['unidade'] ?? p['unidade'] ?? '').toString();
      final titulo = (data['descricao'] ?? p['descricao'] ?? 'Produto').toString();

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Estoque nas filiais',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Brand.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                if (filiais.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Nenhum depósito encontrado.')),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filiais.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final f = Map<String, dynamic>.from(filiais[i] as Map);
                        final empresa = (f['empresa_nome'] ?? '').toString();
                        final estoque = (f['estoque_nome'] ?? '').toString();
                        final atual = (f['atual'] as num?)?.toDouble() ?? 0;
                        final reserv = (f['reservado'] as num?)?.toDouble() ?? 0;
                        final disp = (f['disponivel'] as num?)?.toDouble() ?? 0;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                empresa,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                              ),
                              if (estoque.isNotEmpty)
                                Text(
                                  estoque,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _chipEstoque('Atual', fmtEstoque(atual), Brand.estoqueAtual, Colors.white),
                                  const SizedBox(width: 6),
                                  _chipEstoque(
                                    'Reserv.',
                                    fmtEstoque(reserv),
                                    Brand.estoqueReservado,
                                    Brand.estoqueReservadoText,
                                  ),
                                  const SizedBox(width: 6),
                                  _chipEstoque(
                                    'Disp.',
                                    unidade.isEmpty ? fmtEstoque(disp) : '${fmtEstoque(disp)} $unidade',
                                    Brand.estoqueDisponivel,
                                    Colors.white,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível consultar o estoque: $e')),
      );
    }
  }

  Widget _chipEstoque(String label, String valor, Color bg, Color fg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.9))),
            const SizedBox(height: 2),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaPreco(String label, String valor, Color cor) {
    const fg = Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: cor,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: cor.withValues(alpha: 0.28),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.95),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: fg,
                ),
              ),
            ),
            Text(
              valor,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
