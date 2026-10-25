import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'inventory_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const primaryPurple = Color(0xFF4A2574);

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _mostrarMensaje(String texto, {Color color = Colors.redAccent, int segundos = 6}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: color,
        duration: Duration(seconds: segundos),
      ),
    );
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _mostrarMensaje('Por favor completa todos los campos');
      return;
    }

    setState(() => _isLoading = true);

    final success = await AuthService.login(email, password);

    if (!mounted) return;

    if (!success) {
      setState(() => _isLoading = false);
      _mostrarMensaje(
        AuthService.ultimoError.isEmpty
            ? 'Correo o contraseña incorrectos'
            : AuthService.ultimoError,
        segundos: 8,
      );
      return;
    }

    final user = await AuthService.obtenerUsuarioActual();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user == null) {
      _mostrarMensaje('No se pudo cargar tu sesión. Intenta de nuevo.');
      return;
    }

    TextInput.finishAutofillContext();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => InventorySelectionScreen(
          inventariosVinculados: user.inventarios,
        ),
      ),
    );
  }

  Future<void> _abrirInvitacion() async {
    final correoActivado = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _InvitacionScreen(
          correoInicial: _emailController.text.trim(),
        ),
      ),
    );

    if (correoActivado != null && mounted) {
      setState(() {
        _emailController.text = correoActivado;
        _passwordController.clear();
      });
      _mostrarMensaje(
        'Cuenta activada. Ya puedes iniciar sesión con tu nueva contraseña.',
        color: Colors.green,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.9, -1.0),
            radius: 1.2,
            colors: [Color(0xFFF1EAF7), Colors.white],
          ),
        ),
        child: SafeArea(
          child: _AjusteSinScroll(
            maxWidth: 420,
            padding: 28,
            child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          width: 300,
                          height: 220,
                          child: Image.asset(
                            'assets/logo_autlan.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.change_history_rounded,
                                      size: 100, color: primaryPurple),
                                  SizedBox(height: 8),
                                  Text(
                                    'AUTLAN',
                                    style: TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF2F4858),
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF0F0F3)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [
                                AutofillHints.email,
                                AutofillHints.username
                              ],
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'Ingresa tu correo',
                                hintStyle: TextStyle(
                                    color: Color(0xFF9CA3AF), fontSize: 14),
                                prefixIcon: Icon(Icons.mail_outline_rounded,
                                    color: primaryPurple, size: 18),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 18, horizontal: 12),
                              ),
                            ),
                            const Divider(
                                height: 1,
                                thickness: 1,
                                color: Color(0xFFF0F0F3)),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              enableSuggestions: false,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.password],
                              style: const TextStyle(fontSize: 14),
                              onSubmitted: (_) {
                                if (!_isLoading) _handleLogin();
                              },
                              decoration: InputDecoration(
                                hintText: 'Contraseña',
                                hintStyle: const TextStyle(
                                    color: Color(0xFF9CA3AF), fontSize: 14),
                                prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: primaryPurple,
                                    size: 18),
                                suffixIcon: ExcludeFocus(child: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF6B7280),
                                    size: 18,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                )),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 18, horizontal: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      ExcludeFocus(
                        child: Opacity(
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
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryPurple.withOpacity(0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: _isLoading ? null : _handleLogin,
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5),
                                      )
                                    : const Text(
                                        'Iniciar Sesión',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: ExcludeFocus(
                          child: TextButton.icon(
                          onPressed: _isLoading ? null : _abrirInvitacion,
                          icon: const Icon(Icons.mark_email_read_outlined,
                              size: 18, color: primaryPurple),
                          label: const Text(
                            'Tengo una invitación',
                            style: TextStyle(
                              color: primaryPurple,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

class _AjusteSinScroll extends StatefulWidget {
  final Widget child;
  final double maxWidth;
  final double padding;

  const _AjusteSinScroll({
    required this.child,
    required this.maxWidth,
    this.padding = 20,
  });

  @override
  State<_AjusteSinScroll> createState() => _AjusteSinScrollState();
}

class _AjusteSinScrollState extends State<_AjusteSinScroll> {
  double _anchoBase = 0;
  double _altoBase = 0;

  @override
  Widget build(BuildContext context) {
    final insetTeclado = MediaQuery.of(context).viewInsets.bottom > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        if ((constraints.maxWidth - _anchoBase).abs() > 1) {
          _anchoBase = constraints.maxWidth;
          _altoBase = constraints.maxHeight;
        } else if (constraints.maxHeight > _altoBase) {
          _altoBase = constraints.maxHeight;
        }

        final tecladoVisible =
            insetTeclado || constraints.maxHeight < _altoBase * 0.82;

        final padding = widget.padding;
        final disponible = constraints.maxWidth - padding * 2;
        final ancho = disponible < widget.maxWidth ? disponible : widget.maxWidth;
        final contenido = SizedBox(width: ancho, child: widget.child);

        if (tecladoVisible) {
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
            child: Center(child: contenido),
          );
        }

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: contenido,
            ),
          ),
        );
      },
    );
  }
}

