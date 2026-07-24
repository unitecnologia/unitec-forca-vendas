import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../db/local_db.dart';
import '../platform/whatsapp_direct.dart';
import '../ui/pedido_envio_dialog.dart';
import '../ui/phone_formatter.dart';
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
    final n = dav.isNotEmpty ? dav : ped;
    if (n.isNotEmpty) return 'Segue $tipo nº $n.';
    final cliente = (order['nome_razao'] ?? '').toString().trim();
    if (cliente.isNotEmpty) return 'Segue $tipo ($cliente).';
    return 'Segue $tipo.';
  }

  static String assuntoEmail(Map<String, dynamic> order) {
    final ehOrcamento = (order['tipo'] ?? 'pedido').toString() == 'orcamento';
    final tipo = ehOrcamento ? 'ORCAMENTO' : 'PEDIDO';
    final dav = (order['numero'] ?? '').toString().trim();
    final ped = (order['numero_pedido'] ?? '').toString().trim();
    final n = ehOrcamento
        ? (dav.isNotEmpty ? dav : ped)
        : (ped.isNotEmpty ? ped : dav);
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
    if (digits.startsWith('55') && digits.length > 11) {
      digits = digits.substring(2);
    }
    if (digits.length == 10 || digits.length == 11) {
      digits = '55$digits';
    }
    return digits;
  }

  static String _telefoneCliente(Map<String, dynamic> order) {
    for (final key in ['whatsapp', 'celular1', 'fone1']) {
      final raw = (order[key] ?? '').toString().trim();
      if (raw.isNotEmpty) return raw;
    }
    return '';
  }

  static Map<String, dynamic> _withTipo(Map<String, dynamic> order, String? tipoForcado) {
    if (tipoForcado == null || tipoForcado.isEmpty) return order;
    return {...order, 'tipo': tipoForcado};
  }

  static Rect? _shareOrigin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Compartilha o PDF (com mensagem) pela folha do sistema.
  static Future<void> _sharePdfFile(
    BuildContext context, {
    required File file,
    required String fileName,
    required String text,
    required String subject,
  }) async {
    if (!await file.exists() || await file.length() == 0) {
      _snack(context, 'Não foi possível gerar o PDF.');
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
      text: text,
      subject: subject,
      sharePositionOrigin: _shareOrigin(context),
    );
  }

  /// Mesmo fluxo do fecha pedido: diálogo com WhatsApp/e-mail do cadastro + PDF.
  /// [tipoForcado] sobrescreve o tipo do registro (ex.: tela Orçamentos → 'orcamento').
  static Future<void> compartilhar(
    BuildContext context,
    String uuid, {
    String? tipoForcado,
  }) async {
    final orderRaw = await _loadOrder(uuid);
    if (orderRaw == null) {
      _snack(context, 'Pedido não encontrado. Sincronize novamente.');
      return;
    }
    if (!context.mounted) return;

    final order = _withTipo(orderRaw, tipoForcado);

    final tipoLabel =
        (order['tipo'] ?? 'pedido').toString() == 'orcamento' ? 'orçamento' : 'pedido';
    final clienteNome = (order['nome_razao'] ?? 'Cliente').toString();
    final whats = _telefoneCliente(order);
    final email = (order['email'] ?? '').toString().trim();

    final envio = await showPedidoEnvioDialog(
      context,
      tipoLabel: tipoLabel,
      clienteNome: clienteNome,
      whatsappInicial: whats,
      emailInicial: email,
      mensagemInicial: mensagemPadrao(order),
    );

    if (!context.mounted || envio == null) return;

    if (envio.canal == PedidoEnvioCanal.whatsapp) {
      await enviarWhatsApp(
        context,
        uuid,
        telefone: envio.whatsapp,
        mensagem: envio.mensagem,
        tipoForcado: tipoForcado,
      );
    } else {
      await enviarEmail(
        context,
        uuid,
        email: envio.email,
        mensagem: envio.mensagem,
        tipoForcado: tipoForcado,
      );
    }
  }

  /// Gera o PDF e envia pelo WhatsApp.
  ///
  /// No Android tenta abrir direto no chat do número (Intent + jid).
  /// Se falhar (sem WhatsApp / iOS), cai na folha de compartilhar do sistema.
  static Future<void> enviarWhatsApp(
    BuildContext context,
    String uuid, {
    required String telefone,
    String? mensagem,
    String? tipoForcado,
  }) async {
    final orderRaw = await _loadOrder(uuid);
    if (orderRaw == null) {
      _snack(context, 'Pedido não encontrado.');
      return;
    }
    final order = _withTipo(orderRaw, tipoForcado);

    final digits = _phoneForWhatsApp(telefone);
    if (digits.length < 12) {
      _snack(context, 'WhatsApp inválido.');
      return;
    }

    final text = (mensagem ?? mensagemPadrao(order)).trim();
    final fileName = _fileName(order);
    final file = await _writeTempPdf(order);
    if (!context.mounted) return;

    if (await _enviarWhatsAppDireto(
      context,
      phoneE164: digits,
      file: file,
      text: text,
      telefoneFmt: BrPhoneInputFormatter.format(telefone),
    )) {
      return;
    }

    // Fallback: Share sheet (iOS ou Android sem WhatsApp / MethodChannel).
    final telefoneFmt = BrPhoneInputFormatter.format(telefone);
    await Clipboard.setData(ClipboardData(text: _digitsPhone(telefoneFmt)));
    if (!context.mounted) return;
    _snack(
      context,
      'Número $telefoneFmt copiado. Escolha WhatsApp e envie o PDF ao contato.',
    );

    await _sharePdfFile(
      context,
      file: file,
      fileName: fileName,
      text: text,
      subject: assuntoEmail(order),
    );
  }

  /// Android: Intent ACTION_SEND no pacote WhatsApp com extra `jid` do número.
  /// Retorna true se o envio direto foi disparado com sucesso.
  static Future<bool> _enviarWhatsAppDireto(
    BuildContext context, {
    required String phoneE164,
    required File file,
    required String text,
    required String telefoneFmt,
  }) async {
    if (!WhatsAppDirect.isAndroid) return false;
    if (!await file.exists() || await file.length() == 0) return false;
    if (!await WhatsAppDirect.isAvailable()) return false;

    final shared = await WhatsAppDirect.sharePdf(
      phoneE164: phoneE164,
      filePath: file.path,
      text: text,
    );
    if (!shared) return false;

    if (context.mounted) {
      _snack(context, 'Abrindo WhatsApp de $telefoneFmt…');
    }
    return true;
  }

  /// Abre o compartilhar com o PDF (mailto não anexa arquivo).
  static Future<void> enviarEmail(
    BuildContext context,
    String uuid, {
    required String email,
    String? mensagem,
    String? tipoForcado,
  }) async {
    final orderRaw = await _loadOrder(uuid);
    if (orderRaw == null) {
      _snack(context, 'Pedido não encontrado.');
      return;
    }
    final order = _withTipo(orderRaw, tipoForcado);

    final to = email.trim();
    if (to.isEmpty || !to.contains('@')) {
      _snack(context, 'E-mail inválido.');
      return;
    }

    final subject = assuntoEmail(order);
    final body = (mensagem ?? mensagemPadrao(order)).trim();
    final fileName = _fileName(order);
    final file = await _writeTempPdf(order);
    if (!context.mounted) return;

    await Clipboard.setData(ClipboardData(text: to));
    _snack(context, 'E-mail $to copiado. Escolha o app de e-mail e anexe o PDF.');

    await _sharePdfFile(
      context,
      file: file,
      fileName: fileName,
      text: '$body\n\nPara: $to',
      subject: subject,
    );
  }

  static Future<void> whatsapp(BuildContext context, String uuid) async {
    await compartilhar(context, uuid);
  }

  static Future<void> imprimir(
    BuildContext context,
    String uuid, {
    String? tipoForcado,
  }) async {
    final orderRaw = await _loadOrder(uuid);
    if (orderRaw == null) {
      _snack(context, 'Pedido não encontrado. Sincronize novamente.');
      return;
    }
    final order = _withTipo(orderRaw, tipoForcado);
    final doc = await PedidoPdf.build(order);
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  static void _snack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
