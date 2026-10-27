import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/order_provider.dart';
import '../services/auth_service.dart';
import '../config/theme.dart';
import '../utils/totp.dart';

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
    final limit = _useStaticPin ? 4 : 6;

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
    setState(() => _isVerifying = true);

    bool ok = false;
    if (_useStaticPin) {
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
          launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                        Clipboard.setData(ClipboardData(text: auth.totpSecret));
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
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Text('Forgot Security PIN?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Security PIN resets must be authorized by a Super Admin or requested via your store account owner (markjeo.hinampas@gmail.com).\n\nAlternatively, use Google Authenticator 2FA code to log in directly.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
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
    final user = auth.currentUser;
    final String email = user?.email ?? 'Unknown';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
              onPressed: () => auth.logout(),
              icon: const Icon(Icons.logout),
              label: const Text('Log Out')),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Store Branding Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'GDC SARI-SARI STORE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _useStaticPin ? 'Enter Admin PIN' : 'Enter 6-Digit Code',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Verification required to access financial & staff settings',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      auth.userFullName != null && auth.userFullName!.isNotEmpty
                          ? '${auth.userFullName} ($email)'
                          : email,
                      style: TextStyle(
                          color: Theme.of(context).semantic.success,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _useStaticPin = !_useStaticPin;
                          _pin = '';
                          _errorMessage = null;
                        }),
                        icon: Icon(
                            _useStaticPin
                                ? Icons.security_rounded
                                : Icons.pin_rounded,
                            size: 16),
                        label: Text(
                          _useStaticPin
                              ? 'Use Google Authenticator'
                              : 'Use 4-Digit Offline PIN',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (!_useStaticPin) ...[
                        IconButton(
                          icon: const Icon(Icons.info_outline_rounded,
                              size: 18, color: Colors.blue),
                          tooltip: 'Setup Key',
                          onPressed: () => _showSetupDialog(context),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  // PIN Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                        !_useStaticPin ? 6 : 4,
                        (i) => Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _isLockedOut
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary,
                                    width: 1.5),
                                color: _isLockedOut
                                    ? Theme.of(context)
                                        .colorScheme
                                        .error
                                        .withValues(alpha: 0.3)
                                    : (i < _pin.length
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent)))),
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
                  const SizedBox(height: 20),
                  if (_isVerifying)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary),
                    )
                  else
                    Opacity(
                      opacity: _isLockedOut ? 0.4 : 1.0,
                      child: GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        children: keys.map((k) {
                          final isSetup = k == 'SETUP';
                          return GestureDetector(
                            onTap: isSetup
                                ? () => _showSetupDialog(context)
                                : () => _onKey(k),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSetup
                                    ? Colors.blue.withValues(alpha: 0.1)
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHigh,
                              ),
                              alignment: Alignment.center,
                              child: isSetup
                                  ? const Icon(Icons.fingerprint_rounded,
                                      color: Colors.blue, size: 24)
                                  : Text(
                                      k,
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold),
                                    ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => _showForgotPinDialog(context),
                    child: Text(
                      'Forgot PIN? Contact Super Admin',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600),
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
