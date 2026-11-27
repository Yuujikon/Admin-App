import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../shared/services/admin_messaging_service.dart';
import '../utils/email_validator.dart';
import '../utils/format.dart';
import '../widgets/otp_method_bottom_sheet.dart';
import '../widgets/premium_components.dart';

/// Login and self-registration authentication screen for store staff and store admin accounts.
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirmPass = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();

  bool _isRegistering = false;
  bool _submitted = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  bool _suggestSignIn = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _confirmPass.dispose();
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _setMode(bool registering) {
    if (_loading || _isRegistering == registering) return;
    setState(() {
      _isRegistering = registering;
      _submitted = false;
      _error = null;
      _suggestSignIn = false;
    });
    _formKey.currentState?.reset();
  }

  void _clearErrorOnEdit() {
    if (_error != null || _suggestSignIn) {
      setState(() {
        _error = null;
        _suggestSignIn = false;
      });
    }
  }

  ({double score, String label, Color color}) _evaluatePasswordStrength(
      String password) {
    if (password.isEmpty) {
      return (score: 0, label: '', color: Colors.transparent);
    }
    int points = 0;
    if (password.length >= 6) points++;
    if (password.length >= 10) points++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      points++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) points++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>_\-]').hasMatch(password)) points++;

    if (password.length < 6 || points <= 1) {
      return (score: 0.25, label: 'Weak', color: Colors.red);
    }
    if (points == 2) {
      return (score: 0.5, label: 'Fair', color: Colors.orange);
    }
    if (points == 3) {
      return (score: 0.75, label: 'Good', color: Colors.blue);
    }
    return (score: 1.0, label: 'Strong', color: Colors.green);
  }

  String _mapAuthError(FirebaseAuthException e, {required bool isRegister}) {
    return switch (e.code) {
      'user-not-found' => 'No account found with this email address.',
      'wrong-password' => 'Incorrect password. Please try again.',
      'invalid-credential' =>
        'Invalid email or password. Please check your credentials.',
      'invalid-email' => 'Please enter a valid email address.',
      'user-disabled' =>
        'This account has been disabled. Please contact the Store Admin.',
      'too-many-requests' =>
        'Too many failed attempts. Please wait a few minutes and try again.',
      'network-request-failed' =>
        'Network error. Please check your internet connection and try again.',
      'email-already-in-use' =>
        'An account with this email already exists. Try signing in instead.',
      'weak-password' =>
        'Password is too weak. Please use at least 6 characters with letters and numbers.',
      'operation-not-allowed' =>
        'This sign-in method is currently disabled. Contact the Store Admin.',
      'account-exists-with-different-credential' =>
        'An account already exists with this email using a different sign-in method.',
      _ => e.message ??
          (isRegister
              ? 'Registration failed. Please try again.'
              : 'Login failed. Please check your credentials.'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strength =
        _isRegistering ? _evaluatePasswordStrength(_pass.text) : null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: MaxWidthContainer(
              maxWidth: 440,
              alignment: Alignment.center,
              child: PremiumCard(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    autovalidateMode: _submitted
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.storefront_rounded,
                            size: 44,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'GDC Staff Portal',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isRegistering
                              ? 'Request Store Staff Account Access'
                              : 'Sign in to access POS or Admin Dashboard',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Mode Selector Pill (Sign In / Register)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _ModeTabButton(
                                  label: 'Sign In',
                                  selected: !_isRegistering,
                                  enabled: !_loading,
                                  onTap: () => _setMode(false),
                                ),
                              ),
                              Expanded(
                                child: _ModeTabButton(
                                  label: 'Register',
                                  selected: _isRegistering,
                                  enabled: !_loading,
                                  onTap: () => _setMode(true),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        if (_isRegistering) ...[
                          // Info banner for registration
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer
                                  .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    colorScheme.primary.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: colorScheme.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Registration requires Store Admin review & approval. Once accepted, your account will be activated as a Trusted Partner.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Full Name
                          TextFormField(
                            controller: _fullName,
                            enabled: !_loading,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            onChanged: (_) => _clearErrorOnEdit(),
                            validator: (val) {
                              final trimmed = val?.trim() ?? '';
                              if (trimmed.isEmpty) {
                                return 'Please enter your full name.';
                              }
                              if (trimmed.length < 2) {
                                return 'Full name must be at least 2 characters.';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              hintText: 'e.g. Juan Dela Cruz',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Phone Number
                          TextFormField(
                            controller: _phone,
                            enabled: !_loading,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.telephoneNumber
                            ],
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9+\-\s()]')),
                              LengthLimitingTextInputFormatter(18),
                            ],
                            onChanged: (_) => _clearErrorOnEdit(),
                            validator: validatePhoneNumber,
                            decoration: const InputDecoration(
                              labelText: 'Contact Phone Number (SMS OTP)',
                              hintText: '09123456789',
                              prefixIcon: Icon(Icons.phone_android_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Email Address
                        TextFormField(
                          controller: _email,
                          enabled: !_loading,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          onChanged: (_) => _clearErrorOnEdit(),
                          validator: EmailValidator.validate,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            hintText: 'staff@example.com',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Password
                        TextFormField(
                          controller: _pass,
                          enabled: !_loading,
                          obscureText: _obscurePass,
                          textInputAction: _isRegistering
                              ? TextInputAction.next
                              : TextInputAction.done,
                          autofillHints: [
                            _isRegistering
                                ? AutofillHints.newPassword
                                : AutofillHints.password
                          ],
                          onChanged: (_) {
                            _clearErrorOnEdit();
                            if (_isRegistering) setState(() {});
                          },
                          onFieldSubmitted: (_) {
                            if (!_isRegistering) _login();
                          },
                          validator: (val) {
                            final trimmed = val?.trim() ?? '';
                            if (trimmed.isEmpty) {
                              return 'Please enter your password.';
                            }
                            if (_isRegistering && trimmed.length < 6) {
                              return 'Password must be at least 6 characters long.';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscurePass
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(_obscurePass
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () =>
                                  setState(() => _obscurePass = !_obscurePass),
                            ),
                          ),
                        ),

                        if (_isRegistering &&
                            strength != null &&
                            strength.score > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: strength.score,
                                    minHeight: 5,
                                    backgroundColor: colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        strength.color),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                strength.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: strength.color,
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (_isRegistering) ...[
                          const SizedBox(height: 14),
                          // Confirm Password
                          TextFormField(
                            controller: _confirmPass,
                            enabled: !_loading,
                            obscureText: _obscureConfirm,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.newPassword],
                            onChanged: (_) => _clearErrorOnEdit(),
                            onFieldSubmitted: (_) => _register(),
                            validator: (val) {
                              final trimmed = val?.trim() ?? '';
                              if (trimmed.isEmpty) {
                                return 'Please confirm your password.';
                              }
                              if (trimmed != _pass.text.trim()) {
                                return 'Passwords do not match.';
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              prefixIcon: const Icon(Icons.lock_reset_outlined),
                              suffixIcon: IconButton(
                                tooltip: _obscureConfirm
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(_obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm),
                              ),
                            ),
                          ),
                        ],

                        if (!_isRegistering) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed:
                                  _loading ? null : _showForgotPasswordDialog,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                              ),
                              child: Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],

                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: colorScheme.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.error_outline_rounded,
                                      size: 18,
                                      color: colorScheme.error,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: colorScheme.error,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_suggestSignIn) ...[
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => _setMode(false),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      child: const Text(
                                        'Switch to Sign In',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        PrimaryButton(
                          onPressed: _loading
                              ? null
                              : (_isRegistering ? _register : _login),
                          isLoading: _loading,
                          minWidth: double.infinity,
                          maxWidth: double.infinity,
                          child: Text(
                            _isRegistering
                                ? 'SUBMIT REGISTRATION'
                                : 'SIGN IN TO PORTAL',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),

                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Google Sign-In Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _googleSignIn,
                            icon: const _GoogleLogoIcon(size: 20),
                            label: Text(
                              _isRegistering
                                  ? 'Register with Google'
                                  : 'Sign in with Google',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Toggle Register / Sign In link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isRegistering
                                  ? 'Already registered?'
                                  : "Don't have an account?",
                              style: const TextStyle(fontSize: 13),
                            ),
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => _setMode(!_isRegistering),
                              child: Text(
                                _isRegistering
                                    ? 'Sign In Here'
                                    : 'Register Here',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (_loading) return;

    setState(() {
      _submitted = true;
      _error = null;
      _suggestSignIn = false;
    });

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final email = _email.text.trim();
    final pass = _pass.text.trim();

    setState(() {
      _loading = true;
    });

    try {
      final auth = context.read<AppAuthProvider>();
      await auth.login(email, pass);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _mapAuthError(e, isRegister: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Login failed. Please check your credentials and try again.';
      });
    }
  }

  Future<void> _register() async {
    if (_loading) return;

    setState(() {
      _submitted = true;
      _error = null;
      _suggestSignIn = false;
    });

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final name = _fullName.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim().toLowerCase();
    final pass = _pass.text.trim();

    // Prompt user with BottomSheet choice: [Send to Email] or [Send to SMS]
    await OtpMethodBottomSheet.show(
      context,
      defaultEmail: email,
      defaultPhone: phone,
      title: 'Verify Your Contact Info',
      subtitle:
          'Choose how you would like to receive your 6-digit registration verification code:',
      showBackupCodeOption: false,
      lockContactFields: true,
      onVerifiedWithMethod: (bool verifiedViaEmail) async {
        if (!mounted) return;
        setState(() {
          _loading = true;
          _error = null;
          _suggestSignIn = false;
        });
        try {
          final auth = context.read<AppAuthProvider>();
          await auth.registerEmployee(
            name: name,
            email: email,
            password: pass,
            phoneNumber: phone,
            requestedRole: 'trustedPartner',
            verifiedViaEmailOtp: verifiedViaEmail,
          );
        } on FirebaseAuthException catch (e) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = _mapAuthError(e, isRegister: true);
            _suggestSignIn = e.code == 'email-already-in-use';
          });
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Error registering account: $e';
          });
        }
      },
    );
  }

  Future<void> _googleSignIn() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _suggestSignIn = false;
    });

    try {
      final auth = context.read<AppAuthProvider>();
      final result = await auth.signInWithGoogle();

      if (!mounted) return;
      if (result == GoogleSignInResult.cancelled) {
        setState(() => _loading = false);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _mapAuthError(e, isRegister: _isRegistering);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Google sign-in failed. Please try again.';
      });
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailCtrl = TextEditingController(text: _email.text.trim());
    final resetFormKey = GlobalKey<FormState>();
    bool sending = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submitReset() async {
            if (sending) return;
            if (!(resetFormKey.currentState?.validate() ?? false)) return;

            final email = resetEmailCtrl.text.trim().toLowerCase();
            setDialogState(() {
              sending = true;
              dialogError = null;
            });

            try {
              await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

              // Dispatch branded HTML email via Brevo as non-blocking enhancement
              AdminMessagingService()
                  .sendBrandedPasswordResetEmail(toEmail: email)
                  .catchError((e) {
                debugPrint('Optional branded reset email failed: $e');
                return false;
              });

              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Password reset link sent to $email. Please check your inbox and spam folder.'),
                    backgroundColor: Colors.green.shade700,
                  ),
                );
              }
            } on FirebaseAuthException catch (e) {
              if (ctx.mounted) {
                setDialogState(() {
                  sending = false;
                  dialogError = switch (e.code) {
                    'user-not-found' =>
                      'No account found with this email address.',
                    'invalid-email' => 'Please enter a valid email address.',
                    'too-many-requests' =>
                      'Too many reset requests. Please wait a few minutes.',
                    'network-request-failed' =>
                      'Network error. Check your internet connection.',
                    _ => e.message ?? 'Could not send password reset email.',
                  };
                });
              }
            } catch (_) {
              if (ctx.mounted) {
                setDialogState(() {
                  sending = false;
                  dialogError =
                      'Could not send password reset email. Please try again.';
                });
              }
            }
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.lock_reset_rounded),
                SizedBox(width: 8),
                Text('Reset Password',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Form(
              key: resetFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter the email address associated with your staff account and we will send you a password reset link.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: resetEmailCtrl,
                    enabled: !sending,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => submitReset(),
                    validator: EmailValidator.validate,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                      isDense: true,
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: sending ? null : submitReset,
                child: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('SEND RESET LINK'),
              ),
            ],
          );
        },
      ),
    );

    resetEmailCtrl.dispose();
  }
}

class _ModeTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeTabButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Crisp vector Google "G" emblem so Google Sign-In works offline without broken SVG network requests.
class _GoogleLogoIcon extends StatelessWidget {
  final double size;
  const _GoogleLogoIcon({this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300, width: 0.8),
      ),
      alignment: Alignment.center,
      child: Text(
        'G',
        style: TextStyle(
          fontSize: size * 0.68,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF4285F4),
          height: 1,
        ),
      ),
    );
  }
}
