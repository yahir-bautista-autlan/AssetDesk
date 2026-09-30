import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/auth_service.dart';

class AddAssetScreen extends StatefulWidget {
  final String nombrePestana;
  final List<String> headers;
  final List<Map<String, dynamic>> existingRows;
  final InventoryModel? inventario;

  const AddAssetScreen({
    super.key,
    required this.nombrePestana,
    required this.headers,
    required this.existingRows,
    required this.inventario,
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

  @override
  void initState() {
    super.initState();
    _fechaAuto = _formatearFechaHoraActual();
    _ubicacionAuto = widget.inventario?.ubicacion ?? '';
    _prepararCampos();
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
        _selectValues[header] = combinadas.isNotEmpty ? combinadas.first : null;
        _otroControllers[header] = TextEditingController();
      } else {
        _controllers[header] = TextEditingController();
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
    if (header == 'Fecha/Hora' || header == 'FechaRegistro') return _fechaAuto;
    if (header == 'Responsable') {
      return _cargandoUsuario ? 'Cargando...' : _responsable;
    }
    if (header == 'Ubicación') return _ubicacionAuto;
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

    final exito = await AuthService.agregarActivo(
      spreadsheetId: widget.inventario?.spreadsheetId ?? '',
      pestana: widget.nombrePestana,
      datos: datos,
    );

    if (!mounted) return;

    if (exito) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _errorGeneral = AuthService.ultimoError.isEmpty
            ? 'No se pudo guardar el activo'
            : AuthService.ultimoError;
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
                  const Text(
                    'Agregar Activo',
                    style: TextStyle(
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildCampos(),
                ),
              ),
            ),
            _buildBotonGuardar(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCampos() {
    final widgets = <Widget>[];
    var i = 0;
    while (i < widget.headers.length) {
      final header = widget.headers[i];
      if (header.isEmpty) {
        i++;
        continue;
      }

      if (widget.nombrePestana == 'Captura' &&
          header == 'Disco Duro' &&
          i + 1 < widget.headers.length &&
          widget.headers[i + 1] == 'Memoria') {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildCampo('Disco Duro')),
                const SizedBox(width: 12),
                Expanded(child: _buildCampo('Memoria')),
              ],
            ),
          ),
        );
        i += 2;
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildCampo(header),
        ),
      );
      i++;
    }
    return widgets;
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
      fillColor: const Color(0xFFF7F7FA),
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
    final esPrimero = header == 'Nombre';
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
                        : const Text(
                            'GUARDAR Y GENERAR QR',
                            style: TextStyle(
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
    );
  }
}