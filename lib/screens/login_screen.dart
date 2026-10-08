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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AutofillGroup(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF6B7280),
                                    size: 18,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 18, horizontal: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
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
                      const SizedBox(height: 16),
                      Center(
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
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _correoCtrl;
  final _codigoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _correoCtrl = TextEditingController(text: widget.correoInicial);
    _passCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _correoCtrl.dispose();
    _codigoCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
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

  Future<void> _activar() async {
    if (!_formKey.currentState!.validate()) return;

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
      Navigator.pop(context, correo);
    } else {
      setState(() {
        _isLoading = false;
        _error = AuthService.ultimoError.isEmpty
            ? 'No se pudo activar la cuenta'
            : AuthService.ultimoError;
      });
    }
  }

  InputDecoration _decoracion(String label, IconData icono, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icono, size: 20),
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryPurple, width: 2),
      ),
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
      color = const Color(0xFF16A34A);
      texto = 'Fuerte';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: primaryPurple),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFE8F6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mark_email_read_outlined,
                            color: primaryPurple, size: 34),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Activa tu cuenta',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ingresa el código de 6 dígitos que recibiste por correo y elige tu contraseña. El código es válido por 24 horas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _correoCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _decoracion(
                          'Correo electrónico', Icons.email_outlined),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Ingresa tu correo';
                        if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$')
                            .hasMatch(t)) {
                          return 'Formato de correo no válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _codigoCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _decoracion(
                              'Código de invitación', Icons.pin_outlined)
                          .copyWith(counterText: ''),
                      validator: (v) {
                        if ((v ?? '').trim().length != 6) {
                          return 'El código tiene 6 dígitos';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscurePass,
                      decoration: _decoracion(
                        'Nueva contraseña',
                        Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(_obscurePass
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                      validator: _validarPassword,
                    ),
                    _indicadorFuerza(),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscureConfirm,
                      decoration: _decoracion(
                        'Confirmar contraseña',
                        Icons.lock_reset_outlined,
                        suffix: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      onFieldSubmitted: (_) {
                        if (!_isLoading) _activar();
                      },
                      validator: (v) {
                        if ((v ?? '').isEmpty) return 'Confirma tu contraseña';
                        if (v != _passCtrl.text) {
                          return 'Las contraseñas no coinciden';
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    color: Color(0xFFB91C1C), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _isLoading ? null : _activar,
                            child: Container(
                              height: 52,
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
                                      'Activar cuenta',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
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