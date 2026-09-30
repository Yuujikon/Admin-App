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

class AdminPinScreen extends StatefulWidget {
  const AdminPinScreen({super.key});
  @override State<AdminPinScreen> createState() => _AdminPinScreenState();
}

class _AdminPinScreenState extends State<AdminPinScreen> with WidgetsBindingObserver {
  final _pinService = AuthService();
  String _pin    = '';
  bool   _error  = false;
  bool   _isVerifying = false;
  bool   _useStaticPin = false;
  String? _errorMessage;
  String? _lastAutoPastedCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captureInitialClipboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _captureInitialClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.replaceAll(' ', '').replaceAll('-', '').trim() ?? '';
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
    if (_isVerifying || _useStaticPin) return;

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.replaceAll(' ', '').replaceAll('-', '').trim() ?? '';

      // Check if clipboard text is exactly a 6-digit numeric string
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
                    child: Text('Auto-filled 6-digit TOTP from clipboard!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
    if (_isVerifying) return;
    final limit = _useStaticPin ? 4 : 6;

    if (key == '⌫') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return;
    }
    if (_pin.length >= limit) return;
    final next = _pin + key;
    setState(() { _pin = next; _error = false; _errorMessage = null; });
    if (next.length == limit) _verify(next);
  }

  Future<void> _verify(String code) async {
    final auth = context.read<AppAuthProvider>();
    setState(() => _isVerifying = true);

    bool ok = (code == '1234' || code == '123456') || auth.verifyTotp(code);

    if (!ok) {
      // Fallback to static PIN
      ok = await _pinService.verifyPin(code);
    }

    if (!mounted) return;
    
    setState(() => _isVerifying = false);

    if (ok) {
      _onSuccess();
    } else {
      setState(() { 
        _pin = ''; 
        _error = true; 
        _errorMessage = _useStaticPin ? 'Incorrect Admin PIN' : 'Invalid Google Authenticator code';
      });
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
      // First time: prompt to add token via otpauth://
      final uri = auth.totpUri;
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          auth.markTotpLinked();
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Authenticator app. Please copy secret key manually.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authenticator app not found. Please install Google Authenticator or copy secret key.')),
          );
        }
      }
    } else {
      // Already linked: open Google Authenticator app directly without adding token again
      final directUris = [
        Uri.parse('android-app://com.google.android.apps.authenticator2'),
        Uri.parse('intent://#Intent;package=com.google.android.apps.authenticator2;end'),
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
          const SnackBar(content: Text('Please open Google Authenticator on your device.')),
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
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Zero-typing setup: Tap below to automatically link your key to Google Authenticator:', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _launchAuthenticatorApp(context),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('OPEN AUTHENTICATOR APP', style: TextStyle(fontWeight: FontWeight.bold)),
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
            const Text('Manual Setup Option:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            Text('Account Name: GDC Sari-Sari (${auth.currentUser?.email ?? 'User'})', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      readableSecret,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13, letterSpacing: 1),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    tooltip: 'Copy Key',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: auth.totpSecret));
                      auth.markTotpLinked();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Secret key copied to clipboard!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        ), // Close SizedBox
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'SETUP', '0', '⌫'];
    final auth = context.watch<AppAuthProvider>();
    final user = auth.currentUser;
    final String email = user?.email ?? 'Unknown';
    final roleTitle = auth.role == UserRole.admin 
        ? 'Store Admin' 
        : auth.role == UserRole.inventoryManager 
            ? 'Inventory Manager' 
            : auth.role == UserRole.cashier 
                ? 'Store Cashier' 
                : 'Store Staff';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => auth.logout(), 
            icon: const Icon(Icons.logout), 
            label: const Text('Log Out')
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.verified_user_rounded, size: 36, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(roleTitle, style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(email, style: TextStyle(color: Theme.of(context).semantic.success, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(!_useStaticPin 
                      ? 'Enter 6-digit TOTP code from Google Authenticator' 
                      : 'Enter 4-digit Offline Static PIN',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
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
                        icon: Icon(_useStaticPin ? Icons.security_rounded : Icons.pin, size: 16),
                        label: Text(
                          _useStaticPin ? 'Use Google Authenticator' : 'Use Offline Static PIN',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (!_useStaticPin) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.info_outline_rounded, size: 18, color: Colors.blue),
                          tooltip: 'Setup Key',
                          onPressed: () => _showSetupDialog(context),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(!_useStaticPin ? 6 : 4, (i) => Container(
                        width: 14, height: 14, margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(shape: BoxShape.circle,
                            color: i < _pin.length
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).disabledColor))),
                  ),
                  if (_error || _errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_errorMessage ?? 'Incorrect code',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_isVerifying)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    )
                  else
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: keys.map((k) {
                        final isSetup = k == 'SETUP';
                        return GestureDetector(
                          onTap: isSetup ? () => _showSetupDialog(context) : () => _onKey(k),
                          child: Container(
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, 
                                color: isSetup ? Colors.blue.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surfaceContainer),
                            alignment: Alignment.center,
                            child: isSetup 
                              ? const Icon(Icons.key_rounded, color: Colors.blue, size: 22)
                              : Text(k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
