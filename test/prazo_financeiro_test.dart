import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_forca_vendas/payment/prazo_financeiro.dart';

void main() {
  group('isPrazoFinanceiroValido (espelho ERP)', () {
    test('BOLETO 7 (1,7) é válido sem modo (legado)', () {
      expect(isPrazoFinanceiroValido(1, 7), isTrue);
    });

    test('(3,30) é válido sem modo (legado)', () {
      expect(isPrazoFinanceiroValido(3, 30), isTrue);
    });

    test('default (1,30) NÃO é válido sem modo (legado)', () {
      expect(isPrazoFinanceiroValido(1, 30), isFalse);
    });

    test('max < 1 ou intervalo <= 0 inválidos', () {
      expect(isPrazoFinanceiroValido(0, 7), isFalse);
      expect(isPrazoFinanceiroValido(1, 0), isFalse);
      expect(isPrazoFinanceiroValido(-1, 10), isFalse);
    });

    test('modo financeiro aceita 1×30 intencional', () {
      expect(isPrazoFinanceiroValido(1, 30, 'financeiro'), isTrue);
      expect(isPrazoFinanceiroValido(1, 7, 'financeiro'), isTrue);
      expect(isPrazoFinanceiroValido(3, 30, 'financeiro'), isTrue);
    });

    test('modo tabela ignora max/intervalo mesmo válidos na heurística', () {
      expect(isPrazoFinanceiroValido(1, 7, 'tabela'), isFalse);
      expect(isPrazoFinanceiroValido(3, 30, 'tabela'), isFalse);
      expect(isPrazoFinanceiroValido(1, 30, 'tabela'), isFalse);
    });
  });

  group('diasDePrazoFinanceiro', () {
    test('1×7 → [7]', () {
      expect(diasDePrazoFinanceiro(1, 7), [7]);
    });

    test('3×30 → [30,60,90]', () {
      expect(diasDePrazoFinanceiro(3, 30), [30, 60, 90]);
    });

    test('emissão 28/09/2026 + BOLETO 7 → vencimento 05/10/2026', () {
      final dias = diasDePrazoFinanceiro(1, 7);
      final emissao = DateTime(2026, 9, 28);
      final venc = emissao.add(Duration(days: dias.first));
      expect(venc, DateTime(2026, 10, 5));
    });
  });

  group('diasPrazoFinanceiroDaForma', () {
    test('retorna null para default 1×30 sem modo', () {
      expect(
        diasPrazoFinanceiroDaForma({'max_parcelas': 1, 'intervalo_parcelas': 30}),
        isNull,
      );
    });

    test('retorna dias para BOLETO 7 sem modo', () {
      expect(
        diasPrazoFinanceiroDaForma({'max_parcelas': 1, 'intervalo_parcelas': 7}),
        [7],
      );
    });

    test('modo tabela com 1×7 → null (fluxo Tabela/Avulso)', () {
      expect(
        diasPrazoFinanceiroDaForma({
          'max_parcelas': 1,
          'intervalo_parcelas': 7,
          'modo_prazo': 'tabela',
        }),
        isNull,
      );
    });

    test('modo financeiro com 1×30 → [30]', () {
      expect(
        diasPrazoFinanceiroDaForma({
          'max_parcelas': 1,
          'intervalo_parcelas': 30,
          'modo_prazo': 'financeiro',
        }),
        [30],
      );
    });
  });

  group('podeEscolherTabelaPrazo', () {
    test('financeiro não é escolha', () {
      expect(
        podeEscolherTabelaPrazo(modoPrazo: 'financeiro', clienteTemTabelaFixa: false),
        isFalse,
      );
    });

    test('tabela sem cliente fixo é escolha', () {
      expect(
        podeEscolherTabelaPrazo(modoPrazo: 'tabela', clienteTemTabelaFixa: false),
        isTrue,
      );
    });

    test('cliente com tabela fixa não é escolha', () {
      expect(
        podeEscolherTabelaPrazo(modoPrazo: 'tabela', clienteTemTabelaFixa: true),
        isFalse,
      );
    });
  });
}
