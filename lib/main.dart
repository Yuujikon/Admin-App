import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'config/theme.dart';
import 'providers/inventory_provider.dart';
import 'providers/order_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/printer_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/restock_provider.dart';
import 'providers/shift_provider.dart';
import 'providers/procurement_provider.dart';
import 'screens/staff_login_screen.dart';
import 'screens/admin_pin_screen.dart';
import 'screens/admin_app.dart';

import 'services/notification_service.dart';
import 'shared/services/time_service.dart';
import 'utils/admin_seeder.dart';
import 'utils/format.dart';

/// Top-level background message handler for FCM notifications.
///
/// Processes background push notifications and triggers local SMS pop-ups
/// when appropriate recipients are targeted.
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  final String recipient = message.data['recipient'] ?? '';
  if (recipient == 'customer') return;

  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initializeBackground();

  final String title =
      message.notification?.title ?? message.data['title'] ?? 'Alert';
  final String body = message.notification?.body ??
      message.data['body'] ??
      'New notification received.';

  await NotificationService.showSmsNotificationPopUp(
    title: title,
    body: body,
  );
}

/// Application entry point.
///
/// Initializes Flutter bindings, configures global exception handling,
/// configures Firebase and Firestore offline persistence settings, and launches [GdcAdminApp].
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from assets/.env or root .env
  try {
    await dotenv.load(fileName: "assets/.env");
  } catch (e) {
    try {
      await dotenv.load(fileName: ".env");
    } catch (e2) {
      debugPrint('Could not load .env file: $e2');
    }
  }

  // Catch Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
  };

  // Catch asynchronous errors outside Flutter framework
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Uncaught Async Error: $error');
    return true; // Mark handled
  };

  // Non-recursive, safe, non-scrollable error widget (prevents !_debugDoingThisLayout re-entrancy)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    return Container(
      color: const Color(0xFFB71C1C),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Text(
        'RENDER ERROR:\n${details.exception}',
        style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace'),
        textAlign: TextAlign.center,
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
      ),
    );
  };

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    // 1. Configure Firestore Unlimited Offline Persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Initialize notification service safely without blocking the main UI rendering frame
    NotificationService.initialize().catchError((e) {
      debugPrint('Notification Service Initialization Error: $e');
    });

    FirebaseMessaging.onBackgroundMessage(_bgHandler);
  } catch (e) {
    debugPrint('Firebase Initialization Error: $e');
  }

  runApp(const GdcAdminApp());
}

/// Root widget for the GDC Admin application.
///
/// Sets up global state providers via [MultiProvider] and binds application theming
/// and the primary authentication flow gate.
class GdcAdminApp extends StatelessWidget {
  const GdcAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: TimeService.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppAuthProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => PrinterProvider()),
        ChangeNotifierProvider(create: (_) => RestockProvider()),
        ChangeNotifierProvider(create: (_) => ShiftProvider()),
        ChangeNotifierProvider(create: (_) => ProcurementProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) => MaterialApp(
          title: 'GDC Admin',
          debugShowCheckedModeBanner: false,
          theme: GdcTheme.light,
          darkTheme: GdcTheme.dark,
          themeMode: themeProvider.themeMode,
          home: const _StaffAuthGate(),
        ),
      ),
    );
  }
}

/// Authentication and permissions gate widget.
///
/// Determines UI destination based on user auth state, role assignments,
/// 2FA/TOTP verification status, and manages provider subscriptions.
class _StaffAuthGate extends StatefulWidget {
  const _StaffAuthGate();

  @override
  State<_StaffAuthGate> createState() => _StaffAuthGateState();
}

class _StaffAuthGateState extends State<_StaffAuthGate> {
  String? _activeStaffKey;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final user = auth.currentUser;
    final bool hasStaffAccess = user != null && auth.role != UserRole.none;
    final String? staffKey =
        hasStaffAccess ? '${user.uid}:${auth.role.name}' : null;

