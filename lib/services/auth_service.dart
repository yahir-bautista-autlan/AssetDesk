import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
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
  static const Duration _timeout = Duration(seconds: 45);
  static const Duration _cacheTtl = Duration(seconds: 90);

  static String ultimoError = '';
  static String ultimoMensaje = '';
  static bool ultimaRespuestaPendiente = false;

  static UserModel? _usuarioActual;
  static final Map<String, _CacheEntry> _cache = {};

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

  static void _invalidarCache() {
    _cache.clear();
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

  static Future<Map<String, dynamic>?> _post(Map<String, dynamic> body) async {
    ultimoError = '';
    ultimoMensaje = '';
    ultimaRespuestaPendiente = false;

    try {
      var response = await http
          .post(
            Uri.parse(scriptUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      int redirectCount = 0;
      while ((response.statusCode == 301 ||
              response.statusCode == 302 ||
              response.statusCode == 303 ||
              response.statusCode == 307 ||
              response.statusCode == 308) &&
          redirectCount < 5) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) break;

        response = await http.get(Uri.parse(location)).timeout(_timeout);
        redirectCount++;
      }

      final preview = response.body.length > 150
          ? response.body.substring(0, 150)
          : response.body;

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          ultimoMensaje = (data['message'] ?? '').toString();
          ultimaRespuestaPendiente = data['pendienteAprobacion'] == true;
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
    _usuarioActual = null;
    _invalidarCache();
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
      String spreadsheetIdOrUrl) async {
    final cacheKey = 'inv_$spreadsheetIdOrUrl';
    final cacheado = _leerCache(cacheKey);
    if (cacheado != null) return Map<String, dynamic>.from(cacheado);

    final data = await _post({
      'action': 'obtenerDatosInventario',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetIdOrUrl,
    });
    if (_ok(data) && data!['pestañas'] != null) {
      final resultado = Map<String, dynamic>.from(data['pestañas']);
      _guardarCache(cacheKey, resultado);
      return resultado;
    }
    return {};
  }

  static Future<Map<String, dynamic>> obtenerHojaBajas(
      String spreadsheetIdOrUrl, String pestana) async {
    final cacheKey = 'bajas_${spreadsheetIdOrUrl}_$pestana';
    final cacheado = _leerCache(cacheKey);
    if (cacheado != null) return Map<String, dynamic>.from(cacheado);

    final data = await _post({
      'action': 'obtenerHojaBajas',
      'actorEmail': await _actor(),
      'spreadsheetId': spreadsheetIdOrUrl,
      'pestana': pestana,
    });
    if (_ok(data) && data!['data'] != null) {
      final resultado = Map<String, dynamic>.from(data['data']);
      _guardarCache(cacheKey, resultado);
      return resultado;
    }
    return {'headers': <String>[], 'rows': <dynamic>[]};
  }

  static Future<InventoryModel?> crearInventario({
    required String nombre,
    required String spreadsheet,
    required String ubicacion,
    required String responsableEmail,
  }) async {
    final data = await _post({
      'action': 'crearInventario',
      'actorEmail': await _actor(),
      'nombre': nombre.trim(),
      'spreadsheet': spreadsheet.trim(),
      'ubicacion': ubicacion.trim(),
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
  }) async {
    final data = await _post({
      'action': 'actualizarInventario',
      'actorEmail': await _actor(),
      'idInventario': idInventario,
      'nombre': nombre.trim(),
      'responsableEmail': responsableEmail.trim().toLowerCase(),
      'ubicacion': ubicacion.trim(),
    });
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
    if (_ok(data)) _invalidarCache();
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

  static Future<List<SolicitudModel>> obtenerSolicitudesPendientes() async {
    final data = await _post({
      'action': 'obtenerSolicitudesPendientes',
      'actorEmail': await _actor(),
    });
    if (_ok(data)) {
      return (data!['solicitudes'] as List? ?? [])
          .map((e) => SolicitudModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
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