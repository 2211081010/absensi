// lib/pages/absensi_page.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// AbsensiPage
class AbsensiPage extends StatefulWidget {
  const AbsensiPage({super.key});

  @override
  State<AbsensiPage> createState() => _AbsensiPageState();
}

class _AbsensiPageState extends State<AbsensiPage> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isDetecting = false;
  bool _livenessVerified = false;
  late FaceDetector _faceDetector;
  XFile? _capturedImage;

  int _livenessStep = 0;
  final List<String> _stepsText = [
    "Silahkan Kedipkan Mata",
    "Silahkan Lihat ke Kiri",
    "Silahkan Lihat ke Kanan",
    "Silahkan Lihat ke Atas",
    "Silahkan Lihat ke Bawah",
    "Silahkan Senyum 😊",
  ];

  Rect? _faceBoundingBox;
  bool _multipleFaces = false;
  double _progressValue = 0.0;
  String _statusText = "Arahkan wajah ke dalam bingkai";

  late AnimationController _animController;

  bool get _cameraReady => _cameraController != null && _cameraController!.value.isInitialized;

  @override
  void initState() {
    super.initState();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: true,
        enableTracking: true,
      ),
    );

    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _initializeCamera();
    _updateProgressForStep();
  }

  Future<void> _initializeCamera() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final cameras = await availableCameras();
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);

      _cameraController = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processCameraImage);

      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) print("Error initialize camera: $e");
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || _livenessVerified || !_cameraReady) return;
    _isDetecting = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          _faceBoundingBox = null;
          _multipleFaces = false;
          _statusText = "Tidak terdeteksi wajah ";
        });
      } else {
        if (faces.length > 1) {
          setState(() {
            _multipleFaces = true;
            _statusText = "Terdeteksi lebih dari 1 wajah, pastikan hanya Anda di frame";
            _faceBoundingBox = null;
          });
        } else {
          _multipleFaces = false;
          final face = faces.first;
          setState(() {
            _faceBoundingBox = face.boundingBox;
          });

          final screenSize = MediaQuery.of(context).size;
          final ovalRect = _computeOvalRect(screenSize);
          final faceCenterScreen = _mapFaceRectToScreen(face.boundingBox, image, screenSize);

          final insideOval = _isPointInsideOval(faceCenterScreen, ovalRect);

          if (!insideOval) {
            setState(() {
              _statusText = "Arahkan wajah ke tengah bingkai oval";
            });
          } else {
            await _handleLivenessForFace(face);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error process camera image: $e");
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _handleLivenessForFace(Face face) async {
    switch (_livenessStep) {
      case 0:
        final leftOpen = face.leftEyeOpenProbability ?? 1.0;
        final rightOpen = face.rightEyeOpenProbability ?? 1.0;
        if (leftOpen < 0.45 && rightOpen < 0.45) _advanceStep("Terlihat kedipan, lanjut ke kiri");
        else _statusText = "Silakan kedipkan mata";
        break;
      case 1:
        if ((face.headEulerAngleY ?? 0) > 10) _advanceStep("Baik, sekarang lihat ke kanan");
        else _statusText = "Silahkan lihat ke kiri";
        break;
      case 2:
        if ((face.headEulerAngleY ?? 0) < -10) _advanceStep("Bagus, lihat ke atas");
        else _statusText = "Silahkan lihat ke kanan";
        break;
      case 3:
        if ((face.headEulerAngleX ?? 0) > 10) _advanceStep("Bagus, sekarang lihat ke bawah");
        else _statusText = "Silahkan lihat ke atas";
        break;
      case 4:
        if ((face.headEulerAngleX ?? 0) < -10) _advanceStep("Sekarang senyum untuk menyelesaikan");
        else _statusText = "Silahkan lihat ke bawah";
        break;
      case 5:
        final smile = face.smilingProbability ?? 0;
        if (smile > 0.6) {
          setState(() {
            _livenessVerified = true;
            _statusText = "Liveness terverifikasi";
            _progressValue = 1.0;
          });

          try {
            await _cameraController?.stopImageStream();
            _capturedImage = await _cameraController!.takePicture();
            if (kDebugMode) print("Gambar diambil: ${_capturedImage?.path}");
          } catch (e) {
            if (kDebugMode) print("Error take picture: $e");
          }

          // Langsung verifikasi wajah
          await _verifyFaceAndProceed();
        } else {
          _statusText = "Silakan senyum";
        }
        break;
    }
  }

  void _advanceStep(String newStatus) {
    setState(() {
      if (_livenessStep < 5) _livenessStep++;
      _statusText = newStatus;
      _updateProgressForStep();
    });
    _animController.forward(from: 0);
  }

  void _updateProgressForStep() {
    final stepCount = 6;
    setState(() {
      _progressValue = (_livenessStep + 1) / stepCount;
    });
  }

  Rect _computeOvalRect(Size screen) {
    final w = screen.width * 0.82;
    final h = screen.height * 0.52;
    final left = (screen.width - w) / 2;
    final top = (screen.height - h) / 2 - (screen.height * 0.03);
    return Rect.fromLTWH(left, top, w, h);
  }

  bool _isPointInsideOval(Offset point, Rect ovalRect) {
    final cx = ovalRect.center.dx;
    final cy = ovalRect.center.dy;
    final rx = ovalRect.width / 2;
    final ry = ovalRect.height / 2;
    final dx = point.dx - cx;
    final dy = point.dy - cy;
    return (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0;
  }

  Offset _mapFaceRectToScreen(Rect faceRect, CameraImage image, Size screenSize) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final previewSize = _cameraController!.value.previewSize ?? Size(imgW, imgH);
    final scaleX = screenSize.width / previewSize.width;
    final scaleY = screenSize.height / previewSize.height;

    final left = screenSize.width - (faceRect.right * scaleX);
    final top = faceRect.top * scaleY;
    final right = screenSize.width - (faceRect.left * scaleX);
    final bottom = faceRect.bottom * scaleY;

    return Offset((left + right) / 2, (top + bottom) / 2);
  }

  Future<void> _verifyFaceAndProceed() async {
    if (_capturedImage == null) return;
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://192.168.1.12:8000/api/pegawai/verify-face'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath('foto_live', _capturedImage!.path));

      final response = await request.send();
      final respStr = await response.stream.bytesToString();
      final data = jsonDecode(respStr);

      if (response.statusCode == 200 &&
          data['similarity'] != null &&
          data['similarity'] >= 0.75) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Wajah terverifikasi, lanjut absen!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacementNamed(context, '/next-page');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Wajah tidak cocok, silakan coba lagi"),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _livenessVerified = false;
            _livenessStep = 0;
            _progressValue = 0.0;
          });
          await _cameraController?.startImageStream(_processCameraImage);
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error verifyFaceAndProceed: $e");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    if (!_cameraReady) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text("Liveness Check - Absensi")),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(child: CameraPreview(_cameraController!)),
          Center(child: CustomPaint(size: screen, painter: OvalOverlayPainter(ovalRect: _computeOvalRect(screen)))),
          if (_faceBoundingBox != null && !_multipleFaces)
            CustomPaint(
              size: screen,
              painter: FaceBoxPainter(
                faceRect: _faceBoundingBox!,
                previewSize: _cameraController!.value.previewSize ?? Size(1, 1),
                screenSize: screen,
                isVerified: _livenessVerified,
              ),
            ),
          Positioned(
            top: 34,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Text(_statusText,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: 8,
                  width: screen.width * 0.9,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _progressValue.clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                            color: _livenessVerified ? Colors.green : Colors.lightGreenAccent, borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 26,
            left: 20,
            right: 20,
            child: Column(
              children: [
                if (_multipleFaces)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                    child: const Text("Terdeteksi lebih dari 1 wajah. Pastikan hanya Anda di frame.",
                        style: TextStyle(color: Colors.white)),
                  )
                else if (!_livenessVerified)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(8)),
                    child: Text(_stepsText[_livenessStep], style: const TextStyle(color: Colors.white, fontSize: 18)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                    child: const Text("✔ Liveness Verified", style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OvalOverlayPainter extends CustomPainter {
  final Rect ovalRect;
  OvalOverlayPainter({required this.ovalRect});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final outer = Path()..addRect(full);
    final oval = Path()..addOval(ovalRect);
    final combined = Path.combine(PathOperation.difference, outer, oval);
    canvas.drawPath(combined, Paint()..color = Colors.black.withOpacity(0.62));
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant OvalOverlayPainter oldDelegate) => oldDelegate.ovalRect != ovalRect;
}

class FaceBoxPainter extends CustomPainter {
  final Rect faceRect;
  final Size previewSize;
  final Size screenSize;
  final bool isVerified;

  FaceBoxPainter({required this.faceRect, required this.previewSize, required this.screenSize, required this.isVerified});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = screenSize.width / (previewSize.width == 0 ? 1 : previewSize.width);
    final sy = screenSize.height / (previewSize.height == 0 ? 1 : previewSize.height);

    Rect rect = Rect.fromLTRB(faceRect.left * sx, faceRect.top * sy, faceRect.right * sx, faceRect.bottom * sy);
    rect = Rect.fromLTRB(screenSize.width - rect.right, rect.top, screenSize.width - rect.left, rect.bottom);

    final paint = Paint()
      ..color = isVerified ? Colors.greenAccent : Colors.yellowAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawRect(rect, paint);

    final cornerPaint = Paint()..color = paint.color..strokeWidth = 4..style = PaintingStyle.stroke;
    const markerLen = 14.0;
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(markerLen, 0), cornerPaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, markerLen), cornerPaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-markerLen, 0), cornerPaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, markerLen), cornerPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(markerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -markerLen), cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-markerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -markerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant FaceBoxPainter oldDelegate) => true;
}
