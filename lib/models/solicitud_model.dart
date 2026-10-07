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
    return SolicitudModel(
      requestId: json['requestId']?.toString() ?? '',
      inventoryId: json['inventoryId']?.toString() ?? '',
      inventoryName: json['inventoryName']?.toString() ?? '',
      pestana: json['pestana']?.toString() ?? '',
      actionType: json['actionType']?.toString() ?? '',
      payload: json['payload']?.toString() ?? '{}',
      snOriginal: json['snOriginal']?.toString() ?? '',
      requestedByEmail: json['requestedByEmail']?.toString() ?? '',
      requestedByName: json['requestedByName']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
  
  Map<String, dynamic> get payloadMap {
    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
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