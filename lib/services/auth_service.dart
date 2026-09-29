import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/inventory_model.dart';
import '../models/user_model.dart';

class AuthService {
  static const String scriptUrl =
      'https://script.google.com/macros/s/AKfycbxdDGzCjqaXJuwaH76yiVPGjmeo5alpU1hG5PtAuCxw-yRGQmu8GYkP-e-rSWf5P0tY/exec';

  static String ultimoError = '';
  static String? _accessToken;

  // Instancia configurada para forzar cuentas del dominio corporativo si se desea
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    // hostedDomain: 'autlan.com.mx', // Descomenta esta línea para restringir solo a correos de la empresa
  );

  static Future<Map<String, dynamic>?> _post(Map<String, dynamic> body) async {
    ultimoError = '';
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      
      // Adjuntar credencial corporativa si existe
      if (_accessToken != null) {
        headers['Authorization'] = 'Bearer $_accessToken';
      }

      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: headers,
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
          ultimoError = 'El servidor rechazó la conexión. Revisa los permisos de la Web App.';
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

  static Future<UserModel?> loginConGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        ultimoError = 'Inicio de sesión cancelado';
        return null; 
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      _accessToken = googleAuth.accessToken; // Guardamos el token corporativo temporal

      final data = await _post({
        'action': 'login',
        'correo': googleUser.email.trim().toLowerCase(),
      });

      if (data != null && data['status'] == 'success' && data['usuario'] != null) {
        final user = UserModel.fromJson(data['usuario']);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_data', jsonEncode(data['usuario']));
        } catch (_) {}
        return user;
      }
      
      // Si falló, desconectamos la cuenta para que pueda intentar con otra
      await _googleSignIn.signOut();
      return null;
    } catch (e) {
      ultimoError = 'Error al conectar con Google: $e';
      return null;
    }
  }

  static Future<void> logout() async {
    try {
      await _googleSignIn.signOut();
      _accessToken = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }

  static Future<UserModel?> obtenerUsuarioActual() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user_data');
      if (userString != null && userString.isNotEmpty) {
        // En un escenario real, si se requiere seguridad estricta,
        // se debería validar que el token de Google siga vivo.
        return UserModel.fromJson(jsonDecode(userString));
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> registrarUsuario({
    required String nombre,
    required String correo,
    required String puesto,
    required List<String> inventarios,
  }) async {
    final data = await _post({
      'action': 'registrar',
      'nombre': nombre.trim(),
      'correo': correo.trim().toLowerCase(),
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