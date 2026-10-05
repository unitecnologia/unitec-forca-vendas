import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'api/api_client.dart';
import 'auth/credential_store.dart';
import 'config.dart';
import 'config/erp_url.dart';
import 'db/local_db.dart';
import 'log/app_log.dart';
import 'media/produto_foto_cache.dart';
import 'pricing/item_desconto.dart';
import 'sync/sync_service.dart';

class AppState extends ChangeNotifier {
  AppState(this.config) : api = ApiClient(config) {
    sync = SyncService(config, api)
      ..bloqueada = (() => resetBloqueando)
      ..verificarReset = _verificarResetNaSync
      ..sessaoRecusada = _encerrarSessaoRecusada;
  }

  /// Restaura sessão persistida (sync periódica após reabrir o app).
  Future<void> initialize() async {
    // Sem ping: se já conectou antes, reabre o endereço para login/vendas offline.
    if (config.baseUrl.isEmpty && config.lastBaseUrl.isNotEmpty) {
      config.baseUrl = config.lastBaseUrl;
      await config.save();
      notifyListeners();
      AppLog.instance.info('conexão', 'Restaurada offline: ${config.baseUrl}');
    }
    // Reset interrompido (app fechado no meio): termina de apagar antes de tudo.
    if (config.resetEmAndamentoUuid.isNotEmpty) {
      await _executarReset(config.resetEmAndamentoUuid);
    }
    // Instalação anterior ao vínculo: o último usuário com sessão é o vendedor do
    // aparelho no ERP (o servidor confirma/corrige na lista de usuários).
    if (config.vinculoUserId == null &&
        config.userId != null &&
        config.cachedToken.isNotEmpty) {
      config.vinculoUserId = config.userId;
      await config.save();
    }
    if (config.isLoggedIn) {
      sync.start();
    } else if (config.isConnected) {
      unawaited(verificarResetPendente());
    }
  }

  // ---- Reset da base local (autorizado pelo retaguarda) --------------------

  /// UI: fecha telas/diálogos abertos antes de apagar (rascunho em memória é descartado).
  VoidCallback? onResetIniciado;

  /// UI: avisa que a base foi apagada e o app voltou ao login.
  VoidCallback? onResetConcluido;

  bool _resetExecutando = false;
  Timer? _resetRetry;

  /// Sync e login ficam parados enquanto o reset estiver executando ou incompleto.
  bool get resetBloqueando => _resetExecutando || config.resetEmAndamentoUuid.isNotEmpty;

  /// Consulta o ERP e, havendo autorização pendente, apaga a base local.
  /// Retorna true quando a base foi apagada agora.
  Future<bool> verificarResetPendente() async {
    if (config.resetEmAndamentoUuid.isNotEmpty) {
      return _executarReset(config.resetEmAndamentoUuid);
    }
    final uuid = await _consultarReset();
    if (uuid == null) return false;
    return _executarReset(uuid);
  }

  /// UUID de reset a executar, ou null (sem autorização, offline, ou já executado
  /// e só faltando confirmar no ERP).
  Future<String?> _consultarReset() async {
    if (!config.isConnected || config.deviceUuid.isEmpty) return null;
    String? uuid;
    try {
      uuid = await api.resetPendente();
    } catch (_) {
      return null;
    }
    final jaExecutado = config.resetConcluidoUuid;
    if (uuid == null) {
      if (jaExecutado.isNotEmpty) {
        config.resetConcluidoUuid = '';
        await config.save();
      }
      return null;
    }
    if (uuid == jaExecutado) {
      unawaited(_confirmarReset(uuid));
      return null;
    }
    return uuid;
  }

  Future<bool> _verificarResetNaSync() async {
    if (resetBloqueando) return true;
    final uuid = await _consultarReset();
    if (uuid == null) return false;
    // Sem await: o reset espera esta sync terminar antes de apagar.
    unawaited(_executarReset(uuid));
    return true;
  }

