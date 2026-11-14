import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/otp_verification_screen.dart';
import '../shared/services/admin_messaging_service.dart';

/// BottomSheet choice dialog prompting admin user to select verification method:
/// [Send to Email], [Send to SMS], or [Use Emergency Backup Code].
class OtpMethodBottomSheet extends StatefulWidget {
  final String? defaultEmail;
  final String? defaultPhone;
  final Future<void> Function()? onVerified;

  const OtpMethodBottomSheet({
    super.key,
    this.defaultEmail,
    this.defaultPhone,
    this.onVerified,
  });

  static Future<void> show(
    BuildContext context, {
    String? defaultEmail,
    String? defaultPhone,
    Future<void> Function()? onVerified,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OtpMethodBottomSheet(
        defaultEmail: defaultEmail,
        defaultPhone: defaultPhone,
        onVerified: onVerified,
      ),
    );
  }

  @override
  State<OtpMethodBottomSheet> createState() => _OtpMethodBottomSheetState();
}

class _OtpMethodBottomSheetState extends State<OtpMethodBottomSheet> {
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _backupCodeCtrl;
  final _messagingService = AdminMessagingService();

  String? _selectedMethod; // null (initial), 'email', 'sms', or 'backup'
  bool _loadingEmail = false;
  bool _loadingSms = false;
  bool _loadingBackup = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.defaultEmail ?? '');
    _phoneCtrl =
        TextEditingController(text: widget.defaultPhone ?? '09558297358');
    _backupCodeCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _backupCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp({required bool isEmail}) async {
    if (_loadingEmail || _loadingSms) return;

    final contactMethod =
        isEmail ? _emailCtrl.text.trim() : _phoneCtrl.text.trim();

    if (contactMethod.isEmpty) {
      setState(() {
        _error = isEmail
            ? 'Please enter a valid email address.'
            : 'Please enter a valid contact phone number.';
      });
      return;
    }

    setState(() {
      if (isEmail) {
        _loadingEmail = true;
      } else {
        _loadingSms = true;
      }
      _error = null;
    });

    final res = await _messagingService.sendAdminOtp(
      contactMethod: contactMethod,
      isEmail: isEmail,
    );

    if (!mounted) return;

    setState(() {
      _loadingEmail = false;
      _loadingSms = false;
    });

    if (res['success'] == true) {
      Navigator.pop(context); // Close bottom sheet
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => OtpVerificationScreen(
            contactMethod: contactMethod,
            isEmail: isEmail,
            onVerified: widget.onVerified,
          ),
        ),
      );
    } else {
      setState(() {
        _error = res['message'] as String? ?? 'Failed to send OTP.';
      });
    }
  }

  Future<void> _verifyBackupCode() async {
    if (_loadingBackup) return;

    final code = _backupCodeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error =
            'Please enter your 8-character emergency backup recovery code.';
      });
      return;
    }

    setState(() {
      _loadingBackup = true;
      _error = null;
    });

    try {
      final auth = context.read<AppAuthProvider>();
      final ok = await auth.verifyAndConsumeRecoveryCode(code);

      if (!mounted) return;

      setState(() {
        _loadingBackup = false;
      });

      if (ok) {
        Navigator.pop(context); // Close bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup recovery code verified successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.onVerified != null) {
          await widget.onVerified!();
        }
      } else {
        setState(() {
          _error =
              'Invalid emergency backup code. Please check your 8-character recovery code.';
          _backupCodeCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBackup = false;
          _error = 'Error verifying backup code: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    const copperColor = Color(0xFFC07038);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: bottomPadding + 24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Select OTP Verification Method',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Choose how you would like to receive your 6-digit Admin verification code:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (_selectedMethod == null) ...[
            // Initial option buttons (No input fields shown)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedMethod = 'email';
                    _error = null;
                  });
                },
                icon: const Icon(Icons.mark_email_read_rounded),
                label: const Text('Send to Email',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: copperColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedMethod = 'sms';
                    _error = null;
                  });
                },
                icon: const Icon(Icons.sms_rounded, color: copperColor),
                label: const Text('Send to SMS',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: copperColor)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: copperColor, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Emergency Backup Code Option
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedMethod = 'backup';
                    _error = null;
                  });
                },
                icon: const Icon(Icons.vpn_key_outlined, size: 18),
                label: const Text('Use Emergency Backup Code',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ] else if (_selectedMethod == 'email') ...[
            // Reveal email input when 'Send to Email' is clicked
            TextField(
              controller: _emailCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: copperColor, width: 2),
                ),
                isDense: true,
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadingEmail ? null : () => _sendOtp(isEmail: true),
                icon: _loadingEmail
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('CONFIRM & SEND EMAIL OTP',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: copperColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            TextButton.icon(
              onPressed: _loadingEmail
                  ? null
                  : () {
                      setState(() {
                        _selectedMethod = null;
                        _error = null;
                      });
                    },
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Change Verification Method'),
            ),
          ] else if (_selectedMethod == 'sms') ...[
            // Reveal phone input when 'Send to SMS' is clicked
            TextField(
              controller: _phoneCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Phone Number (SMS)',
                prefixIcon: Icon(Icons.phone_android_outlined),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: copperColor, width: 2),
                ),
                isDense: true,
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadingSms ? null : () => _sendOtp(isEmail: false),
                icon: _loadingSms
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('CONFIRM & SEND SMS OTP',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: copperColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            TextButton.icon(
              onPressed: _loadingSms
                  ? null
                  : () {
                      setState(() {
                        _selectedMethod = null;
                        _error = null;
                      });
                    },
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Change Verification Method'),
            ),
          ] else if (_selectedMethod == 'backup') ...[
            // Reveal backup code input when 'Use Emergency Backup Code' is clicked
            TextField(
              controller: _backupCodeCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Emergency Backup Code',
                hintText: 'XXXX-XXXX',
                prefixIcon: Icon(Icons.vpn_key_outlined),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: copperColor, width: 2),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadingBackup ? null : _verifyBackupCode,
                icon: _loadingBackup
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.shield_outlined),
                label: const Text('VERIFY BACKUP CODE',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: copperColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            TextButton.icon(
              onPressed: _loadingBackup
                  ? null
                  : () {
                      setState(() {
                        _selectedMethod = null;
                        _error = null;
                      });
                    },
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Change Verification Method'),
            ),
          ],
        ],
      ),
    );
  }
}
