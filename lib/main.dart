import 'package:flutter/material.dart';
import 'models/usuario_model.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/admin_management_screen.dart';
import 'screens/inventory_selection_screen.dart';
import 'screens/inventory_dashboard_screen.dart';

void main() {
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
        '/admin': (_) => const AdminManagementScreen(),
        '/inventory_dashboard': (_) => const InventoryDashboardScreen(),
      },
    );
  }
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UsuarioModel?>(
      future: AuthService.obtenerUsuarioActual(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        if (user.esAdmin) return const AdminManagementScreen();
        return InventorySelectionScreen(
          inventariosVinculados: user.inventarios,
        );
      },
    );
  }
}