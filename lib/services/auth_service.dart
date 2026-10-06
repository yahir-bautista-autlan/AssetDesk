import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/inventory_model.dart';

class AuthService {
  static const String apiUrl = 'TU_URL_DE_LA_API_AQUI'; 
  
  static UserModel? _usuarioActual;
  static String ultimoError = '';

  static Future<UserModel?> obtenerUsuarioActual() async {
    if (_usuarioActual != null) return _usuarioActual;
    
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_session');
    
    if (userData != null) {
      final datos = await obtenerDatosCompletos();
      final correoGuardado = jsonDecode(userData)['correo'];
      
      final usuariosList = datos['usuarios'] as List<Map<String, dynamic>>;
      final catalogo = datos['inventarios'] as List<InventoryModel>;
      
      final userMap = usuariosList.firstWhere(
        (u) => u['CORREO'] == correoGuardado || u['correo'] == correoGuardado, 
        orElse: () => {}
      );

      if (userMap.isNotEmpty) {
        _usuarioActual = UserModel.fromJson(userMap, catalogo);
        return _usuarioActual;
      }
    }
    return null;
  }

  static Future<bool> login(String correo, String password) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'login',
          'correo': correo,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['success'] == true) {
          final datos = await obtenerDatosCompletos();
          final catalogo = datos['inventarios'] as List<InventoryModel>;
          
          _usuarioActual = UserModel.fromJson(res['usuario'], catalogo);
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_session', jsonEncode({'correo': correo}));
          
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

  static Future<Map<String, dynamic>> obtenerDatosCompletos() async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getAll'}),
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['success'] == true) {
          final List<dynamic> rawInventarios = res['inventarios'] ?? [];
          final catalogo = rawInventarios.map((e) => InventoryModel.fromJson(e)).toList();
          
          return {
            'usuarios': List<Map<String, dynamic>>.from(res['usuarios'] ?? []),
            'inventarios': catalogo,
          };
        }
      }
      throw Exception('Fallo al obtener datos');
    } catch (e) {
      throw Exception('Error de red: $e');
    }
  }

  static Future<bool> registrarUsuario({
    required String nombre, required String correo, 
    required String password, required String puesto, 
    required List<String> inventarios
  }) async {
    try {
      final response = await _postAction({
        'action': 'createUser',
        'nombre': nombre,
        'correo': correo,
        'password': password,
        'puesto': puesto,
        'inventarios': inventarios.join(','),
      });
      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> actualizarUsuarioAdmin({
    required String correo, required String nombre,
    required String puesto, required List<String> inventarios
  }) async {
    try {
      final response = await _postAction({
        'action': 'updateUser',
        'correo': correo,
        'nombre': nombre,
        'puesto': puesto,
        'inventarios': inventarios.join(','),
      });
      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> eliminarUsuario(String correo) async {
    try {
      final response = await _postAction({
        'action': 'deleteUser',
        'correo': correo,
      });
      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }

  static Future<InventoryModel?> crearInventario({
    required String nombre, required String spreadsheet, required String ubicacion
  }) async {
    try {
      final response = await _postAction({
        'action': 'createInventory',
        'nombre': nombre,
        'spreadsheet': spreadsheet,
        'ubicacion': ubicacion,
      });
      if (response['success'] == true) {
        return InventoryModel.fromJson(response['inventario']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _postAction(Map<String, dynamic> body) async {
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
      return {'success': false};
    }
  }
}