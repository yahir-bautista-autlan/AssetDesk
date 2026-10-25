import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

import '../models/inventory_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'add_asset_screen.dart';
import 'inventory_selection_screen.dart';
import 'qr_scanner_screen.dart';
import 'qr_view_screen.dart';
import 'responsiva_preview_screen.dart';

List<Map<String, dynamic>> _filasTipadas(List<dynamic> filas) {
  return filas
      .map((r) => r is Map<String, dynamic>
          ? r
          : Map<String, dynamic>.from(r as Map))
      .toList(growable: false);
}

bool _requiereAprobacionEn(InventoryModel? inv) {
  final u = AuthService.usuarioCache;
  if (u == null || !u.esResidente) return false;
  if (inv == null) return true;
  return !inv.esResponsable(u.correo);
}

class _AvisoAprobacion extends StatelessWidget {
  final String responsable;
  final EdgeInsetsGeometry margen;

  const _AvisoAprobacion({
    required this.responsable,
    this.margen = const EdgeInsets.only(top: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margen,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded,
              color: Color(0xFFB45309), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              responsable.isEmpty
                  ? 'Este cambio no se aplicará de inmediato: se enviará al responsable del inventario para su aprobación.'
                  : 'Este cambio no se aplicará de inmediato: se enviará a $responsable para su aprobación.',
              style: const TextStyle(
                  fontSize: 12.5, color: Color(0xFF92400E), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

double? _anchoAviso(BuildContext context) =>
    MediaQuery.sizeOf(context).width > 640 ? 420 : null;

bool _avisarSiPendiente(BuildContext context) {
  if (!AuthService.ultimaRespuestaPendiente) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      width: _anchoAviso(context),
      content: Text(AuthService.ultimoMensaje.isEmpty
          ? 'Tu cambio fue enviado al responsable del inventario para su aprobación.'
          : AuthService.ultimoMensaje),
      backgroundColor: const Color(0xFFF59E0B),
      duration: const Duration(seconds: 4),
    ),
  );
  return true;
}

class InventoryDashboardScreen extends StatefulWidget {
  final InventoryModel? inventario;
  final int? pestanaInicial;

  const InventoryDashboardScreen({
    super.key,
    this.inventario,
    this.pestanaInicial,
  });

  @override
  State<InventoryDashboardScreen> createState() =>
      _InventoryDashboardScreenState();
}

class _InventoryDashboardScreenState extends State<InventoryDashboardScreen>
    with WidgetsBindingObserver {
  static const primaryPurple = Color(0xFF532E7C);
  static const lightPurpleBg = Color(0xFFEFE8F6);

  static const double _colWidth = 170;
  static const List<String> _tabs = ['Captura', 'Impresoras', 'Otros', 'Consumibles'];
  static const List<String> _filtros = ['Todos', 'Asignados', 'Disponibles', 'Bajas'];

  final ValueNotifier<int> _tabIndex = ValueNotifier(0);
  final ValueNotifier<String> _searchQuery = ValueNotifier('');
  final ValueNotifier<String> _filtroEstado = ValueNotifier('Todos');
  final ValueNotifier<Map<String, Set<String>>> _columnasPorPestana =
      ValueNotifier({});

  final ValueNotifier<String> _snResaltado = ValueNotifier('');
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  static final ScrollbarThemeData _temaBarras = ScrollbarThemeData(
    thickness: WidgetStateProperty.resolveWith(
        (e) => e.contains(WidgetState.hovered) ? 8.0 : 5.0),
    radius: const Radius.circular(8),
    thumbColor: WidgetStateProperty.resolveWith((e) =>
        e.contains(WidgetState.hovered) || e.contains(WidgetState.dragged)
            ? const Color(0xFF9B87BA)
            : const Color(0x669B87BA)),
    trackVisibility: const WidgetStatePropertyAll(false),
    thumbVisibility: const WidgetStatePropertyAll(false),
    crossAxisMargin: 2,
    mainAxisMargin: 2,
  );

  static const EdgeInsets _paddingCelda = EdgeInsets.symmetric(horizontal: 12);

  static const BoxDecoration _bordeFila = BoxDecoration(
    border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1)),
  );
  Timer? _timerResalte;

  static const Map<String, List<String>> _snPorPestana = {
    'Captura': ['Numero de Serie'],
    'Impresoras': ['Numero de Serie'],
    'Otros': ['Numero de Serie'],
    'Consumibles': ['Numero de Serie'],
  };

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _isLoading = true;
  Map<String, dynamic> _datosHojas = {};
  final Set<String> _bajasEnCarga = {};
  InventoryModel? _inventarioActivo;
  UserModel? _user;
  int _pendientes = 0;

  int _datosVersion = 0;
  int _generacionCarga = 0;
  Timer? _timerSync;
  bool _sondeando = false;
  bool _enPrimerPlano = true;
  int _fallosSync = 0;
  int _saltarSondeos = 0;
  String _secSync = '';
  bool _eventoPropioRecibido = false;
  Future<void>? _cargaTotal;
  final Set<String> _pestanasEnCarga = {};
  final Map<String, (List<String>, List<dynamic>)> _memos = {};
  final Map<String, List<String>> _indiceBusqueda = {};

  late final Listenable _headerListenable =
      Listenable.merge([_tabIndex, _filtroEstado]);
  late final Listenable _tableListenable = Listenable.merge(
      [_tabIndex, _searchQuery, _filtroEstado, _columnasPorPestana, _snResaltado]);

  bool get _puedeEditar => _user?.puedeEditar ?? AuthService.puedeEditar;

  bool get _puedeAprobar {
    final u = _user;
    if (u == null) return false;
    return u.inventarios.any((i) => i.esResponsable(u.correo));
  }

  @override
  void initState() {
    super.initState();
    _inventarioActivo = widget.inventario;
    HardwareKeyboard.instance.addHandler(_teclaNavegacion);
    WidgetsBinding.instance.addObserver(this);
    AuthService.alEventoPropio = (ev) => _recibirEvento(ev, propio: true);
    AuthService.solicitudesPendientes.addListener(_alCambiarPendientes);
    _cargarUsuario();
    _iniciar();
  }

  void _alCambiarPendientes() {
    final total = AuthService.solicitudesPendientes.value;
    if (!mounted || total == _pendientes) return;
    setState(() => _pendientes = total);
  }

  Future<void> _iniciar() async {
    final inicial = widget.pestanaInicial;
    if (inicial != null && inicial >= 0 && inicial < _tabs.length) {
      _tabIndex.value = inicial;
      AuthService.guardarSitio(_inventarioActivo?.id ?? '', inicial);
    } else {
      await _restaurarPestana();
    }
    if (!mounted) return;
    final ss = _inventarioActivo?.spreadsheetId ?? '';
    if (ss.isNotEmpty) {
      AuthService.obtenerCambios(ss, '').then((r) {
        if (mounted && _secSync.isEmpty && r != null) {
          _secSync = (r['seq'] ?? '').toString();
        }
      });
    }
    _cargarDatosRemotos();
    _timerSync?.cancel();
    _timerSync =
        Timer.periodic(const Duration(seconds: 3), (_) => _sondearCambios());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _enPrimerPlano = state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
    if (_enPrimerPlano) _sondearCambios();
  }

  Future<void> _sondearCambios() async {
    if (!mounted || _sondeando || !_enPrimerPlano || _isLoading) return;
    if (_saltarSondeos > 0) {
      _saltarSondeos--;
      return;
    }
    final ss = _inventarioActivo?.spreadsheetId ?? '';
    if (ss.isEmpty) return;

    _sondeando = true;
    try {
      final r = await AuthService.obtenerCambios(ss, _secSync);
      if (!mounted) return;
      if (r == null) {
        _fallosSync++;
        _saltarSondeos = _fallosSync.clamp(1, 6);
        return;
      }
      _fallosSync = 0;
      final previo = _secSync;
      _secSync = (r['seq'] ?? previo).toString();
      if (previo.isEmpty) return;

      if (r['reset'] == true) {
        _cargarDatosRemotos(silencioso: true);
        _recontarPendientes();
        return;
      }

      final eventos = r['eventos'];
      if (eventos is List) {
        final yo = AuthService.sesionId;
        for (final e in eventos) {
          if (e is! Map) continue;
          if (e['s'] == yo) continue;
          _recibirEvento(Map<String, dynamic>.from(e), propio: false);
        }
      }
    } finally {
      _sondeando = false;
    }
  }

  void _recontarPendientes() {
    final ss = _inventarioActivo?.spreadsheetId ?? '';
    AuthService.olvidarDatos(ss, solicitudes: true);
    if (_puedeAprobar) _cargarPendientes();
  }

  List<dynamic>? _filasDe(String clave) {
    final datos = _datosHojas[clave];
    if (datos is! Map) return null;
    return List<dynamic>.from(datos['rows'] as List<dynamic>? ?? const []);
  }

  int _indiceDeSn(List<dynamic> filas, String pestana, String sn) {
    if (sn.isEmpty) return -1;
    for (var i = 0; i < filas.length; i++) {
      final f = filas[i];
      if (f is Map && _snDeFila(f, pestana) == sn) return i;
    }
    return -1;
  }

  void _guardarFilas(String clave, List<dynamic> filas) {
    final datos = Map<String, dynamic>.from(_datosHojas[clave] as Map);
    datos['rows'] = filas;
    _datosHojas[clave] = datos;
  }

  String _upsertFila(
      String clave, String pestana, Map<String, dynamic> fila, String snViejo) {
    final filas = _filasDe(clave);
    if (filas == null) return '';
    final snNuevo = _snDeFila(fila, pestana);
    var i = _indiceDeSn(filas, pestana, snViejo);
    if (i < 0) i = _indiceDeSn(filas, pestana, snNuevo);
    if (i >= 0) {
      filas[i] = fila;
    } else {
      filas.add(fila);
    }
    _guardarFilas(clave, filas);
    return snNuevo;
  }

  void _quitarFila(String clave, String pestana, String sn) {
    final filas = _filasDe(clave);
    if (filas == null) return;
    final i = _indiceDeSn(filas, pestana, sn);
    if (i < 0) return;
    filas.removeAt(i);
    _guardarFilas(clave, filas);
  }

  Future<void> _refrescarPestana(String pestana) async {
    final ss = _inventarioActivo?.spreadsheetId ?? '';
    AuthService.olvidarDatos(ss, pestana: pestana);
    final raw = await AuthService.obtenerPestana(ss, pestana);
    if (!mounted || raw == null) return;
    _aplicarPestana(pestana, raw, conservar: true);
    setState(() {});
  }

  void _recibirEvento(Map<String, dynamic> ev, {required bool propio}) {
    if (!mounted) return;
    final k = (ev['k'] ?? '').toString();
    final p = (ev['p'] ?? '').toString();
    final sn = (ev['sn'] ?? '').toString();
    final fila =
        ev['fila'] is Map ? Map<String, dynamic>.from(ev['fila'] as Map) : null;
    final filaBaja = ev['filaBaja'] is Map
        ? Map<String, dynamic>.from(ev['filaBaja'] as Map)
        : null;
    final claveBajas = _dataKeyFor(p, 'Bajas');
    var snResaltar = '';

    if (propio) _eventoPropioRecibido = true;

    switch (k) {
      case 'alta':
        if (fila != null) snResaltar = _upsertFila(p, p, fila, '');
        break;
      case 'edit':
        if (fila != null) snResaltar = _upsertFila(p, p, fila, sn);
        break;
      case 'baja':
        _quitarFila(p, p, sn);
        if (filaBaja != null && _datosHojas.containsKey(claveBajas)) {
          _upsertFila(claveBajas, p, filaBaja, sn);
        }
        break;
      case 'revertir':
        if (fila != null) snResaltar = _upsertFila(p, p, fila, sn);
        _quitarFila(claveBajas, p, sn);
        break;
      case 'quitar':
        _quitarFila(p, p, sn);
        break;
      case 'recargar':
        if (_datosHojas.containsKey(p)) _refrescarPestana(p);
        break;
      case 'solicitudes':
        _recontarPendientes();
        return;
      default:
        return;
    }

    _datosCambiaron();

    final actual = _tabs[_tabIndex.value];
    if (propio && (k == 'alta' || k == 'revertir')) {
      final i = _tabs.indexOf(p);
      if (i >= 0 && _tabIndex.value != i) _tabIndex.value = i;
      _limpiarVistaParaVer();
    }
    setState(() {});

    if (snResaltar.isNotEmpty && (propio || p == actual)) {
      _resaltarFila(snResaltar, desplazar: propio);
    }
    if (!propio && p == actual && _filtroEstado.value != 'Bajas') {
      _mostrarAviso('Tabla actualizada', primaryPurple, duracion: 2);
    }
  }

  Future<void> _restaurarPestana() async {
    final id = _inventarioActivo?.id ?? '';
    if (id.isEmpty) return;
    final sitio = await AuthService.leerSitio();
    if (!mounted) return;
    if (sitio != null &&
        sitio.$1 == id &&
        sitio.$2 >= 0 &&
        sitio.$2 < _tabs.length) {
      _tabIndex.value = sitio.$2;
    }
    AuthService.guardarSitio(id, _tabIndex.value);
  }

  String _normClave(String s) {
    return s
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .trim();
  }

  String _normSn(dynamic v) => v == null ? '' : v.toString().toLowerCase().trim();

  String? _headerSn(Iterable<dynamic> headers, String pestana) {
    final candidatos =
        (_snPorPestana[pestana] ?? const <String>[]).map(_normClave).toSet();
    for (final h in headers) {
      if (candidatos.contains(_normClave(h.toString()))) return h.toString();
    }
    return null;
  }

  String _snDeFila(Map fila, String pestana) {
    final h = _headerSn(fila.keys, pestana);
    return h == null ? '' : _normSn(fila[h]);
  }

  bool _teclaNavegacion(KeyEvent evento) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) return false;
    if (!mounted) return false;
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) {
      return false;
    }

    final tecla = evento.logicalKey;
    final esFlecha = tecla == LogicalKeyboardKey.arrowRight ||
        tecla == LogicalKeyboardKey.arrowLeft ||
        tecla == LogicalKeyboardKey.arrowDown ||
        tecla == LogicalKeyboardKey.arrowUp ||
        tecla == LogicalKeyboardKey.pageDown ||
        tecla == LogicalKeyboardKey.pageUp ||
        tecla == LogicalKeyboardKey.home ||
        tecla == LogicalKeyboardKey.end;
    if (!esFlecha) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    final contextoFoco = FocusManager.instance.primaryFocus?.context;
    if (contextoFoco != null &&
        (contextoFoco.widget is EditableText ||
            contextoFoco.findAncestorWidgetOfExactType<EditableText>() !=
                null)) {
      return false;
    }

    if (tecla == LogicalKeyboardKey.arrowRight) {
      _desplazar(_hCtrl, 140);
    } else if (tecla == LogicalKeyboardKey.arrowLeft) {
      _desplazar(_hCtrl, -140);
    } else if (tecla == LogicalKeyboardKey.arrowDown) {
      _desplazar(_vCtrl, 104);
    } else if (tecla == LogicalKeyboardKey.arrowUp) {
      _desplazar(_vCtrl, -104);
    } else if (tecla == LogicalKeyboardKey.pageDown) {
      _desplazar(_vCtrl, _paginaVertical());
    } else if (tecla == LogicalKeyboardKey.pageUp) {
      _desplazar(_vCtrl, -_paginaVertical());
    } else if (tecla == LogicalKeyboardKey.home) {
      _irA(_vCtrl, 0);
    } else {
      _irA(_vCtrl, double.infinity);
    }
    return true;
  }

  double _paginaVertical() {
    if (!_vCtrl.hasClients) return 0;
    return _vCtrl.position.viewportDimension * 0.9;
  }

  void _desplazar(ScrollController c, double delta) {
    if (!c.hasClients) return;
    final pos = c.position;
    final destino =
        (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (destino == pos.pixels) return;
    c.animateTo(destino,
        duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
  }

  void _irA(ScrollController c, double destino) {
    if (!c.hasClients) return;
    final pos = c.position;
    c.jumpTo(destino.clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }

  void _seleccionarPestana(int i) {
    if (_tabIndex.value == i) return;
    HapticFeedback.selectionClick();
    _tabIndex.value = i;
    AuthService.guardarSitio(_inventarioActivo?.id ?? '', i);
    _asegurarPestana(_tabs[i]);
    if (_filtroEstado.value == 'Bajas') {
      _asegurarBajasCargadas(_tabs[i]);
    }
  }

  @override
  void dispose() {
    AuthService.solicitudesPendientes.removeListener(_alCambiarPendientes);
    HardwareKeyboard.instance.removeHandler(_teclaNavegacion);
    WidgetsBinding.instance.removeObserver(this);
    _timerSync?.cancel();
    AuthService.alEventoPropio = null;
    _timerResalte?.cancel();
    _hCtrl.dispose();
    _vCtrl.dispose();
    _snResaltado.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    _tabIndex.dispose();
    _searchQuery.dispose();
    _filtroEstado.dispose();
    _columnasPorPestana.dispose();
    super.dispose();
  }

  void _datosCambiaron() {
    _datosVersion++;
    _memos.clear();
    _indiceBusqueda.clear();
  }

  Future<void> _cargarUsuario() async {
    final u = await AuthService.obtenerUsuarioActual();
    if (!mounted) return;
    setState(() => _user = u);
    if (_puedeAprobar) _cargarPendientes();
  }

  Future<void> _cargarPendientes() async {
    final total = await AuthService.contarSolicitudesPendientes();
    if (!mounted) return;
    setState(() => _pendientes = total);
  }

  Future<void> _abrirSolicitudes() async {
    final cambios = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SolicitudesPendientesScreen()),
    );
    if (!mounted) return;
    if (cambios == true) _cargarDatosRemotos(silencioso: true, forzar: true);
    _cargarPendientes();
  }

  Future<void> _abrirCambioPassword() async {
    final u = _user;
    if (u == null) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CambiarPasswordDialog(correo: u.correo),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: _anchoAviso(context),
          content: Text('Contraseña actualizada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _cerrarSesion() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _limpiarVistaParaVer() {
    if (_filtroEstado.value != 'Todos') _filtroEstado.value = 'Todos';
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      _searchQuery.value = '';
    }
  }

  Future<void> _trasCambio({
    required String pestana,
    String sn = '',
    bool alta = false,
    bool baja = false,
    bool revertir = false,
  }) async {
    final pendiente = AuthService.ultimaRespuestaPendiente;
    if (mounted) _avisarSiPendiente(context);

    if (pendiente) {
      _eventoPropioRecibido = false;
      if (_puedeAprobar) _cargarPendientes();
      return;
    }

    final aplicado = _eventoPropioRecibido;
    _eventoPropioRecibido = false;

    if (!mounted) return;

    final indicePestana = _tabs.indexOf(pestana);
    if (indicePestana >= 0 && _tabIndex.value != indicePestana) {
      _tabIndex.value = indicePestana;
    }
    if (alta || revertir) _limpiarVistaParaVer();

    if (baja) {
      _mostrarAviso(
        'Elemento dado de baja',
        const Color(0xFF4B5563),
        duracion: 4,
        etiqueta: 'Ver en Bajas',
        alPulsar: () {
          _filtroEstado.value = 'Bajas';
          _asegurarBajasCargadas(pestana);
        },
      );
    } else if (revertir) {
      _mostrarAviso('Elemento restaurado en "$pestana"', Colors.green);
    }

    if (_puedeAprobar) _cargarPendientes();

    if (!aplicado) {
      await _cargarDatosRemotos(silencioso: true, forzar: true);
      if (!mounted) return;

      final claveBajas = _dataKeyFor(pestana, 'Bajas');
      if (_datosHojas.containsKey(claveBajas) ||
          (_filtroEstado.value == 'Bajas' &&
              _tabs[_tabIndex.value] == pestana)) {
        await _asegurarBajasCargadas(pestana, forzar: true);
      }
    }
  }

  void _mostrarAviso(
    String texto,
    Color color, {
    int duracion = 3,
    String? etiqueta,
    VoidCallback? alPulsar,
  }) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        width: _anchoAviso(context),
        duration: Duration(seconds: duracion > 4 ? 4 : duracion),
        persist: false,
        action: etiqueta == null
            ? null
            : SnackBarAction(
                label: etiqueta,
                textColor: Colors.white,
                onPressed: alPulsar ?? () {},
              ),
      ),
    );
  }

  void _resaltarFila(String sn, {bool desplazar = true}) {
    _timerResalte?.cancel();
    _snResaltado.value = sn;
    if (desplazar) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _irAFila(sn));
    }
    _timerResalte = Timer(const Duration(seconds: 5), () {
      if (mounted) _snResaltado.value = '';
    });
  }

  void _irAFila(String sn) {
    if (!mounted || !_vCtrl.hasClients) return;
    final (headers, filas) = _obtenerDatosVisibles();
    final pestana = _tabs[_tabIndex.value];
    final snHeader = _headerSn(headers, pestana);
    if (snHeader == null) return;

    for (var i = 0; i < filas.length; i++) {
      final fila = filas[i];
      if (fila is Map && _normSn(fila[snHeader]) == sn) {
        final pos = _vCtrl.position;
        final destino = (i * 52.0 - pos.viewportDimension / 3)
            .clamp(0.0, pos.maxScrollExtent);
        _vCtrl.animateTo(
          destino,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }
  }

  String _dataKeyFor(String nombrePestana, String filtro) {
    return filtro == 'Bajas' ? '${nombrePestana}__Bajas' : nombrePestana;
  }

  Map<String, dynamic> _procesarHojaData(dynamic dataRaw) {
    if (dataRaw is! Map || dataRaw['headers'] == null) {
      return {'headers': <String>[], 'rows': <dynamic>[]};
    }

    final List<dynamic> rawHeaders = List<dynamic>.from(dataRaw['headers']);
    final List<String> uniqueHeaders = [];
    final Map<String, int> conteoNombres = {};
    bool hayDuplicados = false;

    for (var h in rawHeaders) {
      final limpio = h.toString().trim();
      if (limpio.isEmpty) continue;

      if (conteoNombres.containsKey(limpio)) {
        hayDuplicados = true;
        conteoNombres[limpio] = conteoNombres[limpio]! + 1;
        uniqueHeaders.add('$limpio (${conteoNombres[limpio]})');
      } else {
        conteoNombres[limpio] = 1;
        uniqueHeaders.add(limpio);
      }
    }

    final List<dynamic> rows = List<dynamic>.from(dataRaw['rows'] ?? []);

    if (!hayDuplicados) {
      return {'headers': uniqueHeaders, 'rows': rows};
    }

    final resultRows = <dynamic>[];
    for (var row in rows) {
      if (row is Map) {
        final Map<String, dynamic> rowMap = Map<String, dynamic>.from(row);
        final Map<String, int> conteoFila = {};

        for (int i = 0; i < uniqueHeaders.length; i++) {
          final originalName = rawHeaders.length > i
              ? rawHeaders[i].toString().trim()
              : '';
          final assignedName = uniqueHeaders[i];

          if (originalName.isNotEmpty && rowMap.containsKey(originalName)) {
            final val = rowMap[originalName];
            conteoFila[originalName] = (conteoFila[originalName] ?? 0) + 1;

            if (conteoFila[originalName]! > 1) {
              rowMap[assignedName] = val;
            }
          }
        }
        resultRows.add(rowMap);
      } else {
        resultRows.add(row);
      }
    }

    return {'headers': uniqueHeaders, 'rows': resultRows};
  }

  Future<void> _asegurarBajasCargadas(String nombrePestana,
      {bool forzar = false, bool refrescar = false}) async {
    final key = _dataKeyFor(nombrePestana, 'Bajas');
    if (_bajasEnCarga.contains(key)) return;
    if (!forzar && !refrescar && _datosHojas.containsKey(key)) return;

    _bajasEnCarga.add(key);
    if (mounted) setState(() {});

    final sheetIdOrName = _inventarioActivo?.spreadsheetId ?? '';
    final dataRaw = await AuthService.obtenerHojaBajas(sheetIdOrName, nombrePestana,
        forzar: forzar);
    final procesado = _procesarHojaData(dataRaw);

    _bajasEnCarga.remove(key);
    if (!mounted) return;

    if (refrescar &&
        (procesado['headers'] as List).isEmpty &&
        _datosHojas.containsKey(key)) {
      setState(() {});
      return;
    }

    _datosCambiaron();
    setState(() {
      _datosHojas[key] = procesado;
    });

    final todas = Set<String>.from(procesado['headers'] as List<String>);
    final previas = _columnasPorPestana.value[key];
    var columnas = todas;
    if (refrescar && previas != null) {
      final conservadas = previas.where(todas.contains).toSet();
      if (conservadas.isNotEmpty) columnas = conservadas;
    }
    _columnasPorPestana.value = {..._columnasPorPestana.value, key: columnas};
  }

  (List<String>, List<dynamic>) _obtenerDatosVisibles() {
    final index = _tabIndex.value;
    final nombrePestana = _tabs[index];
    final filtro = _filtroEstado.value;
    final dataKey = _dataKeyFor(nombrePestana, filtro);
    final query = _searchQuery.value.toLowerCase().trim();

    final memoKey =
        '$_datosVersion|$index|$filtro|$query|${identityHashCode(_columnasPorPestana.value)}';
    final memo = _memos[memoKey];
    if (memo != null) return memo;

    final pestanaData = _datosHojas[dataKey] ?? {'headers': [], 'rows': []};

    final allHeaders = List<String>.from(pestanaData['headers'] ?? []);
    final Set<String> activasSet = _columnasPorPestana.value[dataKey] ?? allHeaders.toSet();
    final List<String> headers = allHeaders.where((h) => activasSet.contains(h)).toList();

    final List<dynamic> rows = pestanaData['rows'] as List<dynamic>? ?? const [];

    final List<String>? indice = query.isEmpty
        ? null
        : (_indiceBusqueda[dataKey] ??= rows
            .map((r) => r is Map
                ? r.values.map((v) => v.toString()).join('\u0001').toLowerCase()
                : '')
            .toList());

    String? claveEstatus;
    for (final h in allHeaders) {
      if (h.toLowerCase().trim() == 'estatus') {
        claveEstatus = h;
        break;
      }
    }
    final filtraEstatus = filtro == 'Asignados' || filtro == 'Disponibles';
    final esConsumibles = nombrePestana == 'Consumibles';

    final filteredRows = <dynamic>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! Map) continue;

      if (filtraEstatus) {
        String estatusValor = '';
        if (claveEstatus != null) {
          estatusValor = (row[claveEstatus]?.toString() ?? '').toLowerCase().trim();
        } else {
          row.forEach((k, v) {
            if (k.toString().toLowerCase().trim() == 'estatus') {
              estatusValor = v.toString().toLowerCase().trim();
            }
          });
        }

        if (esConsumibles) {
          if (filtro == 'Asignados' && estatusValor != 'asignado') continue;
          if (filtro == 'Disponibles' && estatusValor != 'stock') continue;
        } else {
          if (filtro == 'Asignados' && estatusValor != 'activo') continue;
          if (filtro == 'Disponibles' && estatusValor != 'pendiente de asignar') continue;
        }
      }

      if (indice != null && !indice[i].contains(query)) continue;

      filteredRows.add(row);
    }

    final resultado = (headers, filteredRows);
    if (_memos.length >= 8) _memos.remove(_memos.keys.first);
    _memos[memoKey] = resultado;
    return resultado;
  }

  Future<void> _escanearQR() async {
    final String? scannedSN = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (scannedSN == null || scannedSN.isEmpty) return;

    final carga = _cargaTotal;
    if (carga != null) await carga;
    if (!mounted) return;

    const mapaSnKey = {
      'Captura': 'Numero de Serie',
      'Impresoras': 'Numero de Serie',
      'Otros': 'Numero de Serie',
      'Consumibles': 'Numero de Serie',
    };

    String? pestanaEncontrada;
    Map<String, dynamic>? activoEncontrado;

    for (var entry in _datosHojas.entries) {
      final pestana = entry.key;
      final datosPestana = entry.value;
      final snKey = mapaSnKey[pestana];

      if (snKey == null || pestana.contains('__Bajas')) continue;

      final rows = datosPestana['rows'] as List<dynamic>? ?? [];

      for (var row in rows) {
        final Map<String, dynamic> fila = Map<String, dynamic>.from(row);
        final String currentSN = fila[snKey]?.toString().trim() ?? '';

        if (currentSN.toLowerCase() == scannedSN.toLowerCase().trim()) {
          pestanaEncontrada = pestana;
          activoEncontrado = fila;
          break;
        }
      }
      if (activoEncontrado != null) break;
    }

    if (activoEncontrado != null && pestanaEncontrada != null) {
      _abrirDetalle(activoEncontrado, pestanaEncontrada);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            width: _anchoAviso(context),
            content: Text('No se encontró ningún elemento con el código: $scannedSN'),
            backgroundColor: Colors.red.shade600,
                      ),
        );
      }
    }
  }

  Future<void> _cargarDatosRemotos(
      {bool silencioso = false, bool forzar = false}) {
    final f = _cargarTodas(silencioso: silencioso, forzar: forzar);
    _cargaTotal = f;
    return f;
  }

  void _aplicarPestana(String pestana, dynamic raw, {required bool conservar}) {
    final procesado = _procesarHojaData(raw);
    final todas = Set<String>.from(procesado['headers'] as List<String>);
    final previas = _columnasPorPestana.value[pestana];
    Set<String> columnas = todas;
    if (conservar && previas != null) {
      final conservadas = previas.where(todas.contains).toSet();
      if (conservadas.isNotEmpty) columnas = conservadas;
    }
    _datosHojas[pestana] = procesado;
    _datosCambiaron();
    _columnasPorPestana.value = {..._columnasPorPestana.value, pestana: columnas};
  }

  void _avisarErrorCarga() {
    if (!mounted || AuthService.ultimoError.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: _anchoAviso(context),
        content: Text(AuthService.ultimoError),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _cargarTodas(
      {required bool silencioso, required bool forzar}) async {
    if (!silencioso) setState(() => _isLoading = true);

    final id = _inventarioActivo?.spreadsheetId ?? '';
    final prioritaria = _tabs[_tabIndex.value];
    final orden = [prioritaria, ..._tabs.where((t) => t != prioritaria)];
    final generacion = ++_generacionCarga;

    if (!silencioso) {
      _pestanasEnCarga
        ..clear()
        ..addAll(orden);
    }

    final futuros = {
      for (final t in orden) t: AuthService.obtenerPestana(id, t, forzar: forzar)
    };

    var huboError = false;

    Future<void> recibir(String t) async {
      final raw = await futuros[t]!;
      if (!mounted || generacion != _generacionCarga) return;
      _pestanasEnCarga.remove(t);
      if (raw == null) {
        huboError = true;
      } else {
        _aplicarPestana(t, raw, conservar: silencioso);
      }
      if (!silencioso && t == prioritaria) {
        setState(() => _isLoading = false);
      } else {
        setState(() {});
      }
    }

    await Future.wait(orden.map(recibir));
    if (!mounted || generacion != _generacionCarga) return;

    if (_isLoading) setState(() => _isLoading = false);

    if (!silencioso &&
        _filtroEstado.value == 'Bajas' &&
        !_datosHojas.containsKey(_dataKeyFor(_tabs[_tabIndex.value], 'Bajas'))) {
      _asegurarBajasCargadas(_tabs[_tabIndex.value]);
    }

    if (huboError) _avisarErrorCarga();
  }

  Future<void> _asegurarPestana(String pestana) async {
    if (_datosHojas.containsKey(pestana) || _pestanasEnCarga.contains(pestana)) {
      return;
    }
    _pestanasEnCarga.add(pestana);
    if (mounted) setState(() {});

    final raw = await AuthService.obtenerPestana(
        _inventarioActivo?.spreadsheetId ?? '', pestana);
    if (!mounted) return;

    _pestanasEnCarga.remove(pestana);
    if (raw != null) {
      _aplicarPestana(pestana, raw, conservar: false);
    } else {
      _avisarErrorCarga();
    }
    setState(() {});
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () {
      _searchQuery.value = val;
    });
  }

  void _mostrarSelectorColumnas(
      List<String> headersDisponibles, String dataKey) {
    String filtroColumnasQuery = '';
    Set<String> tempColumnasActivas = Set.from(
        _columnasPorPestana.value[dataKey] ?? headersDisponibles);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final headersFiltrados = headersDisponibles.where((h) {
              if (filtroColumnasQuery.isEmpty) return true;
              return h
                  .toLowerCase()
                  .contains(filtroColumnasQuery.toLowerCase());
            }).toList();

            final todasFiltradasSeleccionadas = headersFiltrados.isNotEmpty &&
                headersFiltrados.every((h) => tempColumnasActivas.contains(h));

            return _Compacto(ancho: 480, child: AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Visualizar Columnas',
                    style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                  GestureDetector(
                    onTap: () {
                      setStateDialog(() {
                        tempColumnasActivas.clear();
                        tempColumnasActivas.addAll(headersDisponibles);
                      });
                    },
                    child: const Text(
                      'Restablecer',
                      style: TextStyle(
                          color: primaryPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextField(
                        onChanged: (val) {
                          setStateDialog(() {
                            filtroColumnasQuery = val;
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'Buscar columna...',
                          hintStyle:
                              TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                          prefixIcon:
                              Icon(Icons.search, color: Color(0xFF6B7280), size: 20),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      activeColor: primaryPurple,
                      checkboxShape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      title: Text(
                        todasFiltradasSeleccionadas
                            ? 'Deseleccionar todo'
                            : 'Seleccionar todo',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: primaryPurple),
                      ),
                      value: todasFiltradasSeleccionadas,
                      onChanged: (bool? value) {
                        setStateDialog(() {
                          if (value == true) {
                            tempColumnasActivas.addAll(headersFiltrados);
                          } else {
                            tempColumnasActivas.removeAll(headersFiltrados);
                          }
                        });
                      },
                    ),
                    const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 240,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: headersFiltrados.length,
                        itemBuilder: (context, i) {
                          final header = headersFiltrados[i];
                          final isChecked =
                              tempColumnasActivas.contains(header);
                          return CheckboxListTile(
                            activeColor: primaryPurple,
                            checkboxShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                            title: Text(header,
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.black87)),
                            value: isChecked,
                            onChanged: (bool? value) {
                              setStateDialog(() {
                                if (value == true) {
                                  tempColumnasActivas.add(header);
                                } else {
                                  tempColumnasActivas.remove(header);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${tempColumnasActivas.length} seleccionadas',
                          style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            final nuevoMapa = Map<String, Set<String>>.from(
                                _columnasPorPestana.value);
                            nuevoMapa[dataKey] =
                                Set.from(tempColumnasActivas);
                            _columnasPorPestana.value = nuevoMapa;
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryPurple,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                          child: const Text('Aplicar',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ));
          },
        );
      },
    );
  }

  static const TextStyle _estiloCelda =
      TextStyle(fontSize: 14, color: Colors.black87);

  Widget _buildCellContent(String header, String valor, bool esEstatus) {
    if (esEstatus && valor.isNotEmpty) {
      final v = valor.toLowerCase().trim();
      Color color;
      Color fondo;
      if (v == 'activo' || v == 'active' || v == 'asignado') {
        color = const Color(0xFF15803D);
        fondo = const Color(0xFFDCFCE7);
      } else if (v == 'stock' || v.contains('pendiente')) {
        color = const Color(0xFF6B7280);
        fondo = const Color(0xFFF3F4F6);
      } else {
        color = const Color(0xFF4B5563);
        fondo = const Color(0xFFF3F4F6);
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                valor,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      valor,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _estiloCelda,
    );
  }

  void _abrirDetalle(Map<String, dynamic> fila, String nombrePestana,
      {bool esBaja = false}) {
    final snFila = _snDeFila(fila, nombrePestana);
    final mainData = _datosHojas[nombrePestana] ?? {'headers': [], 'rows': []};
    final mainHeaders = List<String>.from(mainData['headers'] ?? []);
    final mainRows = (mainData['rows'] as List<dynamic>?) ?? const <dynamic>[];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DeviceDetailSheet(
        fila: fila,
        nombrePestana: nombrePestana,
        spreadsheetId: _inventarioActivo?.spreadsheetId ?? '',
        headers: mainHeaders,
        existingRows: mainRows,
        inventario: _inventarioActivo,
        puedeEditar: _puedeEditar,
        esBaja: esBaja,
        onBajaExitosa: () =>
            _trasCambio(pestana: nombrePestana, sn: snFila, baja: true),
        onEditExitosa: () => _trasCambio(pestana: nombrePestana, sn: snFila),
        onRevertirExitosa: () =>
            _trasCambio(pestana: nombrePestana, sn: snFila, revertir: true),
      ),
    );
  }

  Future<void> _abrirFormularioAgregar(
      String nombrePestana, List<String> headers, List<dynamic> rows) async {
    if (headers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: _anchoAviso(context),
            content: Text('No se encontraron columnas para esta pestaña.')),
      );
      return;
    }

    final creado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddAssetScreen(
          nombrePestana: nombrePestana,
          headers: headers,
          existingRows: _filasTipadas(rows),
          inventario: _inventarioActivo,
        ),
      ),
    );

    if (creado == true && mounted) {
      _trasCambio(pestana: nombrePestana, alta: true);
    } else {
      _eventoPropioRecibido = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  RepaintBoundary(child: _buildHeaderArea()),
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  Expanded(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _tableListenable,
                        builder: (context, _) => _buildTableArea(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: _botonEscanear(),
          ),
        ],
      ),
      bottomNavigationBar: RepaintBoundary(child: _buildBottomNav()),
    );
  }

  Widget _botonEscanear() {
    return RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: primaryPurple,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: primaryPurple.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            pressedOpacity: 0.7,
            onPressed: () {
              HapticFeedback.lightImpact();
              _escanearQR();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.barcode_viewfinder,
                    color: CupertinoColors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  'Escanear QR',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _avatar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.account_circle_outlined, color: Colors.black, size: 34),
        if (_pendientes > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text(
                _pendientes > 99 ? '99+' : '$_pendientes',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _itemsMenu() {
    final u = _user;
    final items = <PopupMenuEntry<String>>[];

    if (u != null) {
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                u.nombre,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                u.correo,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: lightPurpleBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  u.rolLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: primaryPurple,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      items.add(const PopupMenuDivider(height: 1));
    }

    if (u != null && u.esAdmin) {
      items.add(
        const PopupMenuItem<String>(
          value: 'admin',
          child: Row(
            children: [
              Icon(Icons.manage_accounts_outlined,
                  color: Colors.black87, size: 20),
              SizedBox(width: 12),
              Text('Administrar cuentas',
                  style: TextStyle(color: Colors.black87, fontSize: 15)),
            ],
          ),
        ),
      );
    }

    if (_puedeAprobar) {
      items.add(
        PopupMenuItem<String>(
          value: 'solicitudes',
          child: Row(
            children: [
              const Icon(Icons.rule_folder_outlined,
                  color: Colors.black87, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Solicitudes pendientes',
                    style: TextStyle(color: Colors.black87, fontSize: 15)),
              ),
              if (_pendientes > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_pendientes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    items.add(
      const PopupMenuItem<String>(
        value: 'password',
        child: Row(
          children: [
            Icon(Icons.lock_reset_outlined, color: Colors.black87, size: 20),
            SizedBox(width: 12),
            Text('Cambiar mi contraseña',
                style: TextStyle(color: Colors.black87, fontSize: 15)),
          ],
        ),
      ),
    );

    items.add(const PopupMenuDivider(height: 1));

    items.add(
      const PopupMenuItem<String>(
        value: 'logout',
        child: Row(
          children: [
            Icon(Icons.logout, color: Color(0xFFDC2626), size: 20),
            SizedBox(width: 12),
            Text('Cerrar sesión',
                style: TextStyle(
                    color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );

    return items;
  }

  Widget _buildHeaderArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: primaryPurple, size: 26),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  const SizedBox(width: 6),
                  ValueListenableBuilder<int>(
                    valueListenable: _tabIndex,
                    builder: (context, index, _) => Text(
                      _tabs[index],
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: primaryPurple,
                      ),
                    ),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                offset: const Offset(0, 40),
                padding: EdgeInsets.zero,
                color: const Color(0xFFF3EDF7),
                elevation: 8,
                shadowColor: Colors.black38,
                surfaceTintColor: Colors.transparent,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                icon: _avatar(),
                onOpened: () {
                  if (_user == null) _cargarUsuario();
                },
                onSelected: (value) {
                  switch (value) {
                    case 'admin':
                      Navigator.pushNamed(context, '/admin');
                      break;
                    case 'solicitudes':
                      _abrirSolicitudes();
                      break;
                    case 'password':
                      _abrirCambioPassword();
                      break;
                    case 'logout':
                      _cerrarSesion();
                      break;
                  }
                },
                itemBuilder: (_) => _itemsMenu(),
              ),
            ],
          ),
          Row(
            children: [
              Flexible(
                child: Text(
                  _inventarioActivo?.nombre ?? 'Inventario',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Text(' - ', style: TextStyle(color: Colors.black54)),
              Text(
                _isLoading ? 'Cargando...' : 'Conectado',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _isLoading ? Colors.orange : const Color(0xFF16A34A),
                ),
              ),
              if (_user != null && _user!.esConsultor) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Solo lectura',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Buscar por artículo, modelo, color...',
                hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Color(0xFF6B7280)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filtros
                  .map((f) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildFiltroChip(f),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _headerListenable,
            builder: (context, _) {
              final nombrePestana = _tabs[_tabIndex.value];
              final dataKey = _dataKeyFor(nombrePestana, _filtroEstado.value);
              final pestanaData =
                  _datosHojas[dataKey] ?? {'headers': [], 'rows': []};
              final allHeaders =
                  List<String>.from(pestanaData['headers'] ?? []);

              final mainData = _datosHojas[nombrePestana] ?? {'headers': [], 'rows': []};
              final mainHeaders = List<String>.from(mainData['headers'] ?? []);
              final mainRows = (mainData['rows'] as List<dynamic>?) ?? const <dynamic>[];

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          _mostrarSelectorColumnas(allHeaders, dataKey),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune, color: Colors.black87, size: 18),
                          SizedBox(width: 6),
                          Text('Columnas',
                              style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        final (activeHeaders, filteredRows) =
                            _obtenerDatosVisibles();

                        if (activeHeaders.isEmpty || filteredRows.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              width: _anchoAviso(context),
                                content:
                                    Text('No hay datos visibles para exportar.')),
                          );
                          return;
                        }

                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => _Compacto(ancho: 460, child: _ExportarDialog(
                            nombrePestana: nombrePestana,
                            headers: activeHeaders,
                            rows: filteredRows,
                            correo: _user?.correo ?? AuthService.actorEmailSync,
                            inventario: widget.inventario?.nombre ?? '',
                          )),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_download_outlined,
                              color: Colors.black87, size: 18),
                          SizedBox(width: 6),
                          Text('Exportar',
                              style: TextStyle(
                                  color: Colors.black87, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (_puedeEditar) ...[
                      const SizedBox(width: 8),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        minSize: 0,
                        borderRadius: BorderRadius.circular(12),
                        pressedOpacity: 0.7,
                        onPressed: () => _abrirFormularioAgregar(
                            nombrePestana, mainHeaders, mainRows),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.add,
                                color: CupertinoColors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Agregar',
                              style: TextStyle(
                                color: CupertinoColors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroChip(String titulo) {
    return ValueListenableBuilder<String>(
      valueListenable: _filtroEstado,
      builder: (context, seleccionado, _) {
        final activo = seleccionado == titulo;
        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _filtroEstado.value = titulo;
            if (titulo == 'Bajas') {
              _asegurarBajasCargadas(_tabs[_tabIndex.value]);
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: activo ? lightPurpleBg : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: activo ? primaryPurple : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Text(
              titulo == 'Disponibles' && _tabs[_tabIndex.value] == 'Consumibles'
                  ? 'Stock'
                  : titulo,
              style: TextStyle(
                color: activo ? primaryPurple : const Color(0xFF4B5563),
                fontWeight: activo ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableArea() {
    final index = _tabIndex.value;
    final nombrePestana = _tabs[index];
    final filtro = _filtroEstado.value;
    final dataKey = _dataKeyFor(nombrePestana, filtro);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: primaryPurple),
      );
    }

    if (filtro != 'Bajas' && !_datosHojas.containsKey(dataKey)) {
      if (_pestanasEnCarga.contains(nombrePestana)) {
        return const Center(
          child: CircularProgressIndicator(color: primaryPurple),
        );
      }
      return Center(
        child: TextButton.icon(
          onPressed: () => _asegurarPestana(nombrePestana),
          icon: const Icon(Icons.refresh_rounded, color: primaryPurple),
          label: const Text('Reintentar carga',
              style: TextStyle(color: primaryPurple)),
        ),
      );
    }

    if (filtro == 'Bajas' && !_datosHojas.containsKey(dataKey)) {
      return const Center(
        child: CircularProgressIndicator(color: primaryPurple),
      );
    }

    final (headers, filteredRows) = _obtenerDatosVisibles();

    if (headers.isEmpty) {
      return Center(
        child: Text(
          filtro == 'Bajas'
              ? 'No hay bajas registradas en esta pestaña.'
              : 'No se encontraron datos visibles con la configuración actual.',
          style: const TextStyle(color: Colors.black54, fontSize: 14),
        ),
      );
    }

    final tableWidth = headers.length * _colWidth;
    final snHeader = _headerSn(headers, nombrePestana);
    final resaltado = _snResaltado.value;
    final claveVista = dataKey;
    final esEstatus = headers
        .map((h) {
          final l = h.toLowerCase();
          return l.contains('estatus') || l.contains('status');
        })
        .toList(growable: false);

    Widget cabecera() => Container(
          height: 44,
          decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: Color(0xFFF0F0F3), width: 1)),
          ),
          child: Row(
            children: headers
                .map((h) => SizedBox(
                      width: _colWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            h,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        );

    return ScrollConfiguration(
      behavior: const _ComportamientoTabla(),
      child: ScrollbarTheme(
        data: _temaBarras,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final anchoTabla = tableWidth < constraints.maxWidth
                ? constraints.maxWidth
                : tableWidth;

            if (filteredRows.isEmpty) {
              return SingleChildScrollView(
                key: ValueKey('h0_$claveVista'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: anchoTabla,
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      cabecera(),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Sin resultados',
                            style:
                                TextStyle(color: Colors.black45, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Scrollbar(
              controller: _vCtrl,
              interactive: true,
              notificationPredicate: (n) => n.depth == 1,
              child: Scrollbar(
                controller: _hCtrl,
                interactive: true,
                notificationPredicate: (n) => n.depth == 0,
                child: SingleChildScrollView(
                  key: ValueKey('h_$claveVista'),
                  controller: _hCtrl,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: anchoTabla,
                    height: constraints.maxHeight,
                    child: Column(
                      children: [
                        cabecera(),
                        Expanded(
                          child: ListView.builder(
                            key: ValueKey('v_$claveVista'),
                            controller: _vCtrl,
                            itemCount: filteredRows.length,
                            itemExtent: 52,
                            addAutomaticKeepAlives: false,
                            cacheExtent: 260,
                            itemBuilder: (context, i) {
                              final map = filteredRows[i] as Map;
                              final esResaltada = resaltado.isNotEmpty &&
                                  snHeader != null &&
                                  _normSn(map[snHeader]) == resaltado;
                              return Material(
                                animationDuration: Duration.zero,
                                color: esResaltada
                                    ? const Color(0xFFE9DDF7)
                                    : (i.isEven
                                        ? Colors.white
                                        : const Color(0xFFFAFAFC)),
                                child: InkWell(
                                  onTap: () => _abrirDetalle(
                                    Map<String, dynamic>.from(map),
                                    nombrePestana,
                                    esBaja: filtro == 'Bajas',
                                  ),
                                  child: Container(
                                    decoration: esResaltada
                                        ? const BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                  color: primaryPurple,
                                                  width: 4),
                                              bottom: BorderSide(
                                                  color: Color(0xFFF3F4F6),
                                                  width: 1),
                                            ),
                                          )
                                        : _bordeFila,
                                    child: Row(
                                      children: List.generate(headers.length, (c) {
                                        final h = headers[c];
                                        final valor = map[h]?.toString() ?? '';
                                        return SizedBox(
                                          width: _colWidth,
                                          child: Padding(
                                            padding: _paddingCelda,
                                            child: _buildCellContent(
                                                h, valor, esEstatus[c]),
                                          ),
                                        );
                                      }, growable: false),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    const icons = [
      (CupertinoIcons.desktopcomputer, 'Captura'),
      (CupertinoIcons.printer, 'Impresoras'),
      (Icons.storage_rounded, 'Otros'),
      (Icons.invert_colors, 'Consumibles'),
    ];

    final amplio = MediaQuery.sizeOf(context).width >= 700;
    final altoBarra = amplio ? 56.0 : 48.0;
    final tamIcono = amplio ? 21.0 : 18.0;
    final tamTexto = amplio ? 11.5 : 10.0;

    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding:
                const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 0),
            child: RepaintBoundary(
              child: Container(
                  height: altoBarra,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCFBFE),
                    borderRadius: BorderRadius.circular(29),
                    border: Border.all(color: const Color(0xFFEDE7F6)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 12,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth / icons.length;
                      return ValueListenableBuilder<int>(
                        valueListenable: _tabIndex,
                        builder: (context, current, _) {
                          return Stack(
                            children: [
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                left: itemWidth * current + 6,
                                top: 6,
                                bottom: 6,
                                width: itemWidth - 12,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: lightPurpleBg,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
                              Row(
                                children: List.generate(icons.length, (i) {
                                  final selected = current == i;
                                  final (icon, label) = icons[i];
                                  return SizedBox(
                                    width: itemWidth,
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _seleccionarPestana(i),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              icon,
                                              color: selected
                                                  ? primaryPurple
                                                  : Colors.grey.shade600,
                                              size: tamIcono,
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              label,
                                              style: TextStyle(
                                                color: selected
                                                    ? primaryPurple
                                                    : Colors.grey.shade600,
                                                fontWeight: selected
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                fontSize: tamTexto,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailField {
  final String key;
  final String label;
  const _DetailField(this.key, this.label);
}

class _DetailSection {
  final String titulo;
  final List<_DetailField> campos;
  const _DetailSection(this.titulo, this.campos);
}

class _DetailConfig {
  final List<String> tituloKeys;
  final String snKey;
  final String badge;
  final List<_DetailSection> secciones;
  const _DetailConfig({
    required this.tituloKeys,
    required this.snKey,
    required this.badge,
    required this.secciones,
  });
}

const Map<String, String> _mapaNombreBajas = {
  'Captura': 'Bajas',
  'Impresoras': 'Bajas_Impresoras',
  'Otros': 'Bajas_Otros',
  'Consumibles': 'Bajas_Consumibles',
};

const _capturaConfig = _DetailConfig(
  tituloKeys: ['Nombre Lógico del Equipo', 'Nombre'],
  snKey: 'Numero de Serie',
  badge: 'Activo',
  secciones: [
    _DetailSection('Datos generales', [
      _DetailField('Nombre', 'Nombre'),
      _DetailField('Nombre Lógico del Equipo', 'Nombre Lógico'),
      _DetailField('Ubicación', 'Ubicación'),
      _DetailField('Usuario de Dominio', 'Usuario de Dominio'),
      _DetailField('Responsable', 'Responsable'),
      _DetailField('Departamento', 'Departamento'),
    ]),
    _DetailSection('Hardware y Red', [
      _DetailField('Equipo', 'Equipo'),
      _DetailField('Modelo', 'Modelo'),
      _DetailField('Numero de Serie', 'Número de Serie'),
      _DetailField('Procesador', 'Procesador'),
      _DetailField('Disco Duro', 'Disco Duro'),
      _DetailField('Memoria', 'Memoria'),
      _DetailField('MAC Address', 'MAC Address'),
      _DetailField('IP Address', 'Dirección IP'),
    ]),
    _DetailSection('Periféricos', [
      _DetailField('Monitor', 'Monitor'),
      _DetailField('Numero de Serie (2)', 'Serie del Monitor'),
    ]),
    _DetailSection('Software y Licencias', [
      _DetailField('Sistema Operativo', 'Sistema Operativo'),
      _DetailField('Licencia1', 'Licencia 1'),
      _DetailField('Microsoft Office', 'Microsoft Office'),
      _DetailField('Licencia2', 'Licencia 2'),
      _DetailField('Productos Autodesk', 'Productos Autodesk'),
      _DetailField('Licencia3', 'Licencia 3'),
      _DetailField('Productos Adobe', 'Productos Adobe'),
      _DetailField('Licencia4', 'Licencia 4'),
      _DetailField('Otros Software', 'Otros Software'),
    ]),
    _DetailSection('Garantía', [
      _DetailField('Proveedor', 'Proveedor'),
      _DetailField('Factura', 'Factura'),
      _DetailField('Costo', 'Costo'),
      _DetailField('Fecha Adquisición', 'Fecha de Adquisición'),
      _DetailField('Años Garantía', 'Años de Garantía'),
    ]),
    _DetailSection('Arrendamiento e Historial', [
      _DetailField('Fecha/Hora', 'Fecha de Registro'),
      _DetailField('Fecha de Inicio (Arrendado)', 'Inicio de Arrendamiento'),
      _DetailField('Fecha de Vencimiento (Arrendado)', 'Vencimiento de Arrendamiento'),
      _DetailField('Numero de Contrato', 'Número de Contrato'),
      _DetailField('Comentarios', 'Comentarios'),
    ]),
  ],
);

const _impresorasConfig = _DetailConfig(
  tituloKeys: ['Nombre'],
  snKey: 'Numero de Serie',
  badge: 'Impresora',
  secciones: [
    _DetailSection('Datos generales', [
      _DetailField('Nombre', 'Nombre'),
      _DetailField('Ubicación', 'Ubicación'),
      _DetailField('Responsable', 'Responsable'),
      _DetailField('Departamento', 'Departamento'),
    ]),
    _DetailSection('Hardware y Red', [
      _DetailField('Modelo', 'Modelo'),
      _DetailField('Numero de Serie', 'Número de Serie'),
      _DetailField('Direccion IP', 'Dirección IP'),
    ]),
    _DetailSection('Detalles adicionales', [
      _DetailField('FechaRegistro', 'Fecha de Registro'),
      _DetailField('Comentarios', 'Comentarios'),
    ]),
  ],
);

const _otrosConfig = _DetailConfig(
  tituloKeys: ['Nombre'],
  snKey: 'Numero de Serie',
  badge: 'Activo',
  secciones: [
    _DetailSection('Datos generales', [
      _DetailField('Nombre', 'Nombre'),
      _DetailField('Ubicación', 'Ubicación'),
      _DetailField('Responsable', 'Responsable'),
      _DetailField('Departamento', 'Departamento'),
    ]),
    _DetailSection('Hardware y Red', [
      _DetailField('Equipo', 'Equipo'),
      _DetailField('Modelo', 'Modelo'),
      _DetailField('Numero de Serie', 'Número de Serie'),
    ]),
    _DetailSection('Detalles adicionales', [
      _DetailField('FechaRegistro', 'Fecha de Registro'),
      _DetailField('Comentarios', 'Comentarios'),
    ]),
  ],
);

const _consumiblesConfig = _DetailConfig(
  tituloKeys: ['Impresora', 'Modelo'],
  snKey: 'Numero de Serie',
  badge: 'Consumible',
  secciones: [
    _DetailSection('Información del Consumible', [
      _DetailField('Impresora', 'Impresora'),
      _DetailField('Modelo', 'Modelo'),
      _DetailField('Color', 'Color'),
      _DetailField('Tipo', 'Tipo'),
      _DetailField('Departamento', 'Departamento'),
      _DetailField('Proveedor', 'Proveedor'),
      _DetailField('Numero de Serie', 'Número de Serie'),
      _DetailField('Responsable', 'Responsable'),
      _DetailField('Fecha', 'Fecha'),
      _DetailField('Comentarios', 'Comentarios'),
    ]),
  ],
);

class _DeviceDetailSheet extends StatefulWidget {
  final Map<String, dynamic> fila;
  final String nombrePestana;
  final String spreadsheetId;
  final List<String> headers;
  final List<dynamic> existingRows;
  final InventoryModel? inventario;
  final bool puedeEditar;
  final bool esBaja;
  final VoidCallback onBajaExitosa;
  final VoidCallback onEditExitosa;
  final VoidCallback onRevertirExitosa;

  const _DeviceDetailSheet({
    required this.fila,
    required this.nombrePestana,
    required this.spreadsheetId,
    required this.headers,
    required this.existingRows,
    required this.inventario,
    required this.puedeEditar,
    required this.esBaja,
    required this.onBajaExitosa,
    required this.onEditExitosa,
    required this.onRevertirExitosa,
  });

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> {
  static const primaryPurple = Color(0xFF532E7C);

  final Set<int> _expandidas = {0};
  bool _revirtiendo = false;

  _DetailConfig get _config {
    switch (widget.nombrePestana) {
      case 'Impresoras':
        return _impresorasConfig;
      case 'Otros':
        return _otrosConfig;
      case 'Consumibles':
        return _consumiblesConfig;
      default:
        return _capturaConfig;
    }
  }

  late final Map<String, String> _clavesNorm = {
    for (final k in widget.fila.keys) _normalizarClave(k): k,
  };

  late final List<_DetailSection> _secciones = _seccionesConDatos();

  bool get _requiereAprobacion => _requiereAprobacionEn(widget.inventario);
  String get _responsableTexto => widget.inventario?.responsableEmail ?? '';

  static final RegExp _espacios = RegExp(r'\s+');
  static const Map<String, String> _acentos = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
  };

  static String _normalizarClave(String k) {
    var n = k.toLowerCase().trim();
    _acentos.forEach((a, b) {
      if (n.contains(a)) n = n.replaceAll(a, b);
    });
    n = n.replaceAll(_espacios, ' ');
    return n == 'unidad' ? 'ubicacion' : n;
  }

  String _claveReal(String key) {
    if (widget.fila.containsKey(key)) return key;
    return _clavesNorm[_normalizarClave(key)] ?? key;
  }

  String _valor(String key) {
    final v = widget.fila[_claveReal(key)];
    return v == null ? '' : v.toString().trim();
  }

  String _titulo() {
    for (final k in _config.tituloKeys) {
      final v = _valor(k);
      if (v.isNotEmpty) return v;
    }
    return 'Sin nombre';
  }

  bool _esActivo() {
    final v = _valor('Estatus').toLowerCase();
    return v == 'activo' || v == 'active' || v == 'asignado';
  }

  List<_DetailSection> _seccionesConDatos() {
    final usadas = <String>{};
    for (final s in _config.secciones) {
      for (final f in s.campos) {
        usadas.add(_claveReal(f.key));
      }
    }
    usadas.add(_claveReal(_config.snKey));
    usadas.addAll(_config.tituloKeys.map(_claveReal));
    usadas.add('Estatus');

    final resultado = _config.secciones
        .map((s) {
          final camposConDatos =
              s.campos.where((f) => _valor(f.key).isNotEmpty).toList();
          return _DetailSection(s.titulo, camposConDatos);
        })
        .where((s) => s.campos.isNotEmpty)
        .toList();

    final restantes = widget.fila.keys
        .where((k) => !usadas.contains(k) && _valor(k).isNotEmpty)
        .map((k) => _DetailField(k, k))
        .toList();

    if (restantes.isNotEmpty) {
      resultado.add(_DetailSection('Otra información', restantes));
    }

    return resultado;
  }

  Future<void> _mostrarConfirmacionBaja() async {
    final esConsumible = widget.nombrePestana == 'Consumibles';

    final motivoElegido = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _Compacto(ancho: 460, child: _ConfirmarBajaDialog(
        titulo: _titulo(),
        nombreSeccionBajas: _mapaNombreBajas[widget.nombrePestana] ?? 'Bajas',
        esConsumible: esConsumible,
        requiereAprobacion: _requiereAprobacion,
        responsable: _responsableTexto,
        onConfirmar: (motivo) {
          final sn = _valor(_config.snKey);
          return AuthService.darDeBaja(
            spreadsheetId: widget.spreadsheetId,
            pestana: widget.nombrePestana,
            sn: sn,
            motivo: motivo,
          );
        },
      )),
    );

    if (motivoElegido == null) return;
    if (!mounted) return;

    final pendiente = AuthService.ultimaRespuestaPendiente;

    if (!pendiente) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _Compacto(ancho: 420, child: _BajaExitosaDialog(
          titulo: _titulo(),
          nombreSeccionBajas: _mapaNombreBajas[widget.nombrePestana] ?? 'Bajas',
          motivo: motivoElegido,
        )),
      );
    }

    if (!mounted) return;
    Navigator.pop(context);
    widget.onBajaExitosa();
  }

  Future<void> _revertirBaja() async {
    final sn = _valor(_config.snKey);
    if (sn.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: _anchoAviso(context),
          content: Text('El elemento no tiene identificador, no se puede revertir'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _Compacto(ancho: 420, child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Revertir baja',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Text(
          '¿Regresar "${_titulo()}" a la pestaña "${widget.nombrePestana}"? Dejará de aparecer en las bajas.',
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF4B5563))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revertir',
                style: TextStyle(
                    color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
          ),
        ],
      )),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _revirtiendo = true);
    final ok = await AuthService.revertirBaja(
      spreadsheetId: widget.spreadsheetId,
      pestana: widget.nombrePestana,
      sn: sn,
    );
    if (!mounted) return;
    setState(() => _revirtiendo = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: _anchoAviso(context),
          content: Text(AuthService.ultimoError.isEmpty
              ? 'No se pudo revertir la baja'
              : AuthService.ultimoError),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    Navigator.pop(context);
    widget.onRevertirExitosa();
  }

  Future<void> _abrirEdicion() async {
    final editado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddAssetScreen(
          nombrePestana: widget.nombrePestana,
          headers: widget.headers,
          existingRows: _filasTipadas(widget.existingRows),
          inventario: widget.inventario,
          existingData: widget.fila,
        ),
      ),
    );

    if (editado == true && mounted) {
      Navigator.pop(context);
      widget.onEditExitosa();
    }
  }

  List<InventoryModel> get _destinosTransferencia {
    final user = AuthService.usuarioCache;
    final actualId = widget.inventario?.id ?? '';
    return (user?.inventarios ?? [])
        .where((i) => i.id != actualId)
        .toList();
  }

  bool get _puedeTransferir =>
      widget.puedeEditar &&
      !widget.esBaja &&
      _valor(_config.snKey).isNotEmpty &&
      _destinosTransferencia.isNotEmpty;

  Future<void> _transferir() async {
    final destino = await showDialog<InventoryModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _Compacto(ancho: 480, child: _TransferirDialog(
        titulo: _titulo(),
        inventarioActual: widget.inventario?.nombre ?? 'Inventario actual',
        pestana: widget.nombrePestana,
        destinos: _destinosTransferencia,
        requiereAprobacion: _requiereAprobacion,
        responsable: _responsableTexto,
        onConfirmar: (dest, motivo) => AuthService.transferirActivo(
          spreadsheetId: widget.spreadsheetId,
          pestana: widget.nombrePestana,
          sn: _valor(_config.snKey),
          destinoInventoryId: dest.id,
          motivo: motivo,
        ),
      )),
    );

    if (destino == null || !mounted) return;

    if (!AuthService.ultimaRespuestaPendiente) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: _anchoAviso(context),
          content: Text('Elemento transferido a ${destino.nombre}'),
          backgroundColor: Colors.green,
                  ),
      );
    }

    Navigator.pop(context);
    widget.onEditExitosa();
  }

  Future<void> _mostrarDialogoAsignar() async {
    final TextEditingController deptoController = TextEditingController(
      text: _valor('Departamento'),
    );
    bool guardandoAsignacion = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setStateDialog) {
            return _Compacto(ancho: 440, child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Asignar Consumible',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Actualiza el departamento al que se asignará este consumible:',
                      style: TextStyle(fontSize: 13, color: Colors.black54)),
                  if (_requiereAprobacion)
                    _AvisoAprobacion(
                      responsable: _responsableTexto,
                      margen: const EdgeInsets.only(top: 14),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: deptoController,
                    decoration: InputDecoration(
                      labelText: 'Departamento destino',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: guardandoAsignacion ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryPurple),
                  onPressed: guardandoAsignacion
                      ? null
                      : () async {
                          setStateDialog(() => guardandoAsignacion = true);
                          final nuevoDepto = deptoController.text.trim();

                          final datosActualizados = Map<String, String>.from(
                            widget.fila.map((k, v) => MapEntry(k, v.toString())),
                          );
                          datosActualizados['Departamento'] = nuevoDepto;
                          datosActualizados['Estatus'] = 'Asignado';

                          final snOriginal = _valor(_config.snKey);

                          final exito = await AuthService.editarActivo(
                            spreadsheetId: widget.spreadsheetId,
                            pestana: widget.nombrePestana,
                            snOriginal: snOriginal,
                            datos: datosActualizados,
                          );

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);

                          if (!mounted) return;
                          if (exito) {
                            Navigator.pop(context);
                            widget.onEditExitosa();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                width: _anchoAviso(context),
                                content: Text(AuthService.ultimoError.isEmpty
                                    ? 'Error al asignar el consumible'
                                    : AuthService.ultimoError),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        },
                  child: guardandoAsignacion
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Asignar', style: TextStyle(color: Colors.white)),
                ),
              ],
            ));
          },
        );
      },
    );

    deptoController.dispose();
  }

  Widget _chipAccion({
    required IconData icono,
    required String texto,
    required Color colorTexto,
    required Color fondo,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 14, color: colorTexto),
            const SizedBox(width: 4),
            Text(
              texto,
              style: TextStyle(
                color: colorTexto,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secciones = _secciones;
    final activo = _esActivo();
    final esConsumible = widget.nombrePestana == 'Consumibles';
    final acciones = _buildAcciones(esConsumible);

    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _titulo(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_puedeTransferir) ...[
                          _chipAccion(
                            icono: Icons.swap_horiz_rounded,
                            texto: 'Transferir',
                            colorTexto: primaryPurple,
                            fondo: const Color(0xFFEFE8F6),
                            onTap: _transferir,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (!esConsumible) ...[
                          _chipAccion(
                            icono: Icons.description_outlined,
                            texto: 'Responsiva',
                            colorTexto: const Color(0xFF3457D5),
                            fondo: const Color(0xFFE3EBFF),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ResponsivaPreviewScreen(
                                    fila: widget.fila,
                                    nombrePestana: widget.nombrePestana,
                                    inventario: widget.inventario,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3F4F6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 18, color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.esBaja)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.remove_circle_outline,
                                size: 18, color: Color(0xFFB91C1C)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _requiereAprobacion
                                    ? 'Este elemento está dado de baja. Solo el responsable del inventario puede revertir la baja.'
                                    : 'Este elemento está dado de baja. Puedes revertir la baja para regresarlo al inventario.',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF7F1D1D),
                                    height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: activo
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: activo
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF9CA3AF),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _valor('Estatus').isEmpty
                                    ? (esConsumible ? 'Stock' : 'Sin estatus')
                                    : _valor('Estatus'),
                                style: TextStyle(
                                  color: activo
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_valor(_config.snKey).isNotEmpty && !esConsumible) ...[
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'SN: ${_valor(_config.snKey)}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFF0F0F3)),
                  Expanded(
                    child: secciones.isEmpty
                        ? const Center(
                            child: Text(
                              'Sin información adicional',
                              style: TextStyle(
                                  color: Colors.black45, fontSize: 14),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: EdgeInsets.fromLTRB(
                                16, 12, 16, acciones.isEmpty ? 24 : 100),
                            itemCount: secciones.length,
                            itemBuilder: (context, index) {
                              final seccion = secciones[index];

                              if (esConsumible) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAFAFC),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: const Color(0xFFEDEDF2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        seccion.titulo,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: primaryPurple,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildCamposGrid(seccion.campos),
                                    ],
                                  ),
                                );
                              }

                              final expandida = _expandidas.contains(index);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAFAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFFEDEDF2)),
                                ),
                                child: Column(
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        setState(() {
                                          if (expandida) {
                                            _expandidas.remove(index);
                                          } else {
                                            _expandidas.add(index);
                                          }
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              seccion.titulo,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            AnimatedRotation(
                                              turns: expandida ? 0.5 : 0,
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              child: const Icon(
                                                  Icons.keyboard_arrow_down,
                                                  color: Color(0xFF6B7280)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    AnimatedSize(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      curve: Curves.easeOutCubic,
                                      alignment: Alignment.topCenter,
                                      child: expandida
                                          ? Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      16, 0, 16, 16),
                                              child: _buildCamposGrid(
                                                  seccion.campos),
                                            )
                                          : const SizedBox(
                                              width: double.infinity),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
              if (acciones.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomActions(acciones),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCamposGrid(List<_DetailField> campos) {
    final filas = <Widget>[];
    for (var i = 0; i < campos.length; i += 2) {
      final izquierdo = campos[i];
      final derecho = i + 1 < campos.length ? campos[i + 1] : null;
      filas.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCampo(izquierdo)),
              const SizedBox(width: 16),
              Expanded(
                  child: derecho != null
                      ? _buildCampo(derecho)
                      : const SizedBox()),
            ],
          ),
        ),
      );
    }
    return Column(children: filas);
  }

  Widget _buildCampo(_DetailField campo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          campo.label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF9CA3AF),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _valor(campo.key),
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _botonQr() {
    return OutlinedButton.icon(
      onPressed: () {
        final serialNumber = _valor(_config.snKey);
        final serialFinal =
            serialNumber.isNotEmpty ? serialNumber : 'NA-00000000';

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QrViewScreen(
              serialNumber: serialFinal,
              nombreActivo: _titulo(),
            ),
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryPurple,
        side: const BorderSide(color: primaryPurple),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: const Icon(Icons.qr_code_rounded, size: 18),
      label: const Text('Ver QR',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  List<Widget> _buildAcciones(bool esConsumible) {
    final acciones = <Widget>[];

    if (widget.esBaja) {
      if (!esConsumible) acciones.add(_botonQr());
      if (widget.puedeEditar && !_requiereAprobacion) {
        acciones.add(
          ElevatedButton.icon(
            onPressed: _revirtiendo ? null : _revertirBaja,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: _revirtiendo
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Revertir baja',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        );
      }
      return acciones;
    }

    if (widget.puedeEditar &&
        esConsumible &&
        _valor('Estatus').toLowerCase() == 'stock') {
      acciones.add(
        ElevatedButton.icon(
          onPressed: _mostrarDialogoAsignar,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.assignment_ind_outlined, size: 18),
          label: const Text('Asignar',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      );
    }

    if (!esConsumible) {
      acciones.add(_botonQr());
    }

    if (widget.puedeEditar) {
      acciones.add(
        ElevatedButton.icon(
          onPressed: _abrirEdicion,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryPurple,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Editar',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      );

      acciones.add(
        OutlinedButton.icon(
          onPressed: _mostrarConfirmacionBaja,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            side: const BorderSide(color: Color(0xFFF3D6D6)),
            backgroundColor: const Color(0xFFFEF2F2),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          label: const Text('Baja',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      );
    }

    return acciones;
  }

  Widget _buildBottomActions(List<Widget> acciones) {
    final hijos = <Widget>[];
    for (var i = 0; i < acciones.length; i++) {
      if (i > 0) hijos.add(const SizedBox(width: 10));
      hijos.add(Expanded(child: acciones[i]));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F3))),
      ),
      child: Row(children: hijos),
    );
  }
}

class _ConfirmarBajaDialog extends StatefulWidget {
  final String titulo;
  final String nombreSeccionBajas;
  final bool esConsumible;
  final bool requiereAprobacion;
  final String responsable;
  final Future<bool> Function(String motivo) onConfirmar;

  const _ConfirmarBajaDialog({
    required this.titulo,
    required this.nombreSeccionBajas,
    required this.esConsumible,
    required this.onConfirmar,
    this.requiereAprobacion = false,
    this.responsable = '',
  });

  @override
  State<_ConfirmarBajaDialog> createState() => _ConfirmarBajaDialogState();
}

class _ConfirmarBajaDialogState extends State<_ConfirmarBajaDialog> {
  static const primaryPurple = Color(0xFF532E7C);

  static const List<String> _motivosEquipo = [
    'Fin de vida útil / Obsolescencia tecnológica',
    'Fin de arrendamiento',
    'Robo o extravío',
    'Falla de hardware irreparable',
    'Venta o donación',
    'Otro',
  ];

  static const List<String> _motivosConsumible = [
    'Consumible agotado / Vencido',
    'Merma o daño',
    'Otro',
  ];

  late final List<String> _motivos;
  late String _motivoSeleccionado;
  final TextEditingController _otroController = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _motivos = widget.esConsumible ? _motivosConsumible : _motivosEquipo;
    _motivoSeleccionado = _motivos.first;
  }

  @override
  void dispose() {
    _otroController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    String motivoFinal = _motivoSeleccionado;
    if (_motivoSeleccionado == 'Otro') {
      final textoExtra = _otroController.text.trim();
      motivoFinal = textoExtra.isEmpty ? 'Otro (Sin especificar)' : 'Otro: $textoExtra';
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    final exito = await widget.onConfirmar(motivoFinal);
    if (!mounted) return;

    if (exito) {
      Navigator.pop(context, motivoFinal);
    } else {
      setState(() {
        _cargando = false;
        _error = AuthService.ultimoError.isEmpty
            ? 'No se pudo dar de baja el registro'
            : AuthService.ultimoError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 540,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2), shape: BoxShape.circle),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFDC2626), size: 28),
                ),
                const SizedBox(height: 16),
                const Text(
                  '¿Dar de baja el elemento?',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
                    children: [
                      const TextSpan(text: 'El registro '),
                      TextSpan(
                        text: widget.titulo,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const TextSpan(text: ' se moverá a la sección '),
                      TextSpan(
                        text: '"${widget.nombreSeccionBajas}"',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626)),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
                if (widget.requiereAprobacion)
                  _AvisoAprobacion(
                    responsable: widget.responsable,
                    margen: const EdgeInsets.only(top: 14),
                  ),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Motivo de la baja',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280)),
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _motivoSeleccionado,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: Colors.white,
                  elevation: 8,
                  menuMaxHeight: 300,
                  focusColor: Colors.transparent,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  iconEnabledColor: const Color(0xFF6B7280),
                  items: _motivos
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: _cargando
                      ? null
                      : (v) {
                          if (v != null) {
                            setState(() => _motivoSeleccionado = v);
                          }
                        },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: primaryPurple, width: 1.5),
                    ),
                  ),
                ),
                if (_motivoSeleccionado == 'Otro') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _otroController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Especifique el motivo o comentario detallado...',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: Color(0xFF9CA3AF)),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: primaryPurple, width: 1.5),
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style:
                        const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _cargando ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('Cancelar',
                            style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _confirmar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: _cargando
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Sí, dar de baja',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BajaExitosaDialog extends StatelessWidget {
  final String titulo;
  final String nombreSeccionBajas;
  final String motivo;

  const _BajaExitosaDialog({
    required this.titulo,
    required this.nombreSeccionBajas,
    required this.motivo,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                        color: Color(0xFFFEE2E2), shape: BoxShape.circle),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFDC2626), size: 28),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '¡Elemento dado de baja!',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
                children: [
                  const TextSpan(text: 'El registro '),
                  TextSpan(
                    text: titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const TextSpan(
                      text: ' ha sido removido y se movió a la sección '),
                  TextSpan(
                    text: '"$nombreSeccionBajas"',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF15803D)),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF0F0F3)),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  children: [
                    const TextSpan(text: 'Motivo registrado: '),
                    TextSpan(
                      text: motivo,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF532E7C),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Entendido',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferirDialog extends StatefulWidget {
  final String titulo;
  final String inventarioActual;
  final String pestana;
  final List<InventoryModel> destinos;
  final Future<bool> Function(InventoryModel destino, String motivo) onConfirmar;
  final bool requiereAprobacion;
  final String responsable;

  const _TransferirDialog({
    required this.titulo,
    required this.inventarioActual,
    required this.pestana,
    required this.destinos,
    required this.onConfirmar,
    this.requiereAprobacion = false,
    this.responsable = '',
  });

  @override
  State<_TransferirDialog> createState() => _TransferirDialogState();
}

class _TransferirDialogState extends State<_TransferirDialog> {
  static const primaryPurple = Color(0xFF532E7C);

  InventoryModel? _destino;
  final TextEditingController _motivoCtrl = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final destino = _destino;
    if (destino == null) {
      setState(() => _error = 'Selecciona el inventario destino');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    final exito = await widget.onConfirmar(destino, _motivoCtrl.text.trim());
    if (!mounted) return;

    if (exito) {
      Navigator.pop(context, destino);
    } else {
      setState(() {
        _cargando = false;
        _error = AuthService.ultimoError.isEmpty
            ? 'No se pudo transferir el elemento'
            : AuthService.ultimoError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                      color: Color(0xFFEFE8F6), shape: BoxShape.circle),
                  child: const Icon(Icons.swap_horiz_rounded,
                      color: primaryPurple, size: 30),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Transferir elemento',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(height: 8),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
                    children: [
                      TextSpan(
                        text: widget.titulo,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const TextSpan(text: ' saldrá de '),
                      TextSpan(
                        text: widget.inventarioActual,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                          text: ' y pasará a la pestaña "${widget.pestana}" del inventario que elijas.'),
                    ],
                  ),
                ),
                if (widget.requiereAprobacion)
                  _AvisoAprobacion(
                    responsable: widget.responsable,
                    margen: const EdgeInsets.only(top: 14),
                  ),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Inventario destino',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280)),
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<InventoryModel>(
                  initialValue: _destino,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: Colors.white,
                  elevation: 8,
                  menuMaxHeight: 300,
                  focusColor: Colors.transparent,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  iconEnabledColor: const Color(0xFF6B7280),
                  hint: const Text('Seleccionar inventario...',
                      style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                  items: widget.destinos
                      .map((i) => DropdownMenuItem<InventoryModel>(
                            value: i,
                            child: Text(
                              i.ubicacion.isNotEmpty
                                  ? '${i.nombre}  ·  ${i.ubicacion}'
                                  : i.nombre,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ))
                      .toList(),
                  onChanged: _cargando
                      ? null
                      : (v) => setState(() {
                            _destino = v;
                            _error = null;
                          }),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: primaryPurple, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _motivoCtrl,
                  maxLines: 2,
                  enabled: !_cargando,
                  decoration: InputDecoration(
                    hintText: 'Motivo de la transferencia (opcional)',
                    hintStyle: const TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: primaryPurple, width: 1.5),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style:
                        const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _cargando ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('Cancelar',
                            style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _confirmar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryPurple,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: _cargando
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Transferir',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportarDialog extends StatefulWidget {
  final String nombrePestana;
  final List<String> headers;
  final List<dynamic> rows;
  final String correo;
  final String inventario;

  const _ExportarDialog({
    required this.nombrePestana,
    required this.headers,
    required this.rows,
    required this.correo,
    this.inventario = '',
  });

  @override
  State<_ExportarDialog> createState() => _ExportarDialogState();
}

class _ExportarDialogState extends State<_ExportarDialog> {
  static const primaryPurple = Color(0xFF532E7C);
  bool _isProcessing = false;
  String? _error;

  Future<void> _procesarExcel(bool descargar) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Reporte');
    final sheet = excel['Reporte'];

    sheet.appendRow(widget.headers.map((h) => TextCellValue(h)).toList());

    for (var row in widget.rows) {
      if (row is Map) {
        final rowData = widget.headers
            .map((h) => TextCellValue(row[h]?.toString() ?? ''))
            .toList();
        sheet.appendRow(rowData);
      }
    }

    final bytes = excel.encode()!;

    if (descargar) {
      if (kIsWeb) {
        final base64data = base64Encode(bytes);
        final a = html.AnchorElement(
            href:
                'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64data');
        a.download = 'Reporte_${widget.nombrePestana}.xlsx';
        a.click();
        a.remove();
      } else {
        final xfile = XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: 'Reporte_${widget.nombrePestana}.xlsx',
        );
        await Share.shareXFiles([xfile],
            text: 'Reporte: ${widget.nombrePestana}');
      }

      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.pop(context);
      }
    } else {
      final enviado = await AuthService.enviarReporteCorreo(
        pestana: widget.nombrePestana,
        archivo: 'Reporte_${widget.nombrePestana}.xlsx',
        inventario: widget.inventario,
        bytes: bytes,
      );

      if (!mounted) return;
      if (enviado) {
        setState(() => _isProcessing = false);
        Navigator.pop(context);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _Compacto(ancho: 420, child: _ExitoExportarDialog(correo: widget.correo)),
        );
      } else {
        setState(() {
          _isProcessing = false;
          _error = AuthService.ultimoError.isEmpty
              ? 'No se pudo enviar el correo. Intenta de nuevo.'
              : AuthService.ultimoError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final correo = widget.correo.isEmpty ? 'tu correo registrado' : widget.correo;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('X',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Exportar reporte',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      Text('Archivo Excel (.xlsx)',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF16A34A))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Se generará el reporte con las columnas seleccionadas. Puedes descargarlo o enviarlo a tu correo registrado:',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFCFAFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE9E0F2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mail_outline, color: primaryPurple, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(correo,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: primaryPurple,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFFDC2626), height: 1.4)),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed:
                      _isProcessing ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Cancelar',
                      style: TextStyle(
                          color: Colors.black54, fontWeight: FontWeight.w600)),
                ),
                OutlinedButton(
                  onPressed: _isProcessing ? null : () => _procesarExcel(true),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: primaryPurple),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: primaryPurple))
                      : const Text('Descargar',
                          style: TextStyle(
                              color: primaryPurple,
                              fontWeight: FontWeight.w600)),
                ),
                ElevatedButton(
                  onPressed: _isProcessing ? null : () => _procesarExcel(false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Enviar correo',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExitoExportarDialog extends StatelessWidget {
  final String correo;

  const _ExitoExportarDialog({required this.correo});

  static const primaryPurple = Color(0xFF532E7C);

  @override
  Widget build(BuildContext context) {
    final texto = correo.isEmpty ? 'tu correo registrado' : correo;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.mail_outline_rounded,
                    size: 64, color: primaryPurple),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF16A34A),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child:
                        const Icon(Icons.check, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Reporte enviado exitosamente!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 12),
            const Text(
              'El archivo Excel (.xlsx) ha sido generado y enviado como archivo adjunto a tu correo registrado:',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryPurple),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mail_outline, color: primaryPurple, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(texto,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: primaryPurple,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPurple,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Entendido',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComportamientoTabla extends MaterialScrollBehavior {
  const _ComportamientoTabla();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

class _Compacto extends StatelessWidget {
  final double ancho;
  final Widget child;
  const _Compacto({required this.ancho, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancho + 48),
        child: child,
      ),
    );
  }
}