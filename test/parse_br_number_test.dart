import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_forca_vendas/ui/format.dart';

void main() {
  test('parseBrNumber aceita ponto e vírgula como decimal', () {
    expect(parseBrNumber('4.00'), 4.0);
    expect(parseBrNumber('4,00'), 4.0);
    expect(parseBrNumber('14.25'), 14.25);
    expect(parseBrNumber('14,25'), 14.25);
    expect(parseBrNumber('1.234,56'), 1234.56);
    expect(parseBrNumber('1,234.56'), 1234.56);
    expect(parseBrNumber('28.07'), closeTo(28.07, 0.0001));
    expect(parseBrNumber('0.50'), 0.5);
    expect(parseBrNumber('400'), 400.0);
  });

  test('desconto 4.00 em 14.25 vira ~28.07%', () {
    final valor = parseBrNumber('4.00');
    final pct = valor / 14.25 * 100;
    expect(pct, closeTo(28.07, 0.01));
    expect(pct, lessThan(100));
  });
}
