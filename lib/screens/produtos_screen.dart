import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../ui/brand.dart';
import '../ui/format.dart';

/// Monta a URL completa da foto a partir do caminho relativo vindo do ERP.
String? _fotoFullUrl(String base, dynamic fotoUrl) {
  final f = (fotoUrl ?? '').toString().trim();
  if (f.isEmpty) return null;
  if (f.startsWith('http://') || f.startsWith('https://')) return f;
  final b = base.replaceFirst(RegExp(r'/+$'), '');
  final path = f.startsWith('/') ? f : '/$f';
  return '$b$path';
}

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
      "SELECT * FROM products WHERE ativo = 1 AND (descricao LIKE ? OR codigo LIKE ? OR codigo_barras LIKE ? OR marca LIKE ?) "
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
    final base = context.read<AppState>().config.baseUrl;
    return Scaffold(
      backgroundColor: Brand.bg,
      appBar: AppBar(title: const Text('Produtos'), backgroundColor: Brand.blue, foregroundColor: Colors.white),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por descrição, código ou marca',
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
            const Expanded(child: Center(child: Text('Nenhum produto encontrado.')))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ProdutoCard(p: _rows[i], base: base, onTap: () => _detalhe(_rows[i])),
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
              const SizedBox(height: 4),
              Text('Cód. ${p['codigo'] ?? ''}  •  ${p['marca'] ?? ''}',
                  style: const TextStyle(color: Colors.black54)),
              const Divider(height: 24),
              _linha('Preço à vista', brMoney(p['preco_venda'] as num?)),
              _linha('Preço a prazo', brMoney(p['preco_venda_prazo'] as num?)),
              _linha('Preço atacado', brMoney(p['preco_atacado'] as num?)),
              if (promo > 0) _linha('Promoção', brMoney(promo), destaque: true),
              _linha('Estoque', '${(p['estoque'] as num?)?.toString() ?? '0'} ${p['unidade'] ?? ''}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linha(String label, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(valor,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: destaque ? Brand.green : const Color(0xFF263238))),
        ],
      ),
    );
  }
}

class _ProdutoCard extends StatelessWidget {
  const _ProdutoCard({required this.p, required this.base, required this.onTap});

  final Map<String, dynamic> p;
  final String base;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estoque = (p['estoque'] as num?)?.toDouble() ?? 0;
    final preco = (p['preco_venda'] as num?)?.toDouble() ?? 0;
    final fotoUrl = _fotoFullUrl(base, p['foto_url']);
    final descricao = (p['descricao'] ?? '').toString();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: GestureDetector(
          onTap: fotoUrl != null ? () => _abrirFoto(context, fotoUrl, descricao) : null,
          child: _Miniatura(url: fotoUrl),
        ),
        title: Text(descricao, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('Cód. ${p['codigo'] ?? ''}  •  Estoque: ${estoque.toStringAsFixed(estoque == estoque.roundToDouble() ? 0 : 2)}'),
        trailing: Text(brMoney(preco),
            style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.blue)),
        onTap: onTap,
      ),
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const double size = 48;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Brand.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.inventory_2_outlined, color: Brand.green),
    );

    if (url == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        },
      ),
    );
  }
}
