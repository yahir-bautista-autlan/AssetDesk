import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/auth_service.dart';
import 'qr_view_screen.dart'; // <-- IMPORTANTE: Importar la vista de QR

const Map<String, String> _mapaSnKeyGlobal = {
  'Captura': 'Numero de Serie',
  'Impresoras': 'Num. de Serie',
  'Otros': 'NoSerie',
};

// ... (Conserva tus mapas de categorías, secciones y configuraciones tal cual los tienes)
const Map<String, String> _categoriaCaptura = {
  'Nombre': 'Datos generales',
  'Nombre Lógico del Equipo': 'Datos generales',
  'Ubicación': 'Datos generales',
  'Usuario de Dominio': 'Datos generales',
  'Responsable': 'Datos generales',
  'Departamento': 'Datos generales',
  'Estatus': 'Datos generales',
  'Equipo': 'Hardware y Red',
  'Modelo': 'Hardware y Red',
  'Numero de Serie': 'Hardware y Red',
  'Procesador': 'Hardware y Red',
  'Disco Duro': 'Hardware y Red',
  'Memoria': 'Hardware y Red',
  'MAC Address': 'Hardware y Red',
  'IP Address': 'Hardware y Red',
  'Monitor': 'Periféricos',
  'Numero de Serie (2)': 'Periféricos',
  'Sistema Operativo': 'Software y Licencias',
  'Licencia1': 'Software y Licencias',
  'Microsoft Office': 'Software y Licencias',
  'Licencia2': 'Software y Licencias',
  'Productos Autodesk': 'Software y Licencias',
  'Licencia3': 'Software y Licencias',
  'Productos Adobe': 'Software y Licencias',
  'Licencia4': 'Software y Licencias',
  'Otros Software': 'Software y Licencias',
  'Proveedor': 'Garantía',
  'Factura': 'Garantía',
  'Costo': 'Garantía',
  'Fecha Adquisición': 'Garantía',
  'Años Garantía': 'Garantía',
  'Fecha/Hora': 'Arrendamiento e Historial',
  'Fecha de Inicio (Arrendado)': 'Arrendamiento e Historial',
  'Fecha de Vencimiento (Arrendado)': 'Arrendamiento e Historial',
  'Numero de Contrato': 'Arrendamiento e Historial',
  'Comentarios': 'Arrendamiento e Historial',
};

const List<String> _ordenSeccionesCaptura = [
  'Datos generales',
  'Hardware y Red',
  'Periféricos',
  'Software y Licencias',
  'Garantía',
  'Arrendamiento e Historial',
];

const Map<String, String> _categoriaImpresoras = {
  'Nombre': 'Datos generales',
  'Ubicación': 'Datos generales',
  'Responsable': 'Datos generales',
  'Departamento': 'Datos generales',
  'Estatus': 'Datos generales',
  'Modelo': 'Hardware y Red',
  'Num. de Serie': 'Hardware y Red',
  'Direccion IP': 'Hardware y Red',
  'FechaRegistro': 'Detalles adicionales',
  'Comentarios': 'Detalles adicionales',
};

const List<String> _ordenSeccionesImpresoras = [
  'Datos generales',
  'Hardware y Red',
  'Detalles adicionales',
];

const Map<String, String> _categoriaOtros = {
  'Nombre': 'Datos generales',
  'Unidad': 'Datos generales',
  'Responsable': 'Datos generales',
  'Departamento': 'Datos generales',
  'Estatus': 'Datos generales',
  'Equipo': 'Hardware y Red',
  'Modelo': 'Hardware y Red',
  'NoSerie': 'Hardware y Red',
  'FechaRegistro': 'Detalles adicionales',
  'Comentarios': 'Detalles adicionales',
};

const List<String> _ordenSeccionesOtros = [
  'Datos generales',
  'Hardware y Red',
  'Detalles adicionales',
];

class AddAssetScreen extends StatefulWidget {
  final String nombrePestana;
  final List<String> headers;
  final List<Map<String, dynamic>> existingRows;
  final InventoryModel? inventario;
  final Map<String, dynamic>? existingData;

