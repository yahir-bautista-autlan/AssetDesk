import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/inventory_model.dart';
import '../services/auth_service.dart';

class ResponsivaExtraData {
  String marcaEquipoManual;
  bool incluyeCargador;
  String marcaCargador;
  String serieCargador;
  bool incluyeMonitor;
  String marcaMonitor;
  String otrosSoftware;
  String nombreResponsableTI;
  String empresaResponsableTI;
  String correoResponsableTI;
  String nombreRecibe;
  String empresaRecibe;
  String correoRecibe;

  ResponsivaExtraData({
    this.marcaEquipoManual = '',
    this.incluyeCargador = false,
    this.marcaCargador = '',
    this.serieCargador = '',
    this.incluyeMonitor = false,
    this.marcaMonitor = '',
    this.otrosSoftware = '',
    this.nombreResponsableTI = '',
    this.empresaResponsableTI = 'AUTLAN',
    this.correoResponsableTI = '',
    this.nombreRecibe = '',
    this.empresaRecibe = 'AUTLAN',
    this.correoRecibe = '',
  });

  ResponsivaExtraData copy() => ResponsivaExtraData(
        marcaEquipoManual: marcaEquipoManual,
        incluyeCargador: incluyeCargador,
        marcaCargador: marcaCargador,
        serieCargador: serieCargador,
        incluyeMonitor: incluyeMonitor,
        marcaMonitor: marcaMonitor,
        otrosSoftware: otrosSoftware,
        nombreResponsableTI: nombreResponsableTI,
        empresaResponsableTI: empresaResponsableTI,
        correoResponsableTI: correoResponsableTI,
        nombreRecibe: nombreRecibe,
        empresaRecibe: empresaRecibe,
        correoRecibe: correoRecibe,
      );
}

class ResponsivaPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> fila;
  final String nombrePestana;
  final InventoryModel? inventario;

  const ResponsivaPreviewScreen({
    super.key,
    required this.fila,
    required this.nombrePestana,
    this.inventario,
  });

  @override
  State<ResponsivaPreviewScreen> createState() =>
      _ResponsivaPreviewScreenState();
}

class _ResponsivaPreviewScreenState extends State<ResponsivaPreviewScreen> {
  late ResponsivaExtraData _datos;
  bool _cargandoInicial = true;

  @override
  void initState() {
    super.initState();
    _datos = ResponsivaExtraData(
      incluyeMonitor: _valor('Monitor').isNotEmpty,
      otrosSoftware: _softwareDesdeFila(),
      nombreRecibe: _valor('Responsable').isNotEmpty
          ? _valor('Responsable')
          : _valor('Usuario de Dominio'),
      correoRecibe: _correoDesdeUsuario(_valor('Responsable').isNotEmpty
          ? _valor('Responsable')
          : _valor('Usuario de Dominio')),
    );
    _cargarResponsableTI();
  }

  String _valor(String key) {
    final v = widget.fila[key];
    return v == null ? '' : v.toString().trim();
  }

  String _snKeyPara(String pestana) {
    switch (pestana) {
      case 'Impresoras':
        return 'Num. de Serie';
      case 'Otros':
        return 'NoSerie';
      default:
        return 'Numero de Serie';
    }
  }

  (String marca, String modelo) _separarMarcaModelo() {
    final modeloCompleto = _valor('Modelo');
    if (_datos.marcaEquipoManual.isNotEmpty) {
      return (_datos.marcaEquipoManual, modeloCompleto);
    }
    if (modeloCompleto.isEmpty) return ('', '');

    final partes = modeloCompleto.split(RegExp(r'\s+'));
    if (partes.length <= 1) return ('', modeloCompleto);

    final marca = partes.first;
    final resto = partes.sublist(1).join(' ');
    return (marca, resto);
  }

  String _correoDesdeUsuario(String usuario) {
    if (usuario.isEmpty) return '';
    if (usuario.contains('@')) return usuario;
    final limpio = usuario.toLowerCase().replaceAll(' ', '.');
    return '$limpio@autlan.com';
  }

  String _softwareDesdeFila() {
    final pares = [
      ['Microsoft Office', 'Licencia1'],
      ['Productos Autodesk', 'Licencia2'],
      ['Productos Adobe', 'Licencia3'],
      ['Otros Software', 'Licencia4'],
    ];
    final partes = <String>[];
    for (final p in pares) {
      final producto = _valor(p[0]);
      final licencia = _valor(p[1]);
      if (producto.isNotEmpty && licencia.isNotEmpty) {
        partes.add('$producto ($licencia)');
      } else if (producto.isNotEmpty) {
        partes.add(producto);
      } else if (licencia.isNotEmpty) {
        partes.add(licencia);
      }
    }
    return partes.join(', ');
  }

