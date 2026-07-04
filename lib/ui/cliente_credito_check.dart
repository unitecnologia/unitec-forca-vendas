import '../db/local_db.dart';
import 'format.dart';

/// Resultado da checagem financeira do cliente antes de finalizar pedido.
class ClienteCreditoAlerta {
  const ClienteCreditoAlerta({
    required this.temBoletoAtrasado,
    required this.boletoAtrasadoSaldo,
    required this.limiteExcedido,
    required this.limiteCredito,
    required this.totalAberto,
    required this.disponivel,
    required this.totalPedido,
  });

  final bool temBoletoAtrasado;
  final double boletoAtrasadoSaldo;
  final bool limiteExcedido;
  final double limiteCredito;
  final double totalAberto;
  final double disponivel;
  final double totalPedido;

  bool get precisaConfirmacao => temBoletoAtrasado || limiteExcedido;

  String get titulo => 'CLIENTE COM PENDÊNCIAS FINANCEIRAS';

  String get detalhe {
    final linhas = <String>[];
    if (temBoletoAtrasado) {
      linhas.add('Boletos vencidos: ${brMoney(boletoAtrasadoSaldo)}');
    }
    if (limiteCredito > 0) {
      linhas.add(
        'Limite: ${brMoney(limiteCredito)} | Em aberto: ${brMoney(totalAberto)}',
      );
      linhas.add(
        'Disponível: ${brMoney(disponivel)} | Pedido: ${brMoney(totalPedido)}',
      );
    }
    return linhas.join('\n');
  }

  static const hint =
      'Confirme se deseja liberar a venda. Este aviso permanece até você escolher Sim ou Não.';
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

    final atrasoRows = await _db.query(
      "SELECT COALESCE(SUM(saldo), 0) AS total FROM financeiro "
      "WHERE cliente_id = ? AND saldo > 0 AND vencimento < ? AND LOWER(COALESCE(forma, '')) = 'boleto'",
      [clienteId, hojeStr],
    );
    final boletoAtrasado =
        (atrasoRows.first['total'] as num?)?.toDouble() ?? 0;
    final temBoletoAtrasado = boletoAtrasado > 0;

    final limiteExcedido =
        limite > 0 && (totalAberto + totalPedido) > limite + 0.009;
    final disponivel = limite > 0 ? (limite - totalAberto).clamp(0.0, double.infinity) : 0.0;

    final alerta = ClienteCreditoAlerta(
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
