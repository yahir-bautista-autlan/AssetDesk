import 'inventory_model.dart';

class UserModel {
  final String nombre;
  final String correo;
  final String puesto;
  final List<InventoryModel> inventarios;

  UserModel({
    required this.nombre,
    required this.correo,
    required this.puesto,
    required this.inventarios,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final rawInv = json['inventarios'];
    final List<InventoryModel> inventarios = [];

    if (rawInv is List) {
      for (final item in rawInv) {
        inventarios.add(InventoryModel.fromJson(item));
      }
    }

    return UserModel(
      nombre: (json['nombre'] ?? '').toString(),
      correo: (json['correo'] ?? '').toString(),
      puesto: (json['puesto'] ?? '').toString(),
      inventarios: inventarios,
    );
  }

  bool get esAdmin {
    final c = correo.toLowerCase().trim();
    final p = puesto.toLowerCase().trim();
    return c == 'admin' || p == 'administrador' || p == 'admin';
  }

  bool get puedeAsignarEquipos => puesto.toLowerCase().trim() != 'residente';
}