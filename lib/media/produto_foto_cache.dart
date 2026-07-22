import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../log/app_log.dart';

/// Monta a URL completa da foto a partir do caminho relativo vindo do ERP.
String? produtoFotoUrl(String base, dynamic fotoUrl) {
  final f = (fotoUrl ?? '').toString().trim();
  if (f.isEmpty) return null;
  if (f.startsWith('http://') || f.startsWith('https://')) return f;
  final b = base.replaceFirst(RegExp(r'/+$'), '');
  final path = f.startsWith('/') ? f : '/$f';
  return '$b$path';
}

/// Cache em disco das fotos de produto (offline-first).
///
/// Na sincronização as imagens são baixadas para a pasta do app. A UI prioriza
/// o arquivo local; se não existir, tenta a URL da rede.
class ProdutoFotoCache {
  ProdutoFotoCache._();
  static final ProdutoFotoCache instance = ProdutoFotoCache._();

  Directory? _dir;
  Future<void>? _inFlight;
  final _pathMemo = <int, String?>{};

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'produto_fotos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  File _metaFile(Directory dir, int productId) =>
      File(p.join(dir.path, '$productId.meta'));

  Future<File?> fileFor(int productId) async {
    final cached = _pathMemo[productId];
    if (cached != null) {
      final f = File(cached);
      if (await f.exists()) return f;
      _pathMemo.remove(productId);
    }

    final dir = await _ensureDir();
    for (final ext in const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'img']) {
      final f = File(p.join(dir.path, '$productId.$ext'));
      if (await f.exists() && await f.length() > 0) {
        _pathMemo[productId] = f.path;
        return f;
      }
    }
    return null;
  }

  Future<String?> pathFor(int productId) async {
    final f = await fileFor(productId);
    return f?.path;
  }

  /// Baixa fotos novas/alteradas após o pull do catálogo (não bloqueia a sync).
  Future<void> syncAfterPull({
    required String baseUrl,
    required List<dynamic> products,
  }) {
    if (_inFlight != null) return _inFlight!;
    _inFlight = _syncAfterPullInternal(baseUrl: baseUrl, products: products);
    return _inFlight!.whenComplete(() => _inFlight = null);
  }

  Future<void> _syncAfterPullInternal({
    required String baseUrl,
    required List<dynamic> products,
  }) async {
    final pendentes = <({int id, String fotoUrl, String fullUrl})>[];

    for (final raw in products) {
      if (raw is! Map) continue;
      final id = (raw['id'] as num?)?.toInt();
      final fotoRel = (raw['foto_url'] ?? '').toString().trim();
      if (id == null || id <= 0 || fotoRel.isEmpty) continue;
      final full = produtoFotoUrl(baseUrl, fotoRel);
      if (full == null) continue;
      pendentes.add((id: id, fotoUrl: fotoRel, fullUrl: full));
    }

    if (pendentes.isEmpty) return;

    final dir = await _ensureDir();
    var baixadas = 0;
    var falhas = 0;
    var puladas = 0;

    const concurrency = 4;
    var index = 0;

    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= pendentes.length) return;
        final item = pendentes[i];
        try {
          final ok = await _ensureOne(
            dir: dir,
            productId: item.id,
            fotoUrlKey: item.fotoUrl,
            fullUrl: item.fullUrl,
          );
          if (ok == true) {
            baixadas++;
          } else if (ok == false) {
            falhas++;
          } else {
            puladas++;
          }
        } catch (_) {
          falhas++;
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));

    if (baixadas > 0 || falhas > 0) {
      AppLog.instance.info(
        'sync',
        'Fotos de produtos: $baixadas baixada(s), $puladas em cache, $falhas falha(s)',
      );
    }
  }

  /// `true` = baixou, `false` = falhou, `null` = já estava em cache.
  Future<bool?> _ensureOne({
    required Directory dir,
    required int productId,
    required String fotoUrlKey,
    required String fullUrl,
  }) async {
    final meta = _metaFile(dir, productId);
    final existing = await fileFor(productId);
    if (existing != null && await meta.exists()) {
      final key = (await meta.readAsString()).trim();
      if (key == fotoUrlKey) return null;
    }

    final resp = await http.get(Uri.parse(fullUrl)).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return false;

    final ext = _extFrom(resp.headers['content-type'], fullUrl);
    await _clearProductFiles(dir, productId);

    final out = File(p.join(dir.path, '$productId.$ext'));
    await out.writeAsBytes(resp.bodyBytes, flush: true);
    await meta.writeAsString(fotoUrlKey, flush: true);
    _pathMemo[productId] = out.path;
    return true;
  }

  Future<void> _clearProductFiles(Directory dir, int productId) async {
    _pathMemo.remove(productId);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == '$productId.meta' ||
          (name.startsWith('$productId.') && !name.endsWith('.meta'))) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  String _extFrom(String? contentType, String url) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.contains('png')) return 'png';
    if (ct.contains('webp')) return 'webp';
    if (ct.contains('gif')) return 'gif';
    if (ct.contains('jpeg') || ct.contains('jpg')) return 'jpg';

    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.gif')) return 'gif';
    return 'jpg';
  }
}