  Future<bool> _executarReset(String uuid) async {
    if (_resetExecutando) return false;
    _resetExecutando = true;
    _resetRetry?.cancel();
    AppLog.instance.warn('reset', 'Reset da base autorizado pelo retaguarda ($uuid)');
    try {
      if (config.resetEmAndamentoUuid != uuid) {
        config.resetEmAndamentoUuid = uuid;
        await config.save();
      }
      notifyListeners();

      sync.stop();
      api.abortarRequisicoes();
      await sync.aguardarOcioso();
      onResetIniciado?.call();

      await ProdutoFotoCache.instance.limparTudo();
      await LocalDb.instance.apagarBase();
      await _limparArquivosTemporarios();
      await CredentialStore.clearSenha();
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();

      config.limparParaBaseLimpa();
      config.resetConcluidoUuid = uuid;
      config.resetEmAndamentoUuid = '';
      await config.save();

      await AppLog.instance.clear();
      AppLog.instance.warn('reset', 'Base local apagada por autorização do retaguarda ($uuid)');
      sync.limparEstado();
      _resetExecutando = false;
      notifyListeners();
      onResetConcluido?.call();
      unawaited(_confirmarReset(uuid));
      return true;
    } catch (e) {
      AppLog.instance.error('reset', 'Falha ao apagar a base local: $e');
      _resetExecutando = false;
      notifyListeners();
      _resetRetry = Timer(const Duration(seconds: 15), () {
        unawaited(verificarResetPendente());
      });
      return false;
    }
  }

  /// Só limpa o marcador depois que o ERP aceitar; falha de rede tenta de novo na próxima consulta.
  Future<void> _confirmarReset(String uuid) async {
    try {
      await api.concluirReset(uuid);
      AppLog.instance.ok('reset', 'Reset confirmado no ERP');
    } on ApiException catch (e) {
      final code = e.statusCode;
      if (code == null || code >= 500 || isNetworkError(e)) return;
      AppLog.instance.warn('reset', 'ERP recusou a confirmação do reset: ${e.message}');
    } catch (_) {
      return;
    }
    if (config.resetConcluidoUuid == uuid) {
      config.resetConcluidoUuid = '';
      await config.save();
    }
  }

  Future<void> _limparArquivosTemporarios() async {
    final tmp = await getTemporaryDirectory();
    if (!await tmp.exists()) return;
    await for (final entry in tmp.list(followLinks: false)) {
      try {
        await entry.delete(recursive: true);
      } catch (_) {}
    }
  }

  final AppConfig config;
  final ApiClient api;
  late final SyncService sync;

  bool get isConnected => config.isConnected;
  bool get isApproved => config.isApproved;
  bool get isLoggedIn => config.isLoggedIn;

