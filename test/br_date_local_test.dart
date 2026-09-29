import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_forca_vendas/ui/format.dart';

void main() {
  group('brDate (data civil — sem toLocal)', () {
    test('YYYY-MM-DD permanece no mesmo dia', () {
      expect(brDate('2026-09-28'), '28/09/2026');
    });

    test('null/vazio → —', () {
      expect(brDate(null), '—');
      expect(brDate(''), '—');
    });

    test('inválido devolve a string original', () {
      expect(brDate('nao-e-data'), 'nao-e-data');
    });

    test('UTC Z NÃO converte (comportamento civil preservado)', () {
      // Componentes UTC: 29/09 — brDate não deve virar 28/09.
      expect(brDate('2026-09-29T02:30:00Z'), '29/09/2026');
    });
  });

  group('brDateLocal (instante → fuso local)', () {
    test('null/vazio → —', () {
      expect(brDateLocal(null), '—');
      expect(brDateLocal(''), '—');
    });

    test('inválido devolve a string original', () {
      expect(brDateLocal('xyz'), 'xyz');
    });

    test('ISO UTC Z usa horário local', () {
      const iso = '2026-09-29T02:30:00Z';
      final local = DateTime.parse(iso).toLocal();
      final expected =
          '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
      expect(brDateLocal(iso), expected);

      // No fuso America/Sao_Paulo (UTC-3) o exemplo obrigatório vale:
      // 02:30Z → 28/09 23:30 local → data 28/09/2026.
      final offset = local.timeZoneOffset;
      if (offset == const Duration(hours: -3)) {
        expect(brDateLocal(iso), '28/09/2026');
        expect(local.hour, 23);
        expect(local.minute, 30);
      }
    });

    test('ISO com -03:00', () {
      const iso = '2026-09-28T23:30:00-03:00';
      final local = DateTime.parse(iso).toLocal();
      final expected =
          '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
      expect(brDateLocal(iso), expected);
      if (local.timeZoneOffset == const Duration(hours: -3)) {
        expect(brDateLocal(iso), '28/09/2026');
      }
    });

    test('data local/sem timezone que já funcionava', () {
      expect(brDateLocal('2026-09-28'), '28/09/2026');
      expect(brDateLocal('2026-09-28T10:15:00'), '28/09/2026');
    });
  });
}
