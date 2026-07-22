import 'package:flutter/material.dart';

import '../media/produto_foto_cache.dart';
import 'brand.dart';
import 'estoque_chips.dart';
import 'format.dart';
import 'produto_foto_image.dart';

export '../media/produto_foto_cache.dart' show produtoFotoUrl;

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
    final productId = (produto['id'] as num?)?.toInt();
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
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Brand.green.withValues(alpha: 0.2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ProdutoFotoImage(
                    productId: productId,
                    networkUrl: fotoUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.contain,
                    borderRadius: 12,
                  ),
                ),
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
