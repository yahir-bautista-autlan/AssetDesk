import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'barra_stub.dart' if (dart.library.js_interop) 'barra_web.dart';

class BarraSuperior extends StatefulWidget {
  final Color color;
  final Widget child;

  const BarraSuperior({super.key, required this.color, required this.child});

  @override
  State<BarraSuperior> createState() => _BarraSuperiorState();
}

class _BarraSuperiorState extends State<BarraSuperior> {
  static final List<Color> _pila = [];
  late final Color _propio;

  @override
  void initState() {
    super.initState();
    _propio = widget.color;
    _pila.add(_propio);
    _aplicar();
  }

  @override
  void dispose() {
    _pila.remove(_propio);
    _aplicar();
    super.dispose();
  }

  static void _aplicar() {
    if (!kIsWeb) return;
    final color = _pila.isEmpty ? Colors.white : _pila.last;
    final hex = (color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    aplicarColorBarra('#$hex');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}