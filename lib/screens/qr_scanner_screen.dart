import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:universal_html/html.dart' as html;

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  static const primaryPurple = Color(0xFF532E7C);

  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  bool _isTorchOn = false;
  final TextEditingController _manualController = TextEditingController();

  @override
  void dispose() {
    _apagarCamaraWeb();
    controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  bool _cerrando = false;

  void _apagarCamaraWeb() {
    if (!kIsWeb) return;
    try {
      for (final el in html.document.querySelectorAll('video')) {
        final dynamic video = el;
        final dynamic flujo = video.srcObject;
        if (flujo != null) {
          for (final pista in (flujo.getTracks() as List)) {
            (pista as dynamic).stop();
          }
        }
        video.pause();
        video.srcObject = null;
      }
    } catch (_) {}
  }

  Future<void> _cerrar([String? valor]) async {
    if (_cerrando) return;
    _cerrando = true;
    if (mounted) setState(() => _isProcessing = true);
    _apagarCamaraWeb();
    try {
      await controller.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _apagarCamaraWeb();
    if (!mounted) return;
    Navigator.pop(context, valor);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      _cerrar(barcodes.first.rawValue!);
    }
  }

  void _buscarManual() {
    final texto = _manualController.text.trim();
    if (texto.isEmpty || _isProcessing) return;
    _cerrar(texto);
  }

  Widget _errorCamara(BuildContext context, MobileScannerException error) {
    return Container(
      color: const Color(0xFF1E1B2E),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_outlined, size: 48, color: Colors.white70),
          SizedBox(height: 12),
          Text(
            'No se pudo acceder a la cámara.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
          Text(
            kIsWeb
                ? 'Permite el acceso a la cámara en tu navegador o ingresa el Número de Serie manualmente.'
                : 'Revisa los permisos de la cámara en tu dispositivo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _visorCamara() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF1E1B2E),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: MobileScanner(
                controller: controller,
                onDetect: _onDetect,
                errorBuilder: _errorCamara,
              ),
            ),
            Center(
              child: Container(
                height: 1,
                width: 250,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: primaryPurple.withOpacity(0.8),
                      blurRadius: 8,
                      spreadRadius: 2,
                    )
                  ],
                  color: primaryPurple,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entradaManual() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿No funciona la cámara? Ingresa el Número de Serie (SN):',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _buscarManual(),
                      decoration: InputDecoration(
                        hintText: 'Ej. 9RGHKN3',
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: primaryPurple, width: 1.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryPurple,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _buscarManual,
                    child: const Text('Buscar',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cerrar();
      },
      child: _contenido(),
    );
  }

  Widget _contenido() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF9FAFB),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () => _cerrar(),
                      icon: const Icon(Icons.arrow_back, color: primaryPurple),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Escanea tu código QR',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: primaryPurple,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Alinea el código dentro del recuadro para escanear',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: kIsWeb
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 688),
                        child: _visorCamara(),
                      ),
                    )
                  : _visorCamara(),
            ),
            if (kIsWeb)
              _entradaManual()
            else ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      controller.toggleTorch();
                      setState(() {
                        _isTorchOn = !_isTorchOn;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryPurple,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: Icon(
                      _isTorchOn ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Linterna',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}