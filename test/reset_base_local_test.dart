import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_forca_vendas/config.dart';

void main() {
  test('reset da base preserva só dados técnicos do aparelho', () {
    final config = AppConfig(
      baseUrl: 'http://192.168.0.10:8765',
      lastBaseUrl: 'http://192.168.0.10:8765',
      deviceUuid: 'device-uuid',
      deviceName: 'Samsung A15',
      pairingCode: '123456',
      deviceApproved: true,
      empresaId: 1,
      empresaNome: 'EMPRESA',
      token: 'token',
      userId: 7,
      userName: 'VENDEDOR A',
      vendedorId: 3,
      vendedorNome: 'A',
      caixaId: 2,
      caixaNome: 'CAIXA',
      pixApiHabilitada: true,
      verTodosClientes: true,
      impValorLiquido: true,
      impSemColunaDesconto: false,
      estoqueNome: 'LOJA',
      tabelaVendaId: 9,
      tabelaVendaCodigo: 'T1',
      tabelaVendaDescricao: 'TABELA',
      lastSyncIso: '2026-10-04T10:00:00Z',
      rememberUser: true,
      biometricEnabled: true,
      cachedToken: 'token',
      cachedEmpresasJson: '[{"id":1}]',
      cachedUsuariosJson: '{"1":[{"id":7}]}',
      resetEmAndamentoUuid: 'reset-1',
    );

    config.limparParaBaseLimpa();

    expect(config.baseUrl, 'http://192.168.0.10:8765');
    expect(config.lastBaseUrl, 'http://192.168.0.10:8765');
    expect(config.deviceUuid, 'device-uuid');
    expect(config.deviceName, 'Samsung A15');
    expect(config.pairingCode, '123456');
    expect(config.deviceApproved, isTrue);
    expect(config.resetEmAndamentoUuid, 'reset-1');

    expect(config.isLoggedIn, isFalse);
    expect(config.token, isEmpty);
    expect(config.cachedToken, isEmpty);
    expect(config.empresaId, isNull);
    expect(config.empresaNome, isEmpty);
    expect(config.userId, isNull);
    expect(config.userName, isEmpty);
    expect(config.vendedorId, isNull);
    expect(config.vendedorNome, isEmpty);
    expect(config.caixaId, isNull);
    expect(config.caixaNome, isEmpty);
    expect(config.pixApiHabilitada, isFalse);
    expect(config.verTodosClientes, isFalse);
    expect(config.impValorLiquido, isFalse);
    expect(config.impSemColunaDesconto, isTrue);
    expect(config.estoqueNome, isEmpty);
    expect(config.tabelaVendaId, isNull);
    expect(config.tabelaVendaCodigo, isEmpty);
    expect(config.tabelaVendaDescricao, isEmpty);
    expect(config.lastSyncIso, isNull);
    expect(config.rememberUser, isFalse);
    expect(config.biometricEnabled, isFalse);
    expect(config.cachedEmpresasJson, '[]');
    expect(config.cachedUsuariosJson, '{}');
  });

  test('vínculo do vendedor sobrevive ao logout e só o reset limpa', () {
    final config = AppConfig(
      deviceUuid: 'device-uuid',
      token: 'token',
      userId: 7,
      vinculoUserId: 7,
      rememberUser: false,
    );

    config.clearSession();
    expect(config.isLoggedIn, isFalse);
    expect(config.userId, isNull);
    expect(config.vinculoUserId, 7);
    expect(AppConfig.fromJson(config.toJson()).vinculoUserId, 7);

    config.limparParaBaseLimpa();
    expect(config.vinculoUserId, isNull);
    expect(config.deviceUuid, 'device-uuid');
  });

  test('marcadores do reset sobrevivem a salvar/carregar', () {
    final config = AppConfig(resetEmAndamentoUuid: 'a', resetConcluidoUuid: 'b');
    final back = AppConfig.fromJson(config.toJson());
    expect(back.resetEmAndamentoUuid, 'a');
    expect(back.resetConcluidoUuid, 'b');
  });
}
