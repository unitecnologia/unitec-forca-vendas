import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'pricing/item_desconto.dart';

/// Configuração de conexão + autorização do aparelho + sessão, persistida.
class AppConfig {
  AppConfig({
    this.baseUrl = '',
    this.lastBaseUrl = '',
    this.deviceUuid = '',
    this.deviceName = '',
    this.pairingCode = '',
    this.deviceApproved = false,
    this.empresaId,
    this.empresaNome = '',
    this.token = '',
    this.userId,
    this.userName = '',
    this.vendedorId,
    this.vendedorNome = '',
    this.caixaId,
    this.caixaNome = '',
    this.pixApiHabilitada = false,
    this.verTodosClientes = false,
    this.descontoReaisItemModo = descontoReaisModoUnitario,
    this.impValorLiquido = false,
    this.impSemColunaDesconto = true,
    this.estoqueNome = '',
    this.tabelaVendaId,
    this.tabelaVendaCodigo = '',
    this.tabelaVendaDescricao = '',
    this.lastSyncIso,
    this.rememberUser = false,
    this.biometricEnabled = false,
    this.cachedToken = '',
    this.cachedEmpresasJson = '[]',
    this.cachedUsuariosJson = '{}',
    this.resetEmAndamentoUuid = '',
    this.resetConcluidoUuid = '',
    this.vinculoUserId,
  });

  String baseUrl;

  /// Último endereço que conectou com sucesso (mantido mesmo após desconectar,
  /// para oferecer "Reconectar" sem digitar de novo).
  String lastBaseUrl;
  String deviceUuid;
  String deviceName;
  String pairingCode;
  bool deviceApproved;
  int? empresaId;
  String empresaNome;
  String token;
  int? userId;
  String userName;
  int? vendedorId;
  String vendedorNome;
  int? caixaId;
  String caixaNome;
  bool pixApiHabilitada;

  /// Empresa liberou base aberta no Força de Vendas (todos os clientes no app).
  bool verTodosClientes;

  /// Empresa → Monitor de vendas: unitario ou linha. Não altera o modo %.
  String descontoReaisItemModo;

  /// Empresa → Imprimir valor unitário líquido nos pedidos.
  bool impValorLiquido;

  /// Empresa → Ocultar coluna de desconto na impressão.
  bool impSemColunaDesconto;

  String estoqueNome;
  int? tabelaVendaId;
  String tabelaVendaCodigo;
  String tabelaVendaDescricao;
  String? lastSyncIso;

  /// Mantém empresa/usuário após sair (preenche o login automaticamente).
  bool rememberUser;

  /// Usa digital/biometria para entrar (exige [rememberUser] e senha guardada).
  bool biometricEnabled;

  /// Último token válido — permite reabrir sessão offline (mesmo após logout com lembrar usuário).
  String cachedToken;

  /// Cache JSON de empresas/usuários para montar o login sem servidor.
  String cachedEmpresasJson;
  String cachedUsuariosJson;

  /// Reset da base autorizado pelo ERP que começou e ainda não terminou de apagar.
  /// Enquanto preenchido, sync e login ficam bloqueados e o app tenta apagar de novo.
  String resetEmAndamentoUuid;

  /// Reset já executado localmente, aguardando confirmação no ERP.
  /// Impede apagar a base de novo para a mesma autorização.
  String resetConcluidoUuid;

  /// Usuário (vendedor) a quem o aparelho está vinculado no ERP. Só ele entra.
  /// Logout e desconectar não limpam; só o Reset da Base libera o aparelho.
  int? vinculoUserId;

  bool get isConnected => baseUrl.isNotEmpty;
  bool get isApproved => deviceApproved;
  bool get isLoggedIn => token.isNotEmpty;

