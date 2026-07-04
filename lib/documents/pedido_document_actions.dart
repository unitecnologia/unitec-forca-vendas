import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../db/local_db.dart';
import 'pedido_pdf.dart';

/// Compartilha ou imprime o PDF de um pedido salvo localmente (outbox).
class PedidoDocumentActions {
  static Future<Map<String, dynamic>?> _loadOrder(String uuid) async {
    return LocalDb.instance.orderForPdf(uuid);
  }

  static String _fileName(Map<String, dynamic> order) {
    final dav = (order['numero'] ?? '').toString();
    final ped = (order['numero_pedido'] ?? '').toString();
    final id = ped.isNotEmpty ? ped : (dav.isNotEmpty ? dav : order['uuid']);
    final tipo = (order['tipo'] ?? 'pedido').toString();
    return '${tipo}_$id.pdf';
  }

  static Future<File> _writeTempPdf(Map<String, dynamic> order) async {
    final doc = await PedidoPdf.build(order);
    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_fileName(order)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> imprimir(BuildContext context, String uuid) async {
    final order = await _loadOrder(uuid);
    if (order == null) {
      _snack(context, 'Pedido não encontrado. Sincronize novamente.');
      return;
    }
    final doc = await PedidoPdf.build(order);
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  static Future<void> compartilhar(BuildContext context, String uuid) async {
    final order = await _loadOrder(uuid);
    if (order == null) {
      _snack(context, 'Pedido não encontrado. Sincronize novamente.');
      return;
    }
    final file = await _writeTempPdf(order);

    final cliente = (order['nome_razao'] ?? 'Cliente').toString();
    final dav = (order['numero'] ?? '').toString();
    final ped = (order['numero_pedido'] ?? '').toString();
    final refs = <String>[];
    if (dav.isNotEmpty) refs.add('DAV $dav');
    if (ped.isNotEmpty) refs.add('Pedido $ped');
    final ref = refs.isEmpty ? '' : ' (${refs.join(' • ')})';

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: '$cliente$ref',
      subject: 'Pedido Unitec',
    );
  }

  static Future<void> whatsapp(BuildContext context, String uuid) async {
    await compartilhar(context, uuid);
  }

  static void _snack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
