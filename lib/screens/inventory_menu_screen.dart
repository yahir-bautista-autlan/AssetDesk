import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/auth_service.dart';
import '../widgets/inventario_imagen.dart';
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

  @override
  void initState() {
    super.initState();
    AuthService.guardarSitio(widget.inventario.id, -1);
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
    return InventarioImagen(
      inventarioId: inv.id,
      tipo: 'logo',
      fileId: inv.logoId,
      fit: BoxFit.contain,
      fallback: respaldo,
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
        child: SafeArea(
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
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _encabezado(),
                          const SizedBox(height: 36),
                          LayoutBuilder(
                            builder: (context, c) {
                              final enFila = c.maxWidth >= 760;
                              final columnas = enFila ? 4 : 2;
                              const espacio = 18.0;
                              final ancho =
                                  (c.maxWidth - espacio * (columnas - 1)) /
                                      columnas;
                              return Wrap(
                                alignment: WrapAlignment.center,
                                spacing: espacio,
                                runSpacing: espacio,
                                children: [
                                  for (var i = 0; i < _opciones.length; i++)
                                    _Entrada(
                                      retraso: 90 * i,
                                      child: SizedBox(
                                        width: ancho.clamp(140.0, 210.0),
                                        child: _Mosaico(
                                          numero: '0${i + 1}',
                                          opcion: _opciones[i],
                                          onTap: () => _abrir(_opciones[i]),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _encabezado() {
    return Column(
      children: [
        SizedBox(height: 76, child: _logo()),
        const SizedBox(height: 18),
        const Text(
          'INVENTARIO GENERAL',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
            color: Color(0xFF9B87BA),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _nombreCorto(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w300,
            letterSpacing: 5,
            height: 1.15,
            color: _morado,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 1, color: const Color(0xFFD9C8EA)),
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFB9A5D3),
                shape: BoxShape.circle,
              ),
            ),
            Container(width: 36, height: 1, color: const Color(0xFFD9C8EA)),
          ],
        ),
      ],
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
  final String numero;
  final _OpcionMenu opcion;
  final VoidCallback onTap;

  const _Mosaico({
    required this.numero,
    required this.opcion,
    required this.onTap,
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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        widget.numero,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: Color(0xFFC9BADD),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: activo
                              ? const [Color(0xFF6B3E9A), Color(0xFF532E7C)]
                              : const [Color(0xFFF6F1FB), Color(0xFFEFE8F6)],
                        ),
                      ),
                      child: Icon(
                        widget.opcion.icono,
                        size: 30,
                        color: activo ? Colors.white : _morado,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.opcion.titulo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
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
                        fontSize: 12,
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}