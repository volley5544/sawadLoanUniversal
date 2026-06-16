import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'components/loan_register_styles.dart';

/// OCR document-capture screen — screen #3 on slide 7.
///
/// Opens the device camera with a document framing mask. On capture the photo
/// is previewed; confirming pops the captured file path back to the caller
/// (collateral step), which stores it for the future OCR API call.
class OcrCapturePage extends StatefulWidget {
  const OcrCapturePage({Key? key}) : super(key: key);

  @override
  State<OcrCapturePage> createState() => _OcrCapturePageState();
}

class _OcrCapturePageState extends State<OcrCapturePage> {
  CameraController? _controller;
  bool _isLoading = true;
  String? _error;
  XFile? _captured;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'No camera available');
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        Platform.isAndroid ? ResolutionPreset.medium : ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'ไม่สามารถเปิดกล้องได้ กรุณาอนุญาตการเข้าถึงกล้อง';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
    try {
      final image = await c.takePicture();
      if (!mounted) return;
      setState(() => _captured = image);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : _error != null
                ? _errorView()
                : _captured != null
                    ? _previewView()
                    : _cameraView(),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansThai(color: Colors.white),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('ปิด',
                  style: GoogleFonts.notoSansThai(
                      color: LoanRegisterStyles.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cameraView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'ถ่ายรูปเอกสาร / OCR',
            style: GoogleFonts.notoSansThai(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(_controller!),
              CustomPaint(
                  size: Size.infinite, painter: _DocumentMaskPainter()),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel',
                    style: GoogleFonts.notoSansThai(color: Colors.white)),
              ),
              _shutter(),
              const SizedBox(width: 64), // balances the Cancel button
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewView() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Image.file(File(_captured!.path), fit: BoxFit.contain),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _actionButton(
                icon: Icons.refresh,
                label: 'ถ่ายใหม่',
                background: Colors.white24,
                onTap: () => setState(() => _captured = null),
              ),
              _actionButton(
                icon: Icons.check,
                label: 'ใช้รูปนี้',
                background: LoanRegisterStyles.primary,
                onTap: () => Navigator.of(context).pop(_captured!.path),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shutter() {
    return GestureDetector(
      onTap: _takePicture,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'PHOTO',
            style: GoogleFonts.notoSansThai(
              color: LoanRegisterStyles.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.white54, width: 4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color background,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(shape: BoxShape.circle, color: background),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.notoSansThai(color: Colors.white)),
        ],
      ),
    );
  }
}

/// Dark overlay with a centered rounded-rectangle "hole" framing the document.
class _DocumentMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.86,
        height: size.height * 0.62,
      ),
      const Radius.circular(12),
    );

    final overlay = Paint()..color = Colors.black.withOpacity(0.6);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlay);

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(hole, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
