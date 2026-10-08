import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/auth_service.dart';
import 'qr_view_screen.dart';

const Map<String, String> _mapaSnKeyGlobal = {
  'Captura': 'Numero de Serie',
  'Impresoras': 'Num. de Serie',
  'Otros': 'NoSerie',
  'Consumibles': 'Numero de serie',
};

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

const Map<String, String> _categoriaConsumibles = {
  'Impresora': 'Información del Consumible',
  'Modelo': 'Información del Consumible',
  'Color': 'Información del Consumible',
  'Tipo': 'Información del Consumible',
  'Departamento': 'Información del Consumible',
  'Proveedor': 'Información del Consumible',
  'Numero de serie': 'Información del Consumible',
  'Responsable': 'Información del Consumible',
  'Fecha': 'Información del Consumible',
  'Comentarios': 'Información del Consumible',
  'Estatus': 'Información del Consumible',
};

const List<String> _ordenSeccionesConsumibles = [
  'Información del Consumible',
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
    'Fecha',
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
    'Color',
    'Tipo',
  };

  static const Set<String> _camposTamano = {'Disco Duro', 'Memoria'};

  static const Map<String, List<String>> _opcionesPorDefecto = {
    'Equipo': ['PC', 'Laptop'],
    'Disco Duro': ['256GB SSD', '512GB SSD', '1TB SSD', '1TB HDD'],
    'Memoria': ['8GB', '16GB', '32GB', '64GB'],
    'Sistema Operativo': ['Windows 10', 'Windows 11', 'macOS', 'Linux'],
    'Departamento': [],
    'Estatus': ['Stock', 'Asignado'],
    'Color': ['Cyan', 'Magenta', 'Amarillo', 'Negro', 'Otro'],
    'Tipo': ['EcoTank', 'Cartucho', 'Tóner', 'Botella'],
  };

  static const String _otroSentinel = '__otro__';

  bool get _esEdicion => widget.existingData != null;

  bool get _requiereAprobacion {
    final u = AuthService.usuarioCache;
    if (u == null || !u.esResidente) return false;
    final inv = widget.inventario;
    if (inv == null) return true;
    return !inv.esResponsable(u.correo);
  }

  bool get _esConsultor => AuthService.usuarioCache?.esConsultor ?? false;

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

  late List<_SeccionCampos> _secciones;
  final Set<int> _expandidas = {0};

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

  String _canonico(String header, String valor) {
    var v = valor.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (v.isEmpty) return v;

    if (_camposTamano.contains(header)) {
      final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(gb|tb|mb)\b\s*(.*)$',
              caseSensitive: false)
          .firstMatch(v);
      if (m != null) {
        final numero = m.group(1)!;
        final unidad = m.group(2)!.toUpperCase();
        final resto = (m.group(3) ?? '').trim();
        v = resto.isEmpty
            ? '$numero$unidad'
            : '$numero$unidad ${resto.toUpperCase()}';
      }
    }
    return v;
  }

  String _claveComparacion(String valor) {
    return valor.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  double _tamanoEnGb(String valor) {
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)(gb|tb|mb)', caseSensitive: false)
        .firstMatch(valor.replaceAll(' ', ''));
    if (m == null) return double.infinity;
    final n = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
    switch (m.group(2)!.toLowerCase()) {
      case 'tb':
        return n * 1024;
      case 'mb':
        return n / 1024;
      default:
        return n;
    }
  }

  void _prepararCampos() {
    for (final header in widget.headers) {
      if (header.isEmpty || _camposEstaticos.contains(header)) continue;

      final valorExistenteCrudo =
          widget.existingData?[header]?.toString().trim() ?? '';

      if (_camposSelect.contains(header)) {
        final valorExistente = _canonico(header, valorExistenteCrudo);
        final vistos = <String, String>{};

        void agregar(String crudo) {
          final c = _canonico(header, crudo);
          if (c.isEmpty) return;
          vistos.putIfAbsent(_claveComparacion(c), () => c);
        }

        for (final row in widget.existingRows) {
          final v = row[header]?.toString();
          if (v != null) agregar(v);
        }
        for (final f in _opcionesPorDefecto[header] ?? const <String>[]) {
          agregar(f);
        }
        agregar(valorExistente);

        final combinadas = vistos.values.toList();

        if (header == 'Estatus') {
          combinadas.sort((a, b) {
            if (a == 'Stock' || a == 'Activo') return -1;
            if (b == 'Stock' || b == 'Activo') return 1;
            return a.compareTo(b);
          });
        } else if (_camposTamano.contains(header)) {
          combinadas.sort((a, b) {
            final cmp = _tamanoEnGb(a).compareTo(_tamanoEnGb(b));
            return cmp != 0 ? cmp : a.compareTo(b);
          });
        } else {
          combinadas.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        }

        String? seleccionado;
        if (valorExistente.isNotEmpty) {
          seleccionado = vistos[_claveComparacion(valorExistente)];
        } else if (combinadas.isNotEmpty) {
          seleccionado = combinadas.first;
        }

        _opcionesPorCampo[header] = combinadas;
        _selectValues[header] = seleccionado;
        _otroControllers[header] = TextEditingController();
      } else {
        _controllers[header] = TextEditingController(text: valorExistenteCrudo);
      }
    }
  }

  Map<String, String> _categoriaMapPara(String pestana) {
    switch (pestana) {
      case 'Impresoras':
        return _categoriaImpresoras;
      case 'Otros':
        return _categoriaOtros;
      case 'Consumibles':
        return _categoriaConsumibles;
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
      case 'Consumibles':
        return _ordenSeccionesConsumibles;
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

  void _expandirSeccionDe(String header) {
    for (var i = 0; i < _secciones.length; i++) {
      if (_secciones[i].headers.contains(header)) {
        _expandidas.add(i);
        return;
      }
    }
  }

  bool _esCampoFecha(String header) {
    return header.toLowerCase().contains('fecha') &&
        !_camposEstaticos.contains(header);
  }

  bool _esCampoNumerico(String header) {
    return header == 'Costo' || header == 'Años Garantía';
  }

  String _valorEstaticoPara(String header) {
    if (header == 'Fecha/Hora' || header == 'FechaRegistro' || header == 'Fecha') {
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

  String _obtenerYValidarNumeroDeSerie(Map<String, String> datos) {
    final snKey = _mapaSnKeyGlobal[widget.nombrePestana];
    if (snKey == null || !widget.headers.contains(snKey)) return 'NA-00000000';

    String snCapturado = datos[snKey]?.trim() ?? '';

    if (snCapturado.isEmpty) {
      int contador = widget.existingRows.length + 1;
      while (true) {
        String candidato = 'NA-${contador.toString().padLeft(8, '0')}';
        bool repetido = widget.existingRows.any((row) {
          if (_esEdicion && row[snKey]?.toString().trim() == _snOriginal) return false;
          return row.values.any((val) => val.toString().trim().toLowerCase() == candidato.toLowerCase());
        });
        if (!repetido) {
          snCapturado = candidato;
          break;
        }
        contador++;
      }
    } else {
      bool repetido = widget.existingRows.any((row) {
        if (_esEdicion && row[snKey]?.toString().trim() == _snOriginal) return false;
        return row.values.any((val) => val.toString().trim().toLowerCase() == snCapturado.toLowerCase());
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
      if (texto.isEmpty) {
        huboError = true;
        _expandirSeccionDe('Nombre');
      }
    }

    for (final header in _camposSelect) {
      if (!widget.headers.contains(header)) continue;
      final seleccionado = _selectValues[header];
      if (seleccionado == null) {
        _erroresSelect[header] = 'Selecciona una opción';
        huboError = true;
        _expandirSeccionDe(header);
      } else if (seleccionado == _otroSentinel) {
        final texto = _otroControllers[header]?.text.trim() ?? '';
        if (texto.isEmpty) {
          _erroresSelect[header] = 'Especifica el valor';
          huboError = true;
          _expandirSeccionDe(header);
        }
      }
    }

    if (huboError) {
      setState(() {
        _errorGeneral = 'Completa los campos obligatorios marcados.';
      });
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
            ? _canonico(header, _otroControllers[header]?.text ?? '')
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
        final quedoPendiente = AuthService.ultimaRespuestaPendiente;

        if (!quedoPendiente &&
            !_esEdicion &&
            widget.nombrePestana != 'Consumibles') {
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

  String get _textoBoton {
    if (_requiereAprobacion) return 'ENVIAR PARA APROBACIÓN';
    return _esEdicion ? 'GUARDAR CAMBIOS' : 'GUARDAR Y GENERAR QR';
  }

  Widget _bannerAprobacion() {
    final responsable = widget.inventario?.responsableEmail ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded,
              color: Color(0xFFB45309), size: 20),
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

  Widget _vistaSoloLectura() {
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
                  const Text(
                    'Solo lectura',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 52, color: Color(0xFF9CA3AF)),
                      SizedBox(height: 14),
                      Text(
                        'Tu rol de Consultor solo permite ver información y exportar reportes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 15, color: Colors.black54, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_esConsultor) return _vistaSoloLectura();

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
                          children: [
                            if (_requiereAprobacion) _bannerAprobacion(),
                            ..._buildSecciones(columnas),
                          ],
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
    final unaSola = _secciones.length == 1;

    for (var i = 0; i < _secciones.length; i++) {
      final seccion = _secciones[i];
      final expandida = unaSola || _expandidas.contains(i);

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDEDF2)),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: unaSola
                    ? null
                    : () {
                        setState(() {
                          if (_expandidas.contains(i)) {
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
                      if (!unaSola)
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
          decoration: _decoracionBase(
            hint: header.toLowerCase().contains('serie')
                ? 'Dejar en blanco para generar auto'
                : null,
          ),
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
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _requiereAprobacion
                            ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
                            : const [Color(0xFF6B3F96), primaryPurple],
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
                                _textoBoton,
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