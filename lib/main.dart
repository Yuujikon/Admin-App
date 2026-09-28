import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'screens/staff_login_screen.dart';
import 'screens/admin_pin_screen.dart';
import 'screens/admin_app.dart';

import 'services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  final String recipient = message.data['recipient'] ?? '';
  if (recipient == 'customer') return;

  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initializeBackground();
  
  final String title = message.notification?.title ?? message.data['title'] ?? 'Alert';
  final String body = message.notification?.body ?? message.data['body'] ?? 'New notification received.';
  
  await NotificationService.showSmsNotificationPopUp(
    title: title,
    body: body,
  );
}

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

  // Release mode graceful error builder
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
              SizedBox(height: 12),
              Text('Something went wrong', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 6),
              Text('Please return to the previous screen or restart the app.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  };
  
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    
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
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) => MaterialApp(
          title:                    'GDC Admin',
          debugShowCheckedModeBanner: false,
          theme:                    GdcTheme.light,
          darkTheme:                GdcTheme.dark,
          themeMode:                themeProvider.themeMode,
          home:                     const _StaffAuthGate(),
        ),
      ),
    );
  }
}

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

    // If logged in but role not fetched yet or role is 'none'
    if (auth.role == UserRole.none) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Access Pending Approval',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your account (${user.email ?? "User"}) requires staff role assignment from an Store Admin.',
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

    // Role-based destination: require 6-digit TOTP/PIN verification for all staff roles when 2FA is enabled
    if (auth.role != UserRole.none && auth.totpEnabled && !auth.adminVerified) {
      return const AdminPinScreen();
    } else {
      return const AdminApp(); 
    }
  }
}
