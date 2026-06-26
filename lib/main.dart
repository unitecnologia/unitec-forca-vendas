import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'config.dart';
import 'log/app_log.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/waiting_approval_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.instance.load();
  AppLog.instance.info('app', 'Aplicativo iniciado');
  final config = await AppConfig.load();
  runApp(UnitecForcaVendasApp(state: AppState(config)));
}

class UnitecForcaVendasApp extends StatelessWidget {
  const UnitecForcaVendasApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
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
