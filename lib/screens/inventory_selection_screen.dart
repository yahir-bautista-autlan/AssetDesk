import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../models/solicitud_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'inventory_dashboard_screen.dart';

class InventorySelectionScreen extends StatefulWidget {
  final List<InventoryModel> inventariosVinculados;

  const InventorySelectionScreen({
    super.key,
    required this.inventariosVinculados,
  });

  @override
  State<InventorySelectionScreen> createState() =>
      _InventorySelectionScreenState();
}

class _InventorySelectionScreenState extends State<InventorySelectionScreen> {
  static const primaryPurple = Color(0xFF532E7C);

  UserModel? _user;
  int _pendientes = 0;

  bool get _puedeAprobar {
    final u = _user;
    if (u == null) return false;
    return u.esAdmin || u.inventarios.any((i) => i.esResponsable(u.correo));
  }

  @override
  void initState() {
    super.initState();
    _cargarUsuario();
  }

  Future<void> _cargarUsuario() async {
    final u = await AuthService.obtenerUsuarioActual();
    if (!mounted) return;
    setState(() => _user = u);
    if (_puedeAprobar) _cargarPendientes();
  }

  Future<void> _cargarPendientes() async {
    final lista = await AuthService.obtenerSolicitudesPendientes();
    if (!mounted) return;
    setState(() => _pendientes = lista.length);
  }

