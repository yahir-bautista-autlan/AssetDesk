import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, ValueNotifier, WidgetsBinding;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_model.dart';
import '../models/solicitud_model.dart';
import '../models/user_model.dart';

class _CacheEntry {
  final dynamic data;
  final DateTime time;
  _CacheEntry(this.data) : time = DateTime.now();
}

class AuthService {
  static const String scriptUrl =
      'https://script.google.com/macros/s/AKfycbxdDGzCjqaXJuwaH76yiVPGjmeo5alpU1hG5PtAuCxw-yRGQmu8GYkP-e-rSWf5P0tY/exec';

  static const String _prefsKey = 'user_data';
  static const String _prefsSitioKey = 'ultimo_sitio';
  static const Duration _timeout = Duration(seconds: 45);
  static const Duration _cacheTtl = Duration(seconds: 90);

  static String ultimoError = '';
  static String ultimoMensaje = '';
  static bool ultimaRespuestaPendiente = false;
  static String ultimaSerieAgregada = '';
  static void Function(Map<String, dynamic> evento)? alEventoPropio;

  static final ValueNotifier<int> solicitudesPendientes = ValueNotifier<int>(0);
  static final StreamController<int> _nuevasSolicitudes =
      StreamController<int>.broadcast();
  static Stream<int> get nuevasSolicitudes => _nuevasSolicitudes.stream;

  static const Duration _intervaloPulso = Duration(seconds: 4);
  static Timer? _timerPulso;
  static String _secPulso = '';
  static bool _pulsando = false;
  static bool _lineaBasePulso = false;
  static int _fallosPulso = 0;
  static int _saltarPulso = 0;

  static bool get _recibeAvisosSolicitudes {
    final u = _usuarioActual;
    if (u == null) return false;
    return u.inventarios.any((i) => i.esResponsable(u.correo));
  }

  static bool get _enPrimerPlano {
    final e = WidgetsBinding.instance.lifecycleState;
    return e == null ||
        e == AppLifecycleState.resumed ||
        e == AppLifecycleState.inactive;
  }

  static void iniciarPulsoSolicitudes() {
    if (_timerPulso != null || !_recibeAvisosSolicitudes) return;
    _timerPulso = Timer.periodic(_intervaloPulso, (_) => _pulsoSolicitudes());
    _pulsoSolicitudes();
  }

  static void detenerPulsoSolicitudes() {
    _timerPulso?.cancel();
    _timerPulso = null;
    _secPulso = '';
    _pulsando = false;
    _lineaBasePulso = false;
    _fallosPulso = 0;
    _saltarPulso = 0;
    solicitudesPendientes.value = 0;
  }

  static Future<void> _pulsoSolicitudes() async {
    if (_pulsando || !_enPrimerPlano) return;
    if (_usuarioActual == null) {
      detenerPulsoSolicitudes();
      return;
    }
    if (_saltarPulso > 0) {
      _saltarPulso--;
      return;
    }

    _pulsando = true;
    try {
      final data = await _post({
        'action': 'pulsoSolicitudes',
        'actorEmail': _usuarioActual?.correo ?? '',
        'desde': _secPulso,
      }, sondeo: true);

      if (_timerPulso == null) return;
      if (data == null || data['status'] != 'success') {
        _fallosPulso++;
        _saltarPulso = _fallosPulso.clamp(1, 6);
        return;
      }

      _fallosPulso = 0;
      _secPulso = (data['seq'] ?? _secPulso).toString();

      if (data['cambio'] == true) {
        final total = (data['total'] as num?)?.toInt() ?? 0;
        final previo = solicitudesPendientes.value;
        _guardarCache('pend_count', total);
        solicitudesPendientes.value = total;
        if (_lineaBasePulso && total > previo) _nuevasSolicitudes.add(total);
        _lineaBasePulso = true;
      }
    } finally {
      _pulsando = false;
    }
  }

  static UserModel? _usuarioActual;
  static final Map<String, _CacheEntry> _cache = {};
  static final Map<String, Uint8List> _imgCache = {};
  static final Map<String, Map<String, String>> _responsablesCache = {};
  static final Map<String, Future<Uint8List?>> _imgEnCurso = {};

