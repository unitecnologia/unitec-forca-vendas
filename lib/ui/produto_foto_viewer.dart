import 'package:flutter/material.dart';

import 'produto_foto_image.dart';

/// Visualizador de imagem em tela cheia com zoom (pinça / duplo toque).
class ProdutoFotoViewer extends StatelessWidget {
  const ProdutoFotoViewer({
    super.key,
    this.productId,
    this.url,
    this.titulo,
  });

  final int? productId;
  final String? url;
  final String? titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          titulo ?? 'Foto do produto',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: ProdutoFotoImage(
            productId: productId,
            networkUrl: url,
            fit: BoxFit.contain,
            borderRadius: 0,
            placeholderIconSize: 64,
            darkPlaceholder: true,
          ),
        ),
      ),
    );
  }
}

void abrirProdutoFoto(
  BuildContext context, {
  int? productId,
  String? url,
  String? titulo,
}) {
  if ((url == null || url.isEmpty) && (productId == null || productId <= 0)) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProdutoFotoViewer(
        productId: productId,
        url: url,
        titulo: titulo,
      ),
    ),
  );
}
