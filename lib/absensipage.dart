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
/// Fitur:
/// - Kamera full screen (front)
/// - Liveness steps (kedip, kiri, kanan, atas, bawah, senyum)
/// - Bounding box overlay realtime
/// - Bingkai oval eKYC (area dalam transparan)
/// - Progress bar animasi per step
/// - Validasi wajah di dalam oval dan hanya 1 wajah
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

  // UI / Step state
  int _livenessStep = 0; // 0..5
  final List<String> _stepsText = [
    "Silahkan Kedipkan Mata",
    "Silahkan Lihat ke Kiri",
    "Silahkan Lihat ke Kanan",
    "Silahkan Lihat ke Atas",
    "Silahkan Lihat ke Bawah",
    "Silahkan Senyum 😊",
  ];

  // overlay & progress
  Rect? _faceBoundingBox;
  bool _multipleFaces = false;
  double _progressValue = 0.14; // progress bar (0..1)
  String _statusText = "Arahkan wajah ke dalam bingkai";

  // animation controller used for small bounce or similar (optional)
  late AnimationController _animController;

  // Detect if camera initialized
  bool get _cameraReady => _cameraController != null && _cameraController!.value.isInitialized;

  @override
  void initState() {
    super.initState();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: true, // required for smilingProbability & eye open
        enableTracking: true,
      ),
    );

    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _initializeCamera();
    _updateProgressForStep(); // set initial texts
  }

  Future<void> _initializeCamera() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final cameras = await availableCameras();
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);

      _cameraController = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();

      // start image stream
      await _cameraController!.startImageStream(_processCameraImage);

      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) print("Error initialize camera: $e");
    }
  }

  // Convert camera image -> InputImage and run MLKit face detection
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || _livenessVerified || !_cameraReady) return;
    _isDetecting = true;

    try {
      // Convert planes to bytes
      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg, // adjust if needed
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      // Update faces status
      if (faces.isEmpty) {
        setState(() {
          _faceBoundingBox = null;
          _multipleFaces = false;
          _statusText = "Tidak terdeteksi wajah";
        });
      } else {
        // multiple faces?
        if (faces.length > 1) {
          setState(() {
            _multipleFaces = true;
            _statusText = "Terdeteksi lebih dari 1 wajah, pastikan hanya Anda di frame";
            _faceBoundingBox = null; // jangan gambar kotak jika >1
          });
        } else {
          _multipleFaces = false;
          final face = faces.first;
          setState(() {
            _faceBoundingBox = face.boundingBox;
          });

          // Map face bounding box center to screen coordinates and check if inside oval
          final screenSize = MediaQuery.of(context).size;
          final ovalRect = _computeOvalRect(screenSize);

          final faceCenterScreen = _mapFaceRectToScreen(face.boundingBox, image, screenSize);

          final insideOval = _isPointInsideOval(faceCenterScreen, ovalRect);

          if (!insideOval) {
            setState(() {
              _statusText = "Arahkan wajah ke tengah bingkai oval";
            });
          } else {
            // proceed to liveness step checks
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
    // Only validate when face is inside oval
    // Each condition moves to next step and updates progress & status text
    switch (_livenessStep) {
      case 0:
        // kedip: both eyes closed briefly (prob < threshold)
        final leftOpen = face.leftEyeOpenProbability ?? 1.0;
        final rightOpen = face.rightEyeOpenProbability ?? 1.0;
        if (leftOpen < 0.45 && rightOpen < 0.45) {
          _advanceStep("Terlihat kedipan, lanjut ke kiri");
        } else {
          _statusText = "Silakan kedipkan mata";
        }
        break;

      case 1:
        // look left: eulerY positive (face turned to left from camera perspective)
        final eulerY = face.headEulerAngleY ?? 0;
        if (eulerY > 10) {
          _advanceStep("Baik, sekarang lihat ke kanan");
        } else {
          _statusText = "Silahkan lihat ke kiri";
        }
        break;

      case 2:
        // look right: eulerY negative
        final eulerY2 = face.headEulerAngleY ?? 0;
        if (eulerY2 < -10) {
          _advanceStep("Bagus, lihat ke atas");
        } else {
          _statusText = "Silahkan lihat ke kanan";
        }
        break;

      case 3:
        // look up: eulerX negative? depending orientation. Using >10 for up (previously used >10)
        final eulerX = face.headEulerAngleX ?? 0;
        if (eulerX > 10) {
          _advanceStep("Bagus, sekarang lihat ke bawah");
        } else {
          _statusText = "Silahkan lihat ke atas";
        }
        break;

      case 4:
        // look down: eulerX < -10
        final eulerX2 = face.headEulerAngleX ?? 0;
        if (eulerX2 < -10) {
          _advanceStep("Sekarang senyum untuk menyelesaikan");
        } else {
          _statusText = "Silahkan lihat ke bawah";
        }
        break;

      case 5:
        // smile
        final smile = face.smilingProbability ?? 0;
        if (smile > 0.6) {
          setState(() {
            _livenessVerified = true;
            _statusText = "Liveness terverifikasi";
            _progressValue = 1.0;
          });

          // Stop stream to safely take picture
          try {
            await _cameraController?.stopImageStream();
          } catch (_) {}

          // take picture
          try {
            _capturedImage = await _cameraController!.takePicture();
            if (kDebugMode) print("Gambar diambil: ${_capturedImage?.path}");
          } catch (e) {
            if (kDebugMode) print("Error take picture: $e");
          }

          // submit and return
          bool success = await _submitAbsensi();
          if (success && mounted) {
            // show success then pop
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Absen berhasil!"), backgroundColor: Colors.green),
              );
              Navigator.pop(context, true);
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Gagal submit absen"), backgroundColor: Colors.red),
              );
            }
          }
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

    // Small animation trigger
    _animController.forward(from: 0);
  }

  void _updateProgressForStep() {
    // Map step 0..5 into progress (0..1)
    final stepCount = 6;
    setState(() {
      _progressValue = (_livenessStep + 1) / stepCount; // fraction
    });
  }

  // Map face bounding box from image coordinate space to screen coordinate space
  Offset _mapFaceRectToScreenCenter(Rect faceRect, CameraImage image, Size screenSize) {
    // image size
    final imageW = image.width.toDouble();
    final imageH = image.height.toDouble();

    // camera preview size from controller (might be swapped)
    final previewSize = _cameraController!.value.previewSize ?? Size(imageW, imageH);

    // In many devices, previewSize.width relates to sensor orientation; we'll map carefully:
    // We assume the camera preview fills the screen (SizedBox.expand). We map by scale factors.
    final previewH = previewSize.height;
    final previewW = previewSize.width;

    final scaleX = screenSize.width / previewW;
    final scaleY = screenSize.height / previewH;

    // Convert center
    final centerX = faceRect.center.dx * scaleX;
    final centerY = faceRect.center.dy * scaleY;

    // front camera mirror horizontally
    final mirroredX = screenSize.width - centerX;

    return Offset(mirroredX, centerY);
  }

  // Variant that maps using CameraImage info (we need image for width/height)
  Offset _mapFaceRectToScreen(Rect faceRect, CameraImage image, Size screenSize) {
    // image width/height
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    // Many devices rotate preview; this mapping may need tuning for specific device.
    // We will map by swapping axes similar to other examples (previewSize may be rotated).
    final previewSize = _cameraController!.value.previewSize ?? Size(imgW, imgH);
    final previewW = previewSize.width;
    final previewH = previewSize.height;

    final scaleX = screenSize.width / previewW;
    final scaleY = screenSize.height / previewH;

    // faceRect from MLKit has origin top-left of image. Mirror horizontally for front camera.
    final left = screenSize.width - (faceRect.right * scaleX);
    final top = faceRect.top * scaleY;
    final right = screenSize.width - (faceRect.left * scaleX);
    final bottom = faceRect.bottom * scaleY;

    final center = Offset((left + right) / 2, (top + bottom) / 2);
    return center;
  }

  // Simpler approx mapping when previewSize available
  Offset _mapFaceRectToScreenOld(Rect faceRect, Size previewSize, Size screenSize) {
    final scaleX = screenSize.width / previewSize.height;
    final scaleY = screenSize.height / previewSize.width;

    Rect scaledRect = Rect.fromLTRB(
      faceRect.left * scaleX,
      faceRect.top * scaleY,
      faceRect.right * scaleX,
      faceRect.bottom * scaleY,
    );

    // Mirror horizontally for front camera
    final mirrored = Rect.fromLTRB(
      screenSize.width - scaledRect.right,
      scaledRect.top,
      screenSize.width - scaledRect.left,
      scaledRect.bottom,
    );

    final center = mirrored.center;
    return center;
  }

  Rect _computeOvalRect(Size screen) {
    final w = screen.width * 0.82;
    final h = screen.height * 0.52;
    final left = (screen.width - w) / 2;
    final top = (screen.height - h) / 2 - (screen.height * 0.03); // sedikit keatas
    return Rect.fromLTWH(left, top, w, h);
  }

  bool _isPointInsideOval(Offset point, Rect ovalRect) {
    final cx = ovalRect.center.dx;
    final cy = ovalRect.center.dy;
    final rx = ovalRect.width / 2;
    final ry = ovalRect.height / 2;

    final dx = point.dx - cx;
    final dy = point.dy - cy;

    final val = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry);
    return val <= 1.0;
  }

  Future<bool> _submitAbsensi() async {
    if (_capturedImage == null) return false;

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? idPegawai = prefs.getString('id_pegawai');
      if (idPegawai == null) return false;

      final todayResp = await http.get(Uri.parse('http://192.168.1.11:8000/api/absensi/today/$idPegawai'));
      if (todayResp.statusCode != 200) {
        if (kDebugMode) print("Gagal cek status absen: ${todayResp.body}");
        return false;
      }
      final Map<String, dynamic> statusData = jsonDecode(todayResp.body);

      String endpoint = statusData["status"] == "belum"
          ? "create"
          : statusData["status"] == "masuk"
              ? "pulang"
              : "";

      if (endpoint.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Anda sudah absen hari ini"),
            backgroundColor: Colors.orange,
          ));
        }
        return false;
      }

      String fileField = endpoint == "create" ? "foto_masuk" : "foto_pulang";

      final request = http.MultipartRequest('POST', Uri.parse('http://192.168.1.11:8000/api/absensi/$endpoint'));
      request.fields['id_pegawai'] = idPegawai;
      request.files.add(await http.MultipartFile.fromPath(fileField, _capturedImage!.path));

      final resp = await request.send();
      final respStr = await resp.stream.bytesToString();
      if (kDebugMode) print("Submit response: $respStr");

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      if (kDebugMode) print("Error submitAbsensi: $e");
      return false;
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

    if (!_cameraReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Liveness Check - Absensi")),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera full screen
          SizedBox.expand(
            child: CameraPreview(_cameraController!),
          ),

          // Dark overlay with oval cutout (eKYC frame)
          Center(
            child: CustomPaint(
              size: screen,
              painter: OvalOverlayPainter(ovalRect: _computeOvalRect(screen)),
            ),
          ),

          // Bounding box painter (if face detected and single)
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

          // Top progress + status
          Positioned(
            top: 34,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Text(
                  _statusText,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                // Animated progress bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: 8,
                  width: screen.width * 0.9,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _progressValue.clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: _livenessVerified ? Colors.green : Colors.lightGreenAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom status / help
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
                    child: const Text("Terdeteksi lebih dari 1 wajah. Pastikan hanya Anda di frame.", style: TextStyle(color: Colors.white)),
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

/// Painter for dark overlay with oval cutout (eKYC style)
class OvalOverlayPainter extends CustomPainter {
  final Rect ovalRect;
  OvalOverlayPainter({required this.ovalRect});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final outer = Path()..addRect(full);
    final oval = Path()..addOval(ovalRect);
    final combined = Path.combine(PathOperation.difference, outer, oval);

    // draw dimmed outside
    canvas.drawPath(
      combined,
      Paint()..color = Colors.black.withOpacity(0.62),
    );

    // draw white stroke around oval
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

/// Painter for face bounding box (maps preview -> screen)
class FaceBoxPainter extends CustomPainter {
  final Rect faceRect; // rect from MLKit (image coords)
  final Size previewSize; // camera preview size from controller
  final Size screenSize;
  final bool isVerified;

  FaceBoxPainter({
    required this.faceRect,
    required this.previewSize,
    required this.screenSize,
    required this.isVerified,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // previewSize may be rotated; many examples swap width/height.
    // We'll calculate scale based on assumption preview fills screen.
    final previewW = previewSize.width;
    final previewH = previewSize.height;

    // Avoid division by zero
    final sx = (screenSize.width) / (previewW == 0 ? 1 : previewW);
    final sy = (screenSize.height) / (previewH == 0 ? 1 : previewH);

    Rect rect = Rect.fromLTRB(
      faceRect.left * sx,
      faceRect.top * sy,
      faceRect.right * sx,
      faceRect.bottom * sy,
    );

    // Mirror horizontally for front camera
    rect = Rect.fromLTRB(
      screenSize.width - rect.right,
      rect.top,
      screenSize.width - rect.left,
      rect.bottom,
    );

    final paint = Paint()
      ..color = isVerified ? Colors.greenAccent : Colors.yellowAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawRect(rect, paint);

    // Small corner markers
    final cornerPaint = Paint()..color = paint.color..strokeWidth = 4..style = PaintingStyle.stroke;
    const markerLen = 14.0;
    // top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(markerLen, 0), cornerPaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, markerLen), cornerPaint);
    // top-right
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-markerLen, 0), cornerPaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, markerLen), cornerPaint);
    // bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(markerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -markerLen), cornerPaint);
    // bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-markerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -markerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant FaceBoxPainter oldDelegate) => true;
}
