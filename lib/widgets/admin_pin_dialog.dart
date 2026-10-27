import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';

/// A 4-digit Admin PIN verification modal with masked digits, auto-submit on 4th digit,
/// and lockout delay after 5 failed attempts (30-second cooldown).
class AdminPinDialog extends StatefulWidget {
  final String title;
  final String message;
  final String correctPin;

  const AdminPinDialog({
    super.key,
    this.title = 'Admin Authorization Required',
    this.message = 'Enter 4-digit Admin PIN to approve action.',
    this.correctPin = '1234', // Default Admin PIN
  });

  static Future<bool> verify(
    BuildContext context, {
    String title = 'Admin Authorization Required',
    String message = 'Enter 4-digit Admin PIN to approve action.',
    String correctPin = '1234',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => AdminPinDialog(
        title: title,
        message: message,
        correctPin: correctPin,
      ),
    );
    return result ?? false;
  }

  @override
  State<AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<AdminPinDialog> {
  final _pinCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _pinService = AuthService();

  bool _isLockedOut = false;
  int _lockoutSeconds = 30;
  Timer? _lockoutTimer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pinCtrl.addListener(_onPinChanged);
    _checkInitialLockout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _focusNode.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialLockout() async {
    final rem = await _pinService.getRemainingLockoutSeconds();
    if (rem > 0 && mounted) {
      _startLockout(rem);
    }
  }

  void _onPinChanged() {
    if (_isLockedOut) return;
    if (_errorMessage != null) setState(() => _errorMessage = null);

    if (_pinCtrl.text.length == 4) {
      _verifyPin(_pinCtrl.text);
    }
  }

  Future<void> _verifyPin(String input) async {
    if (await _pinService.isLockedOut()) {
      final rem = await _pinService.getRemainingLockoutSeconds();
      _startLockout(rem);
      return;
    }

    bool ok = false;
    if (widget.correctPin != '1234') {
      ok = (input == widget.correctPin);
    } else {
      ok = await _pinService.verifyPin(input);
    }

    if (!mounted) return;

    if (ok) {
      await _pinService.resetFailedAttempts();
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } else {
      HapticFeedback.vibrate();
      _pinCtrl.clear();
      final res = await _pinService.recordFailedAttempt();
      final bool nowLocked = res['isLockedOut'] as bool;
      final int remSec = res['remainingSeconds'] as int;
      final int remAtt = res['remainingAttempts'] as int;

      if (nowLocked) {
        _startLockout(remSec);
      } else {
        setState(() {
          _errorMessage =
              'Incorrect PIN ($remAtt ${remAtt == 1 ? "attempt" : "attempts"} left)';
        });
      }
    }
  }

  void _startLockout([int seconds = 30]) {
    _lockoutTimer?.cancel();
    setState(() {
      _isLockedOut = true;
      _lockoutSeconds = seconds;
      _pinCtrl.clear();
      _errorMessage = 'Too many failed attempts. Locked for ${seconds}s.';
    });

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final rem = await _pinService.getRemainingLockoutSeconds();
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (rem > 0) {
        setState(() {
          _isLockedOut = true;
          _lockoutSeconds = rem;
          _errorMessage = 'Too many failed attempts. Locked for ${rem}s.';
        });
      } else {
        timer.cancel();
        await _pinService.resetFailedAttempts();
        if (mounted) {
          setState(() {
            _isLockedOut = false;
            _errorMessage = null;
          });
          _focusNode.requestFocus();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(Icons.security_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.message,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),

          // Masked PIN Indicator Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final bool isFilled = index < _pinCtrl.text.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLockedOut
                      ? Colors.red
                      : (isFilled
                          ? theme.colorScheme.primary
                          : Colors.grey.shade300),
                  border: Border.all(
                    color:
                        _isLockedOut ? Colors.red : theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
              );
            }),
          ),

          // Hidden Input Field
          Opacity(
            opacity: 0,
            child: TextField(
              controller: _pinCtrl,
              focusNode: _focusNode,
              enabled: !_isLockedOut,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          if (_isLockedOut) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: Colors.red),
                const SizedBox(width: 4),
                Text(
                  'Try again in $_lockoutSeconds seconds',
                  style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
