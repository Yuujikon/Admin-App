import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';

class BrandScannerDialog extends StatefulWidget {
  const BrandScannerDialog({super.key});

  @override
  State<BrandScannerDialog> createState() => _BrandScannerDialogState();
}

class _BrandScannerDialogState extends State<BrandScannerDialog> {
  CameraController? _controller;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _isProcessing = false;
  bool _flashOn = false;
  List<String> _candidates = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high, // Higher resolution for better accuracy
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    await _controller?.initialize();
    if (!mounted) return;

    _controller?.startImageStream(_processImage);
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  void _processImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final recognizedText = await _textRecognizer.processImage(inputImage);
      
      if (mounted) {
        // Extract unique lines, prioritizing larger text (brand names are usually big)
        final lines = recognizedText.blocks
            .expand((b) => b.lines)
            .where((l) => l.text.length > 2) // Skip tiny snippets
            .toList();

        // Sort by bounding box area (larger = more likely to be brand)
        lines.sort((a, b) {
          final areaA = a.boundingBox.width * a.boundingBox.height;
          final areaB = b.boundingBox.width * b.boundingBox.height;
          return areaB.compareTo(areaA);
        });

        final uniqueText = lines.map((l) => l.text.trim()).toSet().take(10).toList();

        setState(() {
          _candidates = uniqueText;
        });
      }
    } catch (e) {
      debugPrint('Text recognition error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final sensorOrientation = _controller?.description.sensorOrientation ?? 0;
    
    final orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = orientations[DeviceOrientation.portraitUp];
      if (rotationCompensation == null) return null;
      if (_controller?.description.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || (Platform.isAndroid && format != InputImageFormat.nv21) || (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Brand Name', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              setState(() => _flashOn = !_flashOn);
              _controller?.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller!),
                // Scanning area guide
                Center(
                  child: Container(
                    width: 280,
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Text('Captured Text', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text('Tap the brand name below to select it', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _candidates.isEmpty
                      ? const Center(child: Text('Searching for text...', style: TextStyle(color: Colors.grey)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _candidates.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                          itemBuilder: (ctx, i) => ListTile(
                            title: Text(_candidates[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.add_circle_outline, color: Colors.blue),
                            onTap: () => Navigator.pop(context, _candidates[i]),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
