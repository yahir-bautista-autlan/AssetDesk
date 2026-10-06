import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'inventory_selection_screen.dart';
import 'admin_management_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _correoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  
  bool _isLoading = false;
  bool _obscureText = true;

  @override
  void dispose() {
    _correoCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    final success = await AuthService.login(
      _correoCtrl.text.trim(), 
      _passCtrl.text.trim()
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      final user = await AuthService.obtenerUsuarioActual();
      if (user != null) {
        if (user.esAdmin) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminManagementScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => InventorySelectionScreen(
                inventariosVinculados: user.inventarios,
              ),
            ),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.ultimoError.isNotEmpty 
            ? AuthService.ultimoError 
            : 'Error al iniciar sesión'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryPurple = Color(0xFF532E7C);
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.warehouse_rounded,
                      size: 80,
                      color: primaryPurple,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Bienvenido de nuevo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ingresa tus credenciales para acceder',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                    const SizedBox(height: 48),
                    
                    TextFormField(
                      controller: _correoCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Correo Electrónico',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryPurple, width: 2),
                        ),
                      ),
                      validator: (val) => val!.isEmpty ? 'Ingresa tu correo' : null,
                    ),
                    const SizedBox(height: 20),
                    
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscureText,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscureText = !_obscureText),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryPurple, width: 2),
                        ),
                      ),
                      validator: (val) => val!.isEmpty ? 'Ingresa tu contraseña' : null,
                    ),
                    const SizedBox(height: 40),
                    
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'Ingresar',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
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