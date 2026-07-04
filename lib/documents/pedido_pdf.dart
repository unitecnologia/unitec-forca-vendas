import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart';
import '../ui/format.dart';

/// Gera PDF de pedido/orçamento a partir dos dados locais (outbox).
class PedidoPdf {
  static Future<pw.Document> build(Map<String, dynamic> order) async {
    final doc = pw.Document();
    final extra = _parseMap(order['extra_json'] as String?);
    final itens = _parseItens(order['itens_json'] as String?);
    final tipo = (order['tipo'] ?? 'pedido').toString();
    final titulo = tipo == 'orcamento' ? 'ORÇAMENTO' : 'PEDIDO';
    final numeroDav = (order['numero'] ?? '').toString();
    final numeroPedido = (order['numero_pedido'] ?? '').toString();
    final createdAt = DateTime.tryParse((order['created_at'] ?? '').toString());
    final dataStr = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toLocal())
        : '—';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(kAppName, style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Text(titulo, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (numeroDav.isNotEmpty)
                    pw.Text('Nº DAV: $numeroDav', style: const pw.TextStyle(fontSize: 12)),
                  if (numeroPedido.isNotEmpty)
                    pw.Text('Nº Pedido ERP: $numeroPedido',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Data: $dataStr', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text((order['nome_razao'] ?? 'Cliente').toString(),
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                if ((order['cpf_cnpj'] ?? '').toString().isNotEmpty)
                  pw.Text('Doc: ${order['cpf_cnpj']}', style: const pw.TextStyle(fontSize: 10)),
                pw.Text(_enderecoCliente(order), style: const pw.TextStyle(fontSize: 10)),
                if ((order['fone1'] ?? order['celular1'] ?? order['whatsapp'] ?? '').toString().isNotEmpty)
                  pw.Text(
                    'Fone: ${order['fone1'] ?? order['celular1'] ?? order['whatsapp']}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Table.fromTextArray(
            headers: ['Item', 'Qtd', 'Unit.', 'Total'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.2),
            },
            data: itens.map((item) {
              final qtd = (item['quantidade'] as num?)?.toDouble() ?? 0;
              final unit = (item['preco_unitario'] as num?)?.toDouble() ?? 0;
              final desc = (item['desconto'] as num?)?.toDouble() ?? 0;
              final total = (qtd * unit) - desc;
              return [
                (item['descricao'] ?? 'Produto').toString(),
                qtd.toStringAsFixed(3),
                brMoney(unit),
                brMoney(total),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if ((order['desconto_valor'] as num?) != null && (order['desconto_valor'] as num) > 0)
                  pw.Text('Desconto: ${brMoney(order['desconto_valor'] as num?)}',
                      style: const pw.TextStyle(fontSize: 10)),
                pw.Text(
                  'TOTAL: ${brMoney(order['total'] as num?)}',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
          if ((extra['forma_pagamento'] ?? '').toString().isNotEmpty ||
              (extra['condicao_pagamento'] ?? '').toString().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Pagamento: ${extra['forma_pagamento'] ?? ''}  ${extra['condicao_pagamento'] ?? ''}'.trim(),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
          if ((order['observacoes'] ?? '').toString().trim().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Obs.: ${order['observacoes']}', style: const pw.TextStyle(fontSize: 10)),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} • $kAppVersionLabel',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return doc;
  }

  static String _enderecoCliente(Map<String, dynamic> order) {
    final parts = <String>[
      if ((order['endereco'] ?? '').toString().isNotEmpty) order['endereco'].toString(),
      if ((order['cliente_numero'] ?? '').toString().isNotEmpty) 'nº ${order['cliente_numero']}',
      if ((order['bairro'] ?? '').toString().isNotEmpty) order['bairro'].toString(),
      if ((order['cidade_nome'] ?? '').toString().isNotEmpty)
        '${order['cidade_nome']}/${order['uf'] ?? ''}',
      if ((order['cep'] ?? '').toString().isNotEmpty) 'CEP ${order['cep']}',
    ];
    return parts.isEmpty ? '—' : parts.join(' • ');
  }

  static Map<String, dynamic> _parseMap(String? json) {
    try {
      if (json == null || json.trim().isEmpty) return {};
      final decoded = jsonDecode(json);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  static List<Map<String, dynamic>> _parseItens(String? json) {
    try {
      if (json == null || json.trim().isEmpty) return [];
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }
}
