import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/inventory_model.dart';
import '../models/solicitud_model.dart';

class AuthService {
  static const String apiUrl = 'https://script.google.com/macros/s/AKfycbxdDGzCjqaXJuwaH76yiVPGjmeo5alpU1hG5PtAuCxw-yRGQmu8GYkP-e-rSWf5P0tY/exec'; 
  
  static UsuarioModel? _usuarioActual;
  static String ultimoError = '';

  static UsuarioModel? get usuarioActual => _usuarioActual;
  static bool get esAdmin => _usuarioActual?.esAdmin ?? false;

  static Future<UsuarioModel?> obtenerUsuarioActual() async {
    if (_usuarioActual != null) return _usuarioActual;
    
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_session');
    
    if (userData != null) {
      try {
        final jsonMap = jsonDecode(userData);
        _usuarioActual = UsuarioModel.fromJson(jsonMap);
        return _usuarioActual;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  static Future<bool> login(String correo, String passwordPlana) async {
    try {
      final bytes = utf8.encode(passwordPlana);
      final passwordHash = sha256.convert(bytes).toString();

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'login',
          'correo': correo,
          'passwordHash': passwordHash,
        }),
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['status'] == 'success') {
          _usuarioActual = UsuarioModel.fromJson(res['usuario']);
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_session', jsonEncode(res['usuario']));
          
          ultimoError = '';
          return true;
        } else {
          ultimoError = res['message'] ?? 'Credenciales incorrectas';
          return false;
        }
      }
      ultimoError = 'Error de servidor: ${response.statusCode}';
      return false;
    } catch (e) {
      ultimoError = 'Error de conexión: $e';
      return false;
    }
  }

  static Future<void> logout() async {
    _usuarioActual = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_session');
  }

  static Future<List<InventoryModel>> obtenerInventarios() async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'obtenerInventarios',
        'actorEmail': actorEmail,
      });
      if (response['status'] == 'success') {
        final List<dynamic> raw = response['inventarios'] ?? [];
        return raw.map((e) => InventoryModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> obtenerUsuarios() async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'obtenerUsuarios',
        'actorEmail': actorEmail,
      });
      if (response['status'] == 'success') {
        return List<Map<String, dynamic>>.from(response['usuarios'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> obtenerDatosInventario(String spreadsheetId) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'obtenerDatosInventario',
        'spreadsheetId': spreadsheetId,
        'actorEmail': actorEmail,
      });
      if (response['status'] == 'success') {
        return Map<String, dynamic>.from(response['pestañas'] ?? {});
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> obtenerHojaBajas(String spreadsheetId, String pestana) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'obtenerHojaBajas',
        'spreadsheetId': spreadsheetId,
        'pestana': pestana,
        'actorEmail': actorEmail,
      });
      if (response['status'] == 'success') {
        return Map<String, dynamic>.from(response['data'] ?? {});
      }
      return {'headers': [], 'rows': []};
    } catch (e) {
      return {'headers': [], 'rows': []};
    }
  }

  static Future<bool> registrarUsuario({
    required String nombre,
    required String correo,
    required String passwordPlana,
    required String puesto,
    required String inventarios,
  }) async {
    try {
      final bytes = utf8.encode(passwordPlana);
      final passwordHash = sha256.convert(bytes).toString();

      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'registrar',
        'actorEmail': actorEmail,
        'nombre': nombre,
        'correo': correo,
        'passwordHash': passwordHash,
        'puesto': puesto,
        'inventarios': inventarios,
      });
      return response['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  static Future<bool> actualizarUsuarioAdmin({
    required String correo,
    required String nombre,
    required String puesto,
    required String inventarios,
  }) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'actualizarUsuarioAdmin',
        'actorEmail': actorEmail,
        'correo': correo,
        'nombre': nombre,
        'puesto': puesto,
        'inventarios': inventarios,
      });
      return response['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  static Future<bool> eliminarUsuario(String correo) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'eliminar',
        'actorEmail': actorEmail,
        'correo': correo,
      });
      return response['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  static Future<InventoryModel?> crearInventario({
    required String nombre,
    required String spreadsheet,
    required String responsableEmail,
    required String ubicacion,
  }) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'crearInventario',
        'actorEmail': actorEmail,
        'nombre': nombre,
        'spreadsheet': spreadsheet,
        'responsableEmail': responsableEmail,
        'ubicacion': ubicacion,
      });
      if (response['status'] == 'success') {
        return InventoryModel.fromJson(response['inventario']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> actualizarInventarioAdmin({
    required String idInventario,
    required String nombre,
    required String responsableEmail,
    required String ubicacion,
  }) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'actualizarInventario',
        'actorEmail': actorEmail,
        'idInventario': idInventario,
        'nombre': nombre,
        'responsableEmail': responsableEmail,
        'ubicacion': ubicacion,
      });
      return response['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  static Future<bool> eliminarInventario(String idInventario) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'eliminarInventario',
        'actorEmail': actorEmail,
        'idInventario': idInventario,
      });
      return response['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  static Future<bool> darDeBaja({
    required String spreadsheetId,
    required String pestana,
    required String sn,
    required String motivo,
  }) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'darDeBaja',
        'spreadsheetId': spreadsheetId,
        'pestana': pestana,
        'sn': sn,
        'motivo': motivo,
        'actorEmail': actorEmail,
      });
      return response['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  static Future<bool> agregarActivo({
    required String spreadsheetId,
    required String pestana,
    required Map<String, dynamic> datos,
  }) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'agregarActivo',
        'spreadsheetId': spreadsheetId,
        'pestana': pestana,
        'datos': datos,
        'actorEmail': actorEmail,
      });
      return response['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  static Future<bool> editarActivo({
    required String spreadsheetId,
    required String pestana,
    required String snOriginal,
    required Map<String, dynamic> datos,
  }) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'editarActivo',
        'spreadsheetId': spreadsheetId,
        'pestana': pestana,
        'snOriginal': snOriginal,
        'datos': datos,
        'actorEmail': actorEmail,
      });
      return response['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  static Future<List<SolicitudModel>> obtenerSolicitudesPendientes() async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'obtenerSolicitudesPendientes',
        'actorEmail': actorEmail,
      });
      if (response['status'] == 'success') {
        final List<dynamic> raw = response['solicitudes'] ?? [];
        return raw.map((e) => SolicitudModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> resolverSolicitud({
    required String requestId,
    required bool aprobar,
    required String comentario,
  }) async {
    try {
      final actorEmail = _usuarioActual?.correo ?? '';
      final response = await _postAction({
        'action': 'resolverSolicitud',
        'actorEmail': actorEmail,
        'requestId': requestId,
        'aprobar': aprobar,
        'comentario': comentario,
      });
      return response['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> _postAction(Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        ultimoError = res['message'] ?? '';
        return res;
      } else {
        ultimoError = 'Error HTTP: ${response.statusCode}';
        return {'status': 'error', 'message': ultimoError};
      }
    } catch (e) {
      ultimoError = 'Error de red: $e';
      return {'status': 'error', 'message': ultimoError};
    }
  }
}