import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/auth_service.dart';
import 'inventory_dashboard_screen.dart';

class InventoryMenuScreen extends StatefulWidget {
  final InventoryModel inventario;
  final bool restaurarDashboard;

  const InventoryMenuScreen({
    super.key,
    required this.inventario,
    this.restaurarDashboard = false,
  });

  @override
  State<InventoryMenuScreen> createState() => _InventoryMenuScreenState();
}

class _OpcionMenu {
  final IconData icono;
  final String titulo;
  final String detalle;
  final int pestana;

  const _OpcionMenu({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.pestana,
  });
}

class _InventoryMenuScreenState extends State<InventoryMenuScreen> {
  static const Color _morado = Color(0xFF532E7C);

  static const List<_OpcionMenu> _opciones = [
    _OpcionMenu(
      icono: CupertinoIcons.desktopcomputer,
      titulo: 'Captura',
      detalle: 'Equipos de cómputo',
      pestana: 0,
    ),
    _OpcionMenu(
      icono: CupertinoIcons.printer,
      titulo: 'Impresoras',
      detalle: 'Impresión y multifuncionales',
      pestana: 1,
    ),
    _OpcionMenu(
      icono: Icons.storage_rounded,
      titulo: 'Otros',
      detalle: 'Redes y otros dispositivos',
      pestana: 2,
    ),
    _OpcionMenu(
      icono: Icons.invert_colors,
      titulo: 'Consumibles',
      detalle: 'Insumos y refacciones',
      pestana: 3,
    ),
  ];

  Future<Uint8List?>? _futuroLogo;

  @override
  void initState() {
    super.initState();
    final inv = widget.inventario;
    if (inv.logoId.isNotEmpty) {
      _futuroLogo =
          AuthService.obtenerImagenInventario(inv.id, 'logo', inv.logoId);
    }
    AuthService.guardarSitio(widget.inventario.id, -1);
    AuthService.precargarInventario(widget.inventario.spreadsheetId);
    if (widget.restaurarDashboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _abrir(null);
      });
    }
  }

  String _nombreCorto() {
    final n = widget.inventario.nombre
        .trim()
        .replaceFirst(RegExp(r'^inventario\s+', caseSensitive: false), '')
        .trim();
    return n.isEmpty ? 'INVENTARIO' : n.toUpperCase();
  }

  Future<void> _abrir(_OpcionMenu? opcion) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryDashboardScreen(
          inventario: widget.inventario,
          pestanaInicial: opcion?.pestana,
        ),
      ),
    );
    if (mounted) AuthService.guardarSitio(widget.inventario.id, -1);
  }

  Widget _logo() {
    final inv = widget.inventario;
    final respaldo = Image.asset(
      'assets/logo_autlan.png',
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.inventory_2_outlined, size: 40, color: _morado),
    );
    if (inv.logoId.isEmpty) return respaldo;
    return FutureBuilder<Uint8List?>(
      future: _futuroLogo,
      initialData: AuthService.imagenEnMemoria(inv.logoId),
      builder: (context, snap) {
        final bytes = snap.data;
        final listo = snap.connectionState == ConnectionState.done ||
            bytes != null;
        Widget contenido;
        if (bytes != null) {
          contenido = Image.memory(
            bytes,
            key: const ValueKey('logo'),
            fit: BoxFit.contain,
            cacheWidth: 700,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          );
        } else if (listo) {
          contenido = KeyedSubtree(key: const ValueKey('respaldo'), child: respaldo);
        } else {
          contenido = const SizedBox.expand(key: ValueKey('cargando'));
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: contenido,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF6F1FB), Colors.white],
            stops: [0, 0.55],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(top: -90, right: -70, child: _Halo(280)),
            const Positioned(bottom: -120, left: -90, child: _Halo(320)),
            Positioned.fill(child: _contenido()),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Volver',
                    icon: const Icon(Icons.arrow_back_rounded, size: 26),
                    color: _morado,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final amplio = c.maxWidth >= 760 && c.maxHeight >= 520;
                    return amplio
                        ? _vistaAmplia(c)
                        : _vistaCompacta(c.maxWidth, c.maxHeight);
                  },
                ),
              ),
            ],
          ),
    );
  }

  Widget _vistaAmplia(BoxConstraints c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 520),
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: SizedBox(
            width: 760,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _encabezado(),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _opciones.length; i++) ...[
                      if (i > 0) const SizedBox(width: 18),
                      _Entrada(
                        retraso: 90 * i,
                        child: SizedBox(
                          width: 164,
                          child: _Mosaico(
                            opcion: _opciones[i],
                            onTap: () => _abrir(_opciones[i]),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        ),
        ),
      ),
    );
  }

  Widget _vistaCompacta(double ancho, double alto) {
    final apaisado = ancho >= 560;
    final columnas = apaisado ? 4 : 2;
    final filas = apaisado ? 1 : 2;
    const espacio = 12.0;

    Widget celda(int i) => Expanded(
          child: _Entrada(
            retraso: 70 * i,
            child: _Mosaico(
              opcion: _opciones[i],
              onTap: () => _abrir(_opciones[i]),
              relleno: true,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          _encabezado(compacto: true, alto: alto),
          SizedBox(height: alto < 520 ? 10 : 18),
          Expanded(
            child: Column(
              children: [
                for (var f = 0; f < filas; f++) ...[
                  if (f > 0) const SizedBox(height: espacio),
                  Expanded(
                    child: Row(
                      children: [
                        for (var k = 0; k < columnas; k++) ...[
                          if (k > 0) const SizedBox(width: espacio),
                          celda(f * columnas + k),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezado({bool compacto = false, double alto = 800}) {
    final altoLogo = compacto ? (alto * 0.14).clamp(48.0, 92.0) : 100.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: compacto ? altoLogo * 3.4 : 300,
          height: altoLogo,
          child: _logo(),
        ),
        SizedBox(height: compacto ? 8 : 14),
        Text(
          'INVENTARIO GENERAL',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compacto ? 10.5 : 13,
            fontWeight: FontWeight.w700,
            letterSpacing: compacto ? 3 : 4,
            color: const Color(0xFF9B87BA),
          ),
        ),
        SizedBox(height: compacto ? 4 : 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _nombreCorto(),
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: compacto ? 24 : 28,
              fontWeight: FontWeight.w300,
              letterSpacing: compacto ? 3 : 5,
              height: 1.15,
              color: _morado,
            ),
          ),
        ),
      ],
    );
  }
}

class _Halo extends StatelessWidget {
  final double tamano;
  const _Halo(this.tamano);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: tamano,
        height: tamano,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Color(0x1A532E7C), Color(0x00532E7C)],
          ),
        ),
      ),
    );
  }
}

