import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BarcodeRouting {
  /// Defines what looks like a barcode or SKU.
  /// Standard barcodes are 8-14 digits, but modern SKUs are often alphanumeric.
  /// We define it as a non-empty alphanumeric string without spaces.
  static bool isLikelyBarcode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || trimmed.contains(' ')) return false;
    // Alphanumeric identifier (3 to 50 characters, no spaces)
    return RegExp(r'^[a-zA-Z0-9\-_]+$').hasMatch(trimmed);
  }
}

/// A widget that intercepts keyboard events globally and routes scanner input correctly.
/// High-speed scanner input (<65ms per character burst) is siphoned into barcode actions,
/// while normal manual typing passes through to native Flutter TextFields naturally.
class BarcodeInterceptor extends StatefulWidget {
  final Widget child;
  final Function(String) onBarcodeDetected;
  final Function(String)? onTextDetected;
  final Map<FocusNode, TextEditingController>? controllers;
  final FocusNode? barcodeFocus;
  final FocusNode? nameFocus;
  final bool enabled;

  const BarcodeInterceptor({
    super.key,
    required this.child,
    required this.onBarcodeDetected,
    this.onTextDetected,
    this.controllers,
    this.barcodeFocus,
    this.nameFocus,
    this.enabled = true,
  });

  @override
  State<BarcodeInterceptor> createState() => _BarcodeInterceptorState();
}

class _BarcodeInterceptorState extends State<BarcodeInterceptor> {
  final StringBuffer _buffer = StringBuffer();
  DateTime _lastEventTime = DateTime.now();
  Timer? _scanTimeoutTimer;
  FocusNode? _originalFocus;
  bool _isScanMode = false;
  
  // Timing heuristics
  // Hardware scanners: typically < 30ms per character burst.
  static const _scannerSpeedLimit = Duration(milliseconds: 65);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _scanTimeoutTimer?.cancel();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent || !mounted) return false;

    // Ensure this BarcodeInterceptor is actually rendered and visible
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize || renderObject.size.isEmpty) {
      return false;
    }

    // Check route context (only run when active page/modal route is current)
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final primaryFocus = FocusManager.instance.primaryFocus;
    final bool isOtherFieldFocused = primaryFocus != null &&
        primaryFocus != widget.barcodeFocus &&
        primaryFocus.context != null;

    // If another field (like quantity input or text box) is currently focused by the user,
    // and we are NOT in high-speed hardware scanner mode, do not siphon key events!
    if (isOtherFieldFocused && !_isScanMode) {
      return false;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_lastEventTime);
    _lastEventTime = now;

    final logicalKey = event.logicalKey;
    String? char = event.character;
    
    // Manual mapping for HID digit events
    if (char == null) {
      final kid = logicalKey.keyId;
      if (kid >= LogicalKeyboardKey.digit0.keyId && kid <= LogicalKeyboardKey.digit9.keyId) {
        char = (kid - LogicalKeyboardKey.digit0.keyId).toString();
      } else if (kid >= LogicalKeyboardKey.numpad0.keyId && kid <= LogicalKeyboardKey.numpad9.keyId) {
        char = (kid - LogicalKeyboardKey.numpad0.keyId).toString();
      }
    }

    // Detect Scan Termination (Enter)
    if (logicalKey == LogicalKeyboardKey.enter || logicalKey == LogicalKeyboardKey.numpadEnter) {
      _scanTimeoutTimer?.cancel();
      final content = _buffer.toString().trim();
      _buffer.clear();

      if (content.isNotEmpty && _isScanMode) {
        _dispatchScanResult(content);
        _isScanMode = false;
        return true; // Siphoned scan result
      }
      
      _isScanMode = false;
      return false; 
    }

    // Skip modifiers
    if (logicalKey == LogicalKeyboardKey.shiftLeft || logicalKey == LogicalKeyboardKey.shiftRight ||
        logicalKey == LogicalKeyboardKey.controlLeft || logicalKey == LogicalKeyboardKey.controlRight ||
        logicalKey == LogicalKeyboardKey.altLeft || logicalKey == LogicalKeyboardKey.altRight) {
       return false;
    }

    // Detect Data Characters
    final bool isData = char != null && RegExp(r'[a-zA-Z0-9\s\-_.,]').hasMatch(char);

    if (isData) {
      _scanTimeoutTimer?.cancel();

      // Check if this character arrived at scanner speed (< 65ms)
      if (elapsed < _scannerSpeedLimit) {
        _buffer.write(char);
        if (_buffer.length >= 2 && !_isScanMode) {
          _isScanMode = true;
          _handleScanStarted();
        }
      } else {
        // Slow typing: reset buffer unless scan mode was already locked
        if (!_isScanMode) {
          _buffer.clear();
          _buffer.write(char);
        } else {
          _buffer.write(char);
        }
      }

      if (_isScanMode) {
        // High-speed scan mode: siphon key and set timeout for scan completion
        _scanTimeoutTimer = Timer(const Duration(milliseconds: 600), () {
           if (mounted) {
             final content = _buffer.toString().trim();
             _buffer.clear();
             _isScanMode = false;
             if (content.isNotEmpty) {
               _dispatchScanResult(content);
             }
           }
        });
        return true; // SIPHONED SCANNER KEY
      }

      // Normal manual typing: DO NOT SIPHON! Let Flutter's native TextField handle it.
      return false;
    }

    // Reset on any other non-data key
    _scanTimeoutTimer?.cancel();
    _buffer.clear();
    _isScanMode = false;
    return false;
  }

  void _handleScanStarted() {
    // Capture focus
    widget.controllers?.forEach((node, _) {
      if (node.hasFocus) _originalFocus = node;
    });

    // Jump to safe target
    if (widget.barcodeFocus != null && _originalFocus != widget.barcodeFocus) {
       widget.barcodeFocus!.requestFocus();
    }
  }

  void _dispatchScanResult(String content) {
    if (BarcodeRouting.isLikelyBarcode(content)) {
      widget.onBarcodeDetected(content);
    } else if (widget.onTextDetected != null) {
      widget.onTextDetected!(content);
    } else {
      widget.onBarcodeDetected(content);
    }

    // Restore focus
    if (_originalFocus != null && _originalFocus!.canRequestFocus) {
      _originalFocus!.requestFocus();
      _originalFocus = null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
