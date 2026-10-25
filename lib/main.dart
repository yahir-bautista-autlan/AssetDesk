import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/inventory_model.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/admin_management_screen.dart';
import 'screens/inventory_selection_screen.dart';
import 'screens/inventory_menu_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SystemNavigator.selectSingleEntryHistory();
  runApp(const AssetDeskApp());
}

class _TransicionLigera extends PageTransitionsBuilder {
  const _TransicionLigera();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
      child: child,
    );
  }
}

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

class InactividadService {
  static const Duration limite = Duration(minutes: 15);
  static const Duration _intervaloGuardado = Duration(seconds: 20);
  static const String _clave = 'last_activity_ms';

  static DateTime _ultima = DateTime.now();
  static DateTime _ultimaEscritura = DateTime.fromMillisecondsSinceEpoch(0);

  static void registrar({bool forzar = false}) {
    final ahora = DateTime.now();
    _ultima = ahora;
    if (forzar || ahora.difference(_ultimaEscritura) > _intervaloGuardado) {
      _ultimaEscritura = ahora;
      _guardar(ahora);
    }
  }

  static Future<void> _guardar(DateTime momento) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_clave, momento.millisecondsSinceEpoch);
    } catch (_) {}
  }

  static bool get expiroEnMemoria =>
      DateTime.now().difference(_ultima) > limite;

  static Future<bool> expiroEnDisco() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardado = prefs.getInt(_clave);
      if (guardado == null) return false;
      final ultima = DateTime.fromMillisecondsSinceEpoch(guardado);
      return DateTime.now().difference(ultima) > limite;
    } catch (_) {
      return false;
    }
  }
}

class AssetDeskApp extends StatefulWidget {
  const AssetDeskApp({super.key});

  @override
  State<AssetDeskApp> createState() => _AssetDeskAppState();
}

class _AssetDeskAppState extends State<AssetDeskApp>
    with WidgetsBindingObserver {
  Timer? _vigilante;
  bool _cerrando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_alTeclear);
    _vigilante = Timer.periodic(const Duration(seconds: 30), (_) => _revisar());
    _avisosSolicitudes =
        AuthService.nuevasSolicitudes.listen(_avisarNuevaSolicitud);
  }

  StreamSubscription<int>? _avisosSolicitudes;

  void _avisarNuevaSolicitud(int total) {
    final messenger = _messengerKey.currentState;
    if (messenger == null || AuthService.usuarioCache == null) return;
    final contexto = _navigatorKey.currentContext;
    final ancho = contexto == null ? 0.0 : MediaQuery.sizeOf(contexto).width;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: ancho > 640 ? 440 : null,
          backgroundColor: const Color(0xFF532E7C),
          duration: const Duration(seconds: 4),
          persist: false,
          content: Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  total == 1
                      ? 'Nueva solicitud de cambio pendiente'
                      : 'Tienes $total solicitudes de cambio pendientes',
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Ver',
            textColor: Colors.white,
            onPressed: () {
              _navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => const SolicitudesPendientesScreen(),
                ),
              );
            },
          ),
        ),
      );
  }

  @override
  void dispose() {
    _avisosSolicitudes?.cancel();
    _vigilante?.cancel();
    HardwareKeyboard.instance.removeHandler(_alTeclear);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _alTeclear(KeyEvent evento) {
    InactividadService.registrar();
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _revisar();
  }

  Future<void> _revisar() async {
    if (_cerrando) return;
    if (AuthService.usuarioCache == null) return;
    if (!InactividadService.expiroEnMemoria) return;

    _cerrando = true;
    await AuthService.logout();
    _navigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/login', (route) => false);
    Future.delayed(const Duration(milliseconds: 400), () {
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
                'Tu sesión se cerró por 15 minutos de inactividad. Inicia sesión de nuevo.'),
            backgroundColor: Color(0xFF4A2574),
            duration: Duration(seconds: 4),
          ),
        );
    });
    InactividadService.registrar();
    _cerrando = false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AssetDesk',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A2574)),
        useMaterial3: true,
        pageTransitionsTheme: kIsWeb
            ? PageTransitionsTheme(
                builders: {
                  for (final plataforma in TargetPlatform.values)
                    plataforma: const _TransicionLigera(),
                },
              )
            : const PageTransitionsTheme(),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      builder: (context, child) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => InactividadService.registrar(),
          onPointerMove: (_) => InactividadService.registrar(),
          onPointerHover: (_) => InactividadService.registrar(),
          onPointerSignal: (_) => InactividadService.registrar(),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
            builder: (_) => inventario == null
                ? const _SelectionRoute()
                : InventoryMenuScreen(inventario: inventario),
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
  late final Future<({UserModel? usuario, InventoryModel? inventario, bool enDashboard})> _sesion;

  @override
  void initState() {
    super.initState();
    _sesion = _validar();
  }

  Future<({UserModel? usuario, InventoryModel? inventario, bool enDashboard})> _validar() async {
    if (await InactividadService.expiroEnDisco()) {
      await AuthService.logout();
      Future.delayed(const Duration(milliseconds: 600), () {
        _messengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                  'Tu sesión se cerró por 15 minutos de inactividad. Inicia sesión de nuevo.'),
              backgroundColor: Color(0xFF4A2574),
              duration: Duration(seconds: 4),
            ),
          );
      });
      return (usuario: null, inventario: null, enDashboard: false);
    }

    final usuario = await AuthService.obtenerUsuarioActual();
    if (usuario == null) return (usuario: null, inventario: null, enDashboard: false);

    InactividadService.registrar(forzar: true);

    InventoryModel? inventario;
    var enDashboard = false;
    final sitio = await AuthService.leerSitio();
    if (sitio != null) {
      for (final inv in usuario.inventarios) {
        if (inv.id == sitio.$1) {
          inventario = inv;
          enDashboard = sitio.$2 >= 0;
          break;
        }
      }
    }
    return (usuario: usuario, inventario: inventario, enDashboard: enDashboard);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({UserModel? usuario, InventoryModel? inventario, bool enDashboard})>(
      future: _sesion,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF4A2574)),
            ),
          );
        }
        final sesion = snapshot.data;
        final user = sesion?.usuario;
        if (user == null) return const LoginScreen();
        return _RestauradorSitio(
          usuario: user,
          inventario: sesion?.inventario,
          enDashboard: sesion?.enDashboard ?? false,
        );
      },
    );
  }
}

class _RestauradorSitio extends StatefulWidget {
  final UserModel usuario;
  final InventoryModel? inventario;
  final bool enDashboard;

  const _RestauradorSitio({
    required this.usuario,
    this.inventario,
    this.enDashboard = false,
  });

  @override
  State<_RestauradorSitio> createState() => _RestauradorSitioState();
}

class _RestauradorSitioState extends State<_RestauradorSitio> {
  @override
  void initState() {
    super.initState();
    final inv = widget.inventario;
    if (inv != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => InventoryMenuScreen(
                inventario: inv,
                restaurarDashboard: widget.enDashboard,
              ),
            ))
            .then((_) => AuthService.olvidarSitio());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InventorySelectionScreen(
      inventariosVinculados: widget.usuario.inventarios,
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