  /// Base completa da API de força de vendas.
  String get apiBase => '$baseUrl/api/v1/forca-vendas';

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'lastBaseUrl': lastBaseUrl,
        'deviceUuid': deviceUuid,
        'deviceName': deviceName,
        'pairingCode': pairingCode,
        'deviceApproved': deviceApproved,
        'empresaId': empresaId,
        'empresaNome': empresaNome,
        'token': token,
        'userId': userId,
        'userName': userName,
        'vendedorId': vendedorId,
        'vendedorNome': vendedorNome,
        'caixaId': caixaId,
        'caixaNome': caixaNome,
        'pixApiHabilitada': pixApiHabilitada,
        'verTodosClientes': verTodosClientes,
        'descontoReaisItemModo': descontoReaisItemModo,
        'impValorLiquido': impValorLiquido,
        'impSemColunaDesconto': impSemColunaDesconto,
        'estoqueNome': estoqueNome,
        'tabelaVendaId': tabelaVendaId,
        'tabelaVendaCodigo': tabelaVendaCodigo,
        'tabelaVendaDescricao': tabelaVendaDescricao,
        'lastSyncIso': lastSyncIso,
        'rememberUser': rememberUser,
        'biometricEnabled': biometricEnabled,
        'cachedToken': cachedToken,
        'cachedEmpresasJson': cachedEmpresasJson,
        'cachedUsuariosJson': cachedUsuariosJson,
        'resetEmAndamentoUuid': resetEmAndamentoUuid,
        'resetConcluidoUuid': resetConcluidoUuid,
        'vinculoUserId': vinculoUserId,
      };

  static AppConfig fromJson(Map<String, dynamic> j) => AppConfig(
        baseUrl: j['baseUrl'] ?? '',
        lastBaseUrl: j['lastBaseUrl'] ?? '',
        deviceUuid: j['deviceUuid'] ?? '',
        deviceName: j['deviceName'] ?? '',
        pairingCode: j['pairingCode'] ?? '',
        deviceApproved: j['deviceApproved'] ?? false,
        empresaId: j['empresaId'],
        empresaNome: j['empresaNome'] ?? '',
        token: j['token'] ?? '',
        userId: j['userId'],
        userName: j['userName'] ?? '',
        vendedorId: j['vendedorId'],
        vendedorNome: j['vendedorNome'] ?? '',
        caixaId: j['caixaId'] is int ? j['caixaId'] as int : int.tryParse('${j['caixaId'] ?? ''}'),
        caixaNome: j['caixaNome'] ?? '',
        pixApiHabilitada: j['pixApiHabilitada'] == true,
        verTodosClientes: j['verTodosClientes'] == true,
        descontoReaisItemModo: normalizarDescontoReaisItemModo(j['descontoReaisItemModo']),
        impValorLiquido: j['impValorLiquido'] == true,
        impSemColunaDesconto: j.containsKey('impSemColunaDesconto')
            ? j['impSemColunaDesconto'] == true
            : true,
        estoqueNome: j['estoqueNome'] ?? '',
        tabelaVendaId: j['tabelaVendaId'],
        tabelaVendaCodigo: j['tabelaVendaCodigo'] ?? '',
        tabelaVendaDescricao: j['tabelaVendaDescricao'] ?? '',
        lastSyncIso: j['lastSyncIso'],
        rememberUser: j['rememberUser'] == true,
        biometricEnabled: j['biometricEnabled'] == true,
        cachedToken: j['cachedToken'] ?? '',
        cachedEmpresasJson: j['cachedEmpresasJson'] ?? '[]',
        cachedUsuariosJson: j['cachedUsuariosJson'] ?? '{}',
        resetEmAndamentoUuid: j['resetEmAndamentoUuid'] ?? '',
        resetConcluidoUuid: j['resetConcluidoUuid'] ?? '',
        vinculoUserId: j['vinculoUserId'] is int
            ? j['vinculoUserId'] as int
            : int.tryParse('${j['vinculoUserId'] ?? ''}'),
      );

  static const _key = 'unitec_fv_config';

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return AppConfig();
    }
    try {
      return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppConfig();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }

  /// Reset da base autorizado pelo ERP: volta tudo ao padrão, mantendo só o que o
  /// aparelho precisa para reconectar e continuar reconhecido (UUID, servidor,
  /// autorização técnica) e os marcadores do próprio reset.
  void limparParaBaseLimpa() {
    final limpo = AppConfig(
      baseUrl: baseUrl,
      lastBaseUrl: lastBaseUrl,
      deviceUuid: deviceUuid,
      deviceName: deviceName,
      pairingCode: pairingCode,
      deviceApproved: deviceApproved,
      resetEmAndamentoUuid: resetEmAndamentoUuid,
      resetConcluidoUuid: resetConcluidoUuid,
    );
    empresaId = limpo.empresaId;
    empresaNome = limpo.empresaNome;
    token = limpo.token;
    userId = limpo.userId;
    userName = limpo.userName;
    vendedorId = limpo.vendedorId;
    vendedorNome = limpo.vendedorNome;
    caixaId = limpo.caixaId;
    caixaNome = limpo.caixaNome;
    pixApiHabilitada = limpo.pixApiHabilitada;
    verTodosClientes = limpo.verTodosClientes;
    descontoReaisItemModo = limpo.descontoReaisItemModo;
    impValorLiquido = limpo.impValorLiquido;
    impSemColunaDesconto = limpo.impSemColunaDesconto;
    estoqueNome = limpo.estoqueNome;
    tabelaVendaId = limpo.tabelaVendaId;
    tabelaVendaCodigo = limpo.tabelaVendaCodigo;
    tabelaVendaDescricao = limpo.tabelaVendaDescricao;
    lastSyncIso = limpo.lastSyncIso;
    rememberUser = limpo.rememberUser;
    biometricEnabled = limpo.biometricEnabled;
    cachedToken = limpo.cachedToken;
    cachedEmpresasJson = limpo.cachedEmpresasJson;
    cachedUsuariosJson = limpo.cachedUsuariosJson;
    vinculoUserId = limpo.vinculoUserId;
  }

  /// Limpa apenas a sessão (mantém a conexão e a autorização do aparelho).
  /// Com [rememberUser], empresa, usuário e vínculo do vendedor ficam para login offline.
  /// [verTodosClientes] e as flags de impressão são regra da empresa — não zeram no logout.
  void clearSession() {
    token = '';
    if (!rememberUser) {
      vendedorId = null;
      vendedorNome = '';
      caixaId = null;
      caixaNome = '';
      pixApiHabilitada = false;
      estoqueNome = '';
      tabelaVendaId = null;
      tabelaVendaCodigo = '';
      tabelaVendaDescricao = '';
      empresaId = null;
      empresaNome = '';
      userId = null;
      userName = '';
      biometricEnabled = false;
      cachedToken = '';
    }
  }
}
