import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

/// Espelha a lógica de _salvar / outbox após a correção de duplicação:
/// UUID estável + guard _salvando antes de qualquer await.
class _SalvarGuardSim {
  bool salvando = false;
  late final String pedidoUuid = const Uuid().v4();
  final List<String> persistencias = [];

  Future<void> salvar({
    required Future<bool> Function() antesDeGravar,
  }) async {
    if (salvando) return;
    salvando = true;
    try {
      final ok = await antesDeGravar();
      if (!ok) {
        salvando = false;
        return;
      }
      // Mesmo UUID em todo retry / multi-toque que chegou a gravar.
      persistencias.add(pedidoUuid);
      salvando = false;
    } catch (_) {
      salvando = false;
      rethrow;
    }
  }
}

void main() {
  test('UUID nasce uma vez e não muda entre tentativas', () {
    final g = _SalvarGuardSim();
    final a = g.pedidoUuid;
    final b = g.pedidoUuid;
    expect(a, b);
    expect(a.isNotEmpty, isTrue);
  });

  test('Salvar 1x → 1 persistência com o UUID do rascunho', () async {
    final g = _SalvarGuardSim();
    await g.salvar(antesDeGravar: () async => true);
    expect(g.persistencias, [g.pedidoUuid]);
  });

  test('Salvar 2x rápido → 1 persistência (mesmo UUID)', () async {
    final g = _SalvarGuardSim();
    // Simula GPS lento: segunda chamada entra enquanto salvando==true.
    late final Future<void> primeiro;
    primeiro = g.salvar(antesDeGravar: () async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await g.salvar(antesDeGravar: () async => true);
    await primeiro;
    expect(g.persistencias.length, 1);
    expect(g.persistencias.single, g.pedidoUuid);
  });

  test('Salvar 5x rápido → 1 persistência (mesmo UUID)', () async {
    final g = _SalvarGuardSim();
    late final Future<void> primeiro;
    primeiro = g.salvar(antesDeGravar: () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 5));
    for (var i = 0; i < 4; i++) {
      await g.salvar(antesDeGravar: () async => true);
    }
    await primeiro;
    expect(g.persistencias.length, 1);
    expect(g.persistencias.single, g.pedidoUuid);
  });

  test('cancelamento antes de gravar libera salvando e não persiste', () async {
    final g = _SalvarGuardSim();
    await g.salvar(antesDeGravar: () async => false);
    expect(g.salvando, isFalse);
    expect(g.persistencias, isEmpty);
  });

  test('retry após cancelamento reutiliza o mesmo UUID', () async {
    final g = _SalvarGuardSim();
    final uuid = g.pedidoUuid;
    await g.salvar(antesDeGravar: () async => false);
    await g.salvar(antesDeGravar: () async => true);
    expect(g.persistencias, [uuid]);
  });
}
