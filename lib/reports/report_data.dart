import '../db/local_db.dart';
import '../ui/format.dart';

/// Helpers e consultas dos relatórios offline (Fase 1).
class ReportData {
  ReportData._();

  static final _db = LocalDb.instance;

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Início da semana (segunda-feira).
  static DateTime startOfWeek(DateTime d) {
    final base = startOfDay(d);
    return base.subtract(Duration(days: base.weekday - DateTime.monday));
  }

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  /// IDs dos clientes da carteira FV do vendedor logado.
  static Future<Set<int>> carteiraClienteIds(int? vendedorId) async {
    if (vendedorId == null) return {};
    final rows = await _db.query(
      'SELECT id FROM customers WHERE vendedor_fv_id = ?',
      [vendedorId],
    );
    return rows.map((r) => (r['id'] as num).toInt()).toSet();
  }

  static Future<MinhasVendasResumo> minhasVendas() async {
    final hoje = DateTime.now();
    final inicioHoje = startOfDay(hoje);
    final inicioSemana = startOfWeek(hoje);
    final inicioMes = startOfMonth(hoje);

    final vendas = await _db.query(
      'SELECT data, total FROM historico_vendas WHERE data IS NOT NULL',
    );

    double totalHoje = 0, totalSemana = 0, totalMes = 0;
    var qtdHoje = 0, qtdSemana = 0, qtdMes = 0;

    for (final v in vendas) {
      final d = DateTime.tryParse((v['data'] ?? '').toString());
      if (d == null) continue;
      final dia = startOfDay(d);
      final total = (v['total'] as num?)?.toDouble() ?? 0;

      if (!dia.isBefore(inicioMes)) {
        totalMes += total;
        qtdMes++;
      }
      if (!dia.isBefore(inicioSemana)) {
        totalSemana += total;
        qtdSemana++;
      }
      if (!dia.isBefore(inicioHoje)) {
        totalHoje += total;
        qtdHoje++;
      }
    }

    return MinhasVendasResumo(
      totalHoje: totalHoje,
      totalSemana: totalSemana,
      totalMes: totalMes,
      qtdHoje: qtdHoje,
      qtdSemana: qtdSemana,
      qtdMes: qtdMes,
    );
  }

