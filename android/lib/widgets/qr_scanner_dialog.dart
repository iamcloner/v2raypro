import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/theme/app_theme.dart';

class QrScannerDialog extends StatefulWidget {
  final String locale;
  const QrScannerDialog({super.key, required this.locale});

  static Future<String?> show(BuildContext context, {required String locale}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog.fullscreen(
        child: QrScannerDialog(locale: locale),
      ),
    );
  }

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  late final MobileScannerController _controller;
  bool _isScanned = false;
  bool _isAnalyzingGallery = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _isScanned = true;
        Navigator.of(context).pop(value.trim());
        break;
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isAnalyzingGallery) return;
    setState(() => _isAnalyzingGallery = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null && File(path).existsSync()) {
          final capture = await _controller.analyzeImage(path);
          if (capture != null && capture.barcodes.isNotEmpty) {
            for (final barcode in capture.barcodes) {
              final val = barcode.rawValue;
              if (val != null && val.trim().isNotEmpty) {
                if (mounted) {
                  Navigator.of(context).pop(val.trim());
                }
                return;
              }
            }
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  widget.locale == 'fa'
                      ? 'کد QR معتبری در تصویر یافت نشد.'
                      : 'No valid QR code found in selected image.',
                ),
                backgroundColor: Colors.orangeAccent,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.locale == 'fa'
                  ? 'خطا در خواندن تصویر: $e'
                  : 'Error reading image: $e',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzingGallery = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.locale == 'fa';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_rounded, size: 56, color: Colors.white54),
                      const SizedBox(height: 16),
                      Text(
                        isFa
                            ? 'خطا در دسترسی به دوربین\nلطفاً دسترسی دوربین را تایید کنید یا از گالری تصویر انتخاب کنید.'
                            : 'Camera access error\nPlease allow camera permission or choose an image from gallery.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                        icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
                        label: Text(
                          isFa ? 'انتخاب از گالری' : 'Pick from Gallery',
                          style: const TextStyle(color: Colors.white),
                        ),
                        onPressed: _pickFromGallery,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primaryAccent, width: 2.5),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    isFa ? 'کد QR را داخل کادر قرار دهید' : 'Align QR inside frame',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: ValueListenableBuilder<MobileScannerState>(
                        valueListenable: _controller,
                        builder: (context, state, child) {
                          final isTorchOn = state.torchState == TorchState.on;
                          return Icon(
                            isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                            color: isTorchOn ? Colors.amber : Colors.white,
                          );
                        },
                      ),
                      onPressed: () => _controller.toggleTorch(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.flip_camera_android_rounded, color: Colors.white),
                      onPressed: () => _controller.switchCamera(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 24,
            right: 24,
            child: Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  side: BorderSide(color: AppTheme.primaryAccent.withValues(alpha: 0.6), width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 6,
                ),
                onPressed: _isAnalyzingGallery ? null : _pickFromGallery,
                icon: _isAnalyzingGallery
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.photo_library_rounded, color: AppTheme.primaryAccent),
                label: Text(
                  isFa ? 'اسکن بارکد از گالری' : 'Scan QR from Gallery',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
