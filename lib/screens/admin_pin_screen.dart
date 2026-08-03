import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../services/auth_service.dart';
import '../config/theme.dart';

class AdminPinScreen extends StatefulWidget {
  const AdminPinScreen({super.key});
  @override State<AdminPinScreen> createState() => _AdminPinScreenState();
}

class _AdminPinScreenState extends State<AdminPinScreen> {
  final _pinService = AuthService();
  String _pin    = '';
  bool   _error  = false;
  String? _currentOtp;
  bool   _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendOtp());
  }

  Future<void> _sendOtp() async {
    final auth = context.read<AppAuthProvider>();
    if (auth.phoneNumber == null || auth.phoneNumber!.isEmpty) {
      // If no phone number, we fallback to the static PIN 1234
      // but warn the user.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number set. Using default PIN 1234.'))
      );
      return;
    }

    setState(() => _isSending = true);
    
    // Generate a random 4-digit code
    final otp = (1000 + (DateTime.now().millisecond * 9) % 9000).toString();
    _currentOtp = otp;

    // Simulate SMS Sending
    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SMS Sent to ${auth.phoneNumber}: $otp'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        )
      );
      setState(() => _isSending = false);
    }
  }

  void _onKey(String key) {
    if (_isSending) return;
    if (key == '⌫') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return;
    }
    if (_pin.length >= 4) return;
    final next = _pin + key;
    setState(() { _pin = next; _error = false; });
    if (next.length == 4) _verify(next);
  }

  Future<void> _verify(String pin) async {
    final auth = context.read<AppAuthProvider>();
    
    bool ok = false;
    if (auth.phoneNumber != null && auth.phoneNumber!.isNotEmpty) {
      // Check against the dynamic OTP
      ok = pin == _currentOtp;
    } else {
      // Fallback to static PIN
      ok = await _pinService.verifyPin(pin);
    }

    if (!mounted) return;
    
    if (ok) {
      _onSuccess();
    } else {
      setState(() { _pin = ''; _error = true; });
    }
  }

  void _onSuccess() {
    final auth = context.read<AppAuthProvider>();
    if (auth.currentUser != null) {
      context.read<InventoryProvider>().setAdminEmail(auth.currentUser!.email!);
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
      body: Center(
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
                Text(auth.phoneNumber != null && auth.phoneNumber!.isNotEmpty 
                    ? 'Enter the OTP sent to your phone' 
                    : 'Enter your PIN to continue',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) => Container(
                      width: 16, height: 16, margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          color: i < _pin.length
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).disabledColor))),
                ),
                if (_error) ...[
                  const SizedBox(height: 8),
                  Text('Incorrect OTP/PIN',
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
