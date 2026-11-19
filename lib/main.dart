import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'screens/staff_login_screen.dart';
import 'screens/admin_pin_screen.dart';
import 'screens/admin_app.dart';

import 'services/notification_service.dart';
import 'shared/services/time_service.dart';

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
  String? _activeUid;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final user = auth.currentUser;

    // Manage provider lifecycles based on auth state
    if (user?.uid != _activeUid) {
      _activeUid = user?.uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (user != null) {
          final email = user.email ?? 'Staff';
          debugPrint('AuthGate: Initializing providers & identity for $email');
          context.read<InventoryProvider>().setAdminEmail(email);
          context.read<OrderProvider>().setAdminName(email);

          context.read<InventoryProvider>().initialize();
          context.read<OrderProvider>().initialize();
          context.read<ExpenseProvider>().initialize();
          context.read<RestockProvider>().initialize();
        } else {
          debugPrint('AuthGate: Cancelling subscriptions (Logout)');
          context.read<InventoryProvider>().cancelSubscriptions();
          context.read<OrderProvider>().cancelSubscriptions();
          context.read<ExpenseProvider>().cancelSubscriptions();
          context.read<RestockProvider>().cancelSubscriptions();
        }
      });
    }

    if (!auth.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (user == null) {
      return const StaffLoginScreen();
    }

    // Check if email address needs verification (for email/password sign-up)
    final isPasswordUser =
        user.providerData.any((p) => p.providerId == 'password');
    if (isPasswordUser &&
        !auth.isEmailVerified &&
        user.email != 'markjeo.hinampas@gmail.com') {
      return _EmailVerificationRequiredView(user: user);
    }

    // Account state screens when user has no active staff role assignment
    if (auth.role == UserRole.none) {
      if (auth.isDenied) {
        // ACCESS DENIED SCREEN
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.gpp_bad_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Access Denied',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'ACCESS DENIED / REVOKED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your account (${user.email}) registration request was reviewed and denied by the Store Admin, or your access was revoked.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => auth.refreshRole(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Check Permissions Status'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => auth.logout(),
                    child: const Text('Log Out'),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        // REGISTRATION PENDING APPROVAL SCREEN
        final requestedStr = switch (auth.requestedRole) {
          'admin' => 'Store Admin',
          'trustedPartner' ||
          'cashier' ||
          'inventoryManager' =>
            'Trusted Partner',
          _ => 'Trusted Partner',
        };

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 64,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Registration Pending Approval',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Text(
                      'PENDING ADMIN APPROVAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (auth.userFullName != null &&
                            auth.userFullName!.isNotEmpty) ...[
                          Text('Applicant: ${auth.userFullName}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                        ],
                        Text('Email: ${user.email}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('Requested Access: $requestedStr',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your registration request has been submitted successfully. A Store Admin must review your details and accept your application before your Trusted Partner access is activated.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => auth.refreshRole(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Check Permissions Status'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => auth.logout(),
                    child: const Text('Log Out'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    // Role-based destination: require 6-digit PIN/TOTP verification for all staff roles prior to session grant
    if (auth.role != UserRole.none && !auth.adminVerified) {
      return const AdminPinScreen();
    } else {
      return const AdminApp();
    }
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
  Timer? _autoCheckTimer;

  @override
  void initState() {
    super.initState();
    // Periodically check email verification status every 4 seconds
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkStatus(silent: true);
    });
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus({bool silent = false}) async {
    if (_isChecking) return;
    if (!silent) {
      setState(() => _isChecking = true);
    }
    try {
      final auth = context.read<AppAuthProvider>();
      await auth.refreshRole();
      if (mounted && !silent) {
        if (auth.isEmailVerified) {
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
    if (_isResending) return;
    setState(() => _isResending = true);
    try {
      final auth = context.read<AppAuthProvider>();
      await auth.resendEmailVerification();
      if (mounted) {
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
    final colorScheme = Theme.of(context).colorScheme;
    final auth = context.read<AppAuthProvider>();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
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
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                      onPressed: _isResending ? null : _resendEmail,
                      icon: _isResending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(_isResending
                          ? 'Resending Link...'
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
    );
  }
}
