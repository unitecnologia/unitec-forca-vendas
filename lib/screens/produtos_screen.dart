import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../ui/barcode_scan.dart';
import '../ui/brand.dart';
import '../ui/estoque_chips.dart';
import '../ui/format.dart';
import '../ui/produto_list_card.dart';

/// Monta a URL completa da foto a partir do caminho relativo vindo do ERP.
String? _fotoFullUrl(String base, dynamic fotoUrl) => produtoFotoUrl(base, fotoUrl);

/// Visualizador de imagem em tela cheia com zoom (pinça / duplo toque).
class FotoViewer extends StatelessWidget {
  const FotoViewer({super.key, required this.url, this.titulo});

  final String url;
  final String? titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(titulo ?? 'Foto do produto',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const CircularProgressIndicator(color: Colors.white);
            },
            errorBuilder: (_, __, ___) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                SizedBox(height: 12),
                Text('Não foi possível carregar a foto.',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _abrirFoto(BuildContext context, String url, String? titulo) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => FotoViewer(url: url, titulo: titulo)),
  );
}

class ProdutosScreen extends StatefulWidget {
  const ProdutosScreen({super.key});

  @override
  State<ProdutosScreen> createState() => _ProdutosScreenState();
}

class _ProdutosScreenState extends State<ProdutosScreen> {
  final _db = LocalDb.instance;
  final _buscaCtrl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  String _termo = '';
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _escanearBarras() async {
    final codigo = await escanearCodigoBarras(context);
    if (!mounted || codigo == null || codigo.isEmpty) return;
    _buscaCtrl.text = codigo;
    _termo = codigo;
    await _buscar();
  }

  Future<void> _buscar() async {
    final like = '%${_termo.trim()}%';
    final rows = await _db.query(
      "SELECT * FROM products WHERE ativo = 1 AND mostrar_no_app = 1 AND (descricao LIKE ? OR codigo LIKE ? OR codigo_barras LIKE ? OR marca LIKE ?) "
      'ORDER BY descricao LIMIT 200',
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
                    if (url != null) {
                      _abrirFoto(context, url, (_rows[i]['descricao'] ?? '').toString());
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
    final descricao = (p['descricao'] ?? '').toString();
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
              if (fotoUrl != null)
                Center(
                  child: GestureDetector(
                    onTap: () => _abrirFoto(sheetCtx, fotoUrl, descricao),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        fotoUrl,
                        height: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        loadingBuilder: (context, child, progress) => progress == null
                            ? child
                            : const SizedBox(
                                height: 160,
                                child: Center(child: CircularProgressIndicator())),
                      ),
                    ),
                  ),
                ),
              if (fotoUrl != null) const SizedBox(height: 14),
              Text(descricao,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Cód. ${p['codigo'] ?? ''}  •  ${p['marca'] ?? ''}',
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              EstoquePainel(produto: p),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 10),
              _linhaPreco('Preço à vista', brMoney(p['preco_venda'] as num?), Brand.precoVista),
              _linhaPreco('Preço a prazo', brMoney(p['preco_venda_prazo'] as num?), Brand.precoPrazo),
              _linhaPreco('Preço atacado', brMoney(p['preco_atacado'] as num?), Brand.precoAtacado),
              if (promo > 0)
                _linhaPreco('Promoção', brMoney(promo), const Color(0xFF7C3AED)),
            ],
          ),
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
