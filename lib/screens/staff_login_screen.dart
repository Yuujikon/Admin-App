import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/premium_components.dart';

/// Login and self-registration authentication screen for store staff and store admin accounts.
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirmPass = TextEditingController();
  final _fullName = TextEditingController();

  String _requestedRole = 'cashier';
  bool _isRegistering = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _confirmPass.dispose();
    _fullName.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isRegistering = !_isRegistering;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: MaxWidthContainer(
            maxWidth: MaxWidthContainer.authMaxWidth,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.storefront,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'GDC Staff Portal',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isRegistering
                      ? 'Request Staff Account Access'
                      : 'Sign in to access POS or Dashboard',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),

                if (_isRegistering) ...[
                  // Info banner for registration
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Registration requires a valid email and Store Admin approval before system access is granted.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Full Name
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: _fullName,
                      enabled: !_loading,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Email Address
                SizedBox(
                  width: double.infinity,
                  child: TextField(
                    controller: _email,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(height: 16),

                // Password
                SizedBox(
                  width: double.infinity,
                  child: TextField(
                    controller: _pass,
                    enabled: !_loading,
                    obscureText: _obscurePass,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePass
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                  ),
                ),

                if (_isRegistering) ...[
                  const SizedBox(height: 16),
                  // Confirm Password
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: _confirmPass,
                      enabled: !_loading,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Requested Role
                  SizedBox(
                    width: double.infinity,
                    child: DropdownButtonFormField<String>(
                      value: _requestedRole,
                      decoration: const InputDecoration(
                        labelText: 'Requested Position',
                        prefixIcon: Icon(Icons.work_outline),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'cashier',
                          child: Text('Cashier (POS & Pre-Orders)'),
                        ),
                        DropdownMenuItem(
                          value: 'inventoryManager',
                          child: Text('Inventory Manager (Stock & Suppliers)'),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('Store Admin (Full Management)'),
                        ),
                      ],
                      onChanged: _loading
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _requestedRole = v);
                              }
                            },
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                PrimaryButton(
                  onPressed: _loading
                      ? null
                      : (_isRegistering ? _register : _login),
                  isLoading: _loading,
                  minWidth: 200,
                  maxWidth: 350,
                  child: Text(
                    _isRegistering
                        ? 'SUBMIT REGISTRATION'
                        : 'SIGN IN TO PORTAL',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                if (!_isRegistering) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _resetPassword,
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),

                // Google Sign-In Button
                OutlinedButton.icon(
                  onPressed: _loading ? null : _googleSignIn,
                  icon: Image.network(
                    'https://auth.gfx.ms/16.000.30392.00/images/Google.svg',
                    height: 18,
                    width: 18,
                    errorBuilder: (ctx, err, stack) =>
                        const Icon(Icons.g_mobiledata_rounded, size: 24),
                  ),
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
                    minimumSize: const Size(200, 48),
                    maximumSize: const Size(350, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

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
                      onPressed: _loading ? null : _toggleMode,
                      child: Text(
                        _isRegistering ? 'Sign In Here' : 'Register Here',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
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
    );
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final pass = _pass.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter both email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AppAuthProvider>();
      await auth.login(email, pass);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'user-not-found' => 'No account found with this email.',
          'wrong-password' => 'Incorrect password.',
          'invalid-credential' => 'Invalid login credentials.',
          'invalid-email' => 'Please enter a valid email address.',
          _ => e.message ?? 'Login failed. Check your credentials.',
        };
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Login failed. Please check your credentials.';
      });
    }
  }

  Future<void> _register() async {
    final name = _fullName.text.trim();
    final email = _email.text.trim();
    final pass = _pass.text.trim();
    final confirm = _confirmPass.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }

    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters long.');
      return;
    }

    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AppAuthProvider>();
      await auth.registerEmployee(
        name: name,
        email: email,
        password: pass,
        requestedRole: _requestedRole,
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'email-already-in-use' =>
            'An account with this email already exists.',
          'invalid-email' => 'Invalid email address format.',
          'weak-password' => 'Password is too weak. Try a stronger password.',
          _ => e.message ?? 'Registration failed. Try again.',
        };
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error registering account: $e';
      });
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AppAuthProvider>();
      final isReturning = await auth.signInWithGoogle();

      if (!isReturning && mounted) {
        // First-time Google registrant needs to set full name and requested role
        setState(() => _loading = false);
        await _showGoogleProfileDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Google sign-in cancelled or failed.';
        });
      }
    }
  }

  Future<void> _showGoogleProfileDialog() async {
    final auth = context.read<AppAuthProvider>();
    final googleUser = auth.currentUser;
    final nameCtrl =
        TextEditingController(text: googleUser?.displayName ?? '');
    String selectedRole = 'cashier';

    await showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_pin_rounded),
              SizedBox(width: 8),
              Text('Complete Profile',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please confirm your details and requested position for Store Admin approval.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Requested Position',
                  prefixIcon: Icon(Icons.work_outline),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'cashier',
                    child: Text('Cashier (POS & Pre-Orders)'),
                  ),
                  DropdownMenuItem(
                    value: 'inventoryManager',
                    child: Text('Inventory Manager (Stock & Suppliers)'),
                  ),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Store Admin (Full Management)'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setSt(() => selectedRole = v);
                },
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                setState(() => _loading = true);
                await auth.completeGoogleRegistration(
                  name: name,
                  requestedRole: selectedRole,
                );
              },
              child: const Text('SUBMIT REQUEST'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent! Check your inbox.'),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not send password reset email.');
    }
  }
}
