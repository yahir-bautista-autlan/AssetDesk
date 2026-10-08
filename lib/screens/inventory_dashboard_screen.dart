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

bool _avisarSiPendiente(BuildContext context) {
  if (!AuthService.ultimaRespuestaPendiente) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(AuthService.ultimoMensaje.isEmpty
          ? 'Tu cambio fue enviado al responsable del inventario para su aprobación.'
          : AuthService.ultimoMensaje),
      backgroundColor: const Color(0xFFF59E0B),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
    ),
  );
  return true;
}

class InventoryDashboardScreen extends StatefulWidget {
  final InventoryModel? inventario;

  const InventoryDashboardScreen({super.key, this.inventario});

  @override
  State<InventoryDashboardScreen> createState() =>
      _InventoryDashboardScreenState();
}

class _InventoryDashboardScreenState extends State<InventoryDashboardScreen> {
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

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _isLoading = true;
  Map<String, dynamic> _datosHojas = {};
  final Set<String> _bajasEnCarga = {};
  InventoryModel? _inventarioActivo;
  UserModel? _user;
  int _pendientes = 0;

  late final Listenable _headerListenable =
      Listenable.merge([_tabIndex, _filtroEstado]);
  late final Listenable _tableListenable = Listenable.merge(
      [_tabIndex, _searchQuery, _filtroEstado, _columnasPorPestana]);

  bool get _puedeEditar => _user?.puedeEditar ?? AuthService.puedeEditar;

  bool get _puedeAprobar {
    final u = _user;
    if (u == null) return false;
    return u.esAdmin || u.inventarios.any((i) => i.esResponsable(u.correo));
  }

  @override
  void initState() {
    super.initState();
    _inventarioActivo = widget.inventario;
    _cargarUsuario();
    _cargarDatosRemotos();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tabIndex.dispose();
    _searchQuery.dispose();
    _filtroEstado.dispose();
    _columnasPorPestana.dispose();
    super.dispose();
  }

  Future<void> _cargarUsuario() async {
    final u = await AuthService.obtenerUsuarioActual();
    if (!mounted) return;
    setState(() => _user = u);
    if (_puedeAprobar) _cargarPendientes();
  }

  Future<void> _cargarPendientes() async {
    final lista = await AuthService.obtenerSolicitudesPendientes();
    if (!mounted) return;
    setState(() => _pendientes = lista.length);
  }

