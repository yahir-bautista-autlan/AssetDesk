import 'package:flutter/material.dart';
import 'models/inventory_model.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/admin_management_screen.dart';
import 'screens/inventory_selection_screen.dart';
import 'screens/inventory_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AssetDeskApp());
}

class AssetDeskApp extends StatelessWidget {
  const AssetDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AssetDesk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A2574)),
        useMaterial3: true,
      ),
      home: const SessionGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/admin': (_) => const _AdminGuard(),
        '/inventory_selection': (_) => const _SelectionRoute(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/inventory_dashboard') {
          final args = settings.arguments;
          final inventario = args is InventoryModel ? args : null;
          return MaterialPageRoute(
            builder: (_) => InventoryDashboardScreen(inventario: inventario),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late final Future<UserModel?> _sesion;

  @override
  void initState() {
    super.initState();
    _sesion = AuthService.obtenerUsuarioActual();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: _sesion,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF4A2574)),
            ),
          );
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return InventorySelectionScreen(
          inventariosVinculados: user.inventarios,
        );
      },
    );
  }
}

class _SelectionRoute extends StatelessWidget {
  const _SelectionRoute();

  @override
  Widget build(BuildContext context) {
    final user = AuthService.usuarioCache;
    if (user == null) return const LoginScreen();
    return InventorySelectionScreen(inventariosVinculados: user.inventarios);
  }
}

class _AdminGuard extends StatelessWidget {
  const _AdminGuard();

  @override
  Widget build(BuildContext context) {
    if (!AuthService.esAdmin) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline,
                    size: 48, color: Color(0xFF9CA3AF)),
                const SizedBox(height: 12),
                const Text(
                  'No tienes permiso para acceder a esta sección.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const AdminManagementScreen();
  }
}