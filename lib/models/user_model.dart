import 'inventory_model.dart';

class UserModel {
  final String id;
  final String nombre;
  final String correo;
  final String puesto;
  final bool esAdmin;
  final List<InventoryModel> inventarios;

  UserModel({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.puesto,
    required this.esAdmin,
    required this.inventarios,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, List<InventoryModel> catalogoInventarios) {
    final puestoStr = (json['PUESTO'] ?? json['puesto'] ?? '').toString();
    final esAdmin = puestoStr.toLowerCase().contains('admin') || 
                    (json['ES_ADMIN'] ?? json['es_admin'] ?? false) == true;

    final String invString = (json['INVENTARIOS'] ?? json['inventarios'] ?? '').toString();
    final List<String> invIds = invString.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    List<InventoryModel> misInventarios = [];
    for (var id in invIds) {
      try {
        misInventarios.add(catalogoInventarios.firstWhere((inv) => inv.id == id));
      } catch (_) {}
    }

    return UserModel(
      id: (json['ID'] ?? json['id'] ?? '').toString(),
      nombre: (json['NOMBRE'] ?? json['nombre'] ?? '').toString(),
      correo: (json['CORREO'] ?? json['correo'] ?? '').toString(),
      puesto: puestoStr,
      esAdmin: esAdmin,
      inventarios: misInventarios,
    );
  }
}