  Future<void> _abrirSolicitudes() async {
    final cambios = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SolicitudesPendientesScreen()),
    );
    if (!mounted) return;
    if (cambios == true) _cargarDatosRemotos();
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
        const SnackBar(
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

  void _trasCambio() {
    if (mounted) _avisarSiPendiente(context);
    _cargarDatosRemotos();
    if (_puedeAprobar) _cargarPendientes();
  }

  String _dataKeyFor(String nombrePestana, String filtro) {
    return filtro == 'Bajas' ? '${nombrePestana}__Bajas' : nombrePestana;
  }

  Map<String, dynamic> _procesarHojaData(dynamic dataRaw) {
    if (dataRaw is! Map || dataRaw['headers'] == null) {
      return {'headers': <String>[], 'rows': <dynamic>[]};
    }

    final data = Map<String, dynamic>.from(dataRaw);
    final List<dynamic> rawHeaders = List<dynamic>.from(data['headers']);
    final List<String> uniqueHeaders = [];
    final Map<String, int> conteoNombres = {};

    for (var h in rawHeaders) {
      final limpio = h.toString().trim();
      if (limpio.isEmpty) continue;

      if (conteoNombres.containsKey(limpio)) {
        conteoNombres[limpio] = conteoNombres[limpio]! + 1;
        uniqueHeaders.add('$limpio (${conteoNombres[limpio]})');
      } else {
        conteoNombres[limpio] = 1;
        uniqueHeaders.add(limpio);
      }
    }

    final List<dynamic> rows = List<dynamic>.from(data['rows'] ?? []);
    final List<dynamic> rawOriginalHeaders = List<dynamic>.from(rawHeaders);

    final resultRows = <dynamic>[];
    for (var row in rows) {
      if (row is Map) {
        final Map<String, dynamic> rowMap = Map<String, dynamic>.from(row);
        final Map<String, int> conteoFila = {};

        for (int i = 0; i < uniqueHeaders.length; i++) {
          final originalName = rawOriginalHeaders.length > i
              ? rawOriginalHeaders[i].toString().trim()
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

  Future<void> _asegurarBajasCargadas(String nombrePestana) async {
    final key = _dataKeyFor(nombrePestana, 'Bajas');
    if (_datosHojas.containsKey(key) || _bajasEnCarga.contains(key)) return;

    _bajasEnCarga.add(key);
    if (mounted) setState(() {});

    final sheetIdOrName = _inventarioActivo?.spreadsheetId ?? '';
    final dataRaw = await AuthService.obtenerHojaBajas(sheetIdOrName, nombrePestana);
    final procesado = _procesarHojaData(dataRaw);

    _bajasEnCarga.remove(key);
    if (!mounted) return;

    setState(() {
      _datosHojas[key] = procesado;
    });

    final nuevoMapa = Map<String, Set<String>>.from(_columnasPorPestana.value);
    nuevoMapa[key] = Set<String>.from(procesado['headers'] as List<String>);
    _columnasPorPestana.value = nuevoMapa;
  }

  (List<String>, List<dynamic>) _obtenerDatosVisibles() {
    final index = _tabIndex.value;
    final nombrePestana = _tabs[index];
    final filtro = _filtroEstado.value;
    final dataKey = _dataKeyFor(nombrePestana, filtro);

    final pestanaData = _datosHojas[dataKey] ?? {'headers': [], 'rows': []};

    final allHeaders = List<String>.from(pestanaData['headers'] ?? []);
    final Set<String> activasSet = _columnasPorPestana.value[dataKey] ?? allHeaders.toSet();
    final List<String> headers = allHeaders.where((h) => activasSet.contains(h)).toList();

    final List<dynamic> rows = List<dynamic>.from(pestanaData['rows'] ?? []);
    final query = _searchQuery.value.toLowerCase().trim();

    final filteredRows = rows.where((row) {
      if (row is! Map) return false;

      if (filtro == 'Asignados' || filtro == 'Disponibles') {
        String estatusValor = '';
        row.forEach((k, v) {
          if (k.toString().toLowerCase().trim() == 'estatus') {
            estatusValor = v.toString().toLowerCase().trim();
          }
        });

        if (nombrePestana == 'Consumibles') {
          if (filtro == 'Asignados' && estatusValor != 'asignado') return false;
          if (filtro == 'Disponibles' && estatusValor != 'stock') return false;
        } else {
          if (filtro == 'Asignados' && estatusValor != 'activo') return false;
          if (filtro == 'Disponibles' && estatusValor != 'pendiente de asignar') return false;
        }
      }

      if (query.isEmpty) return true;
      return row.entries.any((entry) => entry.value.toString().toLowerCase().contains(query));
    }).toList();

    return (headers, filteredRows);
  }

  Future<void> _escanearQR() async {
    final String? scannedSN = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (scannedSN == null || scannedSN.isEmpty) return;

    const mapaSnKey = {
      'Captura': 'Numero de Serie',
      'Impresoras': 'Num. de Serie',
      'Otros': 'NoSerie',
      'Consumibles': 'Numero de serie',
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
            content: Text('No se encontró ningún elemento con el código: $scannedSN'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _cargarDatosRemotos() async {
    setState(() => _isLoading = true);

    final sheetIdOrName = _inventarioActivo?.spreadsheetId ?? '';
    final resultado = await AuthService.obtenerDatosInventario(sheetIdOrName);

    if (!mounted) return;

    final datosProcesados = <String, dynamic>{};
    final columnasIniciales = <String, Set<String>>{};

    resultado.forEach((pestana, data) {
      final procesado = _procesarHojaData(data);
      datosProcesados[pestana] = procesado;
      columnasIniciales[pestana] = Set<String>.from(procesado['headers'] as List<String>);
    });

    setState(() {
      _datosHojas = datosProcesados;
      _bajasEnCarga.clear();
      _isLoading = false;
    });
    _columnasPorPestana.value = columnasIniciales;

    if (resultado.isEmpty && AuthService.ultimoError.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.ultimoError),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
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

            return AlertDialog(
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
            );
          },
        );
      },
    );
  }

  Widget _buildCellContent(String header, String valor) {
    final h = header.toLowerCase();
    final v = valor.toLowerCase().trim();
    final esEstatus = h.contains('estatus') || h.contains('status');

    if (esEstatus && v.isNotEmpty) {
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
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
    );
  }

  void _abrirDetalle(Map<String, dynamic> fila, String nombrePestana) {
    final mainData = _datosHojas[nombrePestana] ?? {'headers': [], 'rows': []};
    final mainHeaders = List<String>.from(mainData['headers'] ?? []);
    final mainRows = List<dynamic>.from(mainData['rows'] ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

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
        onBajaExitosa: _trasCambio,
        onEditExitosa: _trasCambio,
      ),
    );
  }

  Future<void> _abrirFormularioAgregar(
      String nombrePestana, List<String> headers, List<dynamic> rows) async {
    if (headers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
          existingRows: rows
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList(),
          inventario: _inventarioActivo,
        ),
      ),
    );

    if (creado == true && mounted) {
      _trasCambio();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
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
      floatingActionButton: RepaintBoundary(
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
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: RepaintBoundary(child: _buildBottomNav()),
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
              PopupMenuButton<String>(
                offset: const Offset(0, 40),
                padding: EdgeInsets.zero,
                color: const Color(0xFFF3EDF7),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              final mainRows = List<dynamic>.from(mainData['rows'] ?? []);

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
                            const SnackBar(
                                content:
                                    Text('No hay datos visibles para exportar.')),
                          );
                          return;
                        }

                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => _ExportarDialog(
                            nombrePestana: nombrePestana,
                            headers: activeHeaders,
                            rows: filteredRows,
                            correo: _user?.correo ?? AuthService.actorEmailSync,
                          ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth < constraints.maxWidth
                ? constraints.maxWidth
                : tableWidth,
            height: constraints.maxHeight,
            child: Column(
              children: [
                Container(
                  height: 44,
                  decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Color(0xFFF0F0F3), width: 1)),
                  ),
                  child: Row(
                    children: headers
                        .map((h) => SizedBox(
                              width: _colWidth,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
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
                ),
                Expanded(
                  child: filteredRows.isEmpty
                      ? const Center(
                          child: Text(
                            'Sin resultados',
                            style:
                                TextStyle(color: Colors.black45, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredRows.length,
                          itemExtent: 52,
                          itemBuilder: (context, i) {
                            final map = filteredRows[i] as Map;
                            return Material(
                              color: i.isEven
                                  ? Colors.white
                                  : const Color(0xFFFAFAFC),
                              child: InkWell(
                                onTap: () => _abrirDetalle(
                                    Map<String, dynamic>.from(map),
                                    nombrePestana),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                          color: Color(0xFFF3F4F6), width: 1),
                                    ),
                                  ),
                                  child: Row(
                                    children: headers.map((h) {
                                      final valor = map[h]?.toString() ?? '';
                                      return SizedBox(
                                        width: _colWidth,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: _buildCellContent(h, valor),
                                          ),
                                        ),
                                      );
                                    }).toList(),
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
        );
      },
    );
  }

  Widget _buildBottomNav() {
    final icons = [
      (CupertinoIcons.desktopcomputer, 'Captura'),
      (CupertinoIcons.printer, 'Impresoras'),
      (Icons.storage_rounded, 'Otros'),
      (Icons.invert_colors, 'Consumibles'),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6, top: 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(29),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.75),
                borderRadius: BorderRadius.circular(29),
                border: Border.all(color: Colors.white.withOpacity(0.6)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
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
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    if (current != i) {
                                      HapticFeedback.selectionClick();
                                      _tabIndex.value = i;
                                      if (_filtroEstado.value == 'Bajas') {
                                        _asegurarBajasCargadas(_tabs[i]);
                                      }
                                    }
                                  },
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        icon,
                                        color: selected
                                            ? primaryPurple
                                            : Colors.grey.shade600,
                                        size: 18,
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
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
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
  snKey: 'Num. de Serie',
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
      _DetailField('Num. de Serie', 'Número de Serie'),
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
  snKey: 'NoSerie',
  badge: 'Activo',
  secciones: [
    _DetailSection('Datos generales', [
      _DetailField('Nombre', 'Nombre'),
      _DetailField('Unidad', 'Unidad'),
      _DetailField('Responsable', 'Responsable'),
      _DetailField('Departamento', 'Departamento'),
    ]),
    _DetailSection('Hardware y Red', [
      _DetailField('Equipo', 'Equipo'),
      _DetailField('Modelo', 'Modelo'),
      _DetailField('NoSerie', 'Número de Serie'),
    ]),
    _DetailSection('Detalles adicionales', [
      _DetailField('FechaRegistro', 'Fecha de Registro'),
      _DetailField('Comentarios', 'Comentarios'),
    ]),
  ],
);

const _consumiblesConfig = _DetailConfig(
  tituloKeys: ['Impresora', 'Modelo'],
  snKey: 'Numero de serie',
  badge: 'Consumible',
  secciones: [
    _DetailSection('Información del Consumible', [
      _DetailField('Impresora', 'Impresora'),
      _DetailField('Modelo', 'Modelo'),
      _DetailField('Color', 'Color'),
      _DetailField('Tipo', 'Tipo'),
      _DetailField('Departamento', 'Departamento'),
      _DetailField('Proveedor', 'Proveedor'),
      _DetailField('Numero de serie', 'Número de Serie'),
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
  final List<Map<String, dynamic>> existingRows;
  final InventoryModel? inventario;
  final bool puedeEditar;
  final VoidCallback onBajaExitosa;
  final VoidCallback onEditExitosa;

  const _DeviceDetailSheet({
    required this.fila,
    required this.nombrePestana,
    required this.spreadsheetId,
    required this.headers,
    required this.existingRows,
    required this.inventario,
    required this.puedeEditar,
    required this.onBajaExitosa,
    required this.onEditExitosa,
  });

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> {
  static const primaryPurple = Color(0xFF532E7C);

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

  String _valor(String key) {
    final v = widget.fila[key];
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
        usadas.add(f.key);
      }
    }
    usadas.add(_config.snKey);
    usadas.addAll(_config.tituloKeys);
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
      builder: (dialogContext) => _ConfirmarBajaDialog(
        titulo: _titulo(),
        nombreSeccionBajas: _mapaNombreBajas[widget.nombrePestana] ?? 'Bajas',
        esConsumible: esConsumible,
        onConfirmar: (motivo) {
          final sn = _valor(_config.snKey);
          return AuthService.darDeBaja(
            spreadsheetId: widget.spreadsheetId,
            pestana: widget.nombrePestana,
            sn: sn,
            motivo: motivo,
          );
        },
      ),
    );

    if (motivoElegido == null) return;
    if (!mounted) return;

    final pendiente = AuthService.ultimaRespuestaPendiente;

    if (!pendiente) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _BajaExitosaDialog(
          titulo: _titulo(),
          nombreSeccionBajas: _mapaNombreBajas[widget.nombrePestana] ?? 'Bajas',
          motivo: motivoElegido,
        ),
      );
    }

    if (!mounted) return;
    Navigator.pop(context);
    widget.onBajaExitosa();
  }

  Future<void> _abrirEdicion() async {
    final editado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddAssetScreen(
          nombrePestana: widget.nombrePestana,
          headers: widget.headers,
          existingRows: widget.existingRows,
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
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Asignar Consumible',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Actualiza el departamento al que se asignará este consumible:',
                      style: TextStyle(fontSize: 13, color: Colors.black54)),
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
            );
          },
        );
      },
    );

    deptoController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secciones = _seccionesConDatos();
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _titulo(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (!esConsumible) ...[
                          InkWell(
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
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3EBFF),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.description_outlined,
                                      size: 14, color: Color(0xFF3457D5)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Responsiva',
                                    style: TextStyle(
                                      color: Color(0xFF3457D5),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAFAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFFEDEDF2)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        seccion.titulo,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: esConsumible
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          color: esConsumible
                                              ? primaryPurple
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildCamposGrid(seccion.campos),
                                    ],
                                  ),
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

  List<Widget> _buildAcciones(bool esConsumible) {
    final acciones = <Widget>[];

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
      acciones.add(
        OutlinedButton.icon(
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.qr_code_rounded, size: 18),
          label: const Text('Ver QR',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      );
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
  final Future<bool> Function(String motivo) onConfirmar;

  const _ConfirmarBajaDialog({
    required this.titulo,
    required this.nombreSeccionBajas,
    required this.esConsumible,
    required this.onConfirmar,
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

class _ExportarDialog extends StatefulWidget {
  final String nombrePestana;
  final List<String> headers;
  final List<dynamic> rows;
  final String correo;

  const _ExportarDialog({
    required this.nombrePestana,
    required this.headers,
    required this.rows,
    required this.correo,
  });

  @override
  State<_ExportarDialog> createState() => _ExportarDialogState();
}

class _ExportarDialogState extends State<_ExportarDialog> {
  static const primaryPurple = Color(0xFF532E7C);
  bool _isProcessing = false;

  Future<void> _procesarExcel(bool descargar) async {
    setState(() => _isProcessing = true);
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
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.pop(context);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _ExitoExportarDialog(correo: widget.correo),
        );
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
              'El archivo Excel (.xlsx) ha sido generado. Un enlace para descargarlo ha sido enviado a tu correo registrado:',
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