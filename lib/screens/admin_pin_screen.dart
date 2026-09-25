import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/order_provider.dart';
import '../services/auth_service.dart';
import '../utils/format.dart';
import '../config/theme.dart';

class AdminPinScreen extends StatefulWidget {
  const AdminPinScreen({super.key});
  @override State<AdminPinScreen> createState() => _AdminPinScreenState();
}

class _AdminPinScreenState extends State<AdminPinScreen> {
  final _pinService = AuthService();
  String _pin    = '';
  bool   _error  = false;
  bool   _isSending = false;
  bool   _useStaticPin = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendOtp());
  }

  Future<void> _sendOtp() async {
    final auth = context.read<AppAuthProvider>();
    
    if (auth.phoneNumber == null || auth.phoneNumber!.isEmpty) {
      setState(() => _useStaticPin = true);
      return;
    }

    // Ensure E.164 format for Firebase
    final phone = formatPhoneNumber(auth.phoneNumber!);

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    // Safety timeout: Never let the spinner run for more than 6 seconds
    Timer(const Duration(seconds: 6), () {
      if (mounted && _isSending) {
        setState(() => _isSending = false);
      }
    });
    
    await auth.sendOtp(
      phone,
      onSent: () {
        if (mounted) {
          setState(() => _isSending = false);
        }
      },
      onFailed: (err) {
        if (mounted) {
          setState(() {
            _isSending = false;
            _errorMessage = err;
          });
        }
      }
    );
  }

  void _onKey(String key) {
    if (_isSending) return;
    final auth = context.read<AppAuthProvider>();
    final isOtp = !_useStaticPin && auth.phoneNumber != null && auth.phoneNumber!.isNotEmpty;
    final limit = isOtp ? 6 : 4;

    if (key == '⌫') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return;
    }
    if (_pin.length >= limit) return;
    final next = _pin + key;
    setState(() { _pin = next; _error = false; });
    if (next.length == limit) _verify(next);
  }

  Future<void> _verify(String pin) async {
    final auth = context.read<AppAuthProvider>();
    
    bool ok = false;
    if (!_useStaticPin && auth.phoneNumber != null && auth.phoneNumber!.isNotEmpty) {
      setState(() => _isSending = true);
      ok = await auth.verifyOtp(pin);
    }
    
    if (!ok) {
      // Fallback to static PIN
      ok = await _pinService.verifyPin(pin);
    }

    if (!mounted) return;
    
    setState(() => _isSending = false);

    if (ok) {
      _onSuccess();
    } else {
      setState(() { _pin = ''; _error = true; });
    }
  }

  void _onSuccess() {
    final auth = context.read<AppAuthProvider>();
    if (auth.currentUser != null) {
      final email = auth.currentUser!.email!;
      context.read<InventoryProvider>().setAdminEmail(email);
      context.read<OrderProvider>().setAdminName(email);
      auth.setAdminVerified(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'RESEND', '0', '⌫'];
    final auth = context.watch<AppAuthProvider>();
    final user = auth.currentUser;
    final String email = user?.email ?? 'Unknown';
    final bool isIdentified = user != null && user.email == "markjeo.hinampas@gmail.com";

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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(isIdentified ? Icons.admin_panel_settings : Icons.person_search_outlined, size: 36,
                        color: isIdentified ? Theme.of(context).colorScheme.primary : Theme.of(context).semantic.warning),
                  ),
                  const SizedBox(height: 16),
                  Text('GDC Admin', style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(email, style: TextStyle(color: Theme.of(context).semantic.success, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(!_useStaticPin && auth.phoneNumber != null && auth.phoneNumber!.isNotEmpty 
                      ? 'Enter the 6-digit OTP sent to your phone' 
                      : 'Enter your Admin PIN to continue',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _useStaticPin = !_useStaticPin;
                      _pin = '';
                    }),
                    icon: Icon(_useStaticPin ? Icons.phone_android : Icons.pin, size: 16),
                    label: Text(_useStaticPin ? 'Switch to Phone OTP SMS' : 'Use Offline Static PIN', style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(!_useStaticPin && auth.phoneNumber != null && auth.phoneNumber!.isNotEmpty ? 6 : 4, (i) => Container(
                        width: 14, height: 14, margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(shape: BoxShape.circle,
                            color: i < _pin.length
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).disabledColor))),
                  ),
                  if (_error || _errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(_errorMessage ?? 'Incorrect OTP code',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_isSending)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    )
                  else
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: keys.map((k) {
                        if (k.isEmpty) return const SizedBox();
                        
                        final isResend = k == 'RESEND';
                        return GestureDetector(
                          onTap: isResend ? _sendOtp : () => _onKey(k),
                          child: Container(
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, 
                                color: isResend ? Theme.of(context).semantic.warning.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surfaceContainer),
                            alignment: Alignment.center,
                            child: isResend 
                              ? Icon(Icons.refresh, color: Theme.of(context).semantic.warning, size: 24)
                              : Text(k, style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w500)),
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
