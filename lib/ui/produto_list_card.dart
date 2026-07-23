import 'package:flutter/material.dart';

import '../media/produto_foto_cache.dart';
import '../pricing/product_preco.dart';
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
    this.listaPreco,
  });

  final Map<String, dynamic> produto;
  final String baseUrl;
  final VoidCallback onTap;
  final VoidCallback? onFotoTap;

  /// Lista de preço ativa do pedido (destaca V/A/E correspondente).
  final Map<String, dynamic>? listaPreco;

  static const _corV = Brand.precoVarejo; // verde
  static const _corA = Brand.blue; // azul
  static const _corE = Color(0xFFEA580C); // laranja

  @override
  Widget build(BuildContext context) {
    final productId = (produto['id'] as num?)?.toInt();
    final fotoUrl = produtoFotoUrl(baseUrl, produto['foto_url']);
    final descricao = (produto['descricao'] ?? '').toString();
    final codigo = (produto['codigo'] ?? '').toString();
    final nivelAtivo = listaPreco == null
        ? null
        : ProductPreco.nivelDaTabela(
            codigo: listaPreco?['codigo']?.toString(),
            descricao: listaPreco?['descricao']?.toString(),
          );

    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0xFF0F2847).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 7, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onFotoTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Brand.green.withValues(alpha: 0.2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ProdutoFotoImage(
                    productId: productId,
                    networkUrl: fotoUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    borderRadius: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      descricao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.2,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 5),
                    EstoqueLinhaGrid(produto: produto, codigo: codigo),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _precosDaLista(
                nivelAtivo: nivelAtivo,
                varejo: ProductPreco.precoVarejo(produto),
                atacado: ProductPreco.precoAtacado(produto),
                especial: ProductPreco.precoEspecial(produto),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Com lista do pedido: só o nível ativo. Sem lista (catálogo): V, A e E.
  Widget _precosDaLista({
    required String? nivelAtivo,
    required double varejo,
    required double atacado,
    required double especial,
  }) {
    final chips = <Widget>[];

    void add(String letra, double valor, Color cor, String nivel) {
      if (nivelAtivo != null && nivelAtivo != nivel) return;
      if (chips.isNotEmpty) chips.add(const SizedBox(height: 3));
      chips.add(_precoChip(
        letra: letra,
        valor: valor,
        cor: cor,
        ativo: nivelAtivo == null || nivelAtivo == nivel,
      ));
    }

    add('V', varejo, _corV, 'varejo');
    add('A', atacado, _corA, 'atacado');
    add('E', especial, _corE, 'especial');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: chips,
    );
  }

  Widget _precoChip({
    required String letra,
    required double valor,
    required Color cor,
    required bool ativo,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cor.withValues(alpha: ativo ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: cor.withValues(alpha: ativo ? 0.55 : 0.22),
          width: ativo ? 1.3 : 1,
        ),
      ),
      child: Text(
        '$letra ${brMoneyShort(valor)}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          height: 1.1,
          color: cor,
        ),
      ),
    );
  }
}
