import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/order_provider.dart';
import '../services/auth_service.dart';
import '../shared/services/admin_messaging_service.dart';
import '../utils/totp.dart';
import '../widgets/otp_method_bottom_sheet.dart';

/// Screen for 2FA TOTP code or Admin PIN verification prior to granting full application access.
class AdminPinScreen extends StatefulWidget {
  const AdminPinScreen({super.key});
  @override
  State<AdminPinScreen> createState() => _AdminPinScreenState();
}

class _AdminPinScreenState extends State<AdminPinScreen>
    with WidgetsBindingObserver {
  final _pinService = AuthService();
  String _pin = '';
  bool _error = false;
  bool _isVerifying = false;
  bool _useStaticPin = false;
  String? _errorMessage;
  String? _lastAutoPastedCode;

  Timer? _lockoutTimer;
  bool _isLockedOut = false;
  int _lockoutSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captureInitialClipboard();
    _checkInitialLockout();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkInitialLockout() async {
    final rem = await _pinService.getRemainingLockoutSeconds();
    if (rem > 0 && mounted) {
      _startLockoutTimer(rem);
    }
  }

  void _startLockoutTimer(int seconds) {
    _lockoutTimer?.cancel();
    setState(() {
      _isLockedOut = true;
      _lockoutSeconds = seconds;
      _pin = '';
      _error = true;
      _errorMessage = 'Too many failed attempts. Locked out for ${seconds}s';
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
          _errorMessage = 'Too many failed attempts. Locked out for ${rem}s';
        });
      } else {
        timer.cancel();
        await _pinService.resetFailedAttempts();
        if (mounted) {
          setState(() {
            _isLockedOut = false;
            _lockoutSeconds = 0;
            _error = false;
            _errorMessage = null;
          });
        }
      }
    });
  }

  Future<void> _captureInitialClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text =
          data?.text?.replaceAll(' ', '').replaceAll('-', '').trim() ?? '';
      if (text.length == 6 && RegExp(r'^\d{6}$').hasMatch(text)) {
        _lastAutoPastedCode = text;
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForTotp();
    }
  }

  Future<void> _checkClipboardForTotp() async {
    if (_isVerifying || _useStaticPin || _isLockedOut) return;

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text =
          data?.text?.replaceAll(' ', '').replaceAll('-', '').trim() ?? '';

      if (text.length == 6 && RegExp(r'^\d{6}$').hasMatch(text)) {
        if (text == _lastAutoPastedCode) return;

        _lastAutoPastedCode = text;
        if (!mounted) return;

        final auth = context.read<AppAuthProvider>();
        final bool isValidTotp = auth.verifyTotp(text);

        if (isValidTotp) {
          setState(() {
            _pin = text;
            _error = false;
            _errorMessage = null;
          });

          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.flash_on_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Auto-filled 6-digit TOTP from clipboard!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.blue.shade700,
            ),
          );

          _verify(text);
        }
      }
    } catch (e) {
      debugPrint('Error reading clipboard: $e');
    }
  }

  void _onKey(String key) {
    if (_isVerifying || _isLockedOut) return;
    const limit = 6;

    if (key == '⌫') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
      return;
    }
    if (_pin.length >= limit) return;
    final next = _pin + key;
    setState(() {
      _pin = next;
      _error = false;
      _errorMessage = null;
    });
    if (next.length == limit) _verify(next);
  }

  Future<void> _verify(String code) async {
    if (_isLockedOut) return;

    final auth = context.read<AppAuthProvider>();
    final bool effectiveUseStaticPin = !auth.totpEnabled ? true : _useStaticPin;

    setState(() => _isVerifying = true);

    bool ok = false;
    if (effectiveUseStaticPin) {
      ok = await _pinService.verifyPin(code);
    } else {
      ok = auth.verifyTotp(code);
      if (!ok) {
        ok = await _pinService.verifyPin(code);
      }
    }

    if (!mounted) return;

    if (ok) {
      await _pinService.resetFailedAttempts();
      setState(() {
        _isVerifying = false;
        _error = false;
        _errorMessage = null;
      });
      _onSuccess();
    } else {
      final res = await _pinService.recordFailedAttempt();
      final bool nowLocked = res['isLockedOut'] as bool;
      final int remSec = res['remainingSeconds'] as int;
      final int remAtt = res['remainingAttempts'] as int;

      if (!mounted) return;

      setState(() {
        _pin = '';
        _isVerifying = false;
        _error = true;
      });

      if (nowLocked) {
        _startLockoutTimer(remSec);
      } else {
        setState(() {
          _errorMessage = _useStaticPin
              ? 'Incorrect Admin PIN. $remAtt ${remAtt == 1 ? "attempt" : "attempts"} remaining.'
              : 'Invalid code. $remAtt ${remAtt == 1 ? "attempt" : "attempts"} remaining.';
        });
      }
    }
  }

  void _onSuccess() {
    final auth = context.read<AppAuthProvider>();
    final email = auth.currentUser?.email ?? 'admin@gdc.com';
    context.read<InventoryProvider>().setAdminEmail(email);
    context.read<OrderProvider>().setAdminName(email);
    auth.setAdminVerified(true);
  }

  Future<void> _launchAuthenticatorApp(BuildContext context) async {
    final auth = context.read<AppAuthProvider>();

    if (!auth.isTotpLinked) {
      final uri = auth.totpUri;
      try {
        final launched =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          auth.markTotpLinked();
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Could not open Authenticator app. Please copy secret key manually.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Authenticator app not found. Please install Google Authenticator or copy secret key.')),
          );
        }
      }
    } else {
      final directUris = [
        Uri.parse('android-app://com.google.android.apps.authenticator2'),
        Uri.parse(
            'intent://#Intent;package=com.google.android.apps.authenticator2;end'),
      ];

      bool launched = false;
      for (final uri in directUris) {
        try {
          launched =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) break;
        } catch (_) {}
      }

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Please open Google Authenticator on your device.')),
        );
      }
    }
  }

  void _showSetupDialog(BuildContext context) {
    final auth = context.read<AppAuthProvider>();
    final readableSecret = TotpUtils.formatSecretReadable(auth.totpSecret);

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Google Authenticator Setup',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Container(
          width: 440,
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Zero-typing setup: Tap below to automatically link your key to Google Authenticator:',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _launchAuthenticatorApp(context),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('OPEN AUTHENTICATOR APP',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Manual Setup Option:',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                  'Account Name: GDC Sari-Sari (${auth.currentUser?.email ?? 'User'})',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        readableSecret,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            fontSize: 13,
                            letterSpacing: 1),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      tooltip: 'Copy Key',
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: auth.totpSecret));
                        auth.markTotpLinked();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Secret key copied to clipboard!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showForgotPinDialog(BuildContext context) {
    final auth = context.read<AppAuthProvider>();
    final user = auth.currentUser;

    OtpMethodBottomSheet.show(
      context,
      defaultEmail: user?.email,
      defaultPhone: auth.phoneNumber ?? '09558297358',
      onVerified: () async {
        _showSetNewPinDialog(context);
      },
    );
  }

  void _showSetNewPinDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => _SetNewPinDialog(
        onCompleted: () {
          _onSuccess();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'SETUP',
      '0',
      '⌫'
    ];
    final auth = context.watch<AppAuthProvider>();
    final bool effectiveUseStaticPin = !auth.totpEnabled ? true : _useStaticPin;
    final user = auth.currentUser;
    final String email = user?.email ?? 'Unknown';

    final copperColor = const Color(0xFFC07038);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Log Out'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Store Branding Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: copperColor.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 40,
                      color: copperColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'GDC SARI-SARI STORE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: copperColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    effectiveUseStaticPin ? 'Enter Admin PIN' : 'Enter 6-Digit Code',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Verification required to access financial & staff settings',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(
                      color: copperColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pill mode toggle button
                  OutlinedButton.icon(
                    onPressed: () {
                      if (!auth.totpEnabled) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Google Authenticator 2FA is turned off in Account Security.',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                      setState(() {
                        _useStaticPin = !_useStaticPin;
                        _pin = '';
                        _errorMessage = null;
                      });
                    },
                    icon: Icon(
                      effectiveUseStaticPin
                          ? Icons.security_rounded
                          : Icons.keyboard_outlined,
                      size: 16,
                      color: copperColor,
                    ),
                    label: Text(
                      effectiveUseStaticPin
                          ? 'Use Google Authenticator'
                          : 'Use 6-Digit Offline PIN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: copperColor,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      side: BorderSide(color: copperColor, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6 Circular PIN Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      6,
                      (i) => Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isLockedOut
                                ? Theme.of(context).colorScheme.error
                                : copperColor,
                            width: 1.5,
                          ),
                          color: _isLockedOut
                              ? Theme.of(context)
                                  .colorScheme
                                  .error
                                  .withValues(alpha: 0.3)
                              : (i < _pin.length
                                  ? copperColor
                                  : Colors.transparent),
                        ),
                      ),
                    ),
                  ),

                  if (_isLockedOut) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_clock_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.error),
                          const SizedBox(width: 8),
                          Text(
                            'Locked out! Try again in ${_lockoutSeconds}s',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_error || _errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _errorMessage ?? 'Incorrect code',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  if (_isVerifying)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(color: copperColor),
                    )
                  else
                    Opacity(
                      opacity: _isLockedOut ? 0.4 : 1.0,
                      child: GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: keys.map((k) {
                          final isSetup = k == 'SETUP';
                          final isBackspace = k == '⌫';
                          if (isSetup) {
                            if (effectiveUseStaticPin) {
                              return const SizedBox();
                            }
                            return GestureDetector(
                              onTap: () => _showSetupDialog(context),
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFD6E4FF),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.fingerprint_rounded,
                                  color: Color(0xFF1967D2),
                                  size: 26,
                                ),
                              ),
                            );
                          } else if (isBackspace) {
                            return GestureDetector(
                              onTap: () => _onKey('⌫'),
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.transparent,
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.backspace_outlined,
                                  size: 22,
                                ),
                              ),
                            );
                          } else {
                            return GestureDetector(
                              onTap: () => _onKey(k),
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.transparent,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  k,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          }
                        }).toList(),
                      ),
                    ),

                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => _showForgotPinDialog(context),
                    child: Text(
                      'Forgot PIN? Contact Super Admin',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminRecoveryDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const _AdminRecoveryDialog({required this.onSuccess});

  @override
  State<_AdminRecoveryDialog> createState() => _AdminRecoveryDialogState();
}