  static Future<List<ClienteAtendido>> clientesAtendidos(int? vendedorId) async {
    final carteira = await carteiraClienteIds(vendedorId);
    if (carteira.isEmpty) return [];

    final map = <int, ClienteAtendido>{};

    void merge(int? id, {double addTotal = 0, int addPedidos = 0, String? dataCompra}) {
      if (id == null || id <= 0 || !carteira.contains(id)) return;
      final c = map.putIfAbsent(id, () => ClienteAtendido(clienteId: id));
      c.totalComprado += addTotal;
      c.qtdPedidos += addPedidos;
      if (dataCompra != null) c._atualizarUltimaCompra(dataCompra);
    }

    final vendas = await _db.query(
      'SELECT cliente_id, data, total FROM historico_vendas WHERE cliente_id IS NOT NULL',
    );
    for (final v in vendas) {
      merge(
        (v['cliente_id'] as num?)?.toInt(),
        addTotal: (v['total'] as num?)?.toDouble() ?? 0,
        addPedidos: 1,
        dataCompra: (v['data'] ?? '').toString(),
      );
    }

    final outbox = await _db.query(
      "SELECT cliente_id, created_at, total FROM outbox_orders "
      "WHERE cliente_id IS NOT NULL AND tipo = 'pedido' AND status IN ('pendente','enviado')",
    );
    for (final o in outbox) {
      merge(
        (o['cliente_id'] as num?)?.toInt(),
        addTotal: (o['total'] as num?)?.toDouble() ?? 0,
        addPedidos: 1,
        dataCompra: (o['created_at'] ?? '').toString().substring(0, 10),
      );
    }

    final visitas = await _db.query(
      'SELECT cliente_id, created_at FROM visitas_sem_venda WHERE cliente_id IS NOT NULL',
    );
    for (final v in visitas) {
      final id = (v['cliente_id'] as num?)?.toInt();
      if (id == null || !carteira.contains(id)) continue;
      map.putIfAbsent(id, () => ClienteAtendido(clienteId: id));
      map[id]!._atualizarUltimaVisita((v['created_at'] ?? '').toString());
    }

    if (map.isEmpty) return [];

    final ids = map.keys.toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final clientes = await _db.query(
      'SELECT id, nome_razao, whatsapp, celular1, fone1 FROM customers WHERE id IN ($placeholders)',
      ids,
    );
    for (final c in clientes) {
      final id = (c['id'] as num?)?.toInt();
      if (id == null || !map.containsKey(id)) continue;
      map[id]!
        ..nome = (c['nome_razao'] ?? 'Cliente').toString()
        ..whatsapp = _telefone(c);
    }

    final hoje = startOfDay(DateTime.now());
    final hojeStr = isoDate(hoje);

    final financeiro = await _db.query(
      'SELECT cliente_id, saldo, vencimento FROM financeiro WHERE saldo > 0 AND cliente_id IN ($placeholders)',
      ids,
    );
    for (final f in financeiro) {
      final id = (f['cliente_id'] as num?)?.toInt();
      if (id == null || !map.containsKey(id)) continue;
      final saldo = (f['saldo'] as num?)?.toDouble() ?? 0;
      map[id]!.valorAberto += saldo;
      final venc = (f['vencimento'] ?? '').toString();
      if (venc.isNotEmpty && venc.compareTo(hojeStr) < 0) {
        map[id]!.temVencido = true;
      }
    }

    for (final c in map.values) {
      c.status = _statusCliente(c, hoje);
    }

    final lista = map.values.toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return lista;
  }

  static Future<List<ClienteSemCompra>> clientesSemCompra(int diasMinimo, int? vendedorId) async {
    if (vendedorId == null) return [];
    final hoje = startOfDay(DateTime.now());
    final map = <int, ClienteSemCompra>{};

    void registrar(int? id, String dataStr) {
      if (id == null || id <= 0) return;
      final d = DateTime.tryParse(dataStr.length >= 10 ? dataStr.substring(0, 10) : dataStr);
      if (d == null) return;
      final existente = map[id];
      if (existente == null || d.isAfter(existente.ultimaCompra)) {
        map[id] = ClienteSemCompra(
          clienteId: id,
          ultimaCompra: startOfDay(d),
        );
      }
    }

    final carteiraRows = await _db.query(
      'SELECT id FROM customers WHERE vendedor_fv_id = ?',
      [vendedorId],
    );
    final carteira = carteiraRows.map((r) => (r['id'] as num).toInt()).toSet();

    final vendas = await _db.query(
      'SELECT cliente_id, data FROM historico_vendas WHERE cliente_id IS NOT NULL',
    );
    for (final v in vendas) {
      final id = (v['cliente_id'] as num?)?.toInt();
      if (id == null || !carteira.contains(id)) continue;
      registrar(id, (v['data'] ?? '').toString());
    }

    final outbox = await _db.query(
      "SELECT cliente_id, created_at FROM outbox_orders "
      "WHERE cliente_id IS NOT NULL AND tipo = 'pedido' AND status IN ('pendente','enviado')",
    );
    for (final o in outbox) {
      final id = (o['cliente_id'] as num?)?.toInt();
      if (id == null || !carteira.contains(id)) continue;
      registrar(id, (o['created_at'] ?? '').toString());
    }

    if (map.isEmpty) return [];

    final filtrados = map.values.where((c) {
      final dias = hoje.difference(c.ultimaCompra).inDays;
      return dias >= diasMinimo;
    }).toList();

    if (filtrados.isEmpty) return [];

    final ids = filtrados.map((e) => e.clienteId).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final clientes = await _db.query(
      'SELECT id, nome_razao, whatsapp, celular1, fone1 FROM customers WHERE id IN ($placeholders)',
      ids,
    );
    final nomes = {for (final c in clientes) (c['id'] as num).toInt(): c};

    for (final item in filtrados) {
      final c = nomes[item.clienteId];
      item.nome = (c?['nome_razao'] ?? 'Cliente').toString();
      item.whatsapp = c != null ? _telefone(c) : '';
      item.diasSemCompra = hoje.difference(item.ultimaCompra).inDays;
    }

    filtrados.sort((a, b) => b.diasSemCompra.compareTo(a.diasSemCompra));
    return filtrados;
  }

