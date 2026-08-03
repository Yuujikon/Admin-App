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
import 'screens/staff_login_screen.dart';
import 'screens/admin_pin_screen.dart';
import 'screens/admin_app.dart';

import 'services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initialize();
  FirebaseMessaging.onBackgroundMessage(_bgHandler);
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
          debugPrint('AuthGate: Initializing providers for ${user.email}');
          context.read<InventoryProvider>().initialize();
          context.read<OrderProvider>().initialize();
          context.read<ExpenseProvider>().initialize();
        } else {
          debugPrint('AuthGate: Cancelling subscriptions (Logout)');
          context.read<InventoryProvider>().cancelSubscriptions();
          context.read<OrderProvider>().cancelSubscriptions();
          context.read<ExpenseProvider>().cancelSubscriptions();
        }
      });
    }
    
    if (!auth.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (user == null) {
      return const StaffLoginScreen();
    }

    // If logged in but role not fetched yet
    if (auth.role == UserRole.none) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Checking permissions...'),
              const SizedBox(height: 16),
              TextButton(onPressed: () => auth.logout(), child: const Text('Log Out'))
            ],
          ),
        ),
      );
    }

    // Role-based destination
    if (auth.role == UserRole.admin && !auth.adminVerified) {
      return const AdminPinScreen();
    } else {
      return const AdminApp(); 
    }
  }
}