class _AdminRecoveryDialogState extends State<_AdminRecoveryDialog> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _codeCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Please enter your Backup Recovery Code.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AppAuthProvider>();
    final ok = await auth.verifyAndConsumeRecoveryCode(input);

    if (!mounted) return;

    if (ok) {
      Navigator.pop(context);
      widget.onSuccess();
    } else {
      setState(() {
        _loading = false;
        _error =
            'Invalid or already used Backup Recovery Code. Please verify your code and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_rounded, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text('Admin Emergency PIN Recovery',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: Container(
        width: 440,
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter one of your 8-character Backup Recovery Codes (e.g. A1B2-C3D4) to remove your current 6-digit PIN and set a new one.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeCtrl,
              enabled: !_loading,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Backup Recovery Code',
                hintText: 'e.g. A1B2-C3D4',
                prefixIcon: Icon(Icons.key_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton.icon(
          onPressed: _loading ? null : _submit,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.verified_user_rounded, size: 18),
          label: const Text('VERIFY & RESET PIN'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _SetNewPinDialog extends StatefulWidget {
  final VoidCallback onCompleted;
  const _SetNewPinDialog({required this.onCompleted});

  @override
  State<_SetNewPinDialog> createState() => _SetNewPinDialogState();
}

class _SetNewPinDialogState extends State<_SetNewPinDialog> {
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPin = _newPinCtrl.text.trim();
    final confirmPin = _confirmPinCtrl.text.trim();

    if (newPin.length != 6 || !RegExp(r'^\d{6}$').hasMatch(newPin)) {
      setState(() => _error = 'New PIN must be exactly 6 digits.');
      return;
    }

    if (newPin != confirmPin) {
      setState(() => _error = 'New 6-digit PINs do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AppAuthProvider>();
      await auth.updateUserPin(newPin);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '6-Digit Security PIN set successfully! You are now logged in. 🔑'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onCompleted();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to update PIN: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: Colors.purple),
          SizedBox(width: 8),
          Expanded(
            child: Text('Set New 6-Digit Admin PIN',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: Container(
        width: 440,
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your old PIN has been removed using your Recovery Code. Please enter and confirm a new 6-digit Security PIN to log in.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _newPinCtrl,
                enabled: !_loading,
                obscureText: _obscureNew,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'New 6-Digit Security PIN',
                  prefixIcon: const Icon(Icons.pin_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureNew ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPinCtrl,
                enabled: !_loading,
                obscureText: _obscureConfirm,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'Confirm New 6-Digit PIN',
                  prefixIcon: const Icon(Icons.check_circle_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
          ),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('SAVE PIN & LOG IN'),
        ),
      ],
    );
  }
}

