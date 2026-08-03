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
  RecognizedText? _recognizedText;
  CustomPaint? _customPaint;

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
      ResolutionPreset.medium,
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
        setState(() {
          _recognizedText = recognizedText;
          // In a real implementation, we would build a custom painter here to show bounding boxes
          // For simplicity in this Sari-Sari app, we'll just show a list or let them tap the preview
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
    
    // Simple conversion for the Sari-Sari use case
    // Note: Detailed byte conversion for all platforms/formats can be complex
    // This is a standard pattern for ML Kit with Camera package
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
      appBar: AppBar(
        title: const Text('Scan Brand Name'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          if (_recognizedText != null)
            _buildTextOverlays(),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Tap on the brand name to capture',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextOverlays() {
    return LayoutBuilder(builder: (context, constraints) {
      final List<Widget> overlays = [];
      
      for (final block in _recognizedText!.blocks) {
        for (final line in block.lines) {
          // Simplistic hit-test area mapping
          // In a production app, we would use proper coordinate transformation
          // from Image space to Screen space based on scale and aspect ratio.
          overlays.add(
            Positioned(
              left: 0, top: 0, // Placeholder - see logic below
              child: GestureDetector(
                onTap: () => Navigator.pop(context, line.text),
                child: Container(
                  // We'll just show the recognized lines in a scrollable list at the bottom 
                  // or floating labels if we had full mapping.
                  // For now, let's provide a selection list for better UX reliability.
                ),
              ),
            )
          );
        }
      }

      return Stack(
        children: [
          // Semi-transparent overlay to help text stand out
          Container(color: Colors.black12),
          
          // Selection List at the bottom
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.all(20),
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: _recognizedText!.blocks.expand((b) => b.lines).map((l) => ListTile(
                  dense: true,
                  title: Text(l.text, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.add_circle_outline, color: Colors.green),
                  onTap: () => Navigator.pop(context, l.text),
                )).toList(),
              ),
            ),
          ),
        ],
      );
    });
  }
}