class _InvitacionScreen extends StatefulWidget {
  final String correoInicial;

  const _InvitacionScreen({this.correoInicial = ''});

  @override
  State<_InvitacionScreen> createState() => _InvitacionScreenState();
}

class _InvitacionScreenState extends State<_InvitacionScreen> {
  static const primaryPurple = Color(0xFF4A2574);
  static const _titulo = Color(0xFF1E1B4B);
  static const _texto = Color(0xFF6B7280);
  static const _bordeCampo = Color(0xFFE3DEEE);
  static const _fondoSeccion = Color(0xFFFAF8FD);
  static const _fondoIcono = Color(0xFFEDE7F6);
  static const _verde = Color(0xFF16A34A);

  final _formVerificacion = GlobalKey<FormState>();
  final _formSeguridad = GlobalKey<FormState>();
  late final TextEditingController _correoCtrl;
  final _codigoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  int _paso = 1;
  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  static final _regexCorreo = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$');

  @override
  void initState() {
    super.initState();
    _correoCtrl = TextEditingController(text: widget.correoInicial);
    _passCtrl.addListener(_actualizar);
    _confirmCtrl.addListener(_actualizar);
  }

  void _actualizar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _correoCtrl.dispose();
    _codigoCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String get _nombrePaso {
    switch (_paso) {
      case 1:
        return 'VERIFICACIÓN';
      default:
        return 'SEGURIDAD';
    }
  }

  String get _subtituloPaso {
    switch (_paso) {
      case 1:
        return 'Ingresa tu correo y el código de 6 dígitos que recibiste en tu invitación. El código es válido por 24 horas.';
      default:
        return 'Elige la contraseña con la que vas a entrar a AssetDesk.';
    }
  }