  const AddAssetScreen({
    super.key,
    required this.nombrePestana,
    required this.headers,
    required this.existingRows,
    required this.inventario,
    this.existingData,
  });

  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> {
  static const primaryPurple = Color(0xFF532E7C);

  static const Set<String> _camposEstaticos = {
    'Fecha/Hora',
    'FechaRegistro',
    'Responsable',
    'Ubicación',
  };

  static const Set<String> _camposSelect = {
    'Equipo',
    'Disco Duro',
    'Memoria',
    'Sistema Operativo',
    'Departamento',
    'Estatus',
  };

  static const Map<String, List<String>> _opcionesPorDefecto = {
    'Equipo': ['PC', 'Laptop'],
    'Disco Duro': ['256GB SSD', '512GB SSD', '1TB SSD', '1TB HDD'],
    'Memoria': ['8GB', '16GB', '32GB', '64GB'],
    'Sistema Operativo': ['Windows 10', 'Windows 11', 'macOS', 'Linux'],
    'Departamento': [],
    'Estatus': ['Activo', 'Pendiente de asignar'],
  };

  static const String _otroSentinel = '__otro__';

  bool get _esEdicion => widget.existingData != null;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, TextEditingController> _otroControllers = {};
  final Map<String, String?> _selectValues = {};
  final Map<String, List<String>> _opcionesPorCampo = {};
  final Map<String, String?> _erroresSelect = {};

  bool _cargandoUsuario = true;
  String _responsable = '';
  late final String _fechaAuto;
  late final String _ubicacionAuto;
  bool _guardando = false;
  String? _errorGeneral;
  String _snOriginal = '';

  late Set<int> _expandidas;
  late List<_SeccionCampos> _secciones;

  @override
  void initState() {
    super.initState();
    _fechaAuto = _formatearFechaHoraActual();
    _ubicacionAuto = widget.inventario?.ubicacion ?? '';

    final snKey = _mapaSnKeyGlobal[widget.nombrePestana];
    if (_esEdicion && snKey != null) {
      _snOriginal = widget.existingData?[snKey]?.toString().trim() ?? '';
    }

    _prepararCampos();
    _secciones = _agruparPorSeccion();
    _expandidas = {0};
    _cargarResponsable();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _otroControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatearFechaHoraActual() {
    final n = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${p2(n.day)}/${p2(n.month)}/${n.year} ${p2(n.hour)}:${p2(n.minute)}';
  }

  Future<void> _cargarResponsable() async {
    if (_esEdicion) {
      final existente = widget.existingData?['Responsable']?.toString().trim();
      if (existente != null && existente.isNotEmpty) {
        setState(() {
          _responsable = existente;
          _cargandoUsuario = false;
        });
        return;
      }
    }

    final user = await AuthService.obtenerUsuarioActual();
    if (!mounted) return;
    setState(() {
      _responsable = user?.nombre.isNotEmpty == true
          ? user!.nombre
          : (user?.correo ?? 'Desconocido');
      _cargandoUsuario = false;
    });
  }

  void _prepararCampos() {
    for (final header in widget.headers) {
      if (header.isEmpty || _camposEstaticos.contains(header)) continue;

      final valorExistente =
          widget.existingData?[header]?.toString().trim() ?? '';

      if (_camposSelect.contains(header)) {
        final distintos = <String>{};
        for (final row in widget.existingRows) {
          final v = row[header]?.toString().trim();
          if (v != null && v.isNotEmpty) distintos.add(v);
        }
        final fallback = _opcionesPorDefecto[header] ?? const [];
        final combinadas = <String>[...distintos];
        for (final f in fallback) {
          if (!combinadas.contains(f)) combinadas.add(f);
        }
        if (valorExistente.isNotEmpty && !combinadas.contains(valorExistente)) {
          combinadas.add(valorExistente);
        }
        if (header == 'Estatus') {
          combinadas.sort((a, b) {
            if (a == 'Activo') return -1;
            if (b == 'Activo') return 1;
            return a.compareTo(b);
          });
        } else {
          combinadas.sort();
        }
        _opcionesPorCampo[header] = combinadas;
        _selectValues[header] = valorExistente.isNotEmpty
            ? valorExistente
            : (combinadas.isNotEmpty ? combinadas.first : null);
        _otroControllers[header] = TextEditingController();
      } else {
        _controllers[header] = TextEditingController(text: valorExistente);
      }
    }
  }

  Map<String, String> _categoriaMapPara(String pestana) {
    switch (pestana) {
      case 'Impresoras':
        return _categoriaImpresoras;
      case 'Otros':
        return _categoriaOtros;
      default:
        return _categoriaCaptura;
    }
  }

  List<String> _ordenSeccionesPara(String pestana) {
    switch (pestana) {
      case 'Impresoras':
        return _ordenSeccionesImpresoras;
      case 'Otros':
        return _ordenSeccionesOtros;
      default:
        return _ordenSeccionesCaptura;
    }
  }

  List<_SeccionCampos> _agruparPorSeccion() {
    final categoriaMap = _categoriaMapPara(widget.nombrePestana);
    final ordenSecciones = _ordenSeccionesPara(widget.nombrePestana);

    final headersPorSeccion = <String, List<String>>{};
    for (final titulo in ordenSecciones) {
      headersPorSeccion[titulo] = [];
    }
    const otrosTitulo = 'Otros datos';
    headersPorSeccion[otrosTitulo] = [];

    for (final header in widget.headers) {
      if (header.isEmpty) continue;
      final categoria = categoriaMap[header] ?? otrosTitulo;
      headersPorSeccion.putIfAbsent(categoria, () => []).add(header);
    }

    final resultado = <_SeccionCampos>[];
    for (final titulo in [...ordenSecciones, otrosTitulo]) {
      final lista = headersPorSeccion[titulo] ?? [];
      if (lista.isNotEmpty) {
        resultado.add(_SeccionCampos(titulo, lista));
      }
    }
    return resultado;
  }

  bool _esCampoFecha(String header) {
    return header.toLowerCase().contains('fecha') &&
        !_camposEstaticos.contains(header);
  }

  bool _esCampoNumerico(String header) {
    return header == 'Costo' || header == 'Años Garantía';
  }

  String _valorEstaticoPara(String header) {
    if (header == 'Fecha/Hora' || header == 'FechaRegistro') {
      if (_esEdicion) {
        final existente = widget.existingData?[header]?.toString().trim();
        if (existente != null && existente.isNotEmpty) return existente;
      }
      return _fechaAuto;
    }
    if (header == 'Responsable') {
      return _cargandoUsuario ? 'Cargando...' : _responsable;
    }
    if (header == 'Ubicación') {
      if (_esEdicion) {
        final existente = widget.existingData?[header]?.toString().trim();
        if (existente != null && existente.isNotEmpty) return existente;
      }
      return _ubicacionAuto;
    }
    return '';
  }

  Future<void> _elegirFecha(String header) async {
    final seleccion = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (seleccion == null) return;
    String p2(int v) => v.toString().padLeft(2, '0');
    final formateada =
        '${p2(seleccion.day)}/${p2(seleccion.month)}/${seleccion.year}';
    setState(() {
      _controllers[header]?.text = formateada;
    });
  }

  // --- NUEVA LÓGICA: GENERAR/VALIDAR NUMERO DE SERIE ÚNICO ---
  String _obtenerYValidarNumeroDeSerie(Map<String, String> datos) {
    final snKey = _mapaSnKeyGlobal[widget.nombrePestana];
    if (snKey == null) return 'NA-00000000';

    String snCapturado = datos[snKey]?.trim() ?? '';

    // Si no se capturó número de serie, generar por defecto NA-00000000 asegurando unicidad
    if (snCapturado.isEmpty) {
      int contador = 1;
      while (true) {
        String candidato = 'NA-${contador.toString().padLeft(8, '0')}';
        bool repetido = widget.existingRows.any((row) {
          if (_esEdicion && row[snKey]?.toString().trim() == _snOriginal) return false;
          return row[snKey]?.toString().trim() == candidato;
        });
        if (!repetido) {
          snCapturado = candidato;
          break;
        }
        contador++;
      }
    } else {
      // Validar si el número de serie capturado ya existe en otro activo
      bool repetido = widget.existingRows.any((row) {
        if (_esEdicion && row[snKey]?.toString().trim() == _snOriginal) return false;
        return row[snKey]?.toString().trim().toLowerCase() == snCapturado.toLowerCase();
      });

      if (repetido) {
        throw Exception('El número de serie "$snCapturado" ya existe en otro activo. Debe ser único.');
      }
    }

    datos[snKey] = snCapturado;
    return snCapturado;
  }

  Map<String, String>? _construirDatos() {
    bool huboError = false;
    _erroresSelect.clear();

    if (widget.headers.contains('Nombre')) {
      final texto = _controllers['Nombre']?.text.trim() ?? '';
      if (texto.isEmpty) huboError = true;
    }

    for (final header in _camposSelect) {
      if (!widget.headers.contains(header)) continue;
      final seleccionado = _selectValues[header];
      if (seleccionado == null) {
        _erroresSelect[header] = 'Selecciona una opción';
        huboError = true;
      } else if (seleccionado == _otroSentinel) {
        final texto = _otroControllers[header]?.text.trim() ?? '';
        if (texto.isEmpty) {
          _erroresSelect[header] = 'Especifica el valor';
          huboError = true;
        }
      }
    }

    if (huboError) {
      setState(() {});
      return null;
    }

    final datos = <String, String>{};
    for (final header in widget.headers) {
      if (header.isEmpty) continue;
      if (_camposEstaticos.contains(header)) {
        datos[header] = _valorEstaticoPara(header);
      } else if (_camposSelect.contains(header)) {
        final seleccionado = _selectValues[header];
        datos[header] = seleccionado == _otroSentinel
            ? (_otroControllers[header]?.text.trim() ?? '')
            : (seleccionado ?? '');
      } else {
        datos[header] = _controllers[header]?.text.trim() ?? '';
      }
    }
    return datos;
  }

  Future<void> _guardar() async {
    final datos = _construirDatos();
    if (datos == null) return;

    setState(() {
      _guardando = true;
      _errorGeneral = null;
    });

    try {
      // Aplicar validación de número de serie único o por defecto
      final snFinal = _obtenerYValidarNumeroDeSerie(datos);

      bool exito;
      if (_esEdicion) {
        exito = await AuthService.editarActivo(
          spreadsheetId: widget.inventario?.spreadsheetId ?? '',
          pestana: widget.nombrePestana,
          snOriginal: _snOriginal,
          datos: datos,
        );
      } else {
        exito = await AuthService.agregarActivo(
          spreadsheetId: widget.inventario?.spreadsheetId ?? '',
          pestana: widget.nombrePestana,
          datos: datos,
        );
      }

      if (!mounted) return;

      if (exito) {
        if (!_esEdicion) {
          // Si es nuevo activo, abrir directamente la vista de código QR con el diálogo de éxito
          final nombreActivo = datos['Nombre'] ?? 'Activo sin nombre';
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => QrViewScreen(
                serialNumber: snFinal,
                nombreActivo: nombreActivo,
                mostrarDialogoExito: true,
              ),
            ),
          );
        } else {
          Navigator.pop(context, true);
        }
      } else {
        setState(() {
          _guardando = false;
          _errorGeneral = AuthService.ultimoError.isEmpty
              ? 'No se pudo guardar el activo'
              : AuthService.ultimoError;
        });
      }
    } catch (e) {
      setState(() {
        _guardando = false;
        _errorGeneral = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.arrow_back, color: primaryPurple),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _esEdicion ? 'Editar Activo' : 'Agregar Activo',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F3)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth =
                      constraints.maxWidth > 1000 ? 1000.0 : constraints.maxWidth;
                  final columnas = contentWidth >= 640 ? 2 : 1;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildSecciones(columnas),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            _buildBotonGuardar(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSecciones(int columnas) {
    final widgets = <Widget>[];
    for (var i = 0; i < _secciones.length; i++) {
      final seccion = _secciones[i];
      final expandida = _expandidas.contains(i);

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDEDF2)),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    if (expandida) {
                      _expandidas.remove(i);
                    } else {
                      _expandidas.add(i);
                    }
                  });
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down,
                            color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState: expandida
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _buildCamposGrid(seccion.headers, columnas),
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildCamposGrid(List<String> headers, int columnas) {
    final filas = <Widget>[];
    for (var i = 0; i < headers.length; i += columnas) {
      final grupo = headers.skip(i).take(columnas).toList();
      filas.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < columnas; j++) ...[
                if (j > 0) const SizedBox(width: 12),
                Expanded(
                  child: j < grupo.length
                      ? _buildCampo(grupo[j])
                      : const SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: filas);
  }

  Widget _buildCampo(String header) {
    if (_camposEstaticos.contains(header)) {
      return _buildCampoEstatico(header);
    }
    if (_camposSelect.contains(header)) {
      return _buildCampoSelect(header);
    }
    if (_esCampoFecha(header)) {
      return _buildCampoFecha(header);
    }
    return _buildCampoTexto(header);
  }

  Widget _label(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: primaryPurple,
        ),
      ),
    );
  }

  InputDecoration _decoracionBase({String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFB0B0B8), fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFECECF0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryPurple, width: 1.6),
      ),
    );
  }

  Widget _buildCampoTexto(String header) {
    final esPrimero = header == 'Nombre' && !_esEdicion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(header),
        TextFormField(
          controller: _controllers[header],
          autofocus: esPrimero,
          keyboardType: _esCampoNumerico(header)
              ? TextInputType.number
              : TextInputType.text,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          decoration: _decoracionBase(),
        ),
      ],
    );
  }

  Widget _buildCampoFecha(String header) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(header),
        TextFormField(
          controller: _controllers[header],
          readOnly: true,
          onTap: () => _elegirFecha(header),
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          decoration: _decoracionBase(
            hint: 'dd/mm/aaaa',
            suffixIcon: const Icon(Icons.calendar_today_outlined,
                size: 18, color: Color(0xFF9CA3AF)),
          ),
        ),
      ],
    );
  }

  Widget _buildCampoEstatico(String header) {
    final valor = _valorEstaticoPara(header);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(header),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            valor.isEmpty ? 'Sin definir' : valor,
            style: const TextStyle(fontSize: 14, color: Color(0xFF8A8A92)),
          ),
        ),
      ],
    );
  }

  Widget _buildCampoSelect(String header) {
    final opciones = _opcionesPorCampo[header] ?? const [];
    final valorActual = _selectValues[header];
    final error = _erroresSelect[header];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(header),
        DropdownButtonFormField<String>(
          initialValue: valorActual,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF)),
          items: [
            ...opciones.map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(
                  o,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ),
            ),
            const DropdownMenuItem(
              value: _otroSentinel,
              child: Text(
                'Otro (especificar)',
                style: TextStyle(
                  fontSize: 14,
                  color: primaryPurple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() {
              _selectValues[header] = v;
              _erroresSelect.remove(header);
            });
          },
          decoration: _decoracionBase().copyWith(errorText: error),
        ),
        if (valorActual == _otroSentinel) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _otroControllers[header],
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: _decoracionBase(hint: 'Escribe el valor...'),
          ),
        ],
      ],
    );
  }

  Widget _buildBotonGuardar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F3))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorGeneral != null) ...[
                Text(
                  _errorGeneral!,
                  style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF6B3F96), primaryPurple],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _guardando ? null : _guardar,
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        child: _guardando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                _esEdicion
                                    ? 'GUARDAR CAMBIOS'
                                    : 'GUARDAR Y GENERAR QR',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeccionCampos {
  final String titulo;
  final List<String> headers;
  const _SeccionCampos(this.titulo, this.headers);
}