class InventoryModel {
  final String id;
  final String nombre;
  final String spreadsheetId;
  final String nombreVisible;
  final String ubicacion;

  const InventoryModel({
    required this.id,
    required this.nombre,
    required this.spreadsheetId,
    required this.nombreVisible,
    required this.ubicacion,
  });

  factory InventoryModel.fromJson(dynamic json) {
    if (json is Map) {
      final id = (json['id'] ?? '').toString();
      final nombre = (json['nombre'] ?? '').toString();
      final sheetId = (json['spreadsheetId'] ?? '').toString();
      final visible = (json['nombreVisible'] ?? sheetId).toString();
      final ubicacion = (json['ubicacion'] ?? '').toString();

      return InventoryModel(
        id: id,
        nombre: nombre.isEmpty ? id : nombre,
        spreadsheetId: sheetId,
        nombreVisible: visible.isEmpty ? sheetId : visible,
        ubicacion: ubicacion,
      );
    }
    final texto = json.toString();
    return InventoryModel(
      id: texto,
      nombre: texto,
      spreadsheetId: texto,
      nombreVisible: texto,
      ubicacion: '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'spreadsheetId': spreadsheetId,
        'nombreVisible': nombreVisible,
        'ubicacion': ubicacion,
      };
}