import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/auth_service.dart';
import 'inventory_dashboard_screen.dart';

class InventorySelectionScreen extends StatelessWidget {
  final List<InventoryModel> inventariosVinculados;

  const InventorySelectionScreen({
    super.key,
    required this.inventariosVinculados,
  });

  static const primaryPurple = Color(0xFF532E7C);

  @override
  Widget build(BuildContext context) {
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
                        icon: const Icon(
                          Icons.account_circle_outlined,
                          color: Colors.black,
                          size: 34,
                        ),
                        onSelected: (value) async {
                          if (value == 'admin') {
                            Navigator.pushNamed(context, '/admin');
                          } else if (value == 'logout') {
                            await AuthService.logout();
                            if (!context.mounted) return;
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              '/login',
                              (route) => false,
                            );
                          }
                        },
                        itemBuilder: (BuildContext context) {
                          final esAdmin = AuthService.esAdmin;
                          return <PopupMenuEntry<String>>[
                            if (esAdmin)
                              const PopupMenuItem<String>(
                                value: 'admin',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.manage_accounts_outlined,
                                      color: Colors.black87,
                                      size: 20,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Administrar cuentas',
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (esAdmin) const PopupMenuDivider(height: 1),
                            const PopupMenuItem<String>(
                              value: 'logout',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.logout,
                                    color: Color(0xFFB3261E),
                                    size: 20,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Cerrar sesión',
                                    style: TextStyle(
                                      color: Color(0xFFB3261E),
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ];
                        },
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
                    child: inventariosVinculados.isEmpty
                        ? const Center(
                            child: Text(
                              'No tienes inventarios asignados.',
                              style: TextStyle(
                                  color: Colors.black45, fontSize: 14),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              int crossAxisCount =
                                  constraints.maxWidth > 700 ? 2 : 1;

                              return GridView.builder(
                                padding: const EdgeInsets.only(
                                    top: 4, bottom: 16),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 24,
                                  mainAxisSpacing: 24,
                                  childAspectRatio:
                                      crossAxisCount == 2 ? 1.6 : 2.2,
                                ),
                                itemCount: inventariosVinculados.length,
                                itemBuilder: (context, index) {
                                  final inv = inventariosVinculados[index];
                                  return _buildInventoryCard(context, inv);
                                },
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