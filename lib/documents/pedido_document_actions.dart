import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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

  static String mensagemPadrao(Map<String, dynamic> order) {
    final tipo = (order['tipo'] ?? 'pedido').toString() == 'orcamento' ? 'orçamento' : 'pedido';
    final dav = (order['numero'] ?? '').toString().trim();
    final ped = (order['numero_pedido'] ?? '').toString().trim();
    if (ped.isNotEmpty) return 'Segue pedido nº $ped.';
    if (dav.isNotEmpty) return 'Segue $tipo nº $dav.';
    final cliente = (order['nome_razao'] ?? '').toString().trim();
    if (cliente.isNotEmpty) return 'Segue $tipo ($cliente).';
    return 'Segue $tipo.';
  }

  static String assuntoEmail(Map<String, dynamic> order) {
    final tipo = (order['tipo'] ?? 'pedido').toString() == 'orcamento' ? 'ORCAMENTO' : 'PEDIDO';
    final dav = (order['numero'] ?? '').toString().trim();
    final ped = (order['numero_pedido'] ?? '').toString().trim();
    final n = ped.isNotEmpty ? ped : (dav.isNotEmpty ? dav : '');
    return n.isEmpty ? tipo : '$tipo N.$n';
  }

  static Future<File> _writeTempPdf(Map<String, dynamic> order) async {
    final doc = await PedidoPdf.build(order);
    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_fileName(order)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _digitsPhone(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  static String _phoneForWhatsApp(String raw) {
    var digits = _digitsPhone(raw);
    if (digits.length == 10 || digits.length == 11) {
      digits = '55$digits';
    }
    return digits;
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

  /// Abre o chat do WhatsApp com o número e compartilha o PDF para anexar.
  static Future<void> enviarWhatsApp(
    BuildContext context,
    String uuid, {
    required String telefone,
    String? mensagem,
  }) async {
    final order = await _loadOrder(uuid);
    if (order == null) {
      _snack(context, 'Pedido não encontrado.');
      return;
    }

    final digits = _phoneForWhatsApp(telefone);
    if (digits.length < 12) {
      _snack(context, 'WhatsApp inválido.');
      return;
    }

    final text = (mensagem ?? mensagemPadrao(order)).trim();
    final file = await _writeTempPdf(order);

    final wa = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(text)}');
    final opened = await launchUrl(wa, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _snack(context, 'Não foi possível abrir o WhatsApp.');
    }

    // Oferece o PDF para anexar na conversa (mesmo esquema do ERP com anexo).
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: text,
      subject: assuntoEmail(order),
    );
  }

  /// Abre o app de e-mail e compartilha o PDF anexável.
  static Future<void> enviarEmail(
    BuildContext context,
    String uuid, {
    required String email,
    String? mensagem,
  }) async {
    final order = await _loadOrder(uuid);
    if (order == null) {
      _snack(context, 'Pedido não encontrado.');
      return;
    }

    final to = email.trim();
    if (to.isEmpty || !to.contains('@')) {
      _snack(context, 'E-mail inválido.');
      return;
    }

    final subject = assuntoEmail(order);
    final body = (mensagem ?? mensagemPadrao(order)).trim();
    final file = await _writeTempPdf(order);

    final mailto = Uri(
      scheme: 'mailto',
      path: to,
      queryParameters: {
        'subject': subject,
        'body': '$body\n\n(Anexe o PDF que será oferecido em seguida.)',
      },
    );
    await launchUrl(mailto);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: body,
      subject: subject,
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