    // Manage provider lifecycles based on authenticated + approved staff role
    if (staffKey != _activeStaffKey) {
      _activeStaffKey = staffKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (hasStaffAccess) {
          final email = user.email ?? 'Staff';
          debugPrint('AuthGate: Initializing providers & identity for $email');
          context.read<InventoryProvider>().setAdminEmail(email);
          context.read<OrderProvider>().setAdminName(email);

          context.read<InventoryProvider>().initialize();
          context.read<OrderProvider>().initialize();
          context.read<ExpenseProvider>().initialize();
          context.read<RestockProvider>().initialize();
          context.read<ProcurementProvider>().initialize();
          context.read<ShiftProvider>().initialize();
        } else {
          debugPrint('AuthGate: Cancelling subscriptions (Logout / Pending)');
          context.read<InventoryProvider>().cancelSubscriptions();
          context.read<OrderProvider>().cancelSubscriptions();
          context.read<ExpenseProvider>().cancelSubscriptions();
          context.read<RestockProvider>().cancelSubscriptions();
          context.read<ProcurementProvider>().cancelSubscriptions();
          context.read<ShiftProvider>().cancelSubscriptions();
        }
      });
    }

    if (!auth.initialized || auth.isLoadingProfile) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (user == null) {
      return const StaffLoginScreen();
    }

    // Complete Google staff profile if first-time Google Sign-In registrant
    if (auth.needsProfileCompletion) {
      return _GoogleProfileCompletionView(user: user);
    }

    // Check if email address needs verification (for email/password sign-up)
    final isPasswordUser =
        user.providerData.any((p) => p.providerId == 'password');
    final isPrimaryAdmin = user.email?.trim().toLowerCase() ==
        AdminSeeder.primaryAdminEmail.toLowerCase();
    if (isPasswordUser &&
        !auth.isEmailVerified &&
        !auth.isEmailOtpVerified &&
        !isPrimaryAdmin) {
      return _EmailVerificationRequiredView(user: user);
    }

    // Account state screens when user has no active staff role assignment
    if (auth.role == UserRole.none) {
      return _AccountStatusView(user: user, isDenied: auth.isDenied);
    }

    // Role-based destination: require 6-digit PIN/TOTP verification for all staff roles prior to session grant
    if (auth.role != UserRole.none && !auth.adminVerified) {
      return const AdminPinScreen();
    } else {
      return const AdminApp();
    }
  }
}

/// Full-screen profile completion form shown for first-time Google Sign-In staff registrants.
/// Handled at the auth gate level so it cannot race with auth state transitions.
class _GoogleProfileCompletionView extends StatefulWidget {
  final User user;
  const _GoogleProfileCompletionView({required this.user});

  @override
  State<_GoogleProfileCompletionView> createState() =>
      _GoogleProfileCompletionViewState();
}

class _GoogleProfileCompletionViewState
    extends State<_GoogleProfileCompletionView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  final _phoneCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.displayName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final auth = context.read<AppAuthProvider>();
      await auth.completeGoogleRegistration(
        name: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        requestedRole: 'trustedPartner',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Failed to submit registration: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final auth = context.read<AppAuthProvider>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer
                                .withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_pin_rounded,
                            size: 44,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Complete Staff Profile',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Signed in as ${widget.user.email ?? "Google User"}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please confirm your details below so the Store Admin can review and approve your Trusted Partner request.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _nameCtrl,
                          enabled: !_submitting,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
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
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _phoneCtrl,
                          enabled: !_submitting,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9+\-\s()]')),
                            LengthLimitingTextInputFormatter(18),
                          ],
                          onFieldSubmitted: (_) => _submit(),
                          validator: validatePhoneNumber,
                          decoration: const InputDecoration(
                            labelText: 'Contact Phone Number (SMS OTP)',
                            hintText: '09123456789',
                            prefixIcon: Icon(Icons.phone_android_outlined),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        ElevatedButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline_rounded),
                          label: Text(_submitting
                              ? 'Submitting Request...'
                              : 'SUBMIT REGISTRATION REQUEST'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _submitting ? null : () => auth.logout(),
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: const Text('Cancel & Sign Out'),
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
}

/// View presented when an authenticated user's staff registration is pending approval or denied.
class _AccountStatusView extends StatefulWidget {
  final User user;
  final bool isDenied;

  const _AccountStatusView({
    required this.user,
    required this.isDenied,
  });

  @override
  State<_AccountStatusView> createState() => _AccountStatusViewState();
}

