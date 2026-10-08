import 'inventory_model.dart';

class UserModel {
  final String idUser;
  final String nombre;
  final String domain;
  final String correo;
  final String puesto;
  final String status;
  final List<InventoryModel> inventarios;

  UserModel({
    required this.idUser,
    required this.nombre,
    required this.domain,
    required this.correo,
    required this.puesto,
    required this.status,
    required this.inventarios,
  });

  bool get esAdmin => puesto.trim().toLowerCase() == 'administrador';
  bool get esJefeDeArea => puesto.trim().toLowerCase() == 'jefe de area';
  bool get esResidente => puesto.trim().toLowerCase() == 'residente';
  bool get esConsultor => puesto.trim().toLowerCase() == 'consultor';

  bool get puedeEditar => !esConsultor;
  bool get puedeGestionarUsuarios => esAdmin;
  bool get puedeGestionarInventarios => esAdmin;

  String get rolLabel {
    if (esAdmin) return 'Administrador';
    if (esJefeDeArea) return 'Jefe de Área';
    if (esResidente) return 'Residente';
    if (esConsultor) return 'Consultor';
    return puesto;
  }

  bool tieneAccesoA(String inventoryId) {
    if (esAdmin) return true;
    return inventarios.any((inv) => inv.id == inventoryId);
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    List<InventoryModel> listaInventarios = [];

    if (json['inventarios'] is List) {
      listaInventarios = (json['inventarios'] as List)
          .map((e) => InventoryModel.fromJson(e))
          .toList();
    }

    return UserModel(
      idUser: json['idUser']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      correo: json['correo']?.toString() ?? '',
      puesto: json['puesto']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Activo',
      inventarios: listaInventarios,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idUser': idUser,
      'nombre': nombre,
      'domain': domain,
      'correo': correo,
      'puesto': puesto,
      'status': status,
      'inventarios': inventarios.map((e) => e.toJson()).toList(),
    };
  }
}