  Future<void> _abrirSolicitudes() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SolicitudesPendientesScreen()),
    );
    if (mounted) _cargarPendientes();
  }

  Future<void> _abrirCambioPassword() async {
    final u = _user;
    if (u == null) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CambiarPasswordDialog(correo: u.correo),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña actualizada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _cerrarSesion() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Widget _avatar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.account_circle_outlined, color: Colors.black, size: 34),
        if (_pendientes > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text(
                _pendientes > 99 ? '99+' : '$_pendientes',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _itemsMenu() {
    final u = _user;
    final items = <PopupMenuEntry<String>>[];

    if (u != null) {
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                u.nombre,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                u.correo,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFE8F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  u.rolLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: primaryPurple,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      items.add(const PopupMenuDivider(height: 1));
    }

    if (u != null && u.esAdmin) {
      items.add(
        const PopupMenuItem<String>(
          value: 'admin',
          child: Row(
            children: [
              Icon(Icons.manage_accounts_outlined,
                  color: Colors.black87, size: 20),
              SizedBox(width: 12),
              Text('Administrar cuentas',
                  style: TextStyle(color: Colors.black87, fontSize: 15)),
            ],
          ),
        ),
      );
    }

    if (_puedeAprobar) {
      items.add(
        PopupMenuItem<String>(
          value: 'solicitudes',
          child: Row(
            children: [
              const Icon(Icons.rule_folder_outlined,
                  color: Colors.black87, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Solicitudes pendientes',
                    style: TextStyle(color: Colors.black87, fontSize: 15)),
              ),
              if (_pendientes > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_pendientes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    items.add(
      const PopupMenuItem<String>(
        value: 'password',
        child: Row(
          children: [
            Icon(Icons.lock_reset_outlined, color: Colors.black87, size: 20),
            SizedBox(width: 12),
            Text('Cambiar mi contraseña',
                style: TextStyle(color: Colors.black87, fontSize: 15)),
          ],
        ),
      ),
    );

    items.add(const PopupMenuDivider(height: 1));

    items.add(
      const PopupMenuItem<String>(
        value: 'logout',
        child: Row(
          children: [
            Icon(Icons.logout, color: Color(0xFFB3261E), size: 20),
            SizedBox(width: 12),
            Text('Cerrar sesión',
                style: TextStyle(color: Color(0xFFB3261E), fontSize: 15)),
          ],
        ),
      ),
    );

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final inventarios = widget.inventariosVinculados;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          'Selecciona tu inventario',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: primaryPurple,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        offset: const Offset(0, 45),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: const Color(0xFFF3EDF7),
                        icon: _avatar(),
                        onOpened: () {
                          if (_user == null) _cargarUsuario();
                        },
                        onSelected: (value) {
                          switch (value) {
                            case 'admin':
                              Navigator.pushNamed(context, '/admin');
                              break;
                            case 'solicitudes':
                              _abrirSolicitudes();
                              break;
                            case 'password':
                              _abrirCambioPassword();
                              break;
                            case 'logout':
                              _cerrarSesion();
                              break;
                          }
                        },
                        itemBuilder: (_) => _itemsMenu(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Espacios de trabajo asignados a tu cuenta.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF555555),
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: inventarios.isEmpty
                        ? const Center(
                            child: Text(
                              'No tienes inventarios asignados.',
                              style:
                                  TextStyle(color: Colors.black45, fontSize: 14),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount =
                                  constraints.maxWidth > 700 ? 2 : 1;

                              return GridView.builder(
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 16),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 24,
                                  mainAxisSpacing: 24,
                                  childAspectRatio:
                                      crossAxisCount == 2 ? 1.6 : 2.2,
                                ),
                                itemCount: inventarios.length,
                                itemBuilder: (context, index) =>
                                    _buildInventoryCard(
                                        context, inventarios[index]),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: primaryPurple,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              '!',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '¿No encuentras tu inventario?',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Solicita acceso al administrador de TI',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryCard(BuildContext context, InventoryModel inv) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFECECEC), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          hoverColor: Colors.transparent,
          highlightColor: const Color(0x11000000),
          splashColor: const Color(0x224A2574),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    InventoryDashboardScreen(inventario: inv),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
            child: Row(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFE8F6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/warehouse_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.warehouse_rounded,
                          size: 42,
                          color: primaryPurple,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inv.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (inv.ubicacion.isNotEmpty)
                        Text(
                          'Ubicación: ${inv.ubicacion}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF4B5563),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Google Sheet: ${inv.nombreVisible.isNotEmpty ? inv.nombreVisible : 'No vinculado'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SolicitudesPendientesScreen extends StatefulWidget {
  const SolicitudesPendientesScreen({super.key});

  @override
  State<SolicitudesPendientesScreen> createState() =>
      _SolicitudesPendientesScreenState();
}

class _SolicitudesPendientesScreenState
    extends State<SolicitudesPendientesScreen> {
  static const primaryPurple = Color(0xFF532E7C);

  List<SolicitudModel> _solicitudes = [];
  bool _cargando = true;
  final Set<String> _procesando = {};
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final lista = await AuthService.obtenerSolicitudesPendientes();
    if (!mounted) return;
    setState(() {
      _solicitudes = lista;
      _cargando = false;
    });
  }

  Color _colorAccion(String tipo) {
    switch (tipo) {
      case 'agregar':
        return const Color(0xFF16A34A);
      case 'editar':
        return const Color(0xFF2563EB);
      case 'baja':
        return const Color(0xFFDC2626);
      default:
        return primaryPurple;
    }
  }

  IconData _iconoAccion(String tipo) {
    switch (tipo) {
      case 'agregar':
        return Icons.add_circle_outline;
      case 'editar':
        return Icons.edit_outlined;
      case 'baja':
        return Icons.remove_circle_outline;
      default:
        return Icons.help_outline;
    }
  }

  List<MapEntry<String, String>> _detalles(SolicitudModel s) {
    if (s.actionType == 'baja') {
      final motivo = s.motivoBaja;
      return motivo.isEmpty ? [] : [MapEntry('Motivo', motivo)];
    }
    return s.payloadMap.entries
        .map((e) => MapEntry(e.key, e.value?.toString().trim() ?? ''))
        .where((e) => e.value.isNotEmpty)
        .toList();
  }

  Future<void> _resolver(SolicitudModel s, bool aprobar) async {
    String comentario = '';

    if (!aprobar) {
      final resultado = await showDialog<String>(
        context: context,
        builder: (_) => const _ComentarioRechazoDialog(),
      );
      if (resultado == null) return;
      comentario = resultado;
    } else {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Aprobar solicitud',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(
            'Se aplicará el cambio solicitado por ${s.requestedByName} directamente en el inventario.',
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Color(0xFF4B5563))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aprobar',
                  style: TextStyle(
                      color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    setState(() => _procesando.add(s.requestId));

    final exito = await AuthService.resolverSolicitud(
      requestId: s.requestId,
      aprobar: aprobar,
      comentario: comentario,
    );

    if (!mounted) return;
    setState(() => _procesando.remove(s.requestId));

    if (exito) {
      _huboCambios = true;
      setState(() => _solicitudes.removeWhere((x) => x.requestId == s.requestId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(aprobar
              ? 'Solicitud aprobada y aplicada'
              : 'Solicitud rechazada'),
          backgroundColor: aprobar ? Colors.green : const Color(0xFF4B5563),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.ultimoError.isEmpty
              ? 'No se pudo procesar la solicitud'
              : AuthService.ultimoError),
          backgroundColor: Colors.redAccent,
        ),
      );
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _huboCambios);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Color(0xFF111827), size: 22),
                          onPressed: () => Navigator.pop(context, _huboCambios),
                        ),
                        const Expanded(
                          child: Text(
                            'Solicitudes pendientes',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: primaryPurple),
                          onPressed: _cargando ? null : _cargar,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _cargando
                        ? const Center(
                            child:
                                CircularProgressIndicator(color: primaryPurple))
                        : _solicitudes.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.task_alt,
                                        size: 56, color: Color(0xFF9CA3AF)),
                                    SizedBox(height: 12),
                                    Text(
                                      'No hay solicitudes pendientes',
                                      style: TextStyle(
                                          color: Colors.black45, fontSize: 15),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                color: primaryPurple,
                                onRefresh: _cargar,
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 8, 20, 24),
                                  itemCount: _solicitudes.length,
                                  itemBuilder: (context, i) =>
                                      _buildTarjeta(_solicitudes[i]),
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTarjeta(SolicitudModel s) {
    final color = _colorAccion(s.actionType);
    final detalles = _detalles(s);
    final procesando = _procesando.contains(s.requestId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconoAccion(s.actionType), size: 14, color: color),
                      const SizedBox(width: 5),
                      Text(
                        s.accionLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  s.fechaCorta,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              s.inventoryName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Pestaña: ${s.pestana}${s.snOriginal.isNotEmpty ? '  ·  Identificador: ${s.snOriginal}' : ''}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 16, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${s.requestedByName} (${s.requestedByEmail})',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF374151)),
                  ),
                ),
              ],
            ),
            if (detalles.isNotEmpty) ...[
              const SizedBox(height: 4),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    s.actionType == 'baja'
                        ? 'Ver motivo'
                        : 'Ver datos del cambio (${detalles.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primaryPurple,
                    ),
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF0F0F3)),
                      ),
                      child: Column(
                        children: detalles
                            .map(
                              (d) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 130,
                                      child: Text(
                                        d.key,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        d.value,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: procesando ? null : () => _resolver(s, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFF3D6D6)),
                      backgroundColor: const Color(0xFFFEF2F2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Rechazar',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: procesando ? null : () => _resolver(s, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: procesando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Aprobar',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComentarioRechazoDialog extends StatefulWidget {
  const _ComentarioRechazoDialog();

  @override
  State<_ComentarioRechazoDialog> createState() =>
      _ComentarioRechazoDialogState();
}

class _ComentarioRechazoDialogState extends State<_ComentarioRechazoDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Rechazar solicitud',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Puedes dejar un comentario para que el solicitante sepa el motivo.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Comentario (opcional)',
              hintStyle:
                  const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF532E7C), width: 1.5),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: Color(0xFF4B5563))),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Rechazar',
              style: TextStyle(
                  color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class CambiarPasswordDialog extends StatefulWidget {
  final String correo;

  const CambiarPasswordDialog({super.key, required this.correo});

  @override
  State<CambiarPasswordDialog> createState() => _CambiarPasswordDialogState();
}

class _CambiarPasswordDialogState extends State<CambiarPasswordDialog> {
  static const primaryPurple = Color(0xFF532E7C);

  final _formKey = GlobalKey<FormState>();
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureActual = true;
  bool _obscureNueva = true;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    final res = await AuthService.cambiarMiPassword(
      correo: widget.correo,
      actualPassword: _actualCtrl.text,
      nuevaPassword: _nuevaCtrl.text,
    );

    if (!mounted) return;

    if (res['exito'] == true) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = (res['mensaje'] ?? 'No se pudo cambiar la contraseña')
            .toString();
      });
    }
  }

  InputDecoration _decoracion(String label, bool oculto, VoidCallback toggle) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      suffixIcon: IconButton(
        icon: Icon(
          oculto ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 18,
        ),
        onPressed: toggle,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryPurple, width: 1.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Cambiar mi contraseña',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _actualCtrl,
                  obscureText: _obscureActual,
                  decoration: _decoracion('Contraseña actual', _obscureActual,
                      () => setState(() => _obscureActual = !_obscureActual)),
                  validator: (v) => (v ?? '').isEmpty
                      ? 'Ingresa tu contraseña actual'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nuevaCtrl,
                  obscureText: _obscureNueva,
                  decoration: _decoracion('Nueva contraseña', _obscureNueva,
                      () => setState(() => _obscureNueva = !_obscureNueva)),
                  validator: (v) {
                    final p = v ?? '';
                    if (p.length < 8) return 'Mínimo 8 caracteres';
                    if (!RegExp(r'[A-Za-z]').hasMatch(p) ||
                        !RegExp(r'\d').hasMatch(p)) {
                      return 'Debe incluir al menos una letra y un número';
                    }
                    if (p == _actualCtrl.text) {
                      return 'Debe ser distinta a la actual';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureNueva,
                  decoration: InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    isDense: true,
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: primaryPurple, width: 1.8),
                    ),
                  ),
                  validator: (v) =>
                      v != _nuevaCtrl.text ? 'Las contraseñas no coinciden' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                        color: Color(0xFFDC2626), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar',
              style: TextStyle(color: Color(0xFF4B5563))),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryPurple,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text('Guardar',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}