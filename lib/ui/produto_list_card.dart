import 'package:flutter/material.dart';

import 'brand.dart';
import 'estoque_chips.dart';
import 'format.dart';

/// Monta a URL completa da foto a partir do caminho relativo vindo do ERP.
String? produtoFotoUrl(String base, dynamic fotoUrl) {
  final f = (fotoUrl ?? '').toString().trim();
  if (f.isEmpty) return null;
  if (f.startsWith('http://') || f.startsWith('https://')) return f;
  final b = base.replaceFirst(RegExp(r'/+$'), '');
  final path = f.startsWith('/') ? f : '/$f';
  return '$b$path';
}

/// Card de produto na listagem (Produtos e seleção no pedido).
class ProdutoListCard extends StatelessWidget {
  const ProdutoListCard({
    super.key,
    required this.produto,
    required this.baseUrl,
    required this.onTap,
    this.onFotoTap,
  });

  final Map<String, dynamic> produto;
  final String baseUrl;
  final VoidCallback onTap;
  final VoidCallback? onFotoTap;

  @override
  Widget build(BuildContext context) {
    final preco = (produto['preco_venda'] as num?)?.toDouble() ?? 0;
    final fotoUrl = produtoFotoUrl(baseUrl, produto['foto_url']);
    final descricao = (produto['descricao'] ?? '').toString();
    final codigo = (produto['codigo'] ?? '').toString();

    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0xFF0F2847).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onFotoTap,
                child: _ProdutoMiniatura(url: fotoUrl),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            descricao,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              height: 1.25,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Brand.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            brMoney(preco),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: Brand.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    EstoqueLinhaGrid(produto: produto, codigo: codigo),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProdutoMiniatura extends StatelessWidget {
  const _ProdutoMiniatura({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const double size = 56;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Brand.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.green.withValues(alpha: 0.2)),
      ),
      child: const Icon(Icons.inventory_2_outlined, color: Brand.green, size: 26),
    );

    if (url == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
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
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        },
      ),
    );
  }
}
