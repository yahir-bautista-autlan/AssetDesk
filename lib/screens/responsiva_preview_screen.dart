import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
  static const int _dpiMin = 144;
  static const int _dpiMax = 480;
  static const double _zoomMin = 1;
  static const double _zoomMax = 5;
  static const PdfPageFormat _formato = PdfPageFormat.a4;

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
  int _dpiActual = _dpiMin;
  String _direccionPlanta = '';
  String _codigoFormato = '';
  Map<String, dynamic> _equipo = {};
  List<Map<String, dynamic>> _impresoras = [];
  static final Map<String, Future<Uint8List?>> _logos = {};

  @override
  void initState() {
    super.initState();
    final esImpresora = widget.nombrePestana == 'Impresoras';
    _equipo = esImpresora ? <String, dynamic>{} : widget.fila;
    _impresoras = esImpresora
        ? <Map<String, dynamic>>[widget.fila]
        : <Map<String, dynamic>>[];
    _datos = ResponsivaExtraData(
      incluyeMonitor: _valorEq('Monitor').isNotEmpty,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _iniciar();
    });
  }

  @override
  void dispose() {
    _tNitidez?.cancel();
    _animCtrl.dispose();
    _zoomCtrl.dispose();
    super.dispose();
  }

  Future<void> _esperarTransicion() async {
    final animacion = ModalRoute.of(context)?.animation;
    if (animacion == null || animacion.status == AnimationStatus.completed) {
      return;
    }
    final listo = Completer<void>();
    void escucha(AnimationStatus estado) {
      if (estado == AnimationStatus.completed ||
          estado == AnimationStatus.dismissed) {
        if (!listo.isCompleted) listo.complete();
      }
    }

    animacion.addStatusListener(escucha);
    await listo.future.timeout(const Duration(milliseconds: 800), onTimeout: () {});
    animacion.removeStatusListener(escucha);
  }

  Future<void> _iniciar() async {
    _logoBytes();
    final inv = widget.inventario;
    final futuroResponsable =
        inv != null ? AuthService.obtenerResponsableInventario(inv.id) : null;
    final futuroRelacionados = _cargarRelacionados();
    await _esperarTransicion();
    if (!mounted) return;
    final user = await AuthService.obtenerUsuarioActual();
    if (!mounted) return;
    await futuroRelacionados;
    if (!mounted) return;
    Map<String, String>? datosInv;
    try {
      datosInv = await futuroResponsable;
    } catch (_) {}
    if (!mounted) return;
    _direccionPlanta = datosInv?['direccion'] ?? '';
    _codigoFormato = datosInv?['codigoFormato'] ?? '';
    final correoUsuario =
        user != null ? _correoDesdeUsuario(user.correo).toLowerCase() : '';
    final correoResponsable = inv?.responsableEmail.trim().toLowerCase() ?? '';
    if (correoResponsable.isNotEmpty) {
      var nombreResponsable = '';
      if (correoResponsable == correoUsuario) {
        nombreResponsable = user?.nombre ?? '';
      } else {
        nombreResponsable = datosInv?['nombre'] ?? '';
      }
      if (!mounted) return;
      _datos.nombreResponsableTI = nombreResponsable.isNotEmpty
          ? nombreResponsable
          : _nombreDesdeCorreo(correoResponsable);
      _datos.correoResponsableTI = correoResponsable;
    } else {
      _datos.nombreResponsableTI = user?.nombre ?? '';
      _datos.correoResponsableTI = correoUsuario;
    }
    setState(() => _cargandoInicial = false);
    await _regenerar();
  }

  Future<void> _regenerar() async {
    final miGeneracion = ++_generacion;
    _genRaster++;
    final dpi = _dpiObjetivo();
    setState(() {
      _renderizando = true;
      _errorRender = null;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 40));
      final bytes = await _generarPdf(_formato);
      final paginas = <Uint8List>[];
      await for (final raster in Printing.raster(bytes, dpi: dpi.toDouble())) {
        paginas.add(await raster.toPng());
      }

      if (!mounted || miGeneracion != _generacion) return;
      _zoomCtrl.value = Matrix4.identity();
      setState(() {
        _pdfBytes = bytes;
        _paginas = paginas;
        _dpiActual = dpi;
        _renderizando = false;
      });
      _programarNitidez();
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

  String _valorEq(String key) {
    final v = _equipo[key];
    return v == null ? '' : v.toString().trim();
  }

  String _claveNombre(dynamic v) {
    if (v == null) return '';
    return v
        .toString()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<List<Map<String, dynamic>>> _filasDe(String pestana) async {
    final ss = widget.inventario?.spreadsheetId ?? '';
    if (ss.isEmpty) return const [];
    try {
      final data = await AuthService.obtenerPestana(ss, pestana);
      final rows = data?['rows'];
      if (rows is List) {
        return [
          for (final r in rows)
            if (r is Map) Map<String, dynamic>.from(r),
        ];
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _cargarRelacionados() async {
    final persona = _claveNombre(_valor('Nombre'));
    if (persona.isEmpty) return;

    final desdeImpresoras = widget.nombrePestana == 'Impresoras';
    final resultados = await Future.wait([
      _filasDe('Impresoras'),
      desdeImpresoras
          ? _filasDe('Captura')
          : Future.value(const <Map<String, dynamic>>[]),
    ]);

    bool delUsuario(Map<String, dynamic> f) =>
        _claveNombre(f['Nombre']) == persona &&
        _claveNombre(f['Estatus']) == 'activo';

    final serieActual = _claveNombre(_valor('Numero de Serie'));
    final impresoras = <Map<String, dynamic>>[
      if (desdeImpresoras) widget.fila,
    ];
    for (final f in resultados[0]) {
      if (!delUsuario(f)) continue;
      if (desdeImpresoras &&
          _claveNombre(f['Numero de Serie']) == serieActual) {
        continue;
      }
      impresoras.add(f);
    }

    var equipo = _equipo;
    if (desdeImpresoras) {
      equipo = <String, dynamic>{};
      for (final f in resultados[1]) {
        if (delUsuario(f)) {
          equipo = f;
          break;
        }
      }
    }

    _equipo = equipo;
    _impresoras = impresoras;
    _datos.incluyeMonitor = _valorEq('Monitor').isNotEmpty;
    _datos.otrosSoftware = _softwareDesdeFila();
  }

  String _na(String v) => v.trim().isEmpty ? 'N/A' : v.trim();

  String _snKeyPara(String pestana) {
    return 'Numero de Serie';
  }

  String get _nombreArchivo {
    final snKey = _snKeyPara(widget.nombrePestana);
    var sn = _valorEq(snKey);
    if (sn.isEmpty && _impresoras.isNotEmpty) {
      sn = _impresoras.first[snKey]?.toString().trim() ?? '';
    }
    return 'Responsiva_${sn.isNotEmpty ? sn : 'AXO'}.pdf';
  }

  (String marca, String modelo) _separarMarcaModelo() {
    return _partirMarcaModelo(_valorEq('Modelo'),
        manual: _datos.marcaEquipoManual);
  }

  (String marca, String modelo) _partirMarcaModelo(String modeloCompleto,
      {String manual = ''}) {
    if (manual.isNotEmpty) {
      return (manual, modeloCompleto);
    }
    if (modeloCompleto.isEmpty) return ('', '');

    final partes = modeloCompleto.split(RegExp(r'\s+'));
    if (partes.length <= 1) return ('', modeloCompleto);

    final marca = partes.first;
    final resto = partes.sublist(1).join(' ');
    return (marca, resto);
  }

  (String marca, String modelo) _separarMonitor() {
    final completo = _valorEq('Monitor');
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

  String _nombreDesdeCorreo(String correo) {
    final local = correo.split('@').first;
    return local
        .split(RegExp(r'[._\-]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
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
      final producto = _valorEq(p[0]);
      final licencia = _valorEq(p[1]);
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
          mostrarMonitor: _valorEq('Monitor').isNotEmpty,
          hayEquipo: _equipo.isNotEmpty,
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
    final bruto = _anchoPagina * _escalaActual * dpr * 72 / _formato.width;
    final paso = (bruto / 24).ceil() * 24;
    return paso.clamp(_dpiMin, _dpiMax).toInt();
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

  Future<Uint8List> _recortarLogo(Uint8List datos) async {
    try {
      final codec = await ui.instantiateImageCodec(datos);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return datos;
      final w = img.width;
      final h = img.height;
      final px = bd.buffer.asUint8List();
      final paso = math.max(1, (w / 240).ceil());
      var minX = w;
      var minY = h;
      var maxX = -1;
      var maxY = -1;
      for (var y = 0; y < h; y += paso) {
        final fila = y * w * 4;
        for (var x = 0; x < w; x += paso) {
          final i = fila + x * 4;
          if (px[i + 3] < 24) continue;
          if (px[i] > 244 && px[i + 1] > 244 && px[i + 2] > 244) continue;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
      if (maxX < minX || maxY < minY) return datos;
      final margen = paso + 2;
      minX = math.max(0, minX - margen);
      minY = math.max(0, minY - margen);
      maxX = math.min(w - 1, maxX + margen);
      maxY = math.min(h - 1, maxY + margen);
      final cw = maxX - minX + 1;
      final ch = maxY - minY + 1;
      if (cw * ch >= w * h * 0.96) return datos;
      final grabador = ui.PictureRecorder();
      final lienzo = ui.Canvas(grabador);
      lienzo.drawImageRect(
        img,
        ui.Rect.fromLTWH(
            minX.toDouble(), minY.toDouble(), cw.toDouble(), ch.toDouble()),
        ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final salida = await grabador.endRecording().toImage(cw, ch);
      final png = await salida.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return datos;
      return png.buffer.asUint8List();
    } catch (_) {
      return datos;
    }
  }

  Future<Uint8List?> _logoBytes() {
    final inv = widget.inventario;
    final clave = inv == null ? 'asset' : '${inv.id}|${inv.logoId}';
    var transitorio = false;
    final futuro = _logos.putIfAbsent(clave, () async {
      Uint8List? datos;
      if (inv != null && inv.logoId.isNotEmpty) {
        try {
          datos = await AuthService.obtenerImagenInventario(
              inv.id, 'logo', inv.logoId);
        } catch (_) {
          transitorio = true;
        }
      }
      if (datos == null || datos.isEmpty) {
        try {
          final ByteData bytes = await rootBundle.load('assets/logo_autlan.png');
          datos = bytes.buffer.asUint8List();
        } catch (_) {
          transitorio = true;
          return null;
        }
      }
      return _recortarLogo(datos);
    });
    futuro.then((_) {
      if (transitorio) _logos.remove(clave);
    });
    return futuro;
  }

  Future<Uint8List> _generarPdf(PdfPageFormat format) async {
    pw.MemoryImage? logo;
    final logoDatos = await _logoBytes();
    if (logoDatos != null) logo = pw.MemoryImage(logoDatos);

    final snKey = _snKeyPara(widget.nombrePestana);
    final hayEquipo = _equipo.isNotEmpty;
    final serieEquipo = _valorEq(snKey);
    final tipoEquipo =
        _valorEq('Equipo').isNotEmpty ? _valorEq('Equipo') : 'Laptop';
    final (marcaEquipo, modeloEquipo) = _separarMarcaModelo();

    final nombreEmpresa = _nombreEncabezado();
    final ahora = DateTime.now();
    final fechaStr =
        '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')}/${ahora.year}';

    final filasTabla = <List<String>>[
      if (hayEquipo) [tipoEquipo, marcaEquipo, modeloEquipo, serieEquipo],
    ];

    if (hayEquipo && _datos.incluyeCargador) {
      filasTabla.add([
        'Cargador',
        _datos.marcaCargador.isNotEmpty ? _datos.marcaCargador : marcaEquipo,
        '',
        _datos.serieCargador,
      ]);
    }

    if (hayEquipo && _datos.incluyeMonitor) {
      final (marcaMon, modeloMon) = _separarMonitor();
      filasTabla.add([
        'Monitor',
        marcaMon,
        modeloMon,
        _valorEq('Numero de Serie (2)'),
      ]);
    }

    for (final impresora in _impresoras) {
      final (marcaImp, modeloImp) =
          _partirMarcaModelo(impresora['Modelo']?.toString().trim() ?? '');
      filasTabla.add([
        'Impresora',
        marcaImp,
        modeloImp,
        impresora[snKey]?.toString().trim() ?? '',
      ]);
    }

    if (filasTabla.isEmpty) filasTabla.add(['', '', '', '']);

    final pdf = pw.Document();

    final azulOscuro = PdfColor.fromHex('#2F5597');
    final fondoClaro = PdfColor.fromHex('#DAEEF5');
    final colorCelesteTexto = PdfColor.fromHex('#4F7599');
    final lineaTabla = PdfColor.fromHex('#9DC3D0');

    const anchosColumnas = [105.5, 129.0, 150.0];
    const cabeceras = ['Equipo', 'Marca', 'Modelo', 'Serie'];
    const tamTabla = 12.5;
    const tamOtros = 11.0;

    final itemsOtros = _na(_datos.otrosSoftware)
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (itemsOtros.isEmpty) itemsOtros.add('N/A');

    var lineasOtros = 1;
    var anchoLinea = 0.0;
    const anchoUtilOtros = 390.0;
    for (final item in itemsOtros) {
      final w = item.length * tamOtros * 0.5 + 16;
      if (anchoLinea > 0 && anchoLinea + w > anchoUtilOtros) {
        lineasOtros++;
        anchoLinea = w;
      } else {
        anchoLinea += w;
      }
    }
    var exceso = (filasTabla.length - 1) * 21.0 +
            (lineasOtros > 1 ? (lineasOtros - 1) * 13.8 + 7 : 0) -
            91;
    double recortar(double maximo) {
      if (exceso <= 0) return 0;
      final r = exceso < maximo ? exceso : maximo;
      exceso -= r;
      return r;
    }

    final espacio1 = 22.0 - recortar(8);
    final espacio2 = 20 - recortar(6);
    final espacio3 = 20.5 - recortar(6.5);

    pw.Widget celda(int k, pw.Widget hijo) {
      if (k < 3) return pw.SizedBox(width: anchosColumnas[k], child: hijo);
      return pw.Expanded(child: hijo);
    }

    pw.Widget filaTabla(List<String> valores, {bool cabecera = false}) {
      return pw.Row(
        children: [
          for (var k = 0; k < 4; k++)
            celda(
              k,
              pw.Text(
                cabecera ? cabeceras[k] : _na(valores[k]),
                style: pw.TextStyle(
                  fontSize: tamTabla,
                  fontWeight:
                      cabecera ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: cabecera ? azulOscuro : PdfColors.black,
                ),
              ),
            ),
        ],
      );
    }

    pw.Widget banda(pw.Widget hijo,
        {required bool relleno, double vertical = 0}) {
      return pw.Container(
        width: double.infinity,
        constraints: const pw.BoxConstraints(minHeight: 21),
        color: relleno ? fondoClaro : PdfColors.white,
        padding: pw.EdgeInsets.fromLTRB(11.5, vertical, 6, vertical),
        alignment: pw.Alignment.centerLeft,
        child: hijo,
      );
    }

    pw.Widget tituloGrueso(String texto, double tam, PdfColor color) {
      final estilo = pw.TextStyle(fontSize: tam, color: color);
      return pw.Stack(
        children: [
          pw.Text(texto, style: estilo),
          pw.Positioned(left: 0.4, top: 0, child: pw.Text(texto, style: estilo)),
          pw.Positioned(
              left: 0.2, top: 0.3, child: pw.Text(texto, style: estilo)),
        ],
      );
    }

    pw.Widget etiqueta(String texto, double izquierda) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(left: izquierda),
        child: pw.Text(
          texto,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      );
    }

    final anchoPag = format.width;
    final altoPag = format.height;

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.Stack(
            fit: pw.StackFit.expand,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 47),
                  pw.SizedBox(
                    width: anchoPag,
                    height: 80,
                    child: pw.Stack(
                      fit: pw.StackFit.expand,
                      children: [
                        pw.Positioned(
                          left: 41,
                          top: 0,
                          child: pw.SizedBox(
                            width: 96,
                            height: 80,
                            child: logo != null
                                ? pw.Image(logo,
                                    fit: pw.BoxFit.contain,
                                    alignment: pw.Alignment.centerLeft)
                                : pw.SizedBox(),
                          ),
                        ),
                        pw.Positioned(
                          left: 0,
                          right: 0,
                          top: 14.9,
                          child: pw.Center(
                            child: tituloGrueso(nombreEmpresa, 15, azulOscuro),
                          ),
                        ),
                        pw.Positioned(
                          left: 0,
                          right: 0,
                          top: 53.4,
                          child: pw.Center(
                            child: pw.Text(
                              'HOJA RESPONSIVA DE EQUIPO',
                              style: pw.TextStyle(
                                fontSize: 12.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 29.3),
                    child: pw.SizedBox(
                      width: anchoPag - 29.3,
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          'Fecha: $fechaStr',
                          style: const pw.TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 47),
                    child: pw.Text(
                      'Descripción del equipo:',
                      style: pw.TextStyle(
                        fontSize: 13.5,
                        fontWeight: pw.FontWeight.bold,
                        color: colorCelesteTexto,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 14),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 38, right: 23.3),
                    child: pw.Container(
                      width: double.infinity,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: azulOscuro, width: 2),
                        borderRadius: pw.BorderRadius.circular(16),
                      ),
                      padding: const pw.EdgeInsets.fromLTRB(4, 9, 4, 13),
                      child: pw.Column(
                        children: [
                          banda(filaTabla(const [], cabecera: true),
                              relleno: false),
                          pw.Container(height: 1, color: lineaTabla),
                          for (var k = 0; k < filasTabla.length; k++)
                            banda(filaTabla(filasTabla[k]), relleno: k.isEven),
                          if (hayEquipo)
                            banda(
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.SizedBox(
                                  width: anchosColumnas[0],
                                  child: pw.Text(
                                    'Otros:',
                                    style: pw.TextStyle(
                                      fontSize: tamTabla,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                                pw.Expanded(
                                  child: pw.Wrap(
                                    spacing: 7,
                                    runSpacing: 2.5,
                                    children: [
                                      for (var k = 0;
                                          k < itemsOtros.length;
                                          k++)
                                        pw.Text(
                                          k < itemsOtros.length - 1
                                              ? '${itemsOtros[k]}  |'
                                              : itemsOtros[k],
                                          style: const pw.TextStyle(
                                              fontSize: tamOtros),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            relleno: filasTabla.length.isEven,
                            vertical: 3.5,
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(height: espacio1),
                  etiqueta('Responsable de TI:', 46),
                  pw.SizedBox(height: 6),
                  _cajaFormulario(
                    borderColor: azulOscuro,
                    nombre: _datos.nombreResponsableTI,
                    empresa: _datos.empresaResponsableTI,
                    correo: _datos.correoResponsableTI,
                    izquierda: 27,
                    derecha: 25.3,
                  ),
                  pw.SizedBox(height: espacio2),
                  etiqueta('Datos de quien Recibe el Equipo:', 46),
                  pw.SizedBox(height: 9),
                  _cajaFormulario(
                    borderColor: azulOscuro,
                    nombre: _datos.nombreRecibe,
                    empresa: _datos.empresaRecibe,
                    correo: _datos.correoRecibe,
                    izquierda: 27,
                    derecha: 25.3,
                  ),
                  pw.SizedBox(height: espacio3),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 47, right: 15.3),
                    child: pw.Text(
                      filasTabla.length > 1
                          ? 'Reconozco que los equipos arriba mencionados, son herramientas de trabajo y se encuentran en óptimas '
                              'condiciones de uso para realizar, exclusivamente, actividades propias de la empresa y los cuales me comprometo a '
                              'presentar y/o a devolver en el momento en que me sean requeridos.'
                          : 'Reconozco que el equipo arriba mencionado, es una herramienta de trabajo y se encuentra en óptimas '
                              'condiciones de uso para realizar, exclusivamente, actividades propias de la empresa y el cual me comprometo a '
                              'presentar y/o a devolver en el momento en que me sea requerido.',
                      style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2.2),
                    ),
                  ),
                ],
              ),
              if (_direccionPlanta.isNotEmpty || _codigoFormato.isNotEmpty)
                pw.Positioned(
                  left: 27,
                  right: 32.3,
                  top: altoPag - 44,
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          _direccionPlanta,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Text(
                        _codigoFormato,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
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
    required double izquierda,
    required double derecha,
  }) {
    pw.Widget fila(String label, pw.Widget valor) {
      return pw.SizedBox(
        height: 26.8,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(
              width: 88,
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

    return pw.Padding(
      padding: pw.EdgeInsets.only(left: izquierda, right: derecha),
      child: pw.Container(
        width: double.infinity,
        height: 132,
        padding: const pw.EdgeInsets.fromLTRB(19, 9.6, 19, 0),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: borderColor, width: 2),
          borderRadius: pw.BorderRadius.circular(20),
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
                width: 134,
                height: 14,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
                  ),
                ),
              ),
            ),
          ],
        ),
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

        final relacion = _formato.width / _formato.height;
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
                            filterQuality: FilterQuality.medium,
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
  final bool hayEquipo;

  const _CompletarDatosResponsivaScreen({
    required this.datosIniciales,
    required this.mostrarMonitor,
    this.hayEquipo = true,
  });

  @override
  State<_CompletarDatosResponsivaScreen> createState() =>
      _CompletarDatosResponsivaScreenState();
}

class _CompletarDatosResponsivaScreenState
    extends State<_CompletarDatosResponsivaScreen> {
  static const _fondo = Color(0xFF2C1D42);
  static const _moradoBoton = Color(0xFF7B3FB0);
  static const _lila = Color(0xFFD9C2F0);
  static const _lilaFuerte = Color(0xFFB98CE0);

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
      incluyeCargador: _incluyeCargador && widget.hayEquipo,
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
        cursorColor: Colors.white,
        style: const TextStyle(fontSize: 15, color: Colors.white),
        decoration: InputDecoration(
          labelText: etiqueta,
          hintText: ayuda,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: _lila),
          floatingLabelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: _lila),
          hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.35), fontSize: 14),
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: Colors.white.withOpacity(0.22), width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _lilaFuerte, width: 2),
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
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
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
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icono, size: 20, color: _lila),
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
                            color: Colors.white)),
                    Text(subtitulo,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white60)),
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
          color: Colors.white.withOpacity(valor ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: valor
                  ? _lilaFuerte.withOpacity(0.6)
                  : Colors.white.withOpacity(0.16)),
        ),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: Colors.white,
          activeTrackColor: _moradoBoton,
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white.withOpacity(0.15),
          title: Text(titulo,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          subtitle: detalle == null
              ? null
              : Text(detalle,
                  style: const TextStyle(fontSize: 12, color: Colors.white60)),
          value: valor,
          onChanged: alCambiar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: Colors.white,
          selectionColor: _moradoBoton.withOpacity(0.55),
          selectionHandleColor: _lilaFuerte,
        ),
      ),
      child: Scaffold(
        backgroundColor: _fondo,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Editar responsiva',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Text('Toca un campo para modificarlo. Lo vacío se imprime como N/A.',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.hayEquipo)
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
                                  mayusculas: TextCapitalization.words,
                                ),
                                _campo(
                                  controlador: _serieCargador,
                                  etiqueta: 'Serie del cargador',
                                  ayuda: 'Ej. 5C50PV8',
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
                          if (widget.hayEquipo)
                          _tarjeta(
                            icono: Icons.apps_outlined,
                            titulo: 'Software y licencias',
                            subtitulo: 'Aparece en la fila "Otros"',
                            hijos: [
                              _campo(
                                controlador: _otrosSoftware,
                                etiqueta: 'Otros',
                                ayuda: 'Ej. Microsoft Office 365',
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
                                mayusculas: TextCapitalization.words,
                              ),
                              _campo(
                                controlador: _correoTI,
                                etiqueta: 'Correo',
                                ayuda: 'nombre@autlan.com.mx',
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
                                mayusculas: TextCapitalization.words,
                              ),
                              _campo(
                                controlador: _empresaRecibe,
                                etiqueta: 'Empresa',
                                ayuda: 'Ej. AUTLAN',
                                mayusculas: TextCapitalization.characters,
                              ),
                              _campo(
                                controlador: _correoRecibe,
                                etiqueta: 'Correo',
                                ayuda: 'nombre@autlan.com.mx',
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(
                  child: ConstrainedBox(
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
                            flex: 2,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                    color: Colors.white.withOpacity(0.55),
                                    width: 1.2),
                                shape: const StadiumBorder(),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Cancelar',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: FilledButton.icon(
                              onPressed: _guardar,
                              style: FilledButton.styleFrom(
                                backgroundColor: _moradoBoton,
                                foregroundColor: Colors.white,
                                shape: const StadiumBorder(),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}