  static bool isNetworkError(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is http.ClientException) return true;
    if (e is ApiException) {
      // Cloudflare / origem fora: 502, 503, 520–530 — tratar como rede para fallback offline.
      final code = e.statusCode;
      if (code != null &&
          (code == 502 ||
              code == 503 ||
              code == 504 ||
              (code >= 520 && code <= 530))) {
        return true;
      }
      final m = e.message.toLowerCase();
      return m.contains('socket') ||
          m.contains('timed out') ||
          m.contains('timeout') ||
          m.contains('connection') ||
          m.contains('failed host') ||
          m.contains('network') ||
          m.contains('conexão') ||
          m.contains('conectar');
    }
    final m = e.toString().toLowerCase();
    return m.contains('socket') ||
        m.contains('timed out') ||
        m.contains('timeout') ||
        m.contains('connection refused') ||
        m.contains('failed host') ||
        m.contains('network is unreachable') ||
        m.contains('clientexception');
  }

  /// Continua com o último servidor sem testar a rede (modo offline).
  Future<void> continueOffline() async {
    final url = config.lastBaseUrl.trim();
    if (url.isEmpty) {
      throw Exception('Nenhum servidor anterior. Conecte online pelo menos uma vez.');
    }
    if (!config.deviceApproved) {
      throw Exception('Aparelho ainda não autorizado. Conecte online para liberar.');
    }
    config.baseUrl = url;
    await ensureDeviceIdentity();
    await config.save();
    AppLog.instance.warn('conexão', 'Modo offline com $url');
    notifyListeners();
  }

  /// Garante um identificador único e um nome padrão (modelo do aparelho).
  Future<void> ensureDeviceIdentity() async {
    var changed = false;
    if (config.deviceUuid.isEmpty) {
      config.deviceUuid = const Uuid().v4();
      changed = true;
    }
    if (config.deviceName.isEmpty) {
      config.deviceName = await _defaultDeviceName();
      changed = true;
    }
    if (changed) {
      await config.save();
      notifyListeners();
    }
  }

  Future<String> _defaultDeviceName() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final brand = info.brand.isNotEmpty
          ? '${info.brand[0].toUpperCase()}${info.brand.substring(1)}'
          : '';
      final name = '$brand ${info.model}'.trim();
      return name.isEmpty ? 'Aparelho Android' : name;
    } catch (_) {
      return 'Aparelho Android';
    }
  }

  String _normalizarUrl(String input, {int defaultPort = 8765}) {
    return ErpUrl.normalize(input, defaultPort: defaultPort);
  }

  /// Conecta a um endereço (IP/porta) digitado manualmente.
  Future<void> connectManual(String url) async {
    final clean = _normalizarUrl(url);
    if (clean.isEmpty) {
      throw Exception('Informe o endereço do servidor.');
    }
    AppLog.instance.info('conexão', 'Testando $clean');
    final r = await ApiClient.pingDetailed(clean, timeout: const Duration(seconds: 5));
    if (!r.ok) {
      AppLog.instance.error('conexão', 'Falhou em $clean: ${r.message}');
      throw Exception('Não foi possível conectar em $clean: ${r.message}');
    }
    AppLog.instance.ok('conexão', 'Conectado a $clean (${r.ms} ms)');
    await _applyConnection(clean);
  }

  Future<void> _applyConnection(String baseUrl) async {
    config.baseUrl = baseUrl;
    config.lastBaseUrl = baseUrl;
    await ensureDeviceIdentity();
    await config.save();
    notifyListeners();
    unawaited(verificarResetPendente());
  }

  Future<void> connectFound(String baseUrl) async {
    AppLog.instance.ok('conexão', 'Servidor encontrado na rede: $baseUrl');
    await _applyConnection(baseUrl);
  }

  Future<void> setDeviceName(String name) async {
    config.deviceName = name.trim();
    await config.save();
    notifyListeners();
  }

  Future<String> registerDevice() async {
    await ensureDeviceIdentity();
    final resp = await api.registerDevice(deviceName: config.deviceName);
    config.pairingCode = (resp['pairing_code'] ?? '').toString();
    config.deviceApproved = resp['approved'] == true;
    await config.save();
    AppLog.instance.info('aparelho',
        'Registrado "${config.deviceName}" — código ${config.pairingCode} (status: ${resp['status'] ?? '-'})');
    notifyListeners();
    return config.pairingCode;
  }

  Future<String> refreshApproval() async {
    final resp = await api.deviceStatus();
    final status = (resp['status'] ?? 'desconhecido').toString();
    final approved = resp['approved'] == true;
    if (resp['pairing_code'] != null) {
      config.pairingCode = resp['pairing_code'].toString();
    }
    if (approved != config.deviceApproved) {
      config.deviceApproved = approved;
      await config.save();
      if (approved) {
        AppLog.instance.ok('aparelho', 'Autorizado pelo administrador');
      } else {
        AppLog.instance.warn('aparelho', 'Status mudou para: $status');
      }
      notifyListeners();
    }
    return status;
  }

  Future<bool> syncDeviceApprovalFromError(Object e) async {
    final blocked = e is ApiException
        ? e.isDeviceBlocked
        : e.toString().toLowerCase().contains('aguardando autorização');
    if (!blocked) return false;
    if (config.deviceApproved) {
      config.deviceApproved = false;
      await config.save();
      AppLog.instance.warn('aparelho', 'Autorização local invalidada: $e');
      notifyListeners();
    }
    return true;
  }

  Future<Map<String, dynamic>> info() async => api.info();

  /// Lista do ERP; com aparelho vinculado vem só o vendedor dele (e o vínculo é gravado).
  Future<List<dynamic>> usuariosDaEmpresa(int empresaId) async {
    final data = await api.usuarios(empresaId);
    if (data.containsKey('vinculo_user_id')) {
      final vinculo = _asInt(data['vinculo_user_id']);
      if (vinculo != config.vinculoUserId) {
        config.vinculoUserId = vinculo;
        await config.save();
        notifyListeners();
      }
    }
    return _somenteVinculado(data['users'] as List<dynamic>? ?? []);
  }

  /// Aparelho vinculado: só o vendedor do aparelho aparece/entra.
  /// Livre: só usuários com vendedor (o ERP já filtra; cache antigo pode ter outros).
  List<dynamic> _somenteVinculado(List<dynamic> users) {
    final vinculo = config.vinculoUserId;
    if (vinculo == null) {
      return users.where((u) => u is Map && (_asInt(u['vendedor_id']) ?? 0) > 0).toList();
    }
    return users.where((u) => u is Map && _asInt(u['id']) == vinculo).toList();
  }

  Future<void> cacheEmpresas(List<dynamic> empresas) async {
    config.cachedEmpresasJson = jsonEncode(empresas);
    await config.save();
  }

  Future<void> cacheUsuarios(int empresaId, List<dynamic> users) async {
    Map<String, dynamic> map = {};
    try {
      map = jsonDecode(config.cachedUsuariosJson) as Map<String, dynamic>? ?? {};
    } catch (_) {}
    map['$empresaId'] = users;
    config.cachedUsuariosJson = jsonEncode(map);
    await config.save();
  }

  List<dynamic> empresasEmCache() {
    try {
      final list = jsonDecode(config.cachedEmpresasJson);
      return list is List ? List<dynamic>.from(list) : [];
    } catch (_) {
      return [];
    }
  }

  List<dynamic> usuariosEmCache(int empresaId) {
    try {
      final map = jsonDecode(config.cachedUsuariosJson) as Map<String, dynamic>?;
      final list = map?['$empresaId'];
      return list is List ? _somenteVinculado(List<dynamic>.from(list)) : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> login(
    int empresaId,
    int userId,
    String senha, {
    String? empresaNome,
    bool rememberUser = false,
    bool biometricEnabled = false,
  }) async {
    if (_resetExecutando) {
      throw Exception('Apagando a base local autorizada pelo retaguarda. Aguarde.');
    }
    if (config.resetEmAndamentoUuid.isNotEmpty &&
        !await _executarReset(config.resetEmAndamentoUuid)) {
      throw Exception('Não foi possível concluir o reset da base local. Tente novamente.');
    }
    final vinculo = config.vinculoUserId;
    if (vinculo != null && vinculo != userId) {
      throw Exception(msgVinculadoOutro);
    }
    // Reset apagado aqui mas ainda não confirmado: o ERP só libera o vínculo ao confirmar.
    if (config.resetConcluidoUuid.isNotEmpty) {
      await _confirmarReset(config.resetConcluidoUuid);
    }
    // Offline-first: com senha/token em cache não consulta o ERP (só 1ª vez online).
    final offlineOk = await _loginOffline(
      empresaId: empresaId,
      userId: userId,
      senha: senha,
      empresaNome: empresaNome,
      rememberUser: rememberUser,
      biometricEnabled: biometricEnabled,
    );
    if (offlineOk) return;

    try {
      final resp = await api.login(
        empresaId: empresaId,
        userId: userId,
        senha: senha,
        deviceUuid: config.deviceUuid,
        deviceName: config.deviceName,
      );
      await _aplicarLoginOnline(
        resp,
        empresaId: empresaId,
        empresaNome: empresaNome,
        rememberUser: rememberUser,
        biometricEnabled: biometricEnabled,
        senha: senha,
      );
    } catch (e) {
      if (e is ApiException && e.code == 'device_vinculado_outro') {
        // Atualiza o vínculo local para a tela mostrar só o vendedor do aparelho.
        try {
          await cacheUsuarios(empresaId, await usuariosDaEmpresa(empresaId));
        } catch (_) {}
      }
      if (isNetworkError(e)) {
        final ok = await _loginOffline(
          empresaId: empresaId,
          userId: userId,
          senha: senha,
          empresaNome: empresaNome,
          rememberUser: rememberUser,
          biometricEnabled: biometricEnabled,
        );
        if (ok) return;
      }
      rethrow;
    }
  }

  Future<void> _aplicarLoginOnline(
    Map<String, dynamic> resp, {
    required int empresaId,
    String? empresaNome,
    required bool rememberUser,
    required bool biometricEnabled,
    required String senha,
  }) async {
    config.token = (resp['token'] ?? '').toString();
    config.cachedToken = config.token;
    config.empresaId = empresaId;
    if (empresaNome != null) config.empresaNome = empresaNome;
    final user = resp['user'] as Map<String, dynamic>?;
    if (user != null) {
      config.userId = user['id'];
      config.userName = (user['name'] ?? '').toString();
      config.vendedorId = user['vendedor_id'];
      config.vendedorNome = (user['vendedor_nome'] ?? '').toString();
      config.caixaId = user['caixa_id'] is int
          ? user['caixa_id'] as int
          : int.tryParse('${user['caixa_id'] ?? ''}');
      config.caixaNome = (user['caixa_nome'] ?? '').toString();
      config.pixApiHabilitada = user['pix_api_habilitada'] == true;
      config.verTodosClientes = user['ver_todos_clientes'] == true;
      if (user.containsKey('desconto_reais_item_modo')) {
        config.descontoReaisItemModo = normalizarDescontoReaisItemModo(user['desconto_reais_item_modo']);
      }
      if (user.containsKey('imp_valor_liquido')) {
        config.impValorLiquido = user['imp_valor_liquido'] == true;
      }
      if (user.containsKey('imp_sem_coluna_desconto')) {
        config.impSemColunaDesconto = user['imp_sem_coluna_desconto'] == true;
      }
      config.estoqueNome = (user['estoque_nome'] ?? '').toString();
      config.tabelaVendaId = user['tabela_venda_id'] is int
          ? user['tabela_venda_id'] as int
          : int.tryParse('${user['tabela_venda_id'] ?? ''}');
      config.tabelaVendaCodigo = (user['tabela_venda_codigo'] ?? '').toString();
      config.tabelaVendaDescricao = (user['tabela_venda_descricao'] ?? '').toString();

      // Garante vendedor no cache de usuários para restaurar no login offline.
      try {
        final cached = usuariosEmCache(empresaId).map((e) {
          if (e is! Map) return e;
          final m = Map<String, dynamic>.from(e);
          if (_asInt(m['id']) == config.userId) {
            m['vendedor_id'] = config.vendedorId;
            m['vendedor_nome'] = config.vendedorNome;
            m['name'] = config.userName;
          }
          return m;
        }).toList();
        if (cached.isNotEmpty) {
          await cacheUsuarios(empresaId, cached);
        }
      } catch (_) {}
    }
    final device = resp['device'];
    config.vinculoUserId =
        (device is Map ? _asInt(device['vinculo_user_id']) : null) ?? config.userId;
    config.rememberUser = rememberUser;
    config.biometricEnabled = rememberUser && biometricEnabled;
    if (rememberUser) {
      await CredentialStore.saveSenha(senha);
    } else {
      await CredentialStore.clearSenha();
    }
    await config.save();
    // Sempre força pull completo no login (evita 304 com base/cache inconsistente).
    await LocalDb.instance.clearMeta('pull_etag');
    AppLog.instance.ok(
      'login',
      'Entrou como ${config.userName} (empresa ${config.empresaNome})'
      '${config.verTodosClientes ? ' [todos clientes]' : ''}',
    );
    sync.start();
    notifyListeners();
  }

  Future<bool> _loginOffline({
    required int empresaId,
    required int userId,
    required String senha,
    String? empresaNome,
    required bool rememberUser,
    required bool biometricEnabled,
  }) async {
    final saved = await CredentialStore.readSenha();
    final token = config.cachedToken.trim();
    if (saved == null || saved.isEmpty || saved != senha) {
      return false;
    }
    if (token.isEmpty) return false;
    if (config.empresaId != null && config.empresaId != empresaId) return false;
    if (config.userId != null && config.userId != userId) return false;
    if (config.vinculoUserId != null && config.vinculoUserId != userId) return false;

    config.token = token;
    config.empresaId = empresaId;
    if (empresaNome != null && empresaNome.isNotEmpty) {
      config.empresaNome = empresaNome;
    }
    config.userId = userId;
    // Restaura nome/vendedor do cache de usuários se a sessão limpa perdeu o vínculo.
    if (config.userName.isEmpty || config.vendedorId == null) {
      for (final raw in usuariosEmCache(empresaId)) {
        if (raw is! Map) continue;
        final u = Map<String, dynamic>.from(raw);
        if (_asInt(u['id']) != userId) continue;
        if (config.userName.isEmpty) {
          config.userName = (u['name'] ?? '').toString();
        }
        final vid = _asInt(u['vendedor_id']);
        if (config.vendedorId == null && vid != null) {
          config.vendedorId = vid;
          config.vendedorNome = (u['vendedor_nome'] ?? '').toString();
        }
        break;
      }
    }
    config.rememberUser = rememberUser;
    config.biometricEnabled = rememberUser && biometricEnabled;
    await config.save();
    AppLog.instance.warn(
      'login',
      'Entrou OFFLINE como ${config.userName.isEmpty ? userId : config.userName}'
      '${config.vendedorId != null ? ' (vendedor ${config.vendedorId})' : ' (sem vendedor)'}',
    );
    sync.start();
    notifyListeners();
    return true;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  static const msgVinculadoOutro = 'Este aparelho está vinculado a outro vendedor.';

  /// UI: sessão encerrada porque o ERP recusou o vínculo (mensagem do servidor).
  void Function(String mensagem)? onSessaoRecusada;

  /// ERP recusou o token deste usuário no aparelho: sai sem permitir reentrar
  /// offline. O vínculo local continua (só o reset libera).
  Future<void> _encerrarSessaoRecusada(ApiException e) async {
    sync.stop();
    await CredentialStore.clearSenha();
    config
      ..biometricEnabled = false
      ..cachedToken = ''
      ..clearSession();
    await config.save();
    AppLog.instance.warn('login', 'Sessão recusada pelo ERP: ${e.message}');
    notifyListeners();
    onSessaoRecusada?.call(e.message);
  }

  Future<void> logout() async {
    sync.stop();
    // Sessão local primeiro — não depende da rede (senão o "Sair" trava no timeout).
    if (!config.rememberUser) {
      await CredentialStore.clearSenha();
      config.biometricEnabled = false;
      config.cachedToken = '';
    }
    config.clearSession();
    await config.save();
    AppLog.instance.info('login', 'Sessão encerrada');
    notifyListeners();
    unawaited(api.logout());
  }

  Future<void> disconnect() async {
    sync.stop();
    await CredentialStore.clearSenha();
    config
      ..baseUrl = ''
      ..pairingCode = ''
      ..rememberUser = false
      ..biometricEnabled = false
      ..empresaId = null
      ..empresaNome = ''
      ..cachedToken = ''
      ..verTodosClientes = false
      ..descontoReaisItemModo = descontoReaisModoUnitario
      ..clearSession();
    await config.save();
    notifyListeners();
  }
}
