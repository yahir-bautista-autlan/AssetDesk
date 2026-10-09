import 'dart:convert';

class CambioCampo {
  final String campo;
  final String anterior;
  final String nuevo;

  const CambioCampo(this.campo, this.anterior, this.nuevo);
}

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
  final Map<String, dynamic> datosActuales;
  final bool referenciaEncontrada;

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
    this.datosActuales = const {},
    this.referenciaEncontrada = true,
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

    Map<String, dynamic> actuales = {};
    final rawActuales = json['datosActuales'];
    if (rawActuales is Map) {
      actuales = Map<String, dynamic>.from(rawActuales);
    } else if (rawActuales is String && rawActuales.trim().isNotEmpty) {
      try {
        final d = jsonDecode(rawActuales);
        if (d is Map) actuales = Map<String, dynamic>.from(d);
      } catch (_) {}
    }

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
      datosActuales: actuales,
      referenciaEncontrada: json['referenciaEncontrada'] != false,
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

  static String _clave(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static String _texto(dynamic v) => v?.toString().trim() ?? '';

  List<CambioCampo> get cambios {
    if (actionType != 'editar') return [];
    final nuevos = payloadMap;
    final resultado = <CambioCampo>[];

    for (final e in nuevos.entries) {
      final nuevo = _texto(e.value);
      final anterior = _texto(datosActuales[e.key]);
      if (_clave(nuevo) == _clave(anterior)) continue;
      resultado.add(CambioCampo(e.key, anterior, nuevo));
    }
    return resultado;
  }

  List<MapEntry<String, String>> get camposSinCambio {
    if (actionType != 'editar') return [];
    final nuevos = payloadMap;
    final resultado = <MapEntry<String, String>>[];

    for (final e in nuevos.entries) {
      final nuevo = _texto(e.value);
      final anterior = _texto(datosActuales[e.key]);
      if (nuevo.isEmpty && anterior.isEmpty) continue;
      if (_clave(nuevo) == _clave(anterior)) {
        resultado.add(MapEntry(e.key, nuevo));
      }
    }
    return resultado;
  }

  List<MapEntry<String, String>> get camposNuevos {
    return payloadMap.entries
        .map((e) => MapEntry(e.key, _texto(e.value)))
        .where((e) => e.value.isNotEmpty)
        .toList();
  }

  List<MapEntry<String, String>> get camposDelElemento {
    return datosActuales.entries
        .map((e) => MapEntry(e.key, _texto(e.value)))
        .where((e) => e.value.isNotEmpty)
        .toList();
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
      'datosActuales': datosActuales,
      'referenciaEncontrada': referenciaEncontrada,
    };
  }
}