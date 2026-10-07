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
    required this.responsableEmail,
    required this.spreadsheetId,
    required this.nombreVisible,
    required this.ubicacion,
  });

  factory InventoryModel.fromJson(Map<String, dynamic> json) {
    return InventoryModel(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      responsableEmail: json['responsableEmail']?.toString() ?? '',
      spreadsheetId: json['spreadsheetId']?.toString() ?? '',
      nombreVisible: json['nombreVisible']?.toString() ?? '',
      ubicacion: json['ubicacion']?.toString() ?? '',
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