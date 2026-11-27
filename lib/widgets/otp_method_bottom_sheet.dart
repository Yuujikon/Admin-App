import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/otp_verification_screen.dart';
import '../shared/services/admin_messaging_service.dart';
import '../utils/email_validator.dart';
import '../utils/format.dart';

/// BottomSheet choice dialog prompting a user to select an OTP verification method:
/// [Send to Email], [Send to SMS], or optionally [Use Emergency Backup Code].
class OtpMethodBottomSheet extends StatefulWidget {
  final String? defaultEmail;
  final String? defaultPhone;
  final String? title;
  final String? subtitle;
  final bool showBackupCodeOption;
  final bool lockContactFields;
  final Future<void> Function()? onVerified;
  final Future<void> Function(bool verifiedViaEmail)? onVerifiedWithMethod;

  const OtpMethodBottomSheet({
    super.key,
    this.defaultEmail,
    this.defaultPhone,
    this.title,
    this.subtitle,
    this.showBackupCodeOption = true,
    this.lockContactFields = false,
    this.onVerified,
    this.onVerifiedWithMethod,
  });

  static Future<void> show(
    BuildContext context, {
    String? defaultEmail,
    String? defaultPhone,
    String? title,
    String? subtitle,
    bool showBackupCodeOption = true,
    bool lockContactFields = false,
    Future<void> Function()? onVerified,
    Future<void> Function(bool verifiedViaEmail)? onVerifiedWithMethod,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OtpMethodBottomSheet(
        defaultEmail: defaultEmail,
        defaultPhone: defaultPhone,
        title: title,
        subtitle: subtitle,
        showBackupCodeOption: showBackupCodeOption,
        lockContactFields: lockContactFields,
        onVerified: onVerified,
        onVerifiedWithMethod: onVerifiedWithMethod,
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
    _phoneCtrl = TextEditingController(text: widget.defaultPhone ?? '');
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

    final rawContact =
        isEmail ? _emailCtrl.text.trim() : _phoneCtrl.text.trim();

    if (isEmail) {
      final emailErr = EmailValidator.validate(rawContact);
      if (emailErr != null) {
        setState(() => _error = emailErr);
        return;
      }
    } else {
      final phoneErr = validatePhoneNumber(rawContact);
      if (phoneErr != null) {
        setState(() => _error = phoneErr);
        return;
      }
    }

    final contactMethod = isEmail ? rawContact.toLowerCase() : rawContact;

    setState(() {
      if (isEmail) {
        _loadingEmail = true;
      } else {
        _loadingSms = true;
      }
      _error = null;
    });

    try {
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
        final navigator = Navigator.of(context);
        navigator.pop(); // Close bottom sheet
        navigator.push(
          MaterialPageRoute(
            builder: (ctx) => OtpVerificationScreen(
              contactMethod: contactMethod,
              isEmail: isEmail,
              onVerified: () async {
                if (widget.onVerifiedWithMethod != null) {
                  await widget.onVerifiedWithMethod!(isEmail);
                } else if (widget.onVerified != null) {
                  await widget.onVerified!();
                }
              },
            ),
          ),
        );
      } else {
        setState(() {
          _error = res['message'] as String? ?? 'Failed to send OTP.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingEmail = false;
        _loadingSms = false;
        _error = 'Error sending OTP: $e';
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
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context); // Close bottom sheet
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Backup recovery code verified successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.onVerifiedWithMethod != null) {
          await widget.onVerifiedWithMethod!(false);
        } else if (widget.onVerified != null) {
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
    final primaryColor = theme.colorScheme.primary;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: bottomPadding + 24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
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
              widget.title ?? 'Select OTP Verification Method',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle ??
                  'Choose how you would like to receive your 6-digit verification code:',
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
                  color:
                      theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: theme.colorScheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_selectedMethod == null) ...[
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
                    backgroundColor: primaryColor,
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
                  icon: Icon(Icons.sms_rounded, color: primaryColor),
                  label: Text('Send to SMS',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: primaryColor)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: primaryColor, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (widget.showBackupCodeOption) ...[
                const SizedBox(height: 12),
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
              ],
            ] else if (_selectedMethod == 'email') ...[
              TextField(
                controller: _emailCtrl,
                autofocus: !widget.lockContactFields,
                readOnly: widget.lockContactFields,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _sendOtp(isEmail: true),
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: const Icon(Icons.email_outlined),
                  suffixIcon: widget.lockContactFields
                      ? const Icon(Icons.lock_outline_rounded, size: 18)
                      : null,
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                  isDense: true,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _loadingEmail ? null : () => _sendOtp(isEmail: true),
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
                    backgroundColor: primaryColor,
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
              TextField(
                controller: _phoneCtrl,
                autofocus: !widget.lockContactFields,
                readOnly: widget.lockContactFields,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _sendOtp(isEmail: false),
                decoration: InputDecoration(
                  labelText: 'Phone Number (SMS)',
                  hintText: '09123456789',
                  prefixIcon: const Icon(Icons.phone_android_outlined),
                  suffixIcon: widget.lockContactFields
                      ? const Icon(Icons.lock_outline_rounded, size: 18)
                      : null,
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                  isDense: true,
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _loadingSms ? null : () => _sendOtp(isEmail: false),
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
                    backgroundColor: primaryColor,
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
              TextField(
                controller: _backupCodeCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _verifyBackupCode(),
                decoration: InputDecoration(
                  labelText: 'Emergency Backup Code',
                  hintText: 'XXXX-XXXX',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: primaryColor, width: 2),
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
                    backgroundColor: primaryColor,
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
      ),
    );
  }
}
