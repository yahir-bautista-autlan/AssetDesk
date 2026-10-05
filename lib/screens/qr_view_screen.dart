import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:universal_html/html.dart' as html;

class QrViewScreen extends StatefulWidget {
  final String serialNumber;
  final String nombreActivo;
  final bool mostrarDialogoExito;

  const QrViewScreen({
    super.key,
    required this.serialNumber,
    required this.nombreActivo,
    this.mostrarDialogoExito = false,
  });

  @override
  State<QrViewScreen> createState() => _QrViewScreenState();
}

class _QrViewScreenState extends State<QrViewScreen> {
  static const primaryPurple = Color(0xFF532E7C);
  
  final GlobalKey _qrKey = GlobalKey(); 
  
  bool _descargado = false;
  bool _mostrandoToast = false;
  bool _isSaving = false;
  bool _mostrarAlertaExito = false;

  @override
  void initState() {
    super.initState();
    _mostrarAlertaExito = widget.mostrarDialogoExito;
    if (_mostrarAlertaExito) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dialogoExitoGuardado();
      });
    }
  }

  void _dialogoExitoGuardado() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Color(0xFF16A34A), size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'CÓDIGO QR GENERADO\nCON ÉXITO',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'El registro ha sido guardado y se ha generado su código QR único.\n¡Listo para descargar!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Cerrar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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

  Future<void> _capturarYGuardarQR() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();

        if (kIsWeb) {
          final base64data = base64Encode(pngBytes);
          final a = html.AnchorElement(href: 'data:image/png;base64,$base64data');
          a.download = 'QR_${widget.serialNumber}.png';
          a.click();
          a.remove();
          
          _mostrarToastExito();
        } else {
          final result = await ImageGallerySaver.saveImage(
            pngBytes,
            quality: 100,
            name: "QR_${widget.serialNumber}",
          );

          if (result != null && (result['isSuccess'] == true || result.toString().isNotEmpty)) {
            _mostrarToastExito();
          }
        }
      }
    } catch (e) {
      debugPrint("Error al guardar QR: $e");
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _mostrarToastExito() {
    setState(() {
      _descargado = true;
      _mostrandoToast = true;
    });

    Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() {
          _mostrandoToast = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: primaryPurple),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Código QR único',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F3)),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedOpacity(
                        opacity: _mostrandoToast ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20),
                              const SizedBox(width: 10),
                              Text(
                                kIsWeb 
                                  ? 'Código QR descargado' 
                                  : 'Código QR guardado en tu galería',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Tarjeta QR con un ancho máximo más amplio para pantallas grandes y adaptable a pequeñas
                      RepaintBoundary(
                        key: _qrKey,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(36),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(color: const Color(0xFFEDEDF2), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      // El tamaño del QR se escala de forma fluida según el espacio disponible
                                      double qrSize = constraints.maxWidth < 350 ? constraints.maxWidth * 0.75 : 280.0;
                                      return QrImageView(
                                        data: widget.serialNumber,
                                        version: QrVersions.auto,
                                        size: qrSize,
                                        backgroundColor: Colors.white, 
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Divider(color: Color(0xFFF0F0F3), height: 1),
                                const SizedBox(height: 16),
                                const Text(
                                  'Número de serie / ID único:',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.serialNumber,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Botón inferior con el mismo ancho máximo (520px) para mantener perfecta simetría
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFF0F0F3))),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : () => _capturarYGuardarQR(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _descargado ? const Color(0xFF16A34A) : primaryPurple,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : Icon(
                              _descargado ? Icons.check : Icons.download_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                      label: Text(
                        _isSaving 
                          ? 'Procesando...' 
                          : (_descargado ? '¡QR Descargado!' : 'Descargar QR'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}