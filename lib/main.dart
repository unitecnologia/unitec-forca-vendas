import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_state.dart';
import 'config.dart';
import 'log/app_log.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/waiting_approval_screen.dart';
import 'update/app_updater.dart';
import 'update/update_dialog.dart';

/// Esconde a barra de navegação do Android (voltar/home/recentes),
/// mantendo só a barra de status no topo.
Future<void> _aplicarModoTela() async {
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _aplicarModoTela();
  // Mantém a tela ligada enquanto o app estiver aberto.
  await WakelockPlus.enable();
  await AppLog.instance.load();
  AppLog.instance.info('app', 'Aplicativo iniciado');
  final config = await AppConfig.load();
  final state = AppState(config);
  await state.initialize();
  runApp(UnitecForcaVendasApp(state: state));
}

class UnitecForcaVendasApp extends StatefulWidget {
  const UnitecForcaVendasApp({super.key, required this.state});

  final AppState state;

  @override
  State<UnitecForcaVendasApp> createState() => _UnitecForcaVendasAppState();
}

class _UnitecForcaVendasAppState extends State<UnitecForcaVendasApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state
      ..onResetIniciado = () {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
      ..onResetConcluido = () {
        _messengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Base local apagada por autorização do retaguarda. Entre novamente.'),
            duration: Duration(seconds: 8),
          ));
      }
      ..onSessaoRecusada = (mensagem) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        _messengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(mensagem),
            duration: const Duration(seconds: 8),
          ));
      };
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificarAtualizacao());
  }

  /// Ao abrir o app (no máximo 1x a cada 24 h): oferece a versão nova da GitHub Release.
  Future<void> _verificarAtualizacao() async {
    final release = await AppUpdater.instance.verificar();
    if (release == null || !mounted || widget.state.resetBloqueando) return;
    final ctx = _navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await mostrarAtualizacaoDisponivel(ctx, release);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Não reaplica SystemChrome aqui: no Android isso costuma fechar/travar o teclado.
      WakelockPlus.enable();
      if (widget.state.isLoggedIn) {
        widget.state.sync.syncNow();
      } else if (widget.state.isConnected) {
        widget.state.verificarResetPendente();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.state,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        title: 'Unitec Força de Vendas',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1565C0),
          useMaterial3: true,
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isConnected) return const ConnectScreen();
    if (!state.isApproved) return const WaitingApprovalScreen();
    if (!state.isLoggedIn) return const LoginScreen();
    return const HomeScreen();
  }
}
