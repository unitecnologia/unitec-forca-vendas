import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config.dart';
import '../db/local_db.dart';

/// PDF do pedido no mesmo formato da impressão de Pedidos do ERP.
class PedidoPdf {
  static Future<pw.Document> build(Map<String, dynamic> order) async {
    final config = await AppConfig.load();
    final extra = _parseMap(order['extra_json'] as String?);
    final itens = _parseItens(order['itens_json'] as String?);
    final produtos = await _produtosPorId(itens);
    final linhas = _linhas(
      itens,
      produtos,
      valorLiquido: config.impValorLiquido,
    );
    final semColunaDesconto = config.impSemColunaDesconto;
    final createdAt = DateTime.tryParse((order['created_at'] ?? '').toString());
    final dataPedido = createdAt != null
        ? DateFormat('dd/MM/yyyy').format(createdAt.toLocal())
        : '';
    final numeroFonte = (order['numero_pedido'] ?? '').toString().trim().isNotEmpty
        ? (order['numero_pedido'] ?? '').toString()
        : (order['numero'] ?? '').toString();
    final pedidoLabel = '${_formatNumero(numeroFonte)}${dataPedido.isEmpty ? '' : ' - $dataPedido'}';

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(22, 18, 22, 18),
        build: (context) => [
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              _statusLabel(order).toUpperCase(),
              style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          _meta(order, extra, pedidoLabel, config.vendedorNome),
          pw.SizedBox(height: 8),
          _tabela(linhas, semColunaDesconto: semColunaDesconto),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              'RECLAMAÇÕES REFERENTES AOS ITENS DESSE PEDIDO SOMENTE NO ATO DA ENTREGA (FAVOR CONFERIR ITEM A ITEM)',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'IMPRESSO POR ${_impressoPor(config)} — ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 7),
              ),
              pw.Text(
                'Desenvolvido Por Unitecnologia Sistemas LTDA',
                style: const pw.TextStyle(fontSize: 7),
              ),
            ],
          ),
        ],
      ),
    );

    return doc;
  }

  static pw.Widget _meta(
    Map<String, dynamic> order,
    Map<String, dynamic> extra,
    String pedidoLabel,
    String repres,
  ) {
    final endereco = [
      (order['endereco'] ?? '').toString().trim(),
      (order['cliente_numero'] ?? '').toString().trim(),
    ].where((p) => p.isNotEmpty).join(', ');
    final fone = (order['fone1'] ?? order['celular1'] ?? order['whatsapp'] ?? '').toString();
    final pedidoSep = pedidoLabel.indexOf(' - ');
    final pedidoNum = pedidoSep >= 0 ? pedidoLabel.substring(0, pedidoSep) : pedidoLabel;
    final pedidoResto = pedidoSep >= 0 ? pedidoLabel.substring(pedidoSep) : '';

    pw.Widget linha(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 9),
              children: [
                pw.TextSpan(
                  text: '$label ',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                ),
                pw.TextSpan(text: value),
              ],
            ),
          ),
        );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              linha('Cliente:', (order['nome_razao'] ?? 'CONSUMIDOR').toString()),
              linha('Fantasia:', (order['apelido_fantasia'] ?? '').toString()),
              linha('Endereço:', endereco),
              linha('Município:', (order['cidade_nome'] ?? '').toString()),
              linha('Repres:', repres.trim()),
              linha('Obs:', (order['cliente_observacoes'] ?? '').toString()),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.RichText(
                  text: pw.TextSpan(
                    style: const pw.TextStyle(fontSize: 9),
                    children: [
                      pw.TextSpan(
                        text: 'CNPJ: ',
                        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                      pw.TextSpan(text: '${order['cpf_cnpj'] ?? ''}   '),
                      pw.TextSpan(
                        text: 'IE: ',
                        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                      pw.TextSpan(text: (order['rg_ie'] ?? '').toString()),
                    ],
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.RichText(
                  text: pw.TextSpan(
                    style: const pw.TextStyle(fontSize: 9),
                    children: [
                      pw.TextSpan(
                        text: 'Pedido: ',
                        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                      pw.TextSpan(
                        text: pedidoNum,
                        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                      pw.TextSpan(text: pedidoResto),
                    ],
                  ),
                ),
              ),
              linha('Cond. Pagamento:', _condicaoPagamento(extra, createdAt: order['created_at'])),
              linha('Bairro:', (order['bairro'] ?? '').toString()),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.RichText(
                  text: pw.TextSpan(
                    style: const pw.TextStyle(fontSize: 9),
                    children: [
                      pw.TextSpan(
                        text: 'CEP: ',
                        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                      pw.TextSpan(text: '${order['cep'] ?? ''}    '),
                      pw.TextSpan(
                        text: 'UF: ',
                        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                      pw.TextSpan(text: (order['uf'] ?? '').toString()),
                    ],
                  ),
                ),
              ),
              linha('Fone:', fone),
              linha('Obs Pedido:', (order['observacoes'] ?? '').toString()),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _tabela(List<_Linha> linhas, {required bool semColunaDesconto}) {
    final headers = <String>[
      'Código',
      'Produto',
      'UN',
      'Qtd',
      'Val. Unitário',
      if (!semColunaDesconto) 'Desconto',
      'Subtotal',
    ];
    final aligns = <pw.Alignment>[
      pw.Alignment.centerLeft,
      pw.Alignment.centerLeft,
      pw.Alignment.center,
      pw.Alignment.centerRight,
      pw.Alignment.centerRight,
      if (!semColunaDesconto) pw.Alignment.centerRight,
      pw.Alignment.centerRight,
    ];
    final widths = semColunaDesconto
        ? <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(10),
            1: const pw.FlexColumnWidth(44),
            2: const pw.FlexColumnWidth(7),
            3: const pw.FlexColumnWidth(11),
            4: const pw.FlexColumnWidth(13),
            5: const pw.FlexColumnWidth(15),
          }
        : <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(10),
            1: const pw.FlexColumnWidth(36),
            2: const pw.FlexColumnWidth(7),
            3: const pw.FlexColumnWidth(11),
            4: const pw.FlexColumnWidth(11),
            5: const pw.FlexColumnWidth(11),
            6: const pw.FlexColumnWidth(14),
          };

    List<String> cells(_Linha linha) => [
          linha.codigo,
          linha.produto.toUpperCase(),
          linha.unidade,
          _formatQuantidade(linha.quantidade),
          _formatMoney(linha.valorUnitario),
          if (!semColunaDesconto) _formatMoney(linha.desconto),
          _formatMoney(linha.subtotal),
        ];

    final qtdTotal = linhas.fold<double>(0, (s, l) => s + l.quantidade);
    final descTotal = linhas.fold<double>(0, (s, l) => s + l.desconto);
    final valorTotal = linhas.fold<double>(0, (s, l) => s + l.subtotal);
    final totais = <String>[
      '',
      'Totais:',
      '',
      _formatQuantidade(qtdTotal),
      '',
      if (!semColunaDesconto) _formatMoney(descTotal),
      _formatMoney(valorTotal),
    ];

    final rows = linhas.isEmpty
        ? <List<String>>[
            [
              'Nenhum item.',
              ...List.filled(headers.length - 1, ''),
            ],
          ]
        : linhas.map(cells).toList();

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.4),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            for (var i = 0; i < headers.length; i++)
              _celula(headers[i], align: aligns[i], bold: true),
          ],
        ),
        for (final row in rows)
          pw.TableRow(
            children: [
              for (var i = 0; i < row.length; i++) _celula(row[i], align: aligns[i]),
            ],
          ),
        if (linhas.isNotEmpty)
          pw.TableRow(
            children: [
              for (var i = 0; i < totais.length; i++)
                _celula(totais[i], align: aligns[i], bold: i == 1 || i >= 3),
            ],
          ),
      ],
    );
  }

  static pw.Widget _celula(String text, {required pw.Alignment align, bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  static List<_Linha> _linhas(
    List<Map<String, dynamic>> itens,
    Map<int, _Produto> produtos, {
    required bool valorLiquido,
  }) {
    final linhas = itens.map((item) {
      final qtd = (item['quantidade'] as num?)?.toDouble() ?? 0;
      final preco = (item['preco_unitario'] as num?)?.toDouble() ??
          (item['valor_item'] as num?)?.toDouble() ??
          0;
      final descontoGravado = (item['desconto'] as num?)?.toDouble() ?? 0;
      final totalInformado = item['total'];
      final subtotal = totalInformado is num && totalInformado != 0
          ? totalInformado.toDouble()
          : _round2((qtd * preco) - descontoGravado);
      var unitario = preco;
      var desconto = descontoGravado;
      if (valorLiquido) {
        unitario = qtd > 0 ? _round2(subtotal / qtd) : 0;
        desconto = 0;
      }
      final productId = (item['product_id'] as num?)?.toInt();
      final produto = produtos[productId];
      final codigo = (produto?.codigo ?? '').trim();
      final unidade = (produto?.unidade ?? '').trim();
      return _Linha(
        codigo: codigo.isEmpty ? '—' : codigo,
        produto: (item['descricao'] ?? 'PRODUTO').toString(),
        unidade: unidade.isEmpty ? 'UN' : unidade,
        quantidade: qtd,
        valorUnitario: unitario,
        desconto: desconto,
        subtotal: subtotal,
      );
    }).toList();

    linhas.sort((a, b) => a.produto.toLowerCase().compareTo(b.produto.toLowerCase()));
    return linhas;
  }

  static Future<Map<int, _Produto>> _produtosPorId(List<Map<String, dynamic>> itens) async {
    final ids = itens
        .map((item) => (item['product_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();
    if (ids.isEmpty) return {};

    final marks = List.filled(ids.length, '?').join(',');
    final rows = await LocalDb.instance.query(
      'SELECT id, codigo, unidade FROM products WHERE id IN ($marks)',
      ids,
    );
    final map = <int, _Produto>{};
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      map[id] = _Produto(
        codigo: (row['codigo'] ?? '').toString(),
        unidade: (row['unidade'] ?? '').toString(),
      );
    }
    return map;
  }

  static String _condicaoPagamento(Map<String, dynamic> extra, {Object? createdAt}) {
    final forma = (extra['forma_pagamento'] ?? '').toString().trim();
    final dias = _parcelasDias(extra);
    if (dias.isEmpty) return forma;

    final parsed = DateTime.tryParse((createdAt ?? '').toString());
    final base = parsed != null
        ? DateTime(parsed.toLocal().year, parsed.toLocal().month, parsed.toLocal().day)
        : DateTime.now();
    final trechos = dias.map((dia) {
      final venc = base.add(Duration(days: dia));
      final data = DateFormat('dd/MM/yyyy').format(venc);
      return dia == 0 ? 'à vista $data' : '$dia dias $data';
    }).toList();
    final detalhe = trechos.join(' · ');
    if (forma.isEmpty) {
      return trechos.length > 1 ? '${trechos.length}x — $detalhe' : detalhe;
    }
    if (trechos.length > 1) {
      return '${forma.toUpperCase()} ${trechos.length}x — $detalhe';
    }
    return '${forma.toUpperCase()} $detalhe';
  }

  static List<int> _parcelasDias(Map<String, dynamic> extra) {
    final canhoto = extra['cartao_canhoto'];
    if (canhoto is Map && canhoto['dias'] is List) {
      final dias = _ints(canhoto['dias'] as List);
      if (dias.isNotEmpty) return dias;
    }

    final avulso = _diasDeString((extra['condicao_pagamento'] ?? '').toString());
    if (avulso.isNotEmpty) return avulso;

    final prazo = extra['tabela_prazo_dias'];
    if (prazo is List) return _ints(prazo);
    return _diasDeString((prazo ?? '').toString());
  }

  static List<int> _ints(List raw) {
    return raw
        .map((d) => int.tryParse('$d') ?? -1)
        .where((d) => d >= 0)
        .toList();
  }

  static List<int> _diasDeString(String raw) {
    return raw
        .split(',')
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty)
        .map((d) => int.tryParse(d))
        .whereType<int>()
        .where((d) => d >= 0)
        .toList();
  }

  static String _statusLabel(Map<String, dynamic> order) {
    if ((order['tipo'] ?? '').toString() == 'orcamento') return 'Orçamento';
    const labels = {
      'pendente': 'Pendente',
      'financeiro': 'Financeiro',
      'confirmado': 'Confirmado',
      'faturado': 'Faturado',
      'cancelado': 'Cancelado',
    };
    final situacao = (order['situacao'] ?? '').toString();
    if (labels.containsKey(situacao)) return labels[situacao]!;
    if ((order['status'] ?? '').toString() == 'financeiro') return 'Financeiro';
    return 'Pendente';
  }

  static String _impressoPor(AppConfig config) {
    final nome = config.userName.trim().isNotEmpty ? config.userName.trim() : config.vendedorNome.trim();
    return nome.isEmpty ? '—' : nome.toUpperCase();
  }

  static String _formatNumero(String? numero) {
    final raw = (numero ?? '').trim();
    if (raw.isEmpty) return '0';
    final trimmed = raw.replaceFirst(RegExp(r'^0+'), '');
    return trimmed.isEmpty ? '0' : trimmed;
  }

  static String _formatMoney(double value) => _numero(value, 2);

  static String _formatQuantidade(double value) {
    if (value == value.truncateToDouble()) return _numero(value, 2);
    var text = _numero(value, 3);
    if (text.contains(',')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      if (text.endsWith(',')) text = text.substring(0, text.length - 1);
    }
    return text;
  }

  static String _numero(double value, int decimals) {
    final neg = value < 0;
    final fixed = value.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      final restante = intPart.length - i;
      if (i > 0 && restante % 3 == 0) buf.write('.');
      buf.write(intPart[i]);
    }
    final dec = parts.length > 1 ? parts[1] : '';
    return '${neg ? '-' : ''}$buf${dec.isEmpty ? '' : ',$dec'}';
  }

  static double _round2(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    final epsilon = value >= 0 ? 1e-8 : -1e-8;
    return ((value * 100) + epsilon).roundToDouble() / 100;
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

class _Linha {
  const _Linha({
    required this.codigo,
    required this.produto,
    required this.unidade,
    required this.quantidade,
    required this.valorUnitario,
    required this.desconto,
    required this.subtotal,
  });

  final String codigo;
  final String produto;
  final String unidade;
  final double quantidade;
  final double valorUnitario;
  final double desconto;
  final double subtotal;
}

class _Produto {
  const _Produto({required this.codigo, required this.unidade});

  final String codigo;
  final String unidade;
}
