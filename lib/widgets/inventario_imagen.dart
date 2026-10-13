import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class InventarioImagen extends StatefulWidget {
  final String inventarioId;
  final String tipo;
  final String fileId;
  final BoxFit fit;
  final Widget fallback;

  const InventarioImagen({
    super.key,
    required this.inventarioId,
    required this.tipo,
    required this.fileId,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  @override
  State<InventarioImagen> createState() => _InventarioImagenState();
}

class _InventarioImagenState extends State<InventarioImagen> {
  Future<Uint8List?>? _futuro;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant InventarioImagen old) {
    super.didUpdateWidget(old);
    if (old.fileId != widget.fileId || old.inventarioId != widget.inventarioId) {
      _cargar();
    }
  }

  void _cargar() {
    _futuro = widget.fileId.isEmpty
        ? Future.value(null)
        : AuthService.obtenerImagenInventario(
            widget.inventarioId, widget.tipo, widget.fileId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _futuro,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return widget.fallback;
        return Image.memory(
          bytes,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
        );
      },
    );
  }
}