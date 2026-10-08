import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  static const primaryPurple = Color(0xFF4A2574);
  static const lightPurpleBg = Color(0xFFEDE4F5);
  static const backgroundColor = Color(0xFFF8F9FA);

  static const List<String> _roles = [
    'Administrador',
    'Jefe de Area',
    'Residente',
    'Consultor',
  ];

  int _tab = 0;
  bool _cargando = true;
  bool _guardando = false;
  bool _modoEdicion = false;

  final _busquedaCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();

  String? _rolSeleccionado;
  final List<String> _seleccionados = [];

  List<Map<String, dynamic>> _usuarios = [];
  List<InventoryModel> _catalogo = [];

  String get _miCorreo => AuthService.actorEmailSync.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    super.dispose();
  }

  List<String> _separar(dynamic raw) {
    return (raw ?? '')
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _limpiar(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  String? _rolCanonico(String raw) {
    final buscado = _limpiar(raw);
    for (final r in _roles) {
      if (_limpiar(r) == buscado) return r;
    }
    return null;
  }

  String _rolVisible(String rol) {
    return rol == 'Jefe de Area' ? 'Jefe de Área' : rol;
  }

  InventoryModel? _inventarioPorId(String id) {
    for (final inv in _catalogo) {
      if (inv.id == id) return inv;
    }
    return null;
  }

  String _etiqueta(String id) {
    final inv = _inventarioPorId(id);
    if (inv == null) return id;
    return inv.ubicacion.isNotEmpty ? inv.ubicacion : inv.nombre;
  }

  void _mensaje(String texto, {Color color = Colors.green, int segundos = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: color,
        duration: Duration(seconds: segundos),
      ),
    );
  }

  String _errorServidor(String porDefecto) {
    return AuthService.ultimoError.isEmpty ? porDefecto : AuthService.ultimoError;
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final resultado = await AuthService.obtenerDatosCompletos();
    if (!mounted) return;
    setState(() {
      _usuarios = List<Map<String, dynamic>>.from(resultado['usuarios'] as List);
      _catalogo = List<InventoryModel>.from(resultado['inventarios'] as List);
      _cargando = false;
    });
    if (_usuarios.isEmpty && AuthService.ultimoError.isNotEmpty) {
      _mensaje(AuthService.ultimoError, color: Colors.redAccent);
    }
  }

  void _limpiarFormulario() {
    _nombreCtrl.clear();
    _correoCtrl.clear();
    _rolSeleccionado = null;
    _seleccionados.clear();
    _modoEdicion = false;
  }

  void _prepararEdicion(Map<String, dynamic> u) {
    setState(() {
      _modoEdicion = true;
      _nombreCtrl.text = (u['nombre'] ?? '').toString();
      _correoCtrl.text = (u['correo'] ?? '').toString();
      _rolSeleccionado = _rolCanonico((u['puesto'] ?? '').toString()) ?? _roles.last;
      _seleccionados
        ..clear()
        ..addAll(_separar(u['inventarios']));
      _tab = 1;
    });
  }

  Future<void> _guardarUsuario() async {
    if (!_formKey.currentState!.validate()) return;

    if (_rolSeleccionado == null) {
      _mensaje('Selecciona un rol', color: Colors.redAccent);
      return;
    }

    final esAdminRol = _rolSeleccionado == 'Administrador';
    if (!esAdminRol && _seleccionados.isEmpty) {
      _mensaje('Asigna al menos un inventario a este rol', color: Colors.redAccent);
      return;
    }

    setState(() => _guardando = true);

    bool exito;
    if (_modoEdicion) {
      exito = await AuthService.actualizarUsuarioAdmin(
        correo: _correoCtrl.text.trim(),
        nombre: _nombreCtrl.text.trim(),
        puesto: _rolSeleccionado!,
        inventarios: _seleccionados.join(','),
      );
    } else {
      exito = await AuthService.invitarUsuario(
        nombre: _nombreCtrl.text.trim(),
        correo: _correoCtrl.text.trim(),
        rol: _rolSeleccionado!,
        inventarios: List<String>.from(_seleccionados),
      );
    }

    if (!mounted) return;
    setState(() => _guardando = false);

    if (exito) {
      final aviso = AuthService.ultimoMensaje;
      final fallaCorreo = aviso.toLowerCase().contains('no se pudo enviar');
      if (_modoEdicion) {
        _mensaje('Usuario actualizado. Si cambiaste su rol, aplicará en su próximo inicio de sesión.');
      } else if (fallaCorreo) {
        _mensaje(aviso, color: const Color(0xFFF59E0B), segundos: 8);
      } else {
        _mensaje('Invitación enviada a ${_correoCtrl.text.trim()}');
      }
      setState(() {
        _limpiarFormulario();
        _tab = 0;
      });
      _cargar();
    } else {
      _mensaje(_errorServidor('Error al procesar la solicitud'), color: Colors.redAccent);
    }
  }

  Future<void> _reenviarInvitacion(Map<String, dynamic> u) async {
    setState(() => _cargando = true);
    final exito = await AuthService.reenviarInvitacion(
        (u['correo'] ?? '').toString());
    if (!mounted) return;
    setState(() => _cargando = false);

    if (exito) {
      final aviso = AuthService.ultimoMensaje;
      final fallaCorreo = aviso.toLowerCase().contains('no se pudo enviar');
      _mensaje(
        fallaCorreo ? aviso : 'Invitación reenviada con un código nuevo',
        color: fallaCorreo ? const Color(0xFFF59E0B) : Colors.green,
        segundos: fallaCorreo ? 8 : 4,
      );
    } else {
      _mensaje(_errorServidor('No se pudo reenviar la invitación'),
          color: Colors.redAccent);
    }
  }

  Future<bool> _confirmar(String titulo, String cuerpo, String accion) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Text(cuerpo,
            style: const TextStyle(fontSize: 15, color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF4B5563), fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(accion,
                style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _eliminarUsuario(Map<String, dynamic> u) async {
    final nombre = (u['nombre'] ?? '').toString();
    final ok = await _confirmar(
      'Eliminar usuario',
      '¿Seguro que deseas eliminar a $nombre? Esta acción no se puede deshacer.',
      'Eliminar',
    );
    if (!ok) return;

    setState(() => _cargando = true);
    final exito =
        await AuthService.eliminarUsuario((u['correo'] ?? '').toString());
    if (!mounted) return;

    if (exito) {
      _mensaje('Usuario $nombre eliminado');
      _cargar();
    } else {
      setState(() => _cargando = false);
      _mensaje(_errorServidor('No se pudo eliminar el usuario'),
          color: Colors.redAccent);
    }
  }

  List<Map<String, String>> _opcionesUsuarios() {
    return _usuarios
        .map((u) => {
              'nombre': (u['nombre'] ?? '').toString(),
              'correo': (u['correo'] ?? '').toString(),
            })
        .where((u) => u['correo']!.isNotEmpty)
        .toList();
  }

  Future<InventoryModel?> _dialogoInventario({InventoryModel? inicial}) async {
    final datos = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _InventarioDialog(
        inicial: inicial,
        usuarios: _opcionesUsuarios(),
      ),
    );
    if (datos == null) return null;

    setState(() => _cargando = true);

    if (inicial == null) {
      final nuevo = await AuthService.crearInventario(
        nombre: datos['nombre'] ?? '',
        spreadsheet: datos['sheet'] ?? '',
        ubicacion: datos['ubicacion'] ?? '',
        responsableEmail: datos['responsable'] ?? '',
      );
      if (!mounted) return null;
      setState(() {
        _cargando = false;
        if (nuevo != null) _catalogo.add(nuevo);
      });
      _mensaje(
        nuevo != null
            ? 'Inventario ${nuevo.id} creado correctamente'
            : _errorServidor('No se pudo crear el inventario'),
        color: nuevo != null ? Colors.green : Colors.redAccent,
      );
      return nuevo;
    }

    final exito = await AuthService.actualizarInventario(
      idInventario: inicial.id,
      nombre: datos['nombre'] ?? '',
      responsableEmail: datos['responsable'] ?? '',
      ubicacion: datos['ubicacion'] ?? '',
    );
    if (!mounted) return null;

    if (exito) {
      _mensaje('Inventario actualizado');
      await _cargar();
    } else {
      setState(() => _cargando = false);
      _mensaje(_errorServidor('No se pudo actualizar el inventario'),
          color: Colors.redAccent);
    }
    return null;
  }

  Future<void> _crearInventarioDesdeFormulario() async {
    final nuevo = await _dialogoInventario();
    if (nuevo != null && mounted) {
      setState(() => _seleccionados.add(nuevo.id));
    }
  }

  Future<void> _eliminarInventario(InventoryModel inv) async {
    final ok = await _confirmar(
      'Eliminar inventario',
      '¿Eliminar "${inv.nombre}"? Se quitará de la lista y de todos los usuarios que lo tengan asignado. Los datos del Google Sheet no se borran.',
      'Eliminar',
    );
    if (!ok) return;

    setState(() => _cargando = true);
    final exito = await AuthService.eliminarInventario(inv.id);
    if (!mounted) return;

    if (exito) {
      _seleccionados.remove(inv.id);
      _mensaje('Inventario eliminado');
      _cargar();
    } else {
      setState(() => _cargando = false);
      _mensaje(_errorServidor('No se pudo eliminar el inventario'),
          color: Colors.redAccent);
    }
  }

  Future<void> _cerrarSesion() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _mostrarOpcionesUsuario(Map<String, dynamic> u) {
    final correo = (u['correo'] ?? '').toString().trim().toLowerCase();
    final nombre = (u['nombre'] ?? '').toString();
    final status = (u['status'] ?? 'Activo').toString();
    final esYo = correo == _miCorreo;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF2F2F7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D1D6),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Gestión de Usuario',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Selecciona una acción para $nombre',
                  style: const TextStyle(color: Color(0xFF3C3C43), fontSize: 16),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _opcionIos(
                        icono: Icons.edit_outlined,
                        color: const Color(0xFF007AFF),
                        texto: 'Editar información',
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _prepararEdicion(u);
                        },
                      ),
                      if (status == 'Invitado') ...[
                        const Divider(
                            height: 1,
                            thickness: 1,
                            indent: 48,
                            color: Color(0xFFE5E5EA)),
                        _opcionIos(
                          icono: Icons.forward_to_inbox_outlined,
                          color: const Color(0xFFF59E0B),
                          texto: 'Reenviar invitación',
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            _reenviarInvitacion(u);
                          },
                        ),
                      ],
                      if (!esYo) ...[
                        const Divider(
                            height: 1,
                            thickness: 1,
                            indent: 48,
                            color: Color(0xFFE5E5EA)),
                        _opcionIos(
                          icono: Icons.delete_outline_rounded,
                          color: const Color(0xFFFF3B30),
                          texto: 'Eliminar usuario',
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            _eliminarUsuario(u);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => Navigator.pop(sheetCtx),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          fontSize: 17,
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _opcionIos({
    required IconData icono,
    required Color color,
    required String texto,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icono, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(texto,
                  style: const TextStyle(fontSize: 17, color: Colors.black)),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFC7C7CC), size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String titulo;
    if (_tab == 0) {
      titulo = 'Gestión de Usuarios';
    } else if (_tab == 1) {
      titulo = _modoEdicion ? 'Editar Usuario' : 'Invitar Usuario';
    } else {
      titulo = 'Inventarios';
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Color(0xFF111827), size: 24),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          titulo,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827)),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: primaryPurple),
                        onPressed: _cargando ? null : _cargar,
                      ),
                      PopupMenuButton<String>(
                        offset: const Offset(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        icon: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD1D5DB),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.person,
                                color: Color(0xFF4B5563), size: 24),
                          ),
                        ),
                        onSelected: (v) {
                          if (v == 'logout') _cerrarSesion();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem<String>(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout,
                                    color: Color(0xFFDC2626), size: 20),
                                SizedBox(width: 12),
                                Text(
                                  'Cerrar sesión',
                                  style: TextStyle(
                                    color: Color(0xFFDC2626),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9EDF2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _tabBoton('Usuarios (${_usuarios.length})', 0, () {
                          setState(() {
                            _tab = 0;
                            _limpiarFormulario();
                          });
                        }),
                        _tabBoton(_modoEdicion ? 'Editar' : 'Invitar', 1, () {
                          setState(() {
                            if (_tab == 0) _limpiarFormulario();
                            _tab = 1;
                          });
                        }),
                        _tabBoton('Inventarios (${_catalogo.length})', 2, () {
                          setState(() {
                            _tab = 2;
                            _limpiarFormulario();
                          });
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _tab == 0
                      ? _vistaUsuarios()
                      : (_tab == 1 ? _vistaFormulario() : _vistaInventarios()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabBoton(String label, int index, VoidCallback onTap) {
    final seleccionado = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: seleccionado ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: seleccionado
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05), blurRadius: 4)
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: seleccionado ? primaryPurple : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniChip(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: lightPurpleBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: primaryPurple),
      ),
    );
  }

  Widget _badgeEstado(String status) {
    Color fondo;
    Color texto;
    switch (status) {
      case 'Invitado':
        fondo = const Color(0xFFFEF3C7);
        texto = const Color(0xFFB45309);
        break;
      case 'Inactivo':
        fondo = const Color(0xFFF3F4F6);
        texto = const Color(0xFF6B7280);
        break;
      default:
        fondo = const Color(0xFFDCFCE7);
        texto = const Color(0xFF15803D);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: texto),
      ),
    );
  }

  Widget _vistaUsuarios() {
    final query = _busquedaCtrl.text.toLowerCase().trim();
    final lista = _usuarios.where((u) {
      final nombre = (u['nombre'] ?? '').toString().toLowerCase();
      final correo = (u['correo'] ?? '').toString().toLowerCase();
      return nombre.contains(query) || correo.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE9EDF2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _busquedaCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o correo...',
                hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.black38),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: primaryPurple))
              : lista.isEmpty
                  ? const Center(
                      child: Text('No hay usuarios registrados',
                          style: TextStyle(color: Colors.black45, fontSize: 14)),
                    )
                  : RefreshIndicator(
                      color: primaryPurple,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24.0, vertical: 8.0),
                        itemCount: lista.length,
                        itemBuilder: (_, i) => _tarjetaUsuario(lista[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _tarjetaUsuario(Map<String, dynamic> u) {
    final listaInv = _separar(u['inventarios']);
    final rol = _rolCanonico((u['puesto'] ?? '').toString()) ??
        (u['puesto'] ?? '').toString();
    final status = (u['status'] ?? 'Activo').toString();
    final esYo = (u['correo'] ?? '').toString().trim().toLowerCase() == _miCorreo;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _mostrarOpcionesUsuario(u),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  (u['nombre'] ?? '').toString(),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF111827)),
                                ),
                              ),
                              if (esYo) ...[
                                const SizedBox(width: 6),
                                const Text('(tú)',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9CA3AF))),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (u['correo'] ?? '').toString(),
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.more_vert, color: Colors.grey, size: 22),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _miniChip(_rolVisible(rol)),
                    const SizedBox(width: 8),
                    _badgeEstado(status),
                  ],
                ),
                if (listaInv.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('INVENTARIOS',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.black38)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            ...listaInv.take(2).map((id) => _miniChip(_etiqueta(id))),
                            if (listaInv.length > 2)
                              _miniChip('+${listaInv.length - 2}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _vistaFormulario() {
    final opciones =
        _catalogo.where((inv) => !_seleccionados.contains(inv.id)).toList();
    final esAdminRol = _rolSeleccionado == 'Administrador';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_modoEdicion)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: Color(0xFF2563EB), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Se enviará un código de 6 dígitos al correo indicado. La persona elegirá su propia contraseña desde la app con "Tengo una invitación". El código vence en 24 horas.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1E40AF),
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                _etiquetaCampo('NOMBRE COMPLETO'),
                _campoTexto(_nombreCtrl, 'Ej. Carlos Mendoza',
                    msg: 'Ingresa el nombre completo'),
                const SizedBox(height: 16),
                _etiquetaCampo('CORREO ELECTRÓNICO'),
                _campoTexto(
                  _correoCtrl,
                  'ejemplo@autlan.com.mx',
                  teclado: TextInputType.emailAddress,
                  msg: 'Ingresa un correo electrónico',
                  esCorreo: true,
                  soloLectura: _modoEdicion,
                ),
                const SizedBox(height: 16),
                _etiquetaCampo('ROL'),
                _dropdownRol(),
                const SizedBox(height: 8),
                Text(
                  _descripcionRol(_rolSeleccionado),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280), height: 1.4),
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFFE5E7EB)),
                const SizedBox(height: 12),
                const Text(
                  'INVENTARIOS ASIGNADOS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryPurple,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  esAdminRol
                      ? 'El Administrador tiene acceso a todos los inventarios'
                      : 'Selecciona uno o más espacios de trabajo',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
                const SizedBox(height: 10),
                if (!esAdminRol) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('inv_${_seleccionados.length}_${_catalogo.length}'),
                    initialValue: null,
                    isExpanded: true,
                    hint: const Text('Seleccionar inventario...',
                        style: TextStyle(color: Colors.black38, fontSize: 14)),
                    items: opciones
                        .map((inv) => DropdownMenuItem<String>(
                              value: inv.id,
                              child: Text(inv.nombre,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14)),
                            ))
                        .toList(),
                    onChanged: opciones.isEmpty
                        ? null
                        : (val) {
                            if (val != null && !_seleccionados.contains(val)) {
                              setState(() => _seleccionados.add(val));
                            }
                          },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: primaryPurple, width: 1.2),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: primaryPurple, width: 1.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _seleccionados.map((id) {
                      return Chip(
                        label: Text(
                          _etiqueta(id),
                          style: const TextStyle(
                            color: primaryPurple,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        backgroundColor: lightPurpleBg,
                        deleteIcon: const Icon(Icons.close,
                            size: 14, color: primaryPurple),
                        onDeleted: () =>
                            setState(() => _seleccionados.remove(id)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: Color(0xFFD9C8EA)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.add_circle,
                            color: Color(0xFF16A34A), size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '¿Necesitas un inventario que aún no existe?',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF166534)),
                          ),
                        ),
                        GestureDetector(
                          onTap: _guardando || _cargando
                              ? null
                              : _crearInventarioDesdeFormulario,
                          child: const Text(
                            'Toca aquí',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Opacity(
                  opacity: _guardando ? 0.7 : 1,
                  child: Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF6B3F96), Color(0xFF4A2574)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _guardando ? null : _guardarUsuario,
                        child: Container(
                          height: 52,
                          alignment: Alignment.center,
                          child: _guardando
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  _modoEdicion
                                      ? 'Guardar Cambios'
                                      : 'Enviar Invitación',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_modoEdicion) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      setState(() {
                        _limpiarFormulario();
                        _tab = 0;
                      });
                    },
                    child: const Text(
                      'Cancelar Edición',
                      style: TextStyle(
                          color: Color(0xFF4B5563),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _descripcionRol(String? rol) {
    switch (rol) {
      case 'Administrador':
        return 'Acceso total: usuarios, inventarios y aprobación de solicitudes.';
      case 'Jefe de Area':
        return 'Alta, edición y baja directa, solo en sus inventarios asignados.';
      case 'Residente':
        return 'Puede proponer cambios en sus inventarios, pero el responsable del inventario debe aprobarlos.';
      case 'Consultor':
        return 'Solo consulta y exporta reportes. No puede modificar nada.';
      default:
        return 'Elige el nivel de acceso de la persona.';
    }
  }

  Widget _vistaInventarios() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _cargando ? null : () => _dialogoInventario(),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Nuevo inventario',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: primaryPurple))
              : _catalogo.isEmpty
                  ? const Center(
                      child: Text('No hay inventarios registrados',
                          style: TextStyle(color: Colors.black45, fontSize: 14)),
                    )
                  : RefreshIndicator(
                      color: primaryPurple,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24.0, vertical: 8.0),
                        itemCount: _catalogo.length,
                        itemBuilder: (_, i) => _tarjetaInventario(_catalogo[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _tarjetaInventario(InventoryModel inv) {
    final asignados = _usuarios
        .where((u) => _separar(u['inventarios']).contains(inv.id))
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: lightPurpleBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.warehouse_rounded,
                color: primaryPurple, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inv.nombre,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${inv.id}${inv.ubicacion.isNotEmpty ? '  ·  ${inv.ubicacion}' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined,
                        size: 14, color: Color(0xFF6B7280)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        inv.responsableEmail.isEmpty
                            ? 'Sin responsable asignado'
                            : inv.responsableEmail,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: inv.responsableEmail.isEmpty
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF374151),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$asignados ${asignados == 1 ? 'usuario' : 'usuarios'} con acceso',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            onSelected: (v) {
              if (v == 'editar') _dialogoInventario(inicial: inv);
              if (v == 'eliminar') _eliminarInventario(inv);
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'editar',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined,
                        size: 20, color: Color(0xFF007AFF)),
                    SizedBox(width: 12),
                    Text('Editar'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'eliminar',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 20, color: Color(0xFFFF3B30)),
                    SizedBox(width: 12),
                    Text('Eliminar',
                        style: TextStyle(color: Color(0xFFFF3B30))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _etiquetaCampo(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF374151),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _campoTexto(
    TextEditingController controller,
    String hint, {
    TextInputType teclado = TextInputType.text,
    String? msg,
    bool soloLectura = false,
    bool esCorreo = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: teclado,
      readOnly: soloLectura,
      validator: (val) {
        final t = (val ?? '').trim();
        if (msg != null && t.isEmpty) return msg;
        if (esCorreo &&
            !RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(t)) {
          return 'Ingresa un formato de correo válido';
        }
        return null;
      },
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black26, fontSize: 14),
        filled: true,
        fillColor: soloLectura ? const Color(0xFFE5E7EB) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryPurple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }

  Widget _dropdownRol() {
    return DropdownButtonFormField<String>(
      key: ValueKey('rol_${_rolSeleccionado ?? 'x'}_$_modoEdicion'),
      initialValue: _rolSeleccionado,
      isExpanded: true,
      hint: const Text('Seleccionar rol...',
          style: TextStyle(color: Colors.black26, fontSize: 14)),
      items: _roles
          .map((r) => DropdownMenuItem<String>(
                value: r,
                child: Text(_rolVisible(r), style: const TextStyle(fontSize: 14)),
              ))
          .toList(),
      onChanged: (val) => setState(() => _rolSeleccionado = val),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryPurple, width: 1.5),
        ),
      ),
    );
  }
}

class _InventarioDialog extends StatefulWidget {
  final InventoryModel? inicial;
  final List<Map<String, String>> usuarios;

  const _InventarioDialog({this.inicial, required this.usuarios});

  @override
  State<_InventarioDialog> createState() => _InventarioDialogState();
}

class _InventarioDialogState extends State<_InventarioDialog> {
  static const primaryPurple = Color(0xFF4A2574);

  late final TextEditingController _nombre;
  late final TextEditingController _sheet;
  late final TextEditingController _ubicacion;
  String? _responsable;
  String? _error;

  bool get _esEdicion => widget.inicial != null;

  @override
  void initState() {
    super.initState();
    final i = widget.inicial;
    _nombre = TextEditingController(text: i?.nombre ?? '');
    _sheet = TextEditingController(text: i?.spreadsheetId ?? '');
    _ubicacion = TextEditingController(text: i?.ubicacion ?? '');
    final actual = i?.responsableEmail.trim().toLowerCase() ?? '';
    _responsable = actual.isEmpty ? null : actual;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _sheet.dispose();
    _ubicacion.dispose();
    super.dispose();
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryPurple, width: 1.5),
      ),
    );
  }

  List<DropdownMenuItem<String>> _itemsResponsable() {
    final items = <DropdownMenuItem<String>>[];
    final vistos = <String>{};

    for (final u in widget.usuarios) {
      final correo = u['correo']!.trim().toLowerCase();
      if (!vistos.add(correo)) continue;
      final nombre = u['nombre']!;
      items.add(DropdownMenuItem<String>(
        value: correo,
        child: Text(
          nombre.isEmpty ? correo : '$nombre  ·  $correo',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ));
    }

    if (_responsable != null && !vistos.contains(_responsable)) {
      items.add(DropdownMenuItem<String>(
        value: _responsable,
        child: Text(_responsable!,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13)),
      ));
    }
    return items;
  }

  void _guardar() {
    if (_nombre.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es obligatorio');
      return;
    }
    if (!_esEdicion && _sheet.text.trim().isEmpty) {
      setState(() => _error = 'El ID o URL del Google Sheet es obligatorio');
      return;
    }
    if (_responsable == null || _responsable!.isEmpty) {
      setState(() => _error = 'Selecciona al responsable del inventario');
      return;
    }

    Navigator.pop(context, {
      'nombre': _nombre.text.trim(),
      'sheet': _sheet.text.trim(),
      'ubicacion': _ubicacion.text.trim(),
      'responsable': _responsable!,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(_esEdicion ? 'Editar inventario' : 'Nuevo inventario',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nombre,
                decoration: _decoracion('Nombre'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _sheet,
                enabled: !_esEdicion,
                decoration: _decoracion('ID o URL del Google Sheet'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ubicacion,
                decoration: _decoracion('Ubicación física'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _responsable,
                isExpanded: true,
                items: _itemsResponsable(),
                onChanged: (v) => setState(() => _responsable = v),
                decoration: _decoracion('Responsable (aprueba cambios)'),
              ),
              if (widget.usuarios.isEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Aún no hay usuarios registrados para elegir como responsable.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: Color(0xFF4B5563))),
        ),
        TextButton(
          onPressed: _guardar,
          child: Text(_esEdicion ? 'Guardar' : 'Crear',
              style: const TextStyle(
                  color: primaryPurple, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}