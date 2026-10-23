import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

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

class _ResponsivaPreviewScreenState extends State<ResponsivaPreviewScreen>
    with SingleTickerProviderStateMixin {
  static const int _dpiBase = 240;
  static const int _dpiMax = 480;
  static const double _zoomMin = 1;
  static const double _zoomMax = 5;

  late ResponsivaExtraData _datos;
  bool _cargandoInicial = true;
  bool _renderizando = true;
  String? _errorRender;

  Uint8List? _pdfBytes;
  List<Uint8List> _paginas = [];

  final TransformationController _zoomCtrl = TransformationController();
  final GlobalKey _visorKey = GlobalKey();
  late final AnimationController _animCtrl;
  VoidCallback? _animPaso;
  Timer? _tNitidez;
  Offset _posDobleToque = Offset.zero;
  Size _viewport = Size.zero;
  double _anchoPagina = 600;
  int _generacion = 0;
  int _genRaster = 0;
  int _dpiActual = _dpiBase;

  @override
  void initState() {
    super.initState();
    _datos = ResponsivaExtraData(
      incluyeMonitor: _valor('Monitor').isNotEmpty,
      otrosSoftware: _softwareDesdeFila(),
      nombreRecibe: _valor('Nombre'),
      correoRecibe: '',
    );
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240))
      ..addListener(() => _animPaso?.call())
      ..addStatusListener((e) {
        if (e == AnimationStatus.completed) _programarNitidez();
      });
    _iniciar();
  }

  @override
  void dispose() {
    _tNitidez?.cancel();
    _animCtrl.dispose();
    _zoomCtrl.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final user = await AuthService.obtenerUsuarioActual();
    if (!mounted) return;
    _datos.nombreResponsableTI = user?.nombre ?? '';
    _datos.correoResponsableTI =
        user != null ? _correoDesdeUsuario(user.correo) : '';
    setState(() => _cargandoInicial = false);
    await _regenerar();
  }

  Future<void> _regenerar() async {
    final miGeneracion = ++_generacion;
    _genRaster++;
    setState(() {
      _renderizando = true;
      _errorRender = null;
    });

    try {
      final bytes = await _generarPdf(PdfPageFormat.letter);
      final paginas = <Uint8List>[];
      await for (final raster in Printing.raster(bytes, dpi: _dpiBase.toDouble())) {
        paginas.add(await raster.toPng());
      }

      if (!mounted || miGeneracion != _generacion) return;
      _zoomCtrl.value = Matrix4.identity();
      setState(() {
        _pdfBytes = bytes;
        _paginas = paginas;
        _dpiActual = _dpiBase;
        _renderizando = false;
      });
    } catch (e) {
      if (!mounted || miGeneracion != _generacion) return;
      setState(() {
        _renderizando = false;
        _errorRender = 'No se pudo generar la vista previa: $e';
      });
    }
  }

  String _valor(String key) {
    final v = widget.fila[key];
    return v == null ? '' : v.toString().trim();
  }

  String _na(String v) => v.trim().isEmpty ? 'N/A' : v.trim();

  String _snKeyPara(String pestana) {
    return 'Numero de Serie';
  }

  String get _nombreArchivo {
    final sn = _valor(_snKeyPara(widget.nombrePestana));
    return 'Responsiva_${sn.isNotEmpty ? sn : 'AXO'}.pdf';
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

  (String marca, String modelo) _separarMonitor() {
    final completo = _valor('Monitor');
    final partes =
        completo.isEmpty ? <String>[] : completo.split(RegExp(r'\s+'));
    final marcaManual = _datos.marcaMonitor.trim();
    if (marcaManual.isNotEmpty) {
      if (partes.length > 1 &&
          partes.first.toLowerCase() == marcaManual.toLowerCase()) {
        return (marcaManual, partes.sublist(1).join(' '));
      }
      return (marcaManual, completo);
    }
    if (partes.isEmpty) return ('', '');
    if (partes.length == 1) return ('', completo);
    return (partes.first, partes.sublist(1).join(' '));
  }

  String _correoDesdeUsuario(String usuario) {
    if (usuario.isEmpty) return '';
    if (usuario.contains('@')) return usuario;
    final limpio = usuario.toLowerCase().replaceAll(' ', '.');
    return '$limpio@autlan.com.mx';
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
    return partes.join(' | ');
  }

  String _nombreEncabezado() {
    var n = widget.inventario?.nombre.trim() ?? '';
    n = n.replaceFirst(RegExp(r'^inventario\s+', caseSensitive: false), '').trim();
    return n.isEmpty ? 'AUTLAN' : n.toUpperCase();
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
      _datos = resultado;
      await _regenerar();
    }
  }

  Future<void> _descargar() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    await Printing.sharePdf(bytes: bytes, filename: _nombreArchivo);
  }

  Future<void> _compartir() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: _nombreArchivo);
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: 'application/pdf',
          name: _nombreArchivo,
        ),
      ],
      text: 'Hoja responsiva',
      sharePositionOrigin:
          box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  double get _escalaActual => _zoomCtrl.value.getMaxScaleOnAxis();

  Matrix4 _limitar(Matrix4 m) {
    final e = m.storage[0].clamp(_zoomMin, _zoomMax).toDouble();
    if (e <= _zoomMin + 0.001) return Matrix4.identity();
    final tx = m.storage[12].clamp(_viewport.width * (1 - e), 0.0).toDouble();
    final ty = m.storage[13].clamp(_viewport.height * (1 - e), 0.0).toDouble();
    return Matrix4(e, 0, 0, 0, 0, e, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
  }

  Matrix4 _zoomAlrededor(double factor, Offset foco) {
    final actual = _escalaActual;
    final destino = (actual * factor).clamp(_zoomMin, _zoomMax).toDouble();
    final k = destino / actual;
    return Matrix4.translationValues(foco.dx, foco.dy, 0) *
        Matrix4.diagonal3Values(k, k, 1) *
        Matrix4.translationValues(-foco.dx, -foco.dy, 0) *
        _zoomCtrl.value;
  }

  void _fijar(Matrix4 m) {
    _animCtrl.stop();
    _zoomCtrl.value = _limitar(m);
    _programarNitidez();
  }

  void _animarA(Matrix4 destino) {
    final d = _limitar(destino);
    final e0 = _escalaActual;
    final x0 = _zoomCtrl.value.storage[12];
    final y0 = _zoomCtrl.value.storage[13];
    final e1 = d.storage[0];
    final x1 = d.storage[12];
    final y1 = d.storage[13];
    _animPaso = () {
      final t = Curves.easeOutCubic.transform(_animCtrl.value);
      final e = e0 + (e1 - e0) * t;
      _zoomCtrl.value = Matrix4(e, 0, 0, 0, 0, e, 0, 0, 0, 0, 1, 0,
          x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 0, 1);
    };
    _animCtrl
      ..stop()
      ..reset()
      ..forward();
  }

  void _panear(double dx, double dy) {
    if (_escalaActual <= _zoomMin + 0.001) return;
    _fijar(Matrix4.translationValues(-dx, -dy, 0) * _zoomCtrl.value);
  }

  void _zoomBoton(double multiplicador) {
    final centro = Offset(_viewport.width / 2, _viewport.height / 2);
    _animarA(_zoomAlrededor(multiplicador, centro));
  }

  void _ajustar() => _animarA(Matrix4.identity());

  void _dobleToque() {
    if (_escalaActual > 1.05) {
      _ajustar();
    } else {
      _animarA(_zoomAlrededor(2.5, _posDobleToque));
    }
  }

  Offset _aLocal(Offset global) {
    final caja = _visorKey.currentContext?.findRenderObject() as RenderBox?;
    return caja != null
        ? caja.globalToLocal(global)
        : Offset(_viewport.width / 2, _viewport.height / 2);
  }

  void _senalPuntero(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
        final s = ev as PointerScrollEvent;
        final ctrl = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (ctrl) {
          _fijar(_zoomAlrededor(
              math.exp(-s.scrollDelta.dy / 240), _aLocal(s.position)));
        } else {
          _panear(s.scrollDelta.dx, s.scrollDelta.dy);
        }
      });
    } else if (e is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
        final s = ev as PointerScaleEvent;
        _fijar(_zoomAlrededor(s.scale, _aLocal(s.position)));
      });
    }
  }

  KeyEventResult _tecla(FocusNode nodo, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    const paso = 90.0;
    if (k == LogicalKeyboardKey.arrowDown) {
      _panear(0, paso);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _panear(0, -paso);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _panear(-paso, 0);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _panear(paso, 0);
    } else if (k == LogicalKeyboardKey.pageDown) {
      _panear(0, _viewport.height * 0.8);
    } else if (k == LogicalKeyboardKey.pageUp) {
      _panear(0, -_viewport.height * 0.8);
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      _zoomBoton(1.3);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _zoomBoton(1 / 1.3);
    } else if (k == LogicalKeyboardKey.digit0 ||
        k == LogicalKeyboardKey.numpad0 ||
        k == LogicalKeyboardKey.home) {
      _ajustar();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  int _dpiObjetivo() {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final dpi = _anchoPagina * _escalaActual * dpr / 8.5;
    for (final n in const [_dpiBase, 320, 400]) {
      if (dpi <= n) return n;
    }
    return _dpiMax;
  }

  void _programarNitidez() {
    _tNitidez?.cancel();
    _tNitidez = Timer(const Duration(milliseconds: 280), () {
      if (!mounted || _pdfBytes == null || _renderizando) return;
      final objetivo = _dpiObjetivo();
      if (objetivo != _dpiActual) _rasterizar(objetivo);
    });
  }

  Future<void> _rasterizar(int dpi) async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    final g = ++_genRaster;
    try {
      final paginas = <Uint8List>[];
      await for (final raster in Printing.raster(bytes, dpi: dpi.toDouble())) {
        paginas.add(await raster.toPng());
      }
      if (!mounted || g != _genRaster || !identical(bytes, _pdfBytes)) return;
      setState(() {
        _paginas = paginas;
        _dpiActual = dpi;
      });
    } catch (_) {}
  }

  Future<Uint8List> _generarPdf(PdfPageFormat format) async {
    pw.MemoryImage? logo;
    final inv = widget.inventario;
    if (inv != null && inv.logoId.isNotEmpty) {
      try {
        final datosLogo =
            await AuthService.obtenerImagenInventario(inv.id, 'logo', inv.logoId);
        if (datosLogo != null && datosLogo.isNotEmpty) {
          logo = pw.MemoryImage(datosLogo);
        }
      } catch (_) {}
    }
    if (logo == null) {
      try {
        final ByteData bytes = await rootBundle.load('assets/logo_autlan.png');
        logo = pw.MemoryImage(bytes.buffer.asUint8List());
      } catch (_) {}
    }

    final snKey = _snKeyPara(widget.nombrePestana);
    final serieEquipo = _valor(snKey);
    final tipoEquipo =
        _valor('Equipo').isNotEmpty ? _valor('Equipo') : 'Laptop';
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
      final (marcaMon, modeloMon) = _separarMonitor();
      filasTabla.add([
        'Monitor',
        marcaMon,
        modeloMon,
        _valor('Numero de Serie (2)'),
      ]);
    }

    final pdf = pw.Document();

    final azulOscuro = PdfColor.fromHex('#2F5597');
    final fondoClaro = PdfColor.fromHex('#E6F0F9');
    final colorCelesteTexto = PdfColor.fromHex('#5B9BD5');
    final lineaTabla = PdfColor.fromHex('#9DC3E6');

    const flexes = [4, 5, 6, 5];
    const cabeceras = ['Equipo', 'Marca', 'Modelo', 'Serie'];

    pw.Widget filaTabla(List<String> valores, {bool cabecera = false}) {
      return pw.Row(
        children: [
          for (var k = 0; k < 4; k++)
            pw.Expanded(
              flex: flexes[k],
              child: pw.Text(
                cabecera ? cabeceras[k] : _na(valores[k]),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight:
                      cabecera ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: cabecera ? azulOscuro : PdfColors.black,
                ),
              ),
            ),
        ],
      );
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 110,
                    height: 95,
                    alignment: pw.Alignment.centerLeft,
                    child: logo != null
                        ? pw.Image(logo,
                            fit: pw.BoxFit.contain,
                            alignment: pw.Alignment.centerLeft)
                        : pw.SizedBox(),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          nombreEmpresa,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 17,
                            color: azulOscuro,
                          ),
                        ),
                        pw.SizedBox(height: 14),
                        pw.Text(
                          'HOJA RESPONSIVA DE EQUIPO',
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 110),
                ],
              ),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Fecha: $fechaStr',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 6),
                child: pw.Text(
                  'Descripción del equipo:',
                  style: pw.TextStyle(
                    fontSize: 12.5,
                    fontWeight: pw.FontWeight.bold,
                    color: colorCelesteTexto,
                  ),
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: azulOscuro, width: 1.8),
                  borderRadius: pw.BorderRadius.circular(14),
                ),
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                  children: [
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: filaTabla(const [], cabecera: true),
                    ),
                    pw.Container(height: 1, color: lineaTabla),
                    for (var k = 0; k < filasTabla.length; k++)
                      pw.Container(
                        width: double.infinity,
                        color: k.isEven ? fondoClaro : PdfColors.white,
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: filaTabla(filasTabla[k]),
                      ),
                    pw.Container(
                      width: double.infinity,
                      color: filasTabla.length.isEven
                          ? fondoClaro
                          : PdfColors.white,
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(
                              text: 'Otros: ',
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold),
                            ),
                            pw.TextSpan(
                              text: _na(_datos.otrosSoftware),
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 34),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 6),
                child: pw.Text(
                  'Responsable de TI:',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 8),
              _cajaFormulario(
                borderColor: azulOscuro,
                nombre: _datos.nombreResponsableTI,
                empresa: _datos.empresaResponsableTI,
                correo: _datos.correoResponsableTI,
              ),
              pw.SizedBox(height: 26),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 6),
                child: pw.Text(
                  'Datos de quien Recibe el Equipo:',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 8),
              _cajaFormulario(
                borderColor: azulOscuro,
                nombre: _datos.nombreRecibe,
                empresa: _datos.empresaRecibe,
                correo: _datos.correoRecibe,
              ),
              pw.SizedBox(height: 26),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                child: pw.Text(
                  'Reconozco que el equipo arriba mencionado, es una herramienta de trabajo y se encuentra en óptimas '
                  'condiciones de uso para realizar, exclusivamente, actividades propias de la empresa y el cual me comprometo a '
                  'presentar y/o a devolver en el momento en que me sea requerido.',
                  style: const pw.TextStyle(fontSize: 9.5, height: 1.35),
                ),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Campamento Minero No.11, Aire Libre, Teziutlán Puebla, C.P.73960',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(
                    'F-FSIS-AXO/Rev.02',
                    style: const pw.TextStyle(fontSize: 8),
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

  pw.Widget _cajaFormulario({
    required PdfColor borderColor,
    required String nombre,
    required String empresa,
    required String correo,
  }) {
    pw.Widget fila(String label, pw.Widget valor) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 68,
              child: pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 11),
              ),
            ),
            valor,
          ],
        ),
      );
    }

    pw.Widget subrayado(String texto) => pw.Text(
          _na(texto),
          style: const pw.TextStyle(
            fontSize: 11,
            decoration: pw.TextDecoration.underline,
          ),
        );

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(20, 16, 20, 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderColor, width: 1.8),
        borderRadius: pw.BorderRadius.circular(18),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          fila('Nombre:', subrayado(nombre)),
          fila('Empresa:', subrayado(empresa)),
          fila('Correo:', subrayado(correo)),
          fila(
            'Firma:',
            pw.Container(
              width: 160,
              height: 12,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _visor() {
    if (_cargandoInicial || _renderizando) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_errorRender != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(
                _errorRender!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _regenerar,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);

        const relacion = 8.5 / 11.0;
        final anchoPorAlto = (constraints.maxHeight - 20) * relacion;
        final anchoPagina = [
          constraints.maxWidth - 24,
          anchoPorAlto,
          900.0,
        ].reduce((a, b) => a < b ? a : b).clamp(200.0, 900.0);
        _anchoPagina = anchoPagina;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: (d) => _posDobleToque = d.localPosition,
          onDoubleTap: _dobleToque,
          child: InteractiveViewer(
            transformationController: _zoomCtrl,
            minScale: _zoomMin,
            maxScale: _zoomMax,
            panEnabled: true,
            scaleEnabled: true,
            trackpadScrollCausesScale: false,
            onInteractionStart: (_) => _animCtrl.stop(),
            onInteractionEnd: (_) => _programarNitidez(),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerSignal: _senalPuntero,
              child: Center(
                child: SizedBox(
                  width: anchoPagina,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final png in _paginas)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Image.memory(
                            png,
                            fit: BoxFit.fitWidth,
                            filterQuality: FilterQuality.high,
                            gaplessPlayback: true,
                            isAntiAlias: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _controlesZoom() {
    Widget boton(IconData icono, String tip, VoidCallback onTap) {
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(icono, color: Colors.white, size: 21),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          boton(Icons.add, 'Acercar', () => _zoomBoton(1.4)),
          Container(
              width: 24, height: 1, color: Colors.white.withOpacity(0.18)),
          boton(Icons.remove, 'Alejar', () => _zoomBoton(1 / 1.4)),
          Container(
              width: 24, height: 1, color: Colors.white.withOpacity(0.18)),
          boton(Icons.fit_screen_outlined, 'Ajustar', _ajustar),
        ],
      ),
    );
  }

  Widget _barraInferior() {
    const moradoBoton = Color(0xFF7B3FB0);
    final habilitado = _pdfBytes != null && !_renderizando;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: habilitado ? _compartir : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white38,
                  side: BorderSide(
                      color: Colors.white.withOpacity(habilitado ? 0.55 : 0.2),
                      width: 1.2),
                  shape: const StadiumBorder(),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                ),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Compartir',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: habilitado ? _descargar : null,
                style: FilledButton.styleFrom(
                  backgroundColor: moradoBoton,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: moradoBoton.withOpacity(0.35),
                  disabledForegroundColor: Colors.white38,
                  shape: const StadiumBorder(),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 20),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Descargar PDF',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _indicadorPagina() {
    final total = _paginas.isEmpty ? 1 : _paginas.length;

    return AnimatedBuilder(
      animation: _zoomCtrl,
      builder: (context, _) {
        final zoom = _escalaActual;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Text(
            zoom > 1.05
                ? 'Pág 1 de $total  ·  ${(zoom * 100).round()}%'
                : 'Pág 1 de $total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final esAncha = ancho >= 600;
    final listo = !_renderizando && _errorRender == null && !_cargandoInicial;

    return Scaffold(
      backgroundColor: const Color(0xFF2C1D42),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
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
            Text(_nombreArchivo,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        ),
        actions: [
          if (esAncha)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: TextButton.icon(
                onPressed: _abrirFormularioCompletar,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.15),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                icon: const Icon(Icons.edit_document, size: 18),
                label: const Text(
                  'Editar responsiva',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Editar responsiva',
              icon: const Icon(Icons.edit_note, color: Colors.white),
              onPressed: _abrirFormularioCompletar,
            ),
        ],
      ),
      body: SafeArea(
        child: Focus(
          autofocus: true,
          onKeyEvent: _tecla,
          child: Column(
            children: [
              Expanded(
                child: ClipRect(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SizedBox.expand(
                          key: _visorKey,
                          child: _visor(),
                        ),
                      ),
                      if (listo)
                        Positioned(
                          right: 12,
                          top: 12,
                          child: _controlesZoom(),
                        ),
                      if (listo)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 10,
                          child: Center(
                            child: IgnorePointer(child: _indicadorPagina()),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(child: _barraInferior()),
              ),
            ],
          ),
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
  static const _borde = Color(0xFFD5D5E0);
  static const _textoSuave = Color(0xFF6B7280);

  late bool _incluyeCargador;
  late bool _incluyeMonitor;
  late final TextEditingController _marcaCargador;
  late final TextEditingController _serieCargador;
  late final TextEditingController _otrosSoftware;
  late final TextEditingController _nombreTI;
  late final TextEditingController _correoTI;
  late final TextEditingController _nombreRecibe;
  late final TextEditingController _empresaRecibe;
  late final TextEditingController _correoRecibe;

  @override
  void initState() {
    super.initState();
    final d = widget.datosIniciales;
    _incluyeCargador = d.incluyeCargador;
    _incluyeMonitor = d.incluyeMonitor;
    _marcaCargador = TextEditingController(text: d.marcaCargador);
    _serieCargador = TextEditingController(text: d.serieCargador);
    _otrosSoftware = TextEditingController(text: d.otrosSoftware);
    _nombreTI = TextEditingController(text: d.nombreResponsableTI);
    _correoTI = TextEditingController(text: d.correoResponsableTI);
    _nombreRecibe = TextEditingController(text: d.nombreRecibe);
    _empresaRecibe = TextEditingController(text: d.empresaRecibe);
    _correoRecibe = TextEditingController(text: d.correoRecibe);
  }

  @override
  void dispose() {
    _marcaCargador.dispose();
    _serieCargador.dispose();
    _otrosSoftware.dispose();
    _nombreTI.dispose();
    _correoTI.dispose();
    _nombreRecibe.dispose();
    _empresaRecibe.dispose();
    _correoRecibe.dispose();
    super.dispose();
  }

  void _guardar() {
    final d = widget.datosIniciales;
    final resultado = ResponsivaExtraData(
      marcaEquipoManual: d.marcaEquipoManual,
      incluyeCargador: _incluyeCargador,
      marcaCargador: _marcaCargador.text.trim(),
      serieCargador: _serieCargador.text.trim(),
      incluyeMonitor: _incluyeMonitor,
      marcaMonitor: d.marcaMonitor,
      otrosSoftware: _otrosSoftware.text.trim(),
      nombreResponsableTI: _nombreTI.text.trim(),
      empresaResponsableTI: d.empresaResponsableTI,
      correoResponsableTI: _correoTI.text.trim(),
      nombreRecibe: _nombreRecibe.text.trim(),
      empresaRecibe: _empresaRecibe.text.trim(),
      correoRecibe: _correoRecibe.text.trim(),
    );
    Navigator.pop(context, resultado);
  }

  Widget _campo({
    required TextEditingController controlador,
    required String etiqueta,
    required IconData icono,
    String? ayuda,
    TextInputType? teclado,
    TextCapitalization mayusculas = TextCapitalization.none,
    int maxLineas = 1,
    bool ultimo = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controlador,
        keyboardType: teclado,
        textCapitalization: mayusculas,
        textInputAction: ultimo ? TextInputAction.done : TextInputAction.next,
        minLines: 1,
        maxLines: maxLineas,
        style: const TextStyle(fontSize: 15, color: Colors.black87),
        decoration: InputDecoration(
          labelText: etiqueta,
          hintText: ayuda,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: primaryPurple),
          hintStyle: const TextStyle(color: Color(0xFFA3A3B0), fontSize: 14),
          prefixIcon: Icon(icono, size: 20, color: primaryPurple),
          suffixIcon: const Icon(Icons.edit_outlined,
              size: 17, color: Color(0xFFB4B4C0)),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _borde, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryPurple, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _tarjeta({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required List<Widget> hijos,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECECF2)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EAF8),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icono, size: 20, color: primaryPurple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    Text(subtitulo,
                        style: const TextStyle(
                            fontSize: 12, color: _textoSuave)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...hijos,
        ],
      ),
    );
  }

  Widget _interruptor({
    required String titulo,
    String? detalle,
    required bool valor,
    required ValueChanged<bool> alCambiar,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: valor ? const Color(0xFFF6F0FB) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: valor ? primaryPurple.withOpacity(0.35) : _borde),
        ),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: primaryPurple,
          title: Text(titulo,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: detalle == null
              ? null
              : Text(detalle,
                  style: const TextStyle(fontSize: 12, color: _textoSuave)),
          value: valor,
          onChanged: alCambiar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: primaryPurple),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Editar responsiva',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const Text(
                          'Toca un campo para modificarlo. Lo vacío se imprime como N/A.',
                          style: TextStyle(fontSize: 12, color: _textoSuave),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE8E8EE)),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tarjeta(
                          icono: Icons.devices_other_outlined,
                          titulo: 'Accesorios incluidos',
                          subtitulo: 'Se agregan como filas en la tabla',
                          hijos: [
                            _interruptor(
                              titulo: 'Cargador',
                              valor: _incluyeCargador,
                              alCambiar: (v) =>
                                  setState(() => _incluyeCargador = v),
                            ),
                            if (_incluyeCargador) ...[
                              const SizedBox(height: 4),
                              _campo(
                                controlador: _marcaCargador,
                                etiqueta: 'Marca del cargador',
                                ayuda: 'Si lo dejas vacío usa la del equipo',
                                icono: Icons.bolt_outlined,
                                mayusculas: TextCapitalization.words,
                              ),
                              _campo(
                                controlador: _serieCargador,
                                etiqueta: 'Serie del cargador',
                                ayuda: 'Ej. 5C50PV8',
                                icono: Icons.tag,
                                mayusculas: TextCapitalization.characters,
                              ),
                            ],
                            if (widget.mostrarMonitor)
                              _interruptor(
                                titulo: 'Monitor',
                                detalle:
                                    'Marca, modelo y serie se toman del registro',
                                valor: _incluyeMonitor,
                                alCambiar: (v) =>
                                    setState(() => _incluyeMonitor = v),
                              ),
                          ],
                        ),
                        _tarjeta(
                          icono: Icons.apps_outlined,
                          titulo: 'Software y licencias',
                          subtitulo: 'Aparece en la fila "Otros"',
                          hijos: [
                            _campo(
                              controlador: _otrosSoftware,
                              etiqueta: 'Otros',
                              ayuda: 'Ej. Microsoft Office 365',
                              icono: Icons.workspace_premium_outlined,
                              maxLineas: 3,
                            ),
                          ],
                        ),
                        _tarjeta(
                          icono: Icons.support_agent_outlined,
                          titulo: 'Responsable de TI',
                          subtitulo: 'Quien entrega el equipo',
                          hijos: [
                            _campo(
                              controlador: _nombreTI,
                              etiqueta: 'Nombre completo',
                              ayuda: 'Escribe el nombre',
                              icono: Icons.person_outline,
                              mayusculas: TextCapitalization.words,
                            ),
                            _campo(
                              controlador: _correoTI,
                              etiqueta: 'Correo',
                              ayuda: 'nombre@autlan.com.mx',
                              icono: Icons.mail_outline,
                              teclado: TextInputType.emailAddress,
                              ultimo: true,
                            ),
                          ],
                        ),
                        _tarjeta(
                          icono: Icons.badge_outlined,
                          titulo: 'Quien recibe el equipo',
                          subtitulo: 'Usuario que firma la responsiva',
                          hijos: [
                            _campo(
                              controlador: _nombreRecibe,
                              etiqueta: 'Nombre completo',
                              ayuda: 'Escribe el nombre',
                              icono: Icons.person_outline,
                              mayusculas: TextCapitalization.words,
                            ),
                            _campo(
                              controlador: _empresaRecibe,
                              etiqueta: 'Empresa',
                              ayuda: 'Ej. AUTLAN',
                              icono: Icons.business_outlined,
                              mayusculas: TextCapitalization.characters,
                            ),
                            _campo(
                              controlador: _correoRecibe,
                              etiqueta: 'Correo',
                              ayuda: 'nombre@autlan.com.mx',
                              icono: Icons.mail_outline,
                              teclado: TextInputType.emailAddress,
                              ultimo: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE8E8EE))),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryPurple,
                            side: const BorderSide(color: _borde),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Cancelar',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: FilledButton.icon(
                          onPressed: _guardar,
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryPurple,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Guardar y actualizar',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
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
}