  static Future<List<ContaAbertoCliente>> contasAbertoCarteira(int? vendedorId) async {
    final carteira = await carteiraClienteIds(vendedorId);
    if (carteira.isEmpty) return [];

    final ids = carteira.toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final hoje = startOfDay(DateTime.now());
    final hojeStr = isoDate(hoje);

    final titulos = await _db.query(
      'SELECT cliente_id, saldo, vencimento FROM financeiro '
      'WHERE saldo > 0 AND cliente_id IN ($placeholders)',
      ids,
    );

    final map = <int, ContaAbertoCliente>{};
    for (final t in titulos) {
      final id = (t['cliente_id'] as num?)?.toInt();
      if (id == null) continue;
      final c = map.putIfAbsent(id, () => ContaAbertoCliente(clienteId: id));
      final saldo = (t['saldo'] as num?)?.toDouble() ?? 0;
      final venc = (t['vencimento'] ?? '').toString();
      if (venc.isNotEmpty && venc.compareTo(hojeStr) < 0) {
        c.valorVencido += saldo;
        final dv = DateTime.tryParse(venc);
        if (dv != null) {
          final dias = hoje.difference(startOfDay(dv)).inDays;
          if (dias > c.maxDiasAtraso) c.maxDiasAtraso = dias;
        }
      } else {
        c.valorAVencer += saldo;
      }
    }

    if (map.isEmpty) return [];

    final clientes = await _db.query(
      'SELECT id, nome_razao, whatsapp, celular1, fone1 FROM customers WHERE id IN ($placeholders)',
      map.keys.toList(),
    );
    for (final c in clientes) {
      final id = (c['id'] as num?)?.toInt();
      if (id == null || !map.containsKey(id)) continue;
      map[id]!
        ..nome = (c['nome_razao'] ?? 'Cliente').toString()
        ..whatsapp = _telefone(c);
    }

    final vendas = await _db.query(
      'SELECT cliente_id, data FROM historico_vendas WHERE cliente_id IN ($placeholders)',
      map.keys.toList(),
    );
    for (final v in vendas) {
      final id = (v['cliente_id'] as num?)?.toInt();
      if (id == null || !map.containsKey(id)) continue;
      map[id]!._atualizarUltimaCompra((v['data'] ?? '').toString());
    }

    final lista = map.values.toList()
      ..sort((a, b) => b.valorVencido.compareTo(a.valorVencido));
    return lista;
  }

  static Future<List<VisitaRegistro>> visitasRealizadas(int? vendedorId) async {
    if (vendedorId == null) return [];
    final rows = await _db.query(
      'SELECT v.uuid, v.cliente_id, v.motivo, v.latitude, v.longitude, v.created_at, v.status, '
      'c.nome_razao, c.whatsapp, c.celular1, c.fone1 '
      'FROM visitas_sem_venda v '
      'INNER JOIN customers c ON c.id = v.cliente_id AND c.vendedor_fv_id = ? '
      'ORDER BY v.created_at DESC LIMIT 500',
      [vendedorId],
    );
    return rows.map(VisitaRegistro.fromRow).toList();
  }

