import 'dart:convert';

class SolicitudModel {
  final String requestId;
  final String inventoryId;
  final String inventoryName;
  final String pestana;
  final String actionType;
  final String payload;
  final String snOriginal;
  final String requestedByEmail;
  final String requestedByName;
  final String createdAt;

  SolicitudModel({
    required this.requestId,
    required this.inventoryId,
    required this.inventoryName,
    required this.pestana,
    required this.actionType,
    required this.payload,
    required this.snOriginal,
    required this.requestedByEmail,
    required this.requestedByName,
    required this.createdAt,
  });

  factory SolicitudModel.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    String payloadString;
    if (rawPayload is Map || rawPayload is List) {
      payloadString = jsonEncode(rawPayload);
    } else {
      payloadString = rawPayload?.toString() ?? '{}';
    }
    if (payloadString.trim().isEmpty) payloadString = '{}';

    return SolicitudModel(
      requestId: json['requestId']?.toString() ?? '',
      inventoryId: json['inventoryId']?.toString() ?? '',
      inventoryName: json['inventoryName']?.toString() ?? '',
      pestana: json['pestana']?.toString() ?? '',
      actionType: json['actionType']?.toString() ?? '',
      payload: payloadString,
      snOriginal: json['snOriginal']?.toString() ?? '',
      requestedByEmail: json['requestedByEmail']?.toString() ?? '',
      requestedByName: json['requestedByName']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> get payloadMap {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {};
    } catch (_) {
      return {};
    }
  }

  String get accionLabel {
    switch (actionType) {
      case 'agregar':
        return 'Agregar elemento';
      case 'editar':
        return 'Editar elemento';
      case 'baja':
        return 'Dar de baja';
      default:
        return actionType;
    }
  }

  String get motivoBaja => payloadMap['motivo']?.toString() ?? '';

  String get fechaCorta {
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return createdAt;
    final l = dt.toLocal();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${p2(l.day)}/${p2(l.month)}/${l.year} ${p2(l.hour)}:${p2(l.minute)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'inventoryId': inventoryId,
      'inventoryName': inventoryName,
      'pestana': pestana,
      'actionType': actionType,
      'payload': payload,
      'snOriginal': snOriginal,
      'requestedByEmail': requestedByEmail,
      'requestedByName': requestedByName,
      'createdAt': createdAt,
    };
  }
}