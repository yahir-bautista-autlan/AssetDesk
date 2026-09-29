import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/auth_service.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  static const primaryPurple = Color(0xFF4A2574);
  static const lightPurpleBg = Color(0xFFEDE4F5);
  static const backgroundColor = Color(0xFFF8F9FA);

  final List<String> _puestosDisponibles = [
    'Administrador',
    'Jefe de Area',
    'Residente',
  ];

  int _selectedTab = 0;
  final _searchController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _puestoSeleccionado;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _esModoEdicion = false;

  List<Map<String, dynamic>> _usuarios = [];
  List<InventoryModel> _catalogo = [];
  final List<String> _seleccionados = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nombreController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
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

  String _limpiarTexto(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  String? _puestoCanonico(String raw) {
    final buscado = _limpiarTexto(raw);
    for (final p in _puestosDisponibles) {
      if (_limpiarTexto(p) == buscado) return p;
    }
    return null;
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

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    try {
      // LLAMADA ÚNICA OPTIMIZADA: Evita múltiples requests y errores 404
      final resultado = await AuthService.obtenerDatosCompletos();
      if (!mounted) return;
      setState(() {
        _usuarios = resultado['usuarios'] as List<Map<String, dynamic>>;
        _catalogo = resultado['inventarios'] as List<InventoryModel>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _limpiarFormulario() {
    _nombreController.clear();
    _correoController.clear();
    _passwordController.clear();
    _puestoSeleccionado = null;
    _seleccionados.clear();
    _esModoEdicion = false;
  }

  void _prepararEdicion(Map<String, dynamic> usuario) {
    setState(() {
      _esModoEdicion = true;
      _nombreController.text = (usuario['nombre'] ?? '').toString();
      _correoController.text = (usuario['correo'] ?? '').toString();
      _passwordController.clear();
      _puestoSeleccionado =
          _puestoCanonico((usuario['puesto'] ?? '').toString()) ??
              _puestosDisponibles.first;
      _seleccionados
        ..clear()
        ..addAll(_separar(usuario['inventarios']));
      _selectedTab = 1;
    });
  }

  Future<void> _crearInventario() async {
    final datos = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _NuevoInventarioDialog(),
    );
    if (datos == null) return;

    setState(() => _isLoading = true);
    final nuevo = await AuthService.crearInventario(
      nombre: datos['nombre'] ?? '',
      spreadsheet: datos['sheet'] ?? '',
      ubicacion: datos['ubicacion'] ?? '',
    );
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (nuevo != null) {
        _catalogo.add(nuevo);
        _seleccionados.add(nuevo.id);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nuevo != null
            ? 'Inventario ${nuevo.id} creado y asignado'
            : (AuthService.ultimoError.isEmpty
                ? 'No se pudo crear el inventario'
                : AuthService.ultimoError)),
      ),
    );
  }

  Future<void> _guardarOActualizarUsuario() async {
    if (!_formKey.currentState!.validate()) return;

    if (_puestoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona un puesto')),
      );
      return;
    }

    final esPuestoAdmin = _puestoSeleccionado!.toLowerCase() == 'administrador';
    if (!esPuestoAdmin && _seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un inventario')),
      );
      return;
    }

    setState(() => _isLoading = true);

    bool exito;
    if (_esModoEdicion) {
      exito = await AuthService.actualizarUsuarioAdmin(
        correo: _correoController.text.trim(),
        nombre: _nombreController.text.trim(),
        puesto: _puestoSeleccionado ?? '',
        inventarios: List<String>.from(_seleccionados),
      );
    } else {
      exito = await AuthService.registrarUsuario(
        nombre: _nombreController.text.trim(),
        correo: _correoController.text.trim(),
       // password: _passwordController.text,
        puesto: _puestoSeleccionado ?? '',
        inventarios: List<String>.from(_seleccionados),
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (exito) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_esModoEdicion
              ? 'Usuario actualizado correctamente'
              : 'Usuario creado exitosamente'),
        ),
      );
      setState(() {
        _limpiarFormulario();
        _selectedTab = 0;
      });
      _cargarDatos();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.ultimoError.isEmpty
              ? 'Error al procesar la solicitud.'
              : AuthService.ultimoError),
        ),
      );
    }
  }

  Future<bool?> _mostrarConfirmacionEliminar(String nombre) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Eliminar Usuario',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar al usuario $nombre? Esta acción no se puede deshacer.',
          style: const TextStyle(fontSize: 15, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.blue, fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar',
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarUsuarioLocal(String correo, String nombre) async {
    setState(() => _isLoading = true);
    final exito = await AuthService.eliminarUsuario(correo);
    if (!mounted) return;

    if (exito) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Usuario $nombre eliminado correctamente'),
        ),
      );
      _cargarDatos();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.ultimoError.isEmpty
              ? 'Error al procesar la solicitud'
              : AuthService.ultimoError),
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  void _mostrarModalOpciones(Map<String, dynamic> usuario) {
    final correo = (usuario['correo'] ?? '').toString();
    final nombre = (usuario['nombre'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF2F2F7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
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
                  style: const TextStyle(
                    color: Color(0xFF3C3C43),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildIosOption(
                        icono: Icons.edit_outlined,
                        colorIcono: const Color(0xFF007AFF),
                        texto: 'Editar Información',
                        onTap: () {
                          Navigator.pop(context);
                          _prepararEdicion(usuario);
                        },
                      ),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 48,
                        color: Color(0xFFE5E5EA),
                      ),
                      _buildIosOption(
                        icono: Icons.delete_outline_rounded,
                        colorIcono: const Color(0xFFFF3B30),
                        texto: 'Eliminar Usuario',
                        onTap: () async {
                          Navigator.pop(context);
                          final confirmar =
                              await _mostrarConfirmacionEliminar(nombre);
                          if (confirmar == true) {
                            _eliminarUsuarioLocal(correo, nombre);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => Navigator.pop(context),
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

  Widget _buildIosOption({
    required IconData icono,
    required Color colorIcono,
    required String texto,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icono, color: colorIcono, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  fontSize: 17,
                  color: Colors.black,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFC7C7CC), size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase();
    final usuariosFiltrados = _usuarios.where((u) {
      final nombre = (u['nombre'] ?? '').toString().toLowerCase();
      final correo = (u['correo'] ?? '').toString().toLowerCase();
      return nombre.contains(query) || correo.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedTab == 0
                        ? 'Usuarios'
                        : (_esModoEdicion ? 'Editar Usuario' : 'Crear Usuario'),
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827)),
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
                    onSelected: (value) async {
                      if (value == 'logout') {
                        await AuthService.logout();
                        if (!context.mounted) return;
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/login',
                          (route) => false,
                        );
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
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
                    _tabBoton('Listado (${_usuarios.length})', 0, () {
                      setState(() {
                        _selectedTab = 0;
                        _limpiarFormulario();
                      });
                    }),
                    _tabBoton(
                        _esModoEdicion ? 'Editar Usuario' : 'Nuevo Usuario', 1,
                        () {
                      setState(() {
                        if (_selectedTab == 0) _limpiarFormulario();
                        _selectedTab = 1;
                      });
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _selectedTab == 0
                  ? _buildListadoView(usuariosFiltrados)
                  : _buildFormularioUsuarioView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBoton(String label, int index, VoidCallback onTap) {
    final seleccionado = _selectedTab == index;
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
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
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

  Widget _buildListadoView(List<Map<String, dynamic>> usuarios) {
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
              controller: _searchController,
              onChanged: (v) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar por usuario, correo...',
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
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: primaryPurple))
              : usuarios.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay usuarios registrados',
                        style: TextStyle(color: Colors.black45, fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 8.0),
                      itemCount: usuarios.length,
                      itemBuilder: (context, index) {
                        final u = usuarios[index];
                        final listaInv = _separar(u['inventarios']);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _mostrarModalOpciones(u),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFFE5E7EB)),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                (u['nombre'] ?? '').toString(),
                                                style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF111827)),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                (u['correo'] ?? '').toString(),
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Color(0xFF6B7280)),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            GestureDetector(
                                              onTap: () =>
                                                  _mostrarModalOpciones(u),
                                              child: const Icon(Icons.more_vert,
                                                  color: Colors.grey, size: 22),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF374151)),
                                        children: [
                                          const TextSpan(
                                              text: 'Puesto: ',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600)),
                                          TextSpan(
                                              text:
                                                  (u['puesto'] ?? '').toString(),
                                              style: const TextStyle(
                                                  color: primaryPurple,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
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
                                                ...listaInv.take(2).map(
                                                    (id) =>
                                                        _miniChip(_etiqueta(id))),
                                                if (listaInv.length > 2)
                                                  _miniChip(
                                                      '+${listaInv.length - 2}'),
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
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildFormularioUsuarioView() {
    final opciones =
        _catalogo.where((inv) => !_seleccionados.contains(inv.id)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFieldLabel('NOMBRE COMPLETO'),
            _buildTextField(_nombreController, 'Ej. Carlos Mendoza',
                validatorMsg: 'Ingresa el nombre'),
            const SizedBox(height: 16),
            _buildFieldLabel('CORREO ELECTRÓNICO'),
            _buildTextField(
              _correoController,
              'ejemplo@correo.com',
              keyboardType: TextInputType.emailAddress,
              validatorMsg: 'Ingresa el correo',
              readOnly: _esModoEdicion,
            ),
            const SizedBox(height: 16),
            if (!_esModoEdicion) ...[
              _buildFieldLabel('CONTRASEÑA'),
              _buildTextField(
                _passwordController,
                'Contraseña',
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.grey),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                validatorMsg: 'Ingresa la contraseña',
              ),
              const SizedBox(height: 16),
            ],
            _buildFieldLabel('PUESTO'),
            _buildDropdownPuesto(),
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
            const Text(
              'Selecciona uno o más espacios de trabajo',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 10),
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: primaryPurple, width: 1.2),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: primaryPurple, width: 1.2),
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
                  deleteIcon:
                      const Icon(Icons.close, size: 14, color: primaryPurple),
                  onDeleted: () {
                    setState(() => _seleccionados.remove(id));
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFFD9C8EA)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                      '¿Deseas agregar otro inventario?',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF166534)),
                    ),
                  ),
                  GestureDetector(
                    onTap: _isLoading ? null : _crearInventario,
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
            const SizedBox(height: 24),
            Opacity(
              opacity: _isLoading ? 0.7 : 1,
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
                    onTap: _isLoading ? null : _guardarOActualizarUsuario,
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _esModoEdicion
                                  ? 'Guardar Cambios'
                                  : 'Guardar Usuario',
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
            if (_esModoEdicion) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _limpiarFormulario();
                    _selectedTab = 0;
                  });
                },
                child: const Text(
                  'Cancelar Edición',
                  style: TextStyle(
                    color: Color(0xFF4B5563),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
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

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? validatorMsg,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      readOnly: readOnly,
      validator: (val) {
        if (validatorMsg != null && (val == null || val.trim().isEmpty)) {
          return validatorMsg;
        }
        return null;
      },
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black26, fontSize: 14),
        filled: true,
        fillColor: readOnly ? const Color(0xFFE5E7EB) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixIcon: suffixIcon,
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

  Widget _buildDropdownPuesto() {
    return DropdownButtonFormField<String>(
      initialValue: _puestoSeleccionado,
      isExpanded: true,
      hint: const Text('Seleccionar puesto...',
          style: TextStyle(color: Colors.black26, fontSize: 14)),
      items: _puestosDisponibles.map((puesto) {
        return DropdownMenuItem<String>(
          value: puesto,
          child: Text(puesto, style: const TextStyle(fontSize: 14)),
        );
      }).toList(),
      onChanged: (val) => setState(() => _puestoSeleccionado = val),
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

class _NuevoInventarioDialog extends StatefulWidget {
  const _NuevoInventarioDialog();

  @override
  State<_NuevoInventarioDialog> createState() => _NuevoInventarioDialogState();
}

class _NuevoInventarioDialogState extends State<_NuevoInventarioDialog> {
  static const primaryPurple = Color(0xFF4A2574);

  final _nombre = TextEditingController();
  final _sheet = TextEditingController();
  final _ubicacion = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _sheet.dispose();
    _ubicacion.dispose();
    super.dispose();
  }

  InputDecoration _decoracion(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryPurple, width: 1.5),
      ),
    );
  }

  void _guardar() {
    if (_nombre.text.trim().isEmpty || _sheet.text.trim().isEmpty) {
      setState(() => _error = 'El nombre y el Spreadsheet son obligatorios');
      return;
    }
    Navigator.pop(context, {
      'nombre': _nombre.text.trim(),
      'sheet': _sheet.text.trim(),
      'ubicacion': _ubicacion.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Nuevo inventario',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nombre,
              decoration: _decoracion('Nombre. Ej. Inventario Planta Tamos'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sheet,
              decoration: _decoracion('URL o ID del Google Sheet'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ubicacion,
              decoration: _decoracion('Ubicación. Ej. Tamos'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: Color(0xFF4B5563)),
            ),
        ),
        TextButton(
          onPressed: _guardar,
          child: const Text('Crear',
              style: TextStyle(
                  color: primaryPurple, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}