  static String _telefone(Map<String, dynamic> c) {
    for (final k in ['whatsapp', 'celular1', 'fone1']) {
      final t = (c[k] ?? '').toString().trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  static String _statusCliente(ClienteAtendido c, DateTime hoje) {
    if (c.temVencido) return 'Inadimplente';
    if (c.ultimaCompra != null) {
      final dias = hoje.difference(c.ultimaCompra!).inDays;
      if (dias > 60) return 'Parado';
    } else if (c.qtdPedidos == 0) {
      return 'Só visita';
    }
    return 'Ativo';
  }
}

class MinhasVendasResumo {
  const MinhasVendasResumo({
    required this.totalHoje,
    required this.totalSemana,
    required this.totalMes,
    required this.qtdHoje,
    required this.qtdSemana,
    required this.qtdMes,
  });

  final double totalHoje;
  final double totalSemana;
  final double totalMes;
  final int qtdHoje;
  final int qtdSemana;
  final int qtdMes;

  double get ticketMedioMes => qtdMes > 0 ? totalMes / qtdMes : 0;
}

class ClienteAtendido {
  ClienteAtendido({required this.clienteId});

  final int clienteId;
  String nome = '';
  String whatsapp = '';
  double totalComprado = 0;
  int qtdPedidos = 0;
  DateTime? ultimaCompra;
  DateTime? ultimaVisita;
  double valorAberto = 0;
  bool temVencido = false;
  String status = 'Ativo';

  void _atualizarUltimaCompra(String dataStr) {
    final d = DateTime.tryParse(dataStr.length >= 10 ? dataStr.substring(0, 10) : dataStr);
    if (d == null) return;
    final dia = ReportData.startOfDay(d);
    if (ultimaCompra == null || dia.isAfter(ultimaCompra!)) ultimaCompra = dia;
  }

  void _atualizarUltimaVisita(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return;
    if (ultimaVisita == null || d.isAfter(ultimaVisita!)) ultimaVisita = d;
  }
}

class ClienteSemCompra {
  ClienteSemCompra({required this.clienteId, required this.ultimaCompra});

  final int clienteId;
  final DateTime ultimaCompra;
  String nome = '';
  String whatsapp = '';
  int diasSemCompra = 0;
}

class ContaAbertoCliente {
  ContaAbertoCliente({required this.clienteId});

  final int clienteId;
  String nome = '';
  String whatsapp = '';
  double valorVencido = 0;
  double valorAVencer = 0;
  int maxDiasAtraso = 0;
  DateTime? ultimaCompra;

  void _atualizarUltimaCompra(String dataStr) {
    final d = DateTime.tryParse(dataStr.length >= 10 ? dataStr.substring(0, 10) : dataStr);
    if (d == null) return;
    final dia = ReportData.startOfDay(d);
    if (ultimaCompra == null || dia.isAfter(ultimaCompra!)) ultimaCompra = dia;
  }
}

class VisitaRegistro {
  VisitaRegistro({
    required this.uuid,
    required this.clienteId,
    required this.clienteNome,
    required this.motivo,
    required this.createdAt,
    required this.status,
    this.latitude,
    this.longitude,
    this.telefone = '',
  });

  final String uuid;
  final int? clienteId;
  final String clienteNome;
  final String motivo;
  final DateTime? createdAt;
  final String status;
  final double? latitude;
  final double? longitude;
  final String telefone;

  bool get temGps => latitude != null && longitude != null;

  factory VisitaRegistro.fromRow(Map<String, dynamic> r) {
    return VisitaRegistro(
      uuid: (r['uuid'] ?? '').toString(),
      clienteId: (r['cliente_id'] as num?)?.toInt(),
      clienteNome: (r['nome_razao'] ?? 'Cliente').toString(),
      motivo: (r['motivo'] ?? '').toString(),
      createdAt: DateTime.tryParse((r['created_at'] ?? '').toString()),
      status: (r['status'] ?? '').toString(),
      latitude: (r['latitude'] as num?)?.toDouble(),
      longitude: (r['longitude'] as num?)?.toDouble(),
      telefone: ReportData._telefone(r),
    );
  }
}
