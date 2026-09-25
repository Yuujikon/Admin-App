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
/// It "siphons" every character and only releases it to the focused field if determined to be manual.
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
  Timer? _releaseTimer;
  FocusNode? _originalFocus;
  bool _isScanMode = false;
  
  // Timing heuristics
  // Scanners: typically < 30ms. Slowest scanners/connection: ~50ms.
  static const _scannerSpeedLimit = Duration(milliseconds: 65);
  // Manual release delay: short enough to be fast, long enough to detect scanner burst.
  static const _manualTypingDelay = Duration(milliseconds: 75);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _releaseTimer?.cancel();
    super.dispose();
  }

  void _releaseBufferToFocusedField() {
    if (!mounted || _isScanMode) return;
    
    final text = _buffer.toString();
    _buffer.clear();
    if (text.isEmpty || widget.controllers == null) return;

    FocusNode? focused;
    widget.controllers!.forEach((node, _) {
      if (node.hasFocus) focused = node;
    });

    if (focused != null) {
      final controller = widget.controllers![focused];
      if (controller != null) {
        final val = controller.value;
        int start = val.selection.start;
        int end = val.selection.end;
        if (start == -1) { start = val.text.length; end = val.text.length; }
        
        final newText = val.text.replaceRange(start, end, text);
        controller.value = val.copyWith(
          text: newText,
          selection: TextSelection.collapsed(offset: start + text.length),
        );
      }
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) return false;

    // Check route context
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final now = DateTime.now();
    final elapsed = now.difference(_lastEventTime);
    _lastEventTime = now;

    final logicalKey = event.logicalKey;
    String? char = event.character;
    
    // Manual mapping for HID digit events (where character might be null)
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
      _releaseTimer?.cancel();
      final content = _buffer.toString().trim();
      _buffer.clear();

      if (content.isNotEmpty && _isScanMode) {
        _dispatchScanResult(content);
        _isScanMode = false;
        return true; // Siphoned
      }
      
      _isScanMode = false;
      _releaseBufferToFocusedField();
      return false; 
    }

    // Skip modifiers without resetting sequence
    if (logicalKey == LogicalKeyboardKey.shiftLeft || logicalKey == LogicalKeyboardKey.shiftRight ||
        logicalKey == LogicalKeyboardKey.controlLeft || logicalKey == LogicalKeyboardKey.controlRight ||
        logicalKey == LogicalKeyboardKey.altLeft || logicalKey == LogicalKeyboardKey.altRight) {
       return false;
    }

    // Detect Data Characters
    final bool isData = char != null && RegExp(r'[a-zA-Z0-9\s\-_.,]').hasMatch(char);

    if (isData) {
      _releaseTimer?.cancel();
      _buffer.write(char);

      // Heuristic: confirm scan mode if we see a fast sequence
      if (elapsed < _scannerSpeedLimit && _buffer.length >= 2) {
        if (!_isScanMode) {
          _isScanMode = true;
          _handleScanStarted();
        }
      }

      if (!_isScanMode) {
        // Potential manual typing
        _releaseTimer = Timer(_manualTypingDelay, _releaseBufferToFocusedField);
      } else {
        // Confirmed scan: keep siphoning until Enter
        _releaseTimer = Timer(const Duration(milliseconds: 600), () {
           if (mounted) {
             _isScanMode = false;
             _releaseBufferToFocusedField();
           }
        });
      }
      return true; // SIPHONED
    }

    // Reset on any other key
    _releaseTimer?.cancel();
    _releaseBufferToFocusedField();
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
