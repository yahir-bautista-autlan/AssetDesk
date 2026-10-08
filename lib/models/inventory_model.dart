class InventoryModel {
  final String id;
  final String nombre;
  final String responsableEmail;
  final String spreadsheetId;
  final String nombreVisible;
  final String ubicacion;

  InventoryModel({
    required this.id,
    required this.nombre,
    this.responsableEmail = '',
    required this.spreadsheetId,
    this.nombreVisible = '',
    this.ubicacion = '',
  });

  bool esResponsable(String correo) =>
      responsableEmail.trim().toLowerCase() == correo.trim().toLowerCase();

  factory InventoryModel.fromJson(dynamic json) {
    if (json is Map) {
      return InventoryModel(
        id: json['id']?.toString() ?? '',
        nombre: json['nombre']?.toString() ?? '',
        responsableEmail: json['responsableEmail']?.toString() ?? '',
        spreadsheetId: json['spreadsheetId']?.toString() ?? '',
        nombreVisible: json['nombreVisible']?.toString() ?? '',
        ubicacion: json['ubicacion']?.toString() ?? '',
      );
    }
    final s = json?.toString() ?? '';
    return InventoryModel(
      id: s,
      nombre: s,
      spreadsheetId: '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'responsableEmail': responsableEmail,
      'spreadsheetId': spreadsheetId,
      'nombreVisible': nombreVisible,
      'ubicacion': ubicacion,
    };
  }
}