class _AccountStatusViewState extends State<_AccountStatusView> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final auth = context.read<AppAuthProvider>();
      await auth.refreshRole();
      if (!mounted) return;
      if (auth.role == UserRole.none) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              auth.isDenied
                  ? 'Status unchanged: account access is still denied.'
                  : 'Still awaiting Store Admin approval. Please check back shortly.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final auth = context.watch<AppAuthProvider>();

    final requestedStr = switch (auth.requestedRole) {
      'admin' => 'Store Admin',
      'trustedPartner' || 'cashier' || 'inventoryManager' => 'Trusted Partner',
      _ => 'Trusted Partner',
    };

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isDenied
                            ? Icons.gpp_bad_rounded
                            : Icons.hourglass_top_rounded,
                        size: 60,
                        color: widget.isDenied
                            ? colorScheme.error
                            : Colors.amber.shade800,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.isDenied
                            ? 'Access Denied'
                            : 'Registration Pending Approval',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: widget.isDenied ? colorScheme.error : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.isDenied
                              ? colorScheme.errorContainer
                              : Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: widget.isDenied
                              ? null
                              : Border.all(color: Colors.amber.shade300),
                        ),
                        child: Text(
                          widget.isDenied
                              ? 'ACCESS DENIED / REVOKED'
                              : 'PENDING ADMIN APPROVAL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: widget.isDenied
                                ? colorScheme.onErrorContainer
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!widget.isDenied) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (auth.userFullName != null &&
                                  auth.userFullName!.isNotEmpty) ...[
                                Text('Applicant: ${auth.userFullName}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                const SizedBox(height: 4),
                              ],
                              Text('Email: ${widget.user.email}',
                                  style: const TextStyle(fontSize: 12)),
                              if (auth.phoneNumber != null &&
                                  auth.phoneNumber!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Phone: ${auth.phoneNumber}',
                                    style: const TextStyle(fontSize: 12)),
                              ],
                              const SizedBox(height: 4),
                              Text('Requested Access: $requestedStr',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        widget.isDenied
                            ? 'Your account (${widget.user.email}) registration request was reviewed and denied by the Store Admin, or your access was revoked.'
                            : 'Your registration request has been submitted successfully. A Store Admin must review your details and accept your application before your Trusted Partner access is activated.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _isRefreshing ? null : _handleRefresh,
                        icon: _isRefreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(_isRefreshing
                            ? 'Checking Status...'
                            : 'Check Permissions Status'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () => auth.logout(),
                        icon: const Icon(Icons.logout_rounded, size: 16),
                        label: const Text('Log Out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// View presented when email/password user needs to verify their email address.
class _EmailVerificationRequiredView extends StatefulWidget {
  final User user;
  const _EmailVerificationRequiredView({required this.user});

  @override
  State<_EmailVerificationRequiredView> createState() =>
      _EmailVerificationRequiredViewState();
}

class _EmailVerificationRequiredViewState
    extends State<_EmailVerificationRequiredView> {
  bool _isChecking = false;
  bool _isResending = false;
  int _resendCooldown = 0;
  Timer? _autoCheckTimer;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Periodically check Firebase Auth email verification status without recreating Firestore listeners.
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStatus(silent: true);
    });
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _checkStatus({bool silent = false}) async {
    if (_isChecking) return;
    if (!silent) {
      setState(() => _isChecking = true);
    }
    try {
      final auth = context.read<AppAuthProvider>();
      final verified = await auth.checkEmailVerificationStatus();
      if (mounted && !silent) {
        if (verified) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verified successfully! Welcome.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Email is not verified yet. Please check your inbox and click the verification link.'),
            ),
          );
        }
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _resendEmail() async {
    if (_isResending || _resendCooldown > 0) return;
    setState(() => _isResending = true);
    try {
      final auth = context.read<AppAuthProvider>();
      await auth.resendEmailVerification();
      if (mounted) {
        _startResendCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Verification email re-sent to ${widget.user.email}! Check your inbox and spam folder.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'too-many-requests') {
          _startResendCooldown();
        }
        final message = switch (e.code) {
          'too-many-requests' =>
            'Verification email was already sent recently. Please check your inbox & spam folder, or wait a minute before requesting another link.',
          _ => e.message ?? 'Could not resend email. Try again later.',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: e.code == 'too-many-requests'
                ? Colors.amber.shade900
                : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final auth = context.read<AppAuthProvider>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mark_email_unread_rounded,
                          size: 48,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Email Verification Required',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'VERIFICATION PENDING',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                          ),
                          children: [
                            const TextSpan(
                                text: 'A verification link was sent to:\n'),
                            TextSpan(
                              text: '${widget.user.email}\n\n',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const TextSpan(
                              text:
                                  'Please check your Inbox and Spam/Junk folder and click the link to verify your account.\n\nThis screen will automatically refresh once verified.',
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _isChecking ? null : () => _checkStatus(),
                        icon: _isChecking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(_isChecking
                            ? 'Checking Status...'
                            : 'I Have Verified / Check Status'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: (_isResending || _resendCooldown > 0)
                            ? null
                            : _resendEmail,
                        icon: _isResending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded, size: 16),
                        label: Text(_isResending
                            ? 'Resending Link...'
                            : _resendCooldown > 0
                                ? 'Resend available in ${_resendCooldown}s'
                                : 'Resend Verification Email'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () => auth.logout(),
                        icon: const Icon(Icons.logout_rounded, size: 16),
                        label: const Text('Log Out & Try Another Email'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
