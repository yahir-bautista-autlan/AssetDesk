import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: 'AssetDesk',
        primaryColor: color.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}