class _Entrada extends StatelessWidget {
  final int retraso;
  final Widget child;

  const _Entrada({required this.retraso, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + retraso),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, hijo) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: hijo),
      ),
    );
  }
}

class _Mosaico extends StatefulWidget {
  final _OpcionMenu opcion;
  final VoidCallback onTap;
  final bool relleno;

  const _Mosaico({
    required this.opcion,
    required this.onTap,
    this.relleno = false,
  });

  @override
  State<_Mosaico> createState() => _MosaicoState();
}

class _MosaicoState extends State<_Mosaico> {
  static const Color _morado = Color(0xFF532E7C);

  bool _encima = false;
  bool _presionado = false;

  @override
  Widget build(BuildContext context) {
    final activo = _encima || _presionado;
    final contenido = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(19),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: activo
                              ? const [Color(0xFF6B3E9A), Color(0xFF532E7C)]
                              : const [Color(0xFFF6F1FB), Color(0xFFEFE8F6)],
                        ),
                        boxShadow: activo
                            ? [
                                BoxShadow(
                                  color: _morado.withOpacity(0.28),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : const [],
                      ),
                      child: Icon(
                        widget.opcion.icono,
                        size: 26,
                        color: activo ? Colors.white : _morado,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.opcion.titulo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: _morado,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.opcion.detalle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: activo ? 1 : 0,
                      child: const Icon(Icons.arrow_forward_rounded,
                          size: 18, color: _morado),
                    ),
                  ],
                );
    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _encima = true),
        onExit: (_) => setState(() => _encima = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _presionado = true),
          onTapCancel: () => setState(() => _presionado = false),
          onTapUp: (_) => setState(() => _presionado = false),
          onTap: widget.onTap,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: Offset(0, _encima && !_presionado ? -0.03 : 0),
            child: AnimatedScale(
              scale: _presionado ? 0.97 : 1,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: widget.relleno
                    ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
                    : const EdgeInsets.fromLTRB(14, 16, 14, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: activo
                        ? const Color(0xFFB9A5D3)
                        : const Color(0xFFEFE8F6),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _morado.withOpacity(activo ? 0.16 : 0.06),
                      blurRadius: activo ? 26 : 16,
                      offset: Offset(0, activo ? 12 : 6),
                    ),
                  ],
                ),
                child: widget.relleno
                    ? Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(width: 150, child: contenido),
                        ),
                      )
                    : contenido,
              ),
            ),
          ),
        ),
      ),
    );
  }
}