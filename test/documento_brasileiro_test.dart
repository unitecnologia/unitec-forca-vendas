import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_forca_vendas/ui/documento_brasileiro.dart';

void main() {
  // CPF válido conhecido (mesmos dígitos usados no ERP).
  const cpf = '52998224725';
  const cpfMask = '529.982.247-25';
  const cnpj = '11222333000181';
  const cnpjMask = '11.222.333/0001-81';

  test('digits remove máscara', () {
    expect(DocumentoBrasileiro.digits(cpfMask), cpf);
    expect(DocumentoBrasileiro.digits(cnpjMask), cnpj);
    expect(DocumentoBrasileiro.digitsOrNull(''), isNull);
    expect(DocumentoBrasileiro.digitsOrNull('   '), isNull);
  });

  test('CPF válido novo', () {
    expect(DocumentoBrasileiro.isValidCpf(cpf), isTrue);
    expect(DocumentoBrasileiro.isValidCpf(cpfMask), isTrue);
    expect(DocumentoBrasileiro.mensagemFormato(cpfMask), isNull);
  });

  test('CPF inválido', () {
    expect(DocumentoBrasileiro.mensagemFormato('111.111.111-11'), 'CPF inválido.');
    expect(DocumentoBrasileiro.mensagemFormato('123'), 'CPF inválido.');
    expect(DocumentoBrasileiro.mensagemFormato('1234567890'), 'CPF inválido.');
  });

  test('CNPJ válido novo', () {
    expect(DocumentoBrasileiro.isValidCnpj(cnpj), isTrue);
    expect(DocumentoBrasileiro.mensagemFormato(cnpjMask), isNull);
  });

  test('CNPJ inválido', () {
    expect(DocumentoBrasileiro.mensagemFormato('11.111.111/1111-11'), 'CNPJ inválido.');
    expect(DocumentoBrasileiro.mensagemFormato('12345678901234'), 'CNPJ inválido.');
  });

  test('vazio permitido', () {
    expect(DocumentoBrasileiro.mensagemFormato(null), isNull);
    expect(DocumentoBrasileiro.mensagemFormato(''), isNull);
  });

  test('mensagem duplicado', () {
    expect(
      DocumentoBrasileiro.mensagemDuplicado(cpf),
      'Já existe um cliente cadastrado com este CPF.',
    );
    expect(
      DocumentoBrasileiro.mensagemDuplicadoComNome(cnpj, 'ACME LTDA'),
      'Já existe um cliente cadastrado com este CNPJ. (ACME LTDA)',
    );
  });
}
