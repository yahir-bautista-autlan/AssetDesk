import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_model.dart';
import '../models/user_model.dart';

class AuthService {
  static const String scriptUrl =
      'https://script.google.com/macros/s/AKfycbxdDGzCjqaXJuwaH76iyVPGjmeo5alpU1hG5PtAuCxw-yRGQmu8GYkP-e-rSWf5P0tY/exec';

  static String ultimoError = '';

  static String hashPassword(String password) {
    final bytes = utf8.encode(password.trim());
    final digest = sha256.convert(bytes);
    return digest.toString().toLowerCase();
  }

  static Future<Map<String, dynamic>?> _post(Map<String, dynamic> body) async {
    ultimoError = '';
    try {
      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['status'] != 'success') {
            ultimoError = (data['message'] ?? 'Error desconocido').toString();
          }
          return data;
        } catch (_) {
          ultimoError =
              'El servidor no devolvió JSON válido. Revisa los permisos de la Web App.';
          return null;
        }
      }

      ultimoError = 'Respuesta HTTP ${response.statusCode}';
      return null;
    } catch (e) {
      ultimoError = 'Error de conexión: $e';
      return null;
    }
  }

  static Future<UserModel?> login(String correo, String password) async {
    final data = await _post({
      'action': 'login',
      'correo': correo.trim().toLowerCase(),
      'passwordHash': hashPassword(password),
    });

    if (data != null && data['status'] == 'success' && data['usuario'] != null) {
      final user = UserModel.fromJson(data['usuario']);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', jsonEncode(data['usuario']));
      } catch (_) {}
      return user;
    }
    return null;
  }

  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }

  static Future<UserModel?> obtenerUsuarioActual() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user_data');
      if (userString != null && userString.isNotEmpty) {
        return UserModel.fromJson(jsonDecode(userString));
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> registrarUsuario({
    required String nombre,
    required String correo,
    required String password,
    required String puesto,
    required List<String> inventarios,
  }) async {
    final data = await _post({
      'action': 'registrar',
      'nombre': nombre.trim(),
      'correo': correo.trim().toLowerCase(),
      'passwordHash': hashPassword(password),
      'puesto': puesto.trim(),
      'inventarios': inventarios.join(','),
    });
    return data != null && data['status'] == 'success';
  }

  static Future<bool> actualizarUsuarioAdmin({
    required String correo,
    required String nombre,
    required String puesto,
    required List<String> inventarios,
  }) async {
    final data = await _post({
      'action': 'actualizarUsuarioAdmin',
      'nombre': nombre.trim(),
      'correo': correo.trim().toLowerCase(),
      'puesto': puesto.trim(),
      'inventarios': inventarios.join(','),
    });
    return data != null && data['status'] == 'success';
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
      'correo': correo.trim().toLowerCase(),
    });
    return data != null && data['status'] == 'success';
  }

  static Future<Map<String, dynamic>> obtenerDatosCompletos() async {
    final data = await _post({'action': 'obtenerTodo'});
    if (data != null && data['status'] == 'success') {
      final usuarios = List<Map<String, dynamic>>.from(data['usuarios'] ?? []);
      final inventarios = (data['inventarios'] as List? ?? [])
          .map((e) => InventoryModel.fromJson(e))
          .toList();
      return {'usuarios': usuarios, 'inventarios': inventarios};
    }
    return {'usuarios': <Map<String, dynamic>>[], 'inventarios': <InventoryModel>[]};
  }

  static Future<List<Map<String, dynamic>>> obtenerUsuarios() async {
    final resultado = await obtenerDatosCompletos();
    return resultado['usuarios'] as List<Map<String, dynamic>>;
  }

  static Future<List<InventoryModel>> obtenerInventarios() async {
    final resultado = await obtenerDatosCompletos();
    return resultado['inventarios'] as List<InventoryModel>;
  }

  static Future<Map<String, dynamic>> obtenerDatosInventario(String spreadsheetIdOrUrl) async {
    final data = await _post({
      'action': 'obtenerDatosInventario',
      'spreadsheetId': spreadsheetIdOrUrl,
    });
    if (data != null && data['status'] == 'success' && data['pestañas'] != null) {
      return Map<String, dynamic>.from(data['pestañas']);
    }
    return {};
  }

  static Future<InventoryModel?> crearInventario({
    required String nombre,
    required String spreadsheet,
    required String ubicacion,
  }) async {
    final data = await _post({
      'action': 'crearInventario',
      'nombre': nombre.trim(),
      'spreadsheet': spreadsheet.trim(),
      'ubicacion': ubicacion.trim(),
    });
    if (data != null &&
        data['status'] == 'success' &&
        data['inventario'] != null) {
      return InventoryModel.fromJson(data['inventario']);
    }
    return null;
  }

  static Future<bool> darDeBaja({
    required String spreadsheetId,
    required String pestana,
    required String sn,
    required String motivo,
  }) async {
    final data = await _post({
      'action': 'darDeBaja',
      'spreadsheetId': spreadsheetId,
      'pestana': pestana,
      'sn': sn,
      'motivo': motivo,
    });
    return data != null && data['status'] == 'success';
  }
}