  int _fuerzaPassword(String p) {
    var puntos = 0;
    if (p.length >= 8) puntos++;
    if (p.length >= 12) puntos++;
    if (RegExp(r'[A-Za-z]').hasMatch(p) && RegExp(r'\d').hasMatch(p)) puntos++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) puntos++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) puntos++;
    return puntos;
  }

  String? _validarPassword(String? v) {
    final p = v ?? '';
    if (p.isEmpty) return 'Elige una contraseña';
    if (p.length < 8) return 'Mínimo 8 caracteres';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
      return 'Debe incluir al menos una letra y un número';
    }
    return null;
  }

  void _irAPaso(int paso) {
    FocusScope.of(context).unfocus();
    setState(() {
      _paso = paso;
      _error = null;
    });
  }

  void _continuar() {
    if (_formVerificacion.currentState!.validate()) _irAPaso(2);
  }

  void _atras() {
    if (_isLoading) return;
    if (_paso > 1) {
      _irAPaso(_paso - 1);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _activar() async {
    if (!_formSeguridad.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final correo = _correoCtrl.text.trim().toLowerCase();
    final exito = await AuthService.completarInvitacion(
      correo: correo,
      codigo: _codigoCtrl.text.trim(),
      nuevaPassword: _passCtrl.text,
    );

    if (!mounted) return;

    if (exito) {
      TextInput.finishAutofillContext();
      Navigator.pop(context, correo);
      return;
    }

    final mensaje = AuthService.ultimoError.isEmpty
        ? 'No se pudo activar la cuenta'
        : AuthService.ultimoError;
    final bajo = mensaje.toLowerCase();
    final esDelCodigo = bajo.contains('código') ||
        bajo.contains('codigo') ||
        bajo.contains('venci') ||
        bajo.contains('invitaci');

    setState(() {
      _isLoading = false;
      _error = mensaje;
      if (esDelCodigo) _paso = 1;
    });
  }

  OutlineInputBorder _borde(Color color, [double ancho = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: ancho),
    );
  }

  InputDecoration _decoracion(String hint, IconData icono, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      prefixIcon: Icon(icono, size: 20, color: const Color(0xFF6B5B8C)),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: _borde(_bordeCampo),
      border: _borde(_bordeCampo),
      focusedBorder: _borde(primaryPurple, 1.6),
      errorBorder: _borde(Colors.redAccent),
      focusedErrorBorder: _borde(Colors.redAccent, 1.6),
    );
  }

  Widget _etiqueta(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: _titulo,
        ),
      ),
    );
  }

  Widget _encabezadoSeccion(IconData icono, String titulo, String detalle) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: _fondoIcono,
            shape: BoxShape.circle,
          ),
          child: Icon(icono, color: primaryPurple, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _titulo,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detalle,
                style: const TextStyle(fontSize: 12.5, color: _texto),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seccion(List<Widget> hijos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _fondoSeccion,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDE8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: hijos,
      ),
    );
  }

  Widget _barraProgreso() {
    Widget segmento(int n) {
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 4,
          margin: EdgeInsets.only(right: n < 2 ? 8 : 0),
          decoration: BoxDecoration(
            color: n <= _paso ? primaryPurple : const Color(0xFFD9CCEA),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [segmento(1), segmento(2)]),
        const SizedBox(height: 12),
        Text(
          'PASO $_paso DE 2  ·  $_nombrePaso',
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.6,
            color: Color(0xFF8B83A3),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _indicadorFuerza() {
    final p = _passCtrl.text;
    if (p.isEmpty) return const SizedBox.shrink();

    final fuerza = _fuerzaPassword(p);
    Color color;
    String texto;
    if (fuerza <= 2) {
      color = const Color(0xFFDC2626);
      texto = 'Débil';
    } else if (fuerza <= 3) {
      color = const Color(0xFFF59E0B);
      texto = 'Aceptable';
    } else {
      color = _verde;
      texto = 'Fuerte';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fuerza / 5,
                minHeight: 5,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            texto,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _requisito(bool cumple, String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            cumple ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: cumple ? _verde : const Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 8),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              color: cumple ? _verde : _texto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pasoVerificacion() {
    return Form(
      key: _formVerificacion,
      child: _seccion([
        _encabezadoSeccion(
          Icons.badge_outlined,
          'Verificación de identidad',
          'Confirma que tienes acceso a la invitación.',
        ),
        const SizedBox(height: 18),
        _etiqueta('Correo electrónico'),
        TextFormField(
          controller: _correoCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: true,
          autofillHints: const [AutofillHints.email, AutofillHints.username],
          decoration:
              _decoracion('Correo electrónico', Icons.mail_outline_rounded),
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return 'Ingresa tu correo';
            if (!_regexCorreo.hasMatch(t)) return 'Formato de correo no válido';
            return null;
          },
        ),
        const SizedBox(height: 16),
        _etiqueta('Código de invitación'),
        TextFormField(
          controller: _codigoCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onFieldSubmitted: (_) => _continuar(),
          decoration: _decoracion('Código de 6 dígitos', Icons.pin_outlined)
              .copyWith(counterText: ''),
          validator: (v) {
            if ((v ?? '').trim().length != 6) return 'El código tiene 6 dígitos';
            return null;
          },
        ),
      ]),
    );
  }

  Widget _pasoSeguridad() {
    final p = _passCtrl.text;
    final tieneLongitud = p.length >= 8;
    final tieneLetraNumero =
        RegExp(r'[A-Za-z]').hasMatch(p) && RegExp(r'\d').hasMatch(p);
    final coincide = p.isNotEmpty && _confirmCtrl.text == p;

    return Form(
      key: _formSeguridad,
      child: _seccion([
        _encabezadoSeccion(
          Icons.lock_outline_rounded,
          'Configuración de seguridad',
          'Establece y confirma tu contraseña.',
        ),
        const SizedBox(height: 18),
        _etiqueta('Nueva contraseña'),
        TextFormField(
          controller: _passCtrl,
          obscureText: _obscurePass,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          decoration: _decoracion(
            'Nueva contraseña',
            Icons.lock_outline_rounded,
            suffix: ExcludeFocus(child: IconButton(
              icon: Icon(
                _obscurePass
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: const Color(0xFF6B5B8C),
              ),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            )),
          ),
          validator: _validarPassword,
        ),
        _indicadorFuerza(),
        const SizedBox(height: 16),
        _etiqueta('Confirmar contraseña'),
        TextFormField(
          controller: _confirmCtrl,
          obscureText: _obscureConfirm,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onFieldSubmitted: (_) {
            if (!_isLoading) _activar();
          },
          decoration: _decoracion(
            'Confirmar contraseña',
            Icons.verified_user_outlined,
            suffix: ExcludeFocus(child: IconButton(
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: const Color(0xFF6B5B8C),
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            )),
          ),
          validator: (v) {
            if ((v ?? '').isEmpty) return 'Confirma tu contraseña';
            if (v != _passCtrl.text) return 'Las contraseñas no coinciden';
            return null;
          },
        ),
        const SizedBox(height: 10),
        _requisito(tieneLongitud, 'Mínimo 8 caracteres'),
        _requisito(tieneLetraNumero, 'Al menos una letra y un número'),
        _requisito(coincide, 'Las contraseñas coinciden'),
      ]),
    );
  }

  Widget _botonPrincipal() {
    final esUltimo = _paso == 2;
    return ExcludeFocus(
      child: Opacity(
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
            boxShadow: [
              BoxShadow(
                color: primaryPurple.withOpacity(0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _isLoading ? null : (esUltimo ? _activar : _continuar),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      esUltimo ? 'Activar cuenta' : 'Continuar',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget contenido = _paso == 1
        ? KeyedSubtree(key: const ValueKey(1), child: _pasoVerificacion())
        : KeyedSubtree(key: const ValueKey(2), child: _pasoSeguridad());

    return PopScope(
      canPop: _paso == 1 && !_isLoading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _atras();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF1EAF9), Color(0xFFF8F5FC), Colors.white],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: ExcludeFocus(
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: primaryPurple),
                        onPressed: _isLoading ? null : _atras,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _AjusteSinScroll(
                    maxWidth: 520,
                    child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: _fondoIcono,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryPurple.withOpacity(0.12),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                    Icons.mark_email_read_outlined,
                                    color: primaryPurple,
                                    size: 30),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Activa tu cuenta',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: _titulo,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                _subtituloPaso,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    color: _texto,
                                    height: 1.45),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 28),
                              child: _barraProgreso(),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(26),
                                border:
                                    Border.all(color: const Color(0xFFF0ECF6)),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryPurple.withOpacity(0.07),
                                    blurRadius: 28,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AutofillGroup(
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      child: contenido,
                                    ),
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: const Color(0xFFFECACA)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.error_outline,
                                              color: Color(0xFFDC2626),
                                              size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _error!,
                                              style: const TextStyle(
                                                  color: Color(0xFFB91C1C),
                                                  fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  _botonPrincipal(),
                                  if (_paso > 1) ...[
                                    const SizedBox(height: 6),
                                    ExcludeFocus(
                                      child: TextButton(
                                        onPressed: _isLoading ? null : _atras,
                                        child: const Text(
                                          'Atrás',
                                          style: TextStyle(
                                            color: primaryPurple,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                    ),
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