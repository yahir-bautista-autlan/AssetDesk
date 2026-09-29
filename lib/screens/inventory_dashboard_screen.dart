import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/auth_service.dart';

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
  static const List<String> _tabs = ['Captura', 'Impresoras', 'Otros'];
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
  InventoryModel? _inventarioActivo;

  late final Listenable _headerListenable =
      Listenable.merge([_tabIndex, _filtroEstado]);
  late final Listenable _tableListenable = Listenable.merge(
      [_tabIndex, _searchQuery, _filtroEstado, _columnasPorPestana]);

  @override
  void initState() {
    super.initState();
    _inventarioActivo = widget.inventario;
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

  String _dataKeyFor(String nombrePestana, String filtro) {
    return filtro == 'Bajas' ? '${nombrePestana}__Bajas' : nombrePestana;
  }

  Future<void> _cargarDatosRemotos() async {
    setState(() => _isLoading = true);

    final sheetIdOrName = _inventarioActivo?.spreadsheetId ?? '';
    final resultado = await AuthService.obtenerDatosInventario(sheetIdOrName);

    if (!mounted) return;

    final columnasIniciales = <String, Set<String>>{};

    resultado.forEach((pestana, data) {
      if (data is Map && data['headers'] != null) {
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

        data['headers'] = uniqueHeaders;

        if (data['rows'] is List) {
          final List<dynamic> rows = data['rows'];
          final List<dynamic> rawOriginalHeaders = List<dynamic>.from(rawHeaders);

          for (var row in rows) {
            if (row is Map) {
              final Map<String, dynamic> rowMap =
                  Map<String, dynamic>.from(row);
              final Map<String, int> conteoFila = {};

              for (int i = 0; i < uniqueHeaders.length; i++) {
                final originalName = rawOriginalHeaders.length > i ? rawOriginalHeaders[i].toString().trim() : '';
                final assignedName = uniqueHeaders[i];

                if (originalName.isNotEmpty && rowMap.containsKey(originalName)) {
                  final val = rowMap[originalName];
                  conteoFila[originalName] = (conteoFila[originalName] ?? 0) + 1;

                  if (conteoFila[originalName]! > 1) {
                    rowMap[assignedName] = val;
                  }
                }
              }
              row.clear();
              row.addAll(rowMap);
            }
          }
        }

        columnasIniciales[pestana] = uniqueHeaders.toSet();
      }
    });

    setState(() {
      _datosHojas = resultado;
      _isLoading = false;
    });
    _columnasPorPestana.value = columnasIniciales;
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
      if (v == 'activo' || v == 'active') {
        color = const Color(0xFF15803D);
        fondo = const Color(0xFFDCFCE7);
      } else if (v.contains('pendiente')) {
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

  _DetailConfig _configPorPestana(String nombrePestana) {
    switch (nombrePestana) {
      case 'Impresoras':
        return _impresorasConfig;
      case 'Otros':
        return _otrosConfig;
      default:
        return _capturaConfig;
    }
  }

  void _abrirDetalle(Map<String, dynamic> fila, String nombrePestana) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DeviceDetailSheet(
        fila: fila,
        config: _configPorPestana(nombrePestana),
        nombrePestana: nombrePestana,
        spreadsheetId: _inventarioActivo?.spreadsheetId ?? '',
        onBajaExitosa: _cargarDatosRemotos,
      ),
    );
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
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                icon: const Icon(Icons.account_circle_outlined,
                    color: Colors.black, size: 34),
                onSelected: (value) async {
                  if (value == 'logout') {
                    await AuthService.logout();
                    if (!context.mounted) return;
                    Navigator.pushNamedAndRemoveUntil(
                        context, '/login', (route) => false);
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Color(0xFFDC2626), size: 20),
                        SizedBox(width: 12),
                        Text(
                          'Cerrar sesión',
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Text(
                _inventarioActivo?.nombre ?? 'Inventario',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
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
                hintText: 'Buscar por usuario, serie...',
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

              return Row(
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
                    onPressed: () {},
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
                            style: TextStyle(color: Colors.black87, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    minSize: 0,
                    borderRadius: BorderRadius.circular(12),
                    pressedOpacity: 0.7,
                    onPressed: () {},
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
              titulo,
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

    final pestanaData =
        _datosHojas[dataKey] ?? {'headers': [], 'rows': []};

    final List<String> allHeaders =
        List<String>.from(pestanaData['headers'] ?? []);
    final Set<String> activasSet =
        _columnasPorPestana.value[dataKey] ?? allHeaders.toSet();
    final List<String> headers =
        allHeaders.where((h) => activasSet.contains(h)).toList();

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

        if (filtro == 'Asignados' && estatusValor != 'activo') return false;
        if (filtro == 'Disponibles' &&
            estatusValor != 'pendiente de asignar') return false;
      }

      if (query.isEmpty) return true;
      return row.entries
          .any((entry) => entry.value.toString().toLowerCase().contains(query));
    }).toList();

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: primaryPurple),
      );
    }

    if (headers.isEmpty) {
      return Center(
        child: Text(
          filtro == 'Bajas'
              ? 'No hay bajas registradas en esta pestaña.'
              : 'No se encontraron datos en esta pestaña.',
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
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
                                            child:
                                                _buildCellContent(h, valor),
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
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 36, right: 36, bottom: 6, top: 0),
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
                                    }
                                  },
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
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
};

