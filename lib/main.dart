import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
    final isPasswordUser = user.providerData.any((p) => p.providerId == 'password');
    if (isPasswordUser && !auth.isEmailVerified && user.email != 'markjeo.hinampas@gmail.com') {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mark_email_unread_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Verify Your Email Address',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'VERIFICATION REQUIRED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'A verification email was sent to ${user.email}.\nPlease check your email inbox and click the link to verify your real email account.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => auth.refreshRole(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('I Have Verified / Check Status'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await auth.resendEmailVerification();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Verification email re-sent! Check your inbox.'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not resend email. Try again later.'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Resend Verification Email'),
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
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          'cashier' => 'Cashier',
          'inventoryManager' => 'Inventory Manager',
          'admin' => 'Store Admin',
          _ => 'Staff Role',
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (auth.userFullName != null && auth.userFullName!.isNotEmpty) ...[
                          Text('Applicant: ${auth.userFullName}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                        ],
                        Text('Email: ${user.email}', style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('Requested Position: $requestedStr',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your registration request has been submitted successfully. A Store Admin must review your details and assign your authorized role before you can access the system.',
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

    // Role-based destination: require 6-digit TOTP/PIN verification for all staff roles when 2FA is enabled
    if (auth.role != UserRole.none && auth.totpEnabled && !auth.adminVerified) {
      return const AdminPinScreen();
    } else {
      return const AdminApp();
    }
  }
}
