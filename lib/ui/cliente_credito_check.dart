import '../db/local_db.dart';
import 'format.dart';

/// Resultado da checagem financeira do cliente antes de finalizar pedido.
class ClienteCreditoAlerta {
  const ClienteCreditoAlerta({
    required this.temTitulosVencidos,
    required this.titulosVencidosSaldo,
    required this.temBoletoAtrasado,
    required this.boletoAtrasadoSaldo,
    required this.limiteExcedido,
    required this.limiteCredito,
    required this.totalAberto,
    required this.disponivel,
    required this.totalPedido,
  });

  /// Qualquer título em aberto com vencimento passado (boleto, carteira, etc.).
  final bool temTitulosVencidos;
  final double titulosVencidosSaldo;

  final bool temBoletoAtrasado;
  final double boletoAtrasadoSaldo;
  final bool limiteExcedido;
  final double limiteCredito;
  final double totalAberto;
  final double disponivel;
  final double totalPedido;

  bool get clienteEmDebito => totalAberto > 0.009;

  bool get precisaConfirmacao => temTitulosVencidos || limiteExcedido;

  double get abertoAposPedido => totalAberto + totalPedido;

  double get disponivelAposPedido {
    if (limiteCredito <= 0) return 0;
    return (limiteCredito - abertoAposPedido).clamp(0.0, double.infinity);
  }

  String get titulo => 'Pendências financeiras';

  List<String> get motivos {
    final list = <String>[];
    if (temTitulosVencidos) {
      list.add('Títulos vencidos: ${brMoney(titulosVencidosSaldo)}');
    }
    if (temBoletoAtrasado) {
      list.add('Boletos vencidos: ${brMoney(boletoAtrasadoSaldo)}');
    }
    if (limiteExcedido) {
      list.add('Limite insuficiente / excedido');
    }
    if (clienteEmDebito && !temTitulosVencidos) {
      list.add('Cliente com débitos em aberto');
    }
    return list;
  }

  /// Pares label/valor para a grade de situação.
  List<({String label, String valor})> get situacao {
    return [
      (label: 'Em aberto', valor: brMoney(totalAberto)),
      if (temTitulosVencidos)
        (label: 'Vencidos', valor: brMoney(titulosVencidosSaldo)),
      (
        label: 'Limite',
        valor: limiteCredito > 0 ? brMoney(limiteCredito) : 'não cadastrado',
      ),
      if (limiteCredito > 0) (label: 'Disponível', valor: brMoney(disponivel)),
      (label: 'Pedido', valor: brMoney(totalPedido)),
      (label: 'Aberto após pedido', valor: brMoney(abertoAposPedido)),
      if (limiteCredito > 0)
        (label: 'Disponível após', valor: brMoney(disponivelAposPedido)),
    ];
  }

  /// Texto compacto (payload ERP / fallback).
  String get detalhe {
    return [
      if (motivos.isNotEmpty) ...[
        'MOTIVOS:',
        ...motivos.map((m) => '• $m'),
      ],
      'SITUAÇÃO:',
      ...situacao.map((r) => '${r.label}: ${r.valor}'),
    ].join('\n');
  }

  /// Snapshot enviado ao ERP para a tela de liberação financeira.
  Map<String, dynamic> toPayload() => {
        'restricao_financeira': true,
        'credito_titulos_vencidos': temTitulosVencidos,
        'credito_titulos_vencidos_saldo': titulosVencidosSaldo,
        'credito_boleto_atrasado': temBoletoAtrasado,
        'credito_boleto_saldo': boletoAtrasadoSaldo,
        'credito_limite_excedido': limiteExcedido,
        'credito_limite': limiteCredito,
        'credito_total_aberto': totalAberto,
        'credito_disponivel': disponivel,
        'credito_total_pedido': totalPedido,
        'credito_aberto_apos_pedido': abertoAposPedido,
        'credito_disponivel_apos_pedido': disponivelAposPedido,
        'credito_cliente_em_debito': clienteEmDebito,
        'credito_motivo': detalhe,
      };

  static const hint =
      'O pedido irá para liberação financeira no ERP. Confirme para enviar ou Não para cancelar.';
}

/// Consulta SQLite local (dados da última sincronização).
class ClienteCreditoCheck {
  ClienteCreditoCheck._();

  static final _db = LocalDb.instance;

  static Future<ClienteCreditoAlerta?> verificar({
    required int clienteId,
    required double totalPedido,
  }) async {
    final hoje = DateTime.now();
    final hojeStr =
        '${hoje.year.toString().padLeft(4, '0')}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';

    final clienteRows = await _db.query(
      'SELECT limite_credito FROM customers WHERE id = ? LIMIT 1',
      [clienteId],
    );
    final limite = (clienteRows.isNotEmpty
            ? (clienteRows.first['limite_credito'] as num?)?.toDouble()
            : null) ??
        0;

    final abertoRows = await _db.query(
      'SELECT COALESCE(SUM(saldo), 0) AS total FROM financeiro WHERE cliente_id = ? AND saldo > 0',
      [clienteId],
    );
    final totalAberto =
        (abertoRows.first['total'] as num?)?.toDouble() ?? 0;

    // Todos os títulos vencidos (qualquer forma de pagamento).
    final vencidosRows = await _db.query(
      'SELECT COALESCE(SUM(saldo), 0) AS total FROM financeiro '
      'WHERE cliente_id = ? AND saldo > 0 AND vencimento < ?',
      [clienteId, hojeStr],
    );
    final titulosVencidos =
        (vencidosRows.first['total'] as num?)?.toDouble() ?? 0;
    final temTitulosVencidos = titulosVencidos > 0.009;

    final atrasoBoletoRows = await _db.query(
      "SELECT COALESCE(SUM(saldo), 0) AS total FROM financeiro "
      "WHERE cliente_id = ? AND saldo > 0 AND vencimento < ? "
      "AND LOWER(COALESCE(forma, '')) = 'boleto'",
      [clienteId, hojeStr],
    );
    final boletoAtrasado =
        (atrasoBoletoRows.first['total'] as num?)?.toDouble() ?? 0;
    final temBoletoAtrasado = boletoAtrasado > 0.009;

    final limiteExcedido =
        limite > 0 && (totalAberto + totalPedido) > limite + 0.009;
    final disponivel =
        limite > 0 ? (limite - totalAberto).clamp(0.0, double.infinity) : 0.0;

    final alerta = ClienteCreditoAlerta(
      temTitulosVencidos: temTitulosVencidos,
      titulosVencidosSaldo: titulosVencidos,
      temBoletoAtrasado: temBoletoAtrasado,
      boletoAtrasadoSaldo: boletoAtrasado,
      limiteExcedido: limiteExcedido,
      limiteCredito: limite,
      totalAberto: totalAberto,
      disponivel: disponivel,
      totalPedido: totalPedido,
    );

    return alerta.precisaConfirmacao ? alerta : null;
  }
}
