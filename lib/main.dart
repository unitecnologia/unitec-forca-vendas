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

/// Mantém barras do sistema padrão — modos manuais/edgeToEdge
/// já atrapalharam o teclado no login em alguns Android.
Future<void> _aplicarModoTela() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.state,
      child: MaterialApp(
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
