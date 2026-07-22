import 'dart:io';

import 'package:flutter/material.dart';

import '../media/produto_foto_cache.dart';
import 'brand.dart';

/// Miniatura/imagem de produto: prioriza arquivo local (offline), senão rede.
class ProdutoFotoImage extends StatefulWidget {
  const ProdutoFotoImage({
    super.key,
    required this.productId,
    this.networkUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 12,
    this.placeholderIconSize = 26,
    this.darkPlaceholder = false,
  });

  final int? productId;
  final String? networkUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final double placeholderIconSize;
  final bool darkPlaceholder;

  @override
  State<ProdutoFotoImage> createState() => _ProdutoFotoImageState();
}

class _ProdutoFotoImageState extends State<ProdutoFotoImage> {
  Future<String?>? _localFuture;

  @override
  void initState() {
    super.initState();
    _localFuture = _resolveLocal();
  }

  @override
  void didUpdateWidget(covariant ProdutoFotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId || oldWidget.networkUrl != widget.networkUrl) {
      _localFuture = _resolveLocal();
    }
  }

  Future<String?> _resolveLocal() async {
    final id = widget.productId;
    if (id == null || id <= 0) return null;
    return ProdutoFotoCache.instance.pathFor(id);
  }

  Widget _placeholder() {
    if (widget.darkPlaceholder) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: widget.placeholderIconSize),
      );
    }
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Brand.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: Brand.green.withValues(alpha: 0.2)),
      ),
      child: Icon(Icons.inventory_2_outlined, color: Brand.green, size: widget.placeholderIconSize),
    );
  }

  Widget _loading() {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: widget.darkPlaceholder ? Colors.white : Brand.blue,
          ),
        ),
      ),
    );
  }

  Widget _fromFile(String path) {
    return Image.file(
      File(path),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (_, __, ___) => _fromNetworkOrPlaceholder(),
    );
  }

  Widget _fromNetworkOrPlaceholder() {
    final url = widget.networkUrl;
    if (url == null || url.isEmpty) return _placeholder();
    return Image.network(
      url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (_, __, ___) => _placeholder(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _loading();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSource = widget.productId != null || (widget.networkUrl?.isNotEmpty ?? false);
    if (!hasSource) return _placeholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: FutureBuilder<String?>(
        future: _localFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            if (widget.networkUrl != null) return _fromNetworkOrPlaceholder();
            return _loading();
          }
          final path = snap.data;
          if (path != null && path.isNotEmpty) return _fromFile(path);
          return _fromNetworkOrPlaceholder();
        },
      ),
    );
  }
}