  String _nombreEncabezado() {
    var n = widget.inventario?.nombre.trim() ?? '';
    if (n.toLowerCase().startsWith('inventario ')) {
      n = n.substring(11).trim();
    }
    return n.isEmpty ? 'AUTLAN' : n.toUpperCase();
  }

  Future<void> _cargarResponsableTI() async {
    final user = await AuthService.obtenerUsuarioActual();
    if (!mounted) return;
    setState(() {
      _datos.nombreResponsableTI = user?.nombre ?? '';
      _datos.correoResponsableTI =
          user != null ? _correoDesdeUsuario(user.correo) : '';
      _cargandoInicial = false;
    });
  }

  Future<void> _abrirFormularioCompletar() async {
    final resultado = await Navigator.push<ResponsivaExtraData>(
      context,
      MaterialPageRoute(
        builder: (_) => _CompletarDatosResponsivaScreen(
          datosIniciales: _datos.copy(),
          mostrarMonitor: _valor('Monitor').isNotEmpty,
        ),
      ),
    );

    if (resultado != null && mounted) {
      setState(() => _datos = resultado);
    }
  }

  Future<Uint8List> _generarPdf(PdfPageFormat format) async {
    pw.MemoryImage? logo;
    try {
      final ByteData bytes = await rootBundle.load('assets/logo_autlan.png');
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {}

    final snKey = _snKeyPara(widget.nombrePestana);
    final serieEquipo = _valor(snKey);
    final tipoEquipo =
        _valor('Equipo').isNotEmpty ? _valor('Equipo') : 'Equipo';
    final (marcaEquipo, modeloEquipo) = _separarMarcaModelo();

    final nombreEmpresa = _nombreEncabezado();
    final fechaStr =
        '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}';

    final filasTabla = <List<String>>[
      [tipoEquipo, marcaEquipo, modeloEquipo, serieEquipo],
    ];

    if (_datos.incluyeCargador) {
      filasTabla.add([
        'Cargador',
        _datos.marcaCargador.isNotEmpty ? _datos.marcaCargador : marcaEquipo,
        '',
        _datos.serieCargador,
      ]);
    }

    if (_datos.incluyeMonitor) {
      filasTabla.add([
        'Monitor',
        _datos.marcaMonitor,
        '',
        _valor('Numero de Serie (2)'),
      ]);
    }

    final pdf = pw.Document();
    final headerColor = PdfColor.fromHex('#532E7C');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 24),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Positioned(
                top: 0,
                right: 0,
                child: pw.Text('Fecha: $fechaStr',
                    style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (logo != null)
                          pw.Container(
                            width: 72,
                            height: 72,
                            margin: const pw.EdgeInsets.only(bottom: 6),
                            child: pw.Image(logo),
                          ),
                        pw.Text(
                          nombreEmpresa,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: headerColor,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'HOJA RESPONSIVA DE EQUIPO',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 22),
                  pw.Text(
                    'Descripción del equipo:',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Table(
                    border: pw.TableBorder.all(color: headerColor, width: 0.7),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(2),
                      1: pw.FlexColumnWidth(2),
                      2: pw.FlexColumnWidth(2.4),
                      3: pw.FlexColumnWidth(2.4),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                            color: PdfColor.fromHex('#EFE8F6')),
                        children: [
                          _celdaTabla('Equipo', negrita: true),
                          _celdaTabla('Marca', negrita: true),
                          _celdaTabla('Modelo', negrita: true),
                          _celdaTabla('Serie', negrita: true),
                        ],
                      ),
                      for (final fila in filasTabla)
                        pw.TableRow(children: [
                          _celdaTabla(fila[0]),
                          _celdaTabla(fila[1]),
                          _celdaTabla(fila[2]),
                          _celdaTabla(fila[3]),
                        ]),
                    ],
                  ),
                  if (_datos.otrosSoftware.isNotEmpty) ...[
                    pw.Container(
                      width: double.infinity,
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          left: pw.BorderSide(color: headerColor, width: 0.7),
                          right: pw.BorderSide(color: headerColor, width: 0.7),
                          bottom:
                              pw.BorderSide(color: headerColor, width: 0.7),
                        ),
                      ),
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        'Otros: ${_datos.otrosSoftware}',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                  pw.SizedBox(height: 20),
                  pw.Text('Responsable de TI:',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  _cajaDatos(
                    headerColor: headerColor,
                    nombre: _datos.nombreResponsableTI,
                    empresa: _datos.empresaResponsableTI,
                    correo: _datos.correoResponsableTI,
                  ),
                  pw.SizedBox(height: 16),
                  pw.Text('Datos de quien Recibe el Equipo:',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  _cajaDatos(
                    headerColor: headerColor,
                    nombre: _datos.nombreRecibe,
                    empresa: _datos.empresaRecibe,
                    correo: _datos.correoRecibe,
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Reconozco que el equipo arriba mencionado, es una herramienta de trabajo y se encuentra en óptimas '
                    'condiciones de uso para realizar, exclusivamente, actividades propias de la empresa y el cual me comprometo a '
                    'presentar y/o a devolver en el momento en que me sea requerido.',
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                  pw.Spacer(),
                  pw.Divider(color: PdfColor.fromHex('#CCCCCC')),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Campamento Minero No.11, Aire Libre, Teziutlán Puebla, C.P.73960',
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                      pw.Text('F-FSIS-AXO/Rev.02',
                          style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _celdaTabla(String texto, {bool negrita = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _cajaDatos({
    required PdfColor headerColor,
    required String nombre,
    required String empresa,
    required String correo,
  }) {
    pw.Widget fila(String label, String valor) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          children: [
            pw.SizedBox(
              width: 60,
              child: pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Expanded(
              child: pw.Text(
                valor.isEmpty ? '____________________' : valor,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: headerColor, width: 0.8),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          fila('Nombre:', nombre),
          fila('Empresa:', empresa),
          fila('Correo:', correo),
          fila('Firma:', ''),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snKey = _snKeyPara(widget.nombrePestana);
    final serie = _valor(snKey).isNotEmpty ? _valor(snKey) : 'AXO';

    return Scaffold(
      backgroundColor: const Color(0xFF2C1D42),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vista previa',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            Text('Responsiva_$serie.pdf',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _abrirFormularioCompletar,
          ),
        ],
      ),
      body: SafeArea(
        child: _cargandoInicial
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : PdfPreview(
                key: ValueKey(_datos.hashCode),
                build: _generarPdf,
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                maxPageWidth: 450,
                pdfFileName: 'Responsiva_$serie.pdf',
                loadingWidget: const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
                scrollViewDecoration:
                    const BoxDecoration(color: Color(0xFF2C1D42)),
              ),
      ),
    );
  }
}

class _CompletarDatosResponsivaScreen extends StatefulWidget {
  final ResponsivaExtraData datosIniciales;
  final bool mostrarMonitor;

  const _CompletarDatosResponsivaScreen({
    required this.datosIniciales,
    required this.mostrarMonitor,
  });

  @override
  State<_CompletarDatosResponsivaScreen> createState() =>
      _CompletarDatosResponsivaScreenState();
}

class _CompletarDatosResponsivaScreenState
    extends State<_CompletarDatosResponsivaScreen> {
  static const primaryPurple = Color(0xFF532E7C);

  late final TextEditingController _marcaEquipoManual;
  late bool _incluyeCargador;
  late final TextEditingController _marcaCargador;
  late final TextEditingController _serieCargador;
  late bool _incluyeMonitor;
  late final TextEditingController _marcaMonitor;
  late final TextEditingController _otrosSoftware;
  late final TextEditingController _nombreTI;
  late final TextEditingController _empresaTI;
  late final TextEditingController _correoTI;
  late final TextEditingController _nombreRecibe;
  late final TextEditingController _empresaRecibe;
  late final TextEditingController _correoRecibe;

  @override
  void initState() {
    super.initState();
    final d = widget.datosIniciales;
    _marcaEquipoManual = TextEditingController(text: d.marcaEquipoManual);
    _incluyeCargador = d.incluyeCargador;
    _marcaCargador = TextEditingController(text: d.marcaCargador);
    _serieCargador = TextEditingController(text: d.serieCargador);
    _incluyeMonitor = d.incluyeMonitor;
    _marcaMonitor = TextEditingController(text: d.marcaMonitor);
    _otrosSoftware = TextEditingController(text: d.otrosSoftware);
    _nombreTI = TextEditingController(text: d.nombreResponsableTI);
    _empresaTI = TextEditingController(text: d.empresaResponsableTI);
    _correoTI = TextEditingController(text: d.correoResponsableTI);
    _nombreRecibe = TextEditingController(text: d.nombreRecibe);
    _empresaRecibe = TextEditingController(text: d.empresaRecibe);
    _correoRecibe = TextEditingController(text: d.correoRecibe);
  }

  @override
  void dispose() {
    _marcaEquipoManual.dispose();
    _marcaCargador.dispose();
    _serieCargador.dispose();
    _marcaMonitor.dispose();
    _otrosSoftware.dispose();
    _nombreTI.dispose();
    _empresaTI.dispose();
    _correoTI.dispose();
    _nombreRecibe.dispose();
    _empresaRecibe.dispose();
    _correoRecibe.dispose();
    super.dispose();
  }

  void _guardar() {
    final resultado = ResponsivaExtraData(
      marcaEquipoManual: _marcaEquipoManual.text.trim(),
      incluyeCargador: _incluyeCargador,
      marcaCargador: _marcaCargador.text.trim(),
      serieCargador: _serieCargador.text.trim(),
      incluyeMonitor: _incluyeMonitor,
      marcaMonitor: _marcaMonitor.text.trim(),
      otrosSoftware: _otrosSoftware.text.trim(),
      nombreResponsableTI: _nombreTI.text.trim(),
      empresaResponsableTI: _empresaTI.text.trim(),
      correoResponsableTI: _correoTI.text.trim(),
      nombreRecibe: _nombreRecibe.text.trim(),
      empresaRecibe: _empresaRecibe.text.trim(),
      correoRecibe: _correoRecibe.text.trim(),
    );
    Navigator.pop(context, resultado);
  }

  InputDecoration _decoracion(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFB0B0B8), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF7F7FA),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

  Widget _tituloSeccion(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: primaryPurple,
        ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: primaryPurple),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Completar Responsiva',
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _tituloSeccion('Equipo principal'),
                    TextField(
                      controller: _marcaEquipoManual,
                      decoration: _decoracion('Marca (opcional)',
                          hint:
                              'Se detecta automáticamente del Modelo si se deja vacío'),
                    ),
                    const SizedBox(height: 16),
                    _tituloSeccion('Accesorios'),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: primaryPurple,
                      checkboxShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _incluyeCargador,
                      title: const Text('¿Incluye cargador?',
                          style: TextStyle(fontSize: 14)),
                      onChanged: (v) =>
                          setState(() => _incluyeCargador = v ?? false),
                    ),
                    if (_incluyeCargador) ...[
                      const SizedBox(height: 8),
                      TextField(
                          controller: _marcaCargador,
                          decoration: _decoracion('Marca del cargador')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _serieCargador,
                          decoration: _decoracion('Serie del cargador')),
                    ],
                    if (widget.mostrarMonitor) ...[
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: primaryPurple,
                        checkboxShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _incluyeMonitor,
                        title: const Text('¿Incluye monitor?',
                            style: TextStyle(fontSize: 14)),
                        onChanged: (v) =>
                            setState(() => _incluyeMonitor = v ?? false),
                      ),
                      if (_incluyeMonitor) ...[
                        const SizedBox(height: 8),
                        TextField(
                            controller: _marcaMonitor,
                            decoration: _decoracion('Marca del monitor')),
                      ],
                    ],
                    const SizedBox(height: 16),
                    _tituloSeccion('Software / Licencias'),
                    TextField(
                      controller: _otrosSoftware,
                      maxLines: 2,
                      decoration: _decoracion('Otros',
                          hint: 'Ej. Microsoft Office 365'),
                    ),
                    const SizedBox(height: 16),
                    _tituloSeccion('Responsable de TI'),
                    TextField(
                        controller: _nombreTI,
                        decoration: _decoracion('Nombre')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _empresaTI,
                        decoration: _decoracion('Empresa')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _correoTI,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _decoracion('Correo')),
                    const SizedBox(height: 16),
                    _tituloSeccion('Quien recibe el equipo'),
                    TextField(
                        controller: _nombreRecibe,
                        decoration: _decoracion('Nombre')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _empresaRecibe,
                        decoration: _decoracion('Empresa')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _correoRecibe,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _decoracion('Correo')),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFF0F0F3))),
              ),
              child: SizedBox(
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
                      onTap: _guardar,
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        child: const Text(
                          'APLICAR Y ACTUALIZAR VISTA',
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
            ),
          ],
        ),
      ),
    );
  }
}