const _capturaConfig = _DetailConfig(
  tituloKeys: ['Nombre Lógico del Equipo', 'Nombre'],
  snKey: 'Numero de Serie',
  badge: 'Responsiva',
  secciones: [
    _DetailSection('Datos generales', [
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

class _DeviceDetailSheet extends StatefulWidget {
  final Map<String, dynamic> fila;
  final _DetailConfig config;
  final String nombrePestana;
  final String spreadsheetId;
  final VoidCallback onBajaExitosa;

  const _DeviceDetailSheet({
    required this.fila,
    required this.config,
    required this.nombrePestana,
    required this.spreadsheetId,
    required this.onBajaExitosa,
  });

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> {
  static const primaryPurple = Color(0xFF532E7C);

  late Set<int> _expandidas;

  @override
  void initState() {
    super.initState();
    _expandidas = {0};
  }

  String _valor(String key) {
    final v = widget.fila[key];
    return v == null ? '' : v.toString().trim();
  }

  String _titulo() {
    for (final k in widget.config.tituloKeys) {
      final v = _valor(k);
      if (v.isNotEmpty) return v;
    }
    return 'Sin nombre';
  }

  bool _esActivo() {
    final v = _valor('Estatus').toLowerCase();
    return v == 'activo' || v == 'active';
  }

  List<_DetailSection> _seccionesConDatos() {
    final usadas = <String>{};
    for (final s in widget.config.secciones) {
      for (final f in s.campos) {
        usadas.add(f.key);
      }
    }
    usadas.add(widget.config.snKey);
    usadas.addAll(widget.config.tituloKeys);
    usadas.add('Estatus');

    final resultado = widget.config.secciones
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

  Future<void> _mostrarConfirmacionBaja(BuildContext sheetContext) async {
    final motivoElegido = await showDialog<String>(
      context: sheetContext,
      barrierDismissible: false,
      builder: (dialogContext) => _ConfirmarBajaDialog(
        titulo: _titulo(),
        nombreSeccionBajas: _mapaNombreBajas[widget.nombrePestana] ?? 'Bajas',
        onConfirmar: (motivo) {
          final sn = _valor(widget.config.snKey);
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

    await showDialog(
      context: sheetContext,
      barrierDismissible: false,
      builder: (dialogContext) => _BajaExitosaDialog(
        titulo: _titulo(),
        nombreSeccionBajas: _mapaNombreBajas[widget.nombrePestana] ?? 'Bajas',
        motivo: motivoElegido,
      ),
    );

    if (!mounted) return;
    Navigator.pop(context);
    widget.onBajaExitosa();
  }

  @override
  Widget build(BuildContext context) {
    final secciones = _seccionesConDatos();
    final activo = _esActivo();

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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3EBFF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.description_outlined,
                                  size: 14, color: Color(0xFF3457D5)),
                              const SizedBox(width: 4),
                              Text(
                                widget.config.badge,
                                style: const TextStyle(
                                  color: Color(0xFF3457D5),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
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
                                    ? 'Sin estatus'
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
                        if (_valor(widget.config.snKey).isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            'SN: ${_valor(widget.config.snKey)}',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 13,
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
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 16, 100),
                            itemCount: secciones.length,
                            itemBuilder: (context, index) {
                              final seccion = secciones[index];
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
                                    AnimatedCrossFade(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      crossFadeState: expandida
                                          ? CrossFadeState.showFirst
                                          : CrossFadeState.showSecond,
                                      firstChild: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 16),
                                        child:
                                            _buildCamposGrid(seccion.campos),
                                      ),
                                      secondChild: const SizedBox(
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
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomActions(context),
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
          padding: const EdgeInsets.only(top: 10),
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

  Widget _buildBottomActions(BuildContext sheetContext) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {},
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
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {},
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
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _mostrarConfirmacionBaja(sheetContext),
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
          ),
        ],
      ),
    );
  }
}

class _ConfirmarBajaDialog extends StatefulWidget {
  final String titulo;
  final String nombreSeccionBajas;
  final Future<bool> Function(String motivo) onConfirmar;

  const _ConfirmarBajaDialog({
    required this.titulo,
    required this.nombreSeccionBajas,
    required this.onConfirmar,
  });

  @override
  State<_ConfirmarBajaDialog> createState() => _ConfirmarBajaDialogState();
}

class _ConfirmarBajaDialogState extends State<_ConfirmarBajaDialog> {
  static const primaryPurple = Color(0xFF532E7C);
  static const List<String> _motivos = [
    'Fin de vida útil / Obsolescencia tecnológica',
    'Fin de arrendamiento',
    'Robo o extravío',
    'Falla de hardware irreparable',
    'Venta o donación',
    'Otro',
  ];

  String _motivoSeleccionado = _motivos.first;
  final TextEditingController _otroController = TextEditingController();
  bool _cargando = false;
  String? _error;

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
            ? 'No se pudo dar de baja el activo'
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
                '¿Dar de baja el activo?',
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
                    const TextSpan(text: 'El equipo '),
                    TextSpan(
                      text: widget.titulo,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const TextSpan(
                        text: ' dejará de estar asignado y se moverá a la sección '),
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
                value: _motivoSeleccionado,
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
                    borderSide: const BorderSide(color: primaryPurple, width: 1.5),
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
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
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
                      borderSide: const BorderSide(color: primaryPurple, width: 1.5),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
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
              '¡Activo dado de baja!',
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
                  const TextSpan(text: 'El equipo '),
                  TextSpan(
                    text: titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const TextSpan(
                      text:
                          ' ha sido removido del inventario activo y se movió a la sección '),
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
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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