  static UserModel? get usuarioCache => _usuarioActual;
  static String get actorEmailSync => _usuarioActual?.correo ?? '';
  static bool get esAdmin => _usuarioActual?.esAdmin ?? false;
  static bool get esJefeDeArea => _usuarioActual?.esJefeDeArea ?? false;
  static bool get esResidente => _usuarioActual?.esResidente ?? false;
  static bool get esConsultor => _usuarioActual?.esConsultor ?? false;
  static bool get puedeEditar => _usuarioActual?.puedeEditar ?? false;

  static String hashPassword(String password) {
    final bytes = utf8.encode(password.trim());
    final digest = sha256.convert(bytes);
    return digest.toString().toLowerCase();
  }

  static int _generacionCache = 0;
  static final Map<String, Future<Map<String, dynamic>?>> _pestanasEnCurso = {};

  static void _invalidarCache() {
    _generacionCache++;
    _cache.clear();
    _pestanasEnCurso.clear();
  }

  static dynamic _leerCache(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.time) > _cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return entry.data;
  }

  static void _guardarCache(String key, dynamic data) {
    _cache[key] = _CacheEntry(data);
  }

  static Future<String> _actor() async {
    if (_usuarioActual == null) await obtenerUsuarioActual();
    return _usuarioActual?.correo ?? '';
  }

  static final String sesionId = _generarSesionId();

  static String _generarSesionId() {
    final r = DateTime.now().microsecondsSinceEpoch;
    return 's${r.toRadixString(36)}${(r * 7919 % 1000003).toRadixString(36)}';
  }

  static Future<Map<String, dynamic>?> _post(Map<String, dynamic> body,
      {bool lectura = false, bool sondeo = false}) async {
    final errorPrevio = ultimoError;
    final resultado = await _postInterno(body,
        lectura: lectura || sondeo,
        limite: sondeo ? const Duration(seconds: 12) : _timeout);
    if (sondeo) ultimoError = errorPrevio;
    return resultado;
  }

  static Future<Map<String, dynamic>?> _postInterno(Map<String, dynamic> body,
      {bool lectura = false, Duration limite = _timeout}) async {
    if (!lectura) {
      ultimoError = '';
      ultimoMensaje = '';
      ultimaRespuestaPendiente = false;
    }

    try {
      var response = await http
          .post(
            Uri.parse(scriptUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({...body, 'sesion': sesionId}),
          )
          .timeout(limite);

      int redirectCount = 0;
      while ((response.statusCode == 301 ||
              response.statusCode == 302 ||
              response.statusCode == 303 ||
              response.statusCode == 307 ||
              response.statusCode == 308) &&
          redirectCount < 5) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) break;

        response = await http.get(Uri.parse(location)).timeout(limite);
        redirectCount++;
      }

      final preview = response.body.length > 150
          ? response.body.substring(0, 150)
          : response.body;

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (!lectura) {
            ultimoMensaje = (data['message'] ?? '').toString();
            ultimaRespuestaPendiente = data['pendienteAprobacion'] == true;
            if (data['status'] == 'success' && data['evento'] is Map) {
              alEventoPropio
                  ?.call(Map<String, dynamic>.from(data['evento'] as Map));
            }
          }
          if (data['status'] != 'success') {
            ultimoError = (data['message'] ?? 'Error desconocido').toString();
          }
          return data;
        } catch (_) {
          ultimoError =
              'Status ${response.statusCode} | Bytes: ${response.bodyBytes.length} | Body: "$preview"';
          return null;
        }
      }

      ultimoError =
          'Status ${response.statusCode} | Bytes: ${response.bodyBytes.length} | Body: "$preview"';
      return null;
    } on TimeoutException {
      ultimoError = 'El servidor tardó demasiado en responder. Intenta de nuevo.';
      return null;
    } catch (e) {
      ultimoError = 'Error de conexión: $e';
      return null;
    }
  }

  static bool _ok(Map<String, dynamic>? data) {
    return data != null && data['status'] == 'success';
  }

  static Future<bool> login(String correo, String password) async {
    final data = await _post({
      'action': 'login',
      'correo': correo.trim().toLowerCase(),
      'passwordHash': hashPassword(password),
    });

    if (_ok(data) && data!['usuario'] != null) {
      final usuarioJson = Map<String, dynamic>.from(data['usuario']);
      _usuarioActual = UserModel.fromJson(usuarioJson);
      _invalidarCache();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_usuarioActual!.toJson()));
      } catch (_) {}
      return true;
    }
    return false;
  }

  static Future<void> logout() async {
    detenerPulsoSolicitudes();
    _usuarioActual = null;
    _invalidarCache();
    _imgCache.clear();
    _responsablesCache.clear();
    _imgEnCurso.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }

  static Future<UserModel?> obtenerUsuarioActual() async {
    if (_usuarioActual != null) return _usuarioActual;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString(_prefsKey);
      if (userString != null && userString.isNotEmpty) {
        _usuarioActual =
            UserModel.fromJson(Map<String, dynamic>.from(jsonDecode(userString)));
        return _usuarioActual;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> reenviarInvitacion(String correo) async {
    final data = await _post({
      'action': 'reenviarInvitacion',
      'actorEmail': await _actor(),
      'correo': correo.trim().toLowerCase(),
    });
    return _ok(data);
  }

  static Future<bool> invitarUsuario({
    required String nombre,
    required String correo,
    required String rol,
    required List<String> inventarios,
  }) async {
    final data = await _post({
      'action': 'invitarUsuario',
      'actorEmail': await _actor(),
      'nombre': nombre.trim(),
      'correo': correo.trim().toLowerCase(),
      'rol': rol.trim(),
      'inventarios': inventarios.join(','),
    });
    return _ok(data);
  }

  static Future<bool> registrarUsuario({
    required String nombre,
    required String correo,
    required String passwordPlana,
    required String puesto,
    required String inventarios,
  }) async {
    final lista = inventarios
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return invitarUsuario(
      nombre: nombre,
      correo: correo,
      rol: puesto,
      inventarios: lista,
    );
  }

  static Future<bool> completarInvitacion({
    required String correo,
    required String codigo,
    required String nuevaPassword,
  }) async {
    final data = await _post({
      'action': 'completarInvitacion',
      'correo': correo.trim().toLowerCase(),
      'codigo': codigo.trim(),
      'nuevaPasswordHash': hashPassword(nuevaPassword),
    });
    return _ok(data);
  }

  static Future<bool> actualizarUsuarioAdmin({
    required String correo,
    required String nombre,
    required String puesto,
    required String inventarios,
  }) async {
    final data = await _post({
      'action': 'actualizarUsuarioAdmin',
      'actorEmail': await _actor(),
      'correo': correo.trim().toLowerCase(),
      'nombre': nombre.trim(),
      'puesto': puesto.trim(),
      'inventarios': inventarios,
    });
    return _ok(data);
  }

  static Future<Map<String, dynamic>> cambiarMiPassword({
    required String correo,
    required String actualPassword,
    required String nuevaPassword,
  }) async {
    final data = await _post({
      'action': 'cambiarMiPassword',
      'correo': correo.trim().toLowerCase(),
      'actualPasswordHash': hashPassword(actualPassword),
      'nuevaPasswordHash': hashPassword(nuevaPassword),
    });

    if (data == null) {
      return {'exito': false, 'mensaje': 'Error de conexión con el servidor'};
    }
    return {
      'exito': data['status'] == 'success',
      'mensaje': data['message'] ?? 'Error desconocido',
    };
  }

  static Future<bool> eliminarUsuario(String correo) async {
    final data = await _post({
      'action': 'eliminar',
      'actorEmail': await _actor(),
      'correo': correo.trim().toLowerCase(),
    });
    return _ok(data);
  }

  static Future<Map<String, dynamic>> obtenerDatosCompletos() async {
    final data = await _post({
      'action': 'obtenerTodo',
      'actorEmail': await _actor(),
    });
    if (_ok(data)) {
      final usuarios = (data!['usuarios'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final inventarios = (data['inventarios'] as List? ?? [])
          .map((e) => InventoryModel.fromJson(e))
          .toList();
      return {'usuarios': usuarios, 'inventarios': inventarios};
    }
    return {
      'usuarios': <Map<String, dynamic>>[],
      'inventarios': <InventoryModel>[],
    };
  }

  static Future<List<Map<String, dynamic>>> obtenerUsuarios() async {
    final resultado = await obtenerDatosCompletos();
    return resultado['usuarios'] as List<Map<String, dynamic>>;
  }

  static Future<List<InventoryModel>> obtenerInventarios() async {
    final resultado = await obtenerDatosCompletos();
    return resultado['inventarios'] as List<InventoryModel>;
  }

  static Future<Map<String, dynamic>> obtenerDatosInventario(
      String spreadsheetIdOrUrl,
      {bool forzar = false}) async {
    final cacheKey = 'inv_$spreadsheetIdOrUrl';
    if (!forzar) {
      final cacheado = _leerCache(cacheKey);
      if (cacheado != null) return Map<String, dynamic>.from(cacheado);
    }

    final data = await _post({
      'action': 'obtenerDatosInventario',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetIdOrUrl,
      'forzar': forzar,
    });
    if (_ok(data) && data!['pestañas'] != null) {
      final resultado = Map<String, dynamic>.from(data['pestañas']);
      _guardarCache(cacheKey, resultado);
      return resultado;
    }
    return {};
  }

  static Future<Map<String, dynamic>?> obtenerPestana(
      String spreadsheetIdOrUrl, String pestana,
      {bool forzar = false}) {
    final cacheKey = 'pest_${spreadsheetIdOrUrl}_$pestana';
    if (!forzar) {
      final cacheado = _leerCache(cacheKey);
      if (cacheado != null) {
        return Future.value(Map<String, dynamic>.from(cacheado));
      }
      final enCurso = _pestanasEnCurso[cacheKey];
      if (enCurso != null) return enCurso;
    }

    final generacion = _generacionCache;
    final futuro = _pedirPestana(spreadsheetIdOrUrl, pestana, forzar)
        .then((resultado) {
      if (resultado != null && generacion == _generacionCache) {
        _guardarCache(cacheKey, resultado);
      }
      return resultado;
    }).whenComplete(() {
      if (generacion == _generacionCache) _pestanasEnCurso.remove(cacheKey);
    });
    if (generacion == _generacionCache) _pestanasEnCurso[cacheKey] = futuro;
    return futuro;
  }

  static Future<Map<String, dynamic>?> _pedirPestana(
      String spreadsheetIdOrUrl, String pestana, bool forzar) async {
    final data = await _post({
      'action': 'obtenerPestana',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetIdOrUrl,
      'pestana': pestana,
      'forzar': forzar,
    }, lectura: true);
    if (_ok(data) && data!['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    return null;
  }

  static void precargarInventario(String spreadsheetIdOrUrl,
      {String primera = 'Captura'}) {
    if (spreadsheetIdOrUrl.isEmpty) return;
    const todas = ['Captura', 'Impresoras', 'Otros', 'Consumibles'];
    obtenerPestana(spreadsheetIdOrUrl, primera).whenComplete(() {
      for (final p in todas.where((t) => t != primera)) {
        obtenerPestana(spreadsheetIdOrUrl, p);
      }
    });
  }

  static Future<Map<String, dynamic>?> obtenerCambios(
      String spreadsheetIdOrUrl, String desde) async {
    final data = await _post({
      'action': 'obtenerCambios',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetIdOrUrl,
      'desde': desde,
    }, sondeo: true);
    if (_ok(data)) return Map<String, dynamic>.from(data!);
    return null;
  }

  static void olvidarDatos(String spreadsheetIdOrUrl,
      {String? pestana, bool bajas = false, bool solicitudes = false}) {
    _generacionCache++;
    if (pestana != null) {
      final k = bajas
          ? 'bajas_${spreadsheetIdOrUrl}_$pestana'
          : 'pest_${spreadsheetIdOrUrl}_$pestana';
      _cache.remove(k);
      _pestanasEnCurso.remove(k);
    }
    if (solicitudes) _cache.remove('pend_count');
    _cache.remove('inv_$spreadsheetIdOrUrl');
  }

  static Future<Map<String, dynamic>> obtenerHojaBajas(
      String spreadsheetIdOrUrl, String pestana,
      {bool forzar = false}) async {
    final cacheKey = 'bajas_${spreadsheetIdOrUrl}_$pestana';
    if (!forzar) {
      final cacheado = _leerCache(cacheKey);
      if (cacheado != null) return Map<String, dynamic>.from(cacheado);
    }

    final data = await _post({
      'action': 'obtenerHojaBajas',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetIdOrUrl,
      'pestana': pestana,
      'forzar': forzar,
    });
    if (_ok(data) && data!['data'] != null) {
      final resultado = Map<String, dynamic>.from(data['data']);
      _guardarCache(cacheKey, resultado);
      return resultado;
    }
    return {'headers': <String>[], 'rows': <dynamic>[]};
  }

  static Future<bool> enviarReporteCorreo({
    required String pestana,
    required String archivo,
    required String inventario,
    required List<int> bytes,
  }) async {
    final data = await _post({
      'action': 'enviarReporteCorreo',
      'actorEmail': await _actor(),
      'pestana': pestana,
      'archivo': archivo,
      'inventario': inventario,
      'base64': base64Encode(bytes),
    });
    return _ok(data);
  }

  static Future<Map<String, String>?> obtenerResponsableInventario(
      String inventarioId) async {
    final cacheado = _responsablesCache[inventarioId];
    if (cacheado != null) return cacheado;
    final data = await _post({
      'action': 'obtenerResponsableInventario',
      'actorEmail': await _actor(),
      'idInventario': inventarioId,
    }, lectura: true);
    if (_ok(data)) {
      final r = {
        'nombre': (data!['nombre'] ?? '').toString().trim(),
        'correo': (data['correo'] ?? '').toString().trim().toLowerCase(),
        'direccion': (data['direccion'] ?? '').toString().trim(),
        'codigoFormato': (data['codigoFormato'] ?? '').toString().trim(),
      };
      _responsablesCache[inventarioId] = r;
      return r;
    }
    return null;
  }

  static const String _prefijoImg = 'img_';
  static const String _indiceImg = 'img_indice';
  static const int _maxImagenesDisco = 6;
  static const int _maxCharsImagenDisco = 1400000;

  static Future<Uint8List?> _leerImagenDisco(String fileId) async {
    if (kIsWeb) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final b64 = prefs.getString('$_prefijoImg$fileId');
      if (b64 == null || b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _guardarImagenDisco(String fileId, String b64) async {
    if (kIsWeb || b64.length > _maxCharsImagenDisco) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final indice = prefs.getStringList(_indiceImg) ?? <String>[];
      indice.remove(fileId);
      indice.add(fileId);
      while (indice.length > _maxImagenesDisco) {
        final viejo = indice.removeAt(0);
        await prefs.remove('$_prefijoImg$viejo');
      }
      await prefs.setString('$_prefijoImg$fileId', b64);
      await prefs.setStringList(_indiceImg, indice);
    } catch (_) {}
  }

  static Uint8List? imagenEnMemoria(String fileId) => _imgCache[fileId];

  static void precargarImagenes(List<InventoryModel> inventarios) {
    for (final inv in inventarios) {
      if (inv.portadaId.isNotEmpty) {
        obtenerImagenInventario(inv.id, 'portada', inv.portadaId);
      }
    }
    for (final inv in inventarios) {
      if (inv.logoId.isNotEmpty) {
        obtenerImagenInventario(inv.id, 'logo', inv.logoId);
      }
    }
  }

  static Future<Uint8List?> obtenerImagenInventario(
      String inventarioId, String tipo, String fileId) {
    if (fileId.isEmpty) return Future.value(null);
    final cacheada = _imgCache[fileId];
    if (cacheada != null) return Future.value(cacheada);

    return _imgEnCurso[fileId] ??= () async {
      try {
        final disco = await _leerImagenDisco(fileId);
        if (disco != null) {
          _imgCache[fileId] = disco;
          return disco;
        }

        final data = await _post({
          'action': 'obtenerImagenInventario',
          'actorEmail': await _actor(),
          'idInventario': inventarioId,
          'tipo': tipo,
        }, lectura: true);
        if (_ok(data) && data!['base64'] != null) {
          final b64 = data['base64'].toString();
          final bytes = base64Decode(b64);
          _imgCache[fileId] = bytes;
          _guardarImagenDisco(fileId, b64);
          return bytes;
        }
        return null;
      } finally {
        _imgEnCurso.remove(fileId);
      }
    }();
  }

  static Future<bool> guardarImagenInventario({
    required String idInventario,
    required String tipo,
    required Uint8List bytes,
    required String mime,
  }) async {
    final actor = await _actor();
    final cuerpo = base64Encode(bytes);
    for (var intento = 0; intento < 3; intento++) {
      final data = await _post({
        'action': 'guardarImagenInventario',
        'actorEmail': actor,
        'idInventario': idInventario,
        'tipo': tipo,
        'base64': cuerpo,
        'mime': mime,
      });
      if (_ok(data)) return true;
      final error = ultimoError.toLowerCase();
      final reintentable = error.contains('candado') ||
          error.contains('ocupado') ||
          error.contains('lock');
      if (!reintentable) return false;
      await Future.delayed(Duration(seconds: 2 + intento * 2));
    }
    return false;
  }

  static Future<List<InventoryModel>?> refrescarInventariosUsuario() async {
    final data = await _post({
      'action': 'obtenerInventarios',
      'actorEmail': await _actor(),
    });
    if (!_ok(data)) return null;

    final raw = (data!['inventarios'] as List? ?? []);
    final lista = raw.map((e) => InventoryModel.fromJson(e)).toList();
    precargarImagenes(lista);

    final u = _usuarioActual;
    if (u != null) {
      try {
        final json = Map<String, dynamic>.from(u.toJson());
        json['inventarios'] = raw;
        _usuarioActual = UserModel.fromJson(json);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_usuarioActual!.toJson()));
      } catch (_) {}
    }
    return lista;
  }

  static Future<InventoryModel?> crearInventario({
    required String nombre,
    required String spreadsheet,
    required String ubicacion,
    required String responsableEmail,
    String direccion = '',
    String codigoFormato = '',
  }) async {
    final data = await _post({
      'action': 'crearInventario',
      'actorEmail': await _actor(),
      'nombre': nombre.trim(),
      'spreadsheet': spreadsheet.trim(),
      'ubicacion': ubicacion.trim(),
      'direccion': direccion.trim(),
      'codigoFormato': codigoFormato.trim(),
      'responsableEmail': responsableEmail.trim().toLowerCase(),
    });
    if (_ok(data) && data!['inventario'] != null) {
      return InventoryModel.fromJson(data['inventario']);
    }
    return null;
  }

  static Future<bool> actualizarInventario({
    required String idInventario,
    required String nombre,
    required String responsableEmail,
    required String ubicacion,
    String? direccion,
    String? codigoFormato,
  }) async {
    final data = await _post({
      'action': 'actualizarInventario',
      'actorEmail': await _actor(),
      'idInventario': idInventario,
      'nombre': nombre.trim(),
      'responsableEmail': responsableEmail.trim().toLowerCase(),
      'ubicacion': ubicacion.trim(),
      if (direccion != null) 'direccion': direccion.trim(),
      if (codigoFormato != null) 'codigoFormato': codigoFormato.trim(),
    });
    _responsablesCache.remove(idInventario);
    return _ok(data);
  }

  static Future<bool> eliminarInventario(String idInventario) async {
    final data = await _post({
      'action': 'eliminarInventario',
      'actorEmail': await _actor(),
      'idInventario': idInventario,
    });
    return _ok(data);
  }

  static Future<bool> darDeBaja({
    required String spreadsheetId,
    required String pestana,
    required String sn,
    required String motivo,
  }) async {
    final data = await _post({
      'action': 'darDeBaja',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetId,
      'pestana': pestana,
      'sn': sn,
      'motivo': motivo,
    });
    if (_ok(data)) _invalidarCache();
    return _ok(data);
  }

  static Future<bool> revertirBaja({
    required String spreadsheetId,
    required String pestana,
    required String sn,
  }) async {
    final data = await _post({
      'action': 'revertirBaja',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetId,
      'pestana': pestana,
      'sn': sn,
    });
    if (_ok(data)) _invalidarCache();
    return _ok(data);
  }

  static Future<void> guardarSitio(String inventarioId, int pestana) async {
    if (inventarioId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsSitioKey, '$inventarioId|$pestana');
    } catch (_) {}
  }

  static Future<(String, int)?> leerSitio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsSitioKey);
      if (raw == null || raw.isEmpty) return null;
      final partes = raw.split('|');
      if (partes.length != 2) return null;
      final pestana = int.tryParse(partes[1]) ?? 0;
      return (partes[0], pestana);
    } catch (_) {
      return null;
    }
  }

  static Future<void> olvidarSitio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsSitioKey);
    } catch (_) {}
  }

  static Future<bool> transferirActivo({
    required String spreadsheetId,
    required String pestana,
    required String sn,
    required String destinoInventoryId,
    String motivo = '',
  }) async {
    final data = await _post({
      'action': 'transferirActivo',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetId,
      'pestana': pestana,
      'sn': sn,
      'destinoInventoryId': destinoInventoryId,
      'motivo': motivo,
    });
    if (_ok(data)) _invalidarCache();
    return _ok(data);
  }

  static Future<bool> agregarActivo({
    required String spreadsheetId,
    required String pestana,
    required Map<String, String> datos,
  }) async {
    final data = await _post({
      'action': 'agregarActivo',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetId,
      'pestana': pestana,
      'datos': datos,
    });
    ultimaSerieAgregada = '';
    if (_ok(data)) {
      _invalidarCache();
      ultimaSerieAgregada = (data!['serie'] ?? '').toString();
    }
    return _ok(data);
  }

  static Future<bool> editarActivo({
    required String spreadsheetId,
    required String pestana,
    required String snOriginal,
    required Map<String, String> datos,
  }) async {
    final data = await _post({
      'action': 'editarActivo',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetId,
      'pestana': pestana,
      'snOriginal': snOriginal,
      'datos': datos,
    });
    if (_ok(data)) _invalidarCache();
    return _ok(data);
  }

  static Future<int> contarSolicitudesPendientes() async {
    final cacheado = _leerCache('pend_count');
    if (cacheado is int) return cacheado;

    final data = await _post({
      'action': 'contarSolicitudesPendientes',
      'actorEmail': await _actor(),
    });
    if (_ok(data)) {
      final total = (data!['total'] as num?)?.toInt() ?? 0;
      _guardarCache('pend_count', total);
      return total;
    }
    return 0;
  }

  static Future<List<SolicitudModel>> obtenerSolicitudesPendientes() async {
    final data = await _post({
      'action': 'obtenerSolicitudesPendientes',
      'actorEmail': await _actor(),
    });
    if (_ok(data)) {
      final lista = (data!['solicitudes'] as List? ?? [])
          .map((e) => SolicitudModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _guardarCache('pend_count', lista.length);
      return lista;
    }
    return <SolicitudModel>[];
  }

  static Future<bool> resolverSolicitud({
    required String requestId,
    required bool aprobar,
    String comentario = '',
  }) async {
    final data = await _post({
      'action': 'resolverSolicitud',
      'actorEmail': await _actor(),
      'requestId': requestId,
      'aprobar': aprobar,
      'comentario': comentario,
    });
    if (_ok(data)) _invalidarCache();
    return _ok(data);
  }
}