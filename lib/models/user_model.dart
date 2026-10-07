import 'inventory_model.dart';

class UserModel {
  final String idUser;
  final String nombre;
  final String domain;
  final String correo;
  final String puesto;
  final List<InventoryModel> inventarios;
  final String status;

  bool get esAdmin => puesto == 'Administrador';

  UserModel({
    required this.idUser,
    required this.nombre,
    required this.domain,
    required this.correo,
    required this.puesto,
    required this.inventarios,
    required this.status,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    var rawInventarios = json['inventarios'];
    List<InventoryModel> invList = [];

    if (rawInventarios is List) {
      invList = rawInventarios
          .map((i) => InventoryModel.fromJson(i))
          .toList();
    }

    return UserModel(
      idUser: json['idUser']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      correo: json['correo']?.toString() ?? '',
      puesto: json['puesto']?.toString() ?? '',
      inventarios: invList,
      status: json['status']?.toString() ?? 'Activo',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idUser': idUser,
      'nombre': nombre,
      'domain': domain,
      'correo': correo,
      'puesto': puesto,
      'inventarios': inventarios.map((i) => i.toJson()).toList(),
      'status': status,
    };
  }
}