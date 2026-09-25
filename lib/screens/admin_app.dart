import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../config/theme.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'inventory_screen.dart';
import 'pre_orders_screen.dart';
import 'expenses_screen.dart';
import 'more_management_screen.dart';

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});
  @override State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  int _tab = 0;
  String? _inventoryCategory;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final bool isAdmin = auth.role == UserRole.admin;
    final bool isInv   = auth.role == UserRole.inventoryManager;

    // Define tabs based on role
    late final List<Widget> children;
    late final List<NavigationDestination> destinations;

    if (isAdmin) {
      children = [
        DashboardScreen(onTabChange: (i, {category}) {
          setState(() {
            _tab = i;
            _inventoryCategory = category;
          });
        }),
        const PosScreen(),
        const PreOrdersScreen(),
        InventoryScreen(initialCategory: _inventoryCategory),
        const ExpensesScreen(),
        const MoreManagementScreen(),
      ];
      destinations = const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined),     label: 'Dashboard'),
        NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'POS'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined),  label: 'Pre-Orders'),
        NavigationDestination(icon: Icon(Icons.inventory_2_outlined),   label: 'Inventory'),
        NavigationDestination(icon: Icon(Icons.attach_money_outlined),  label: 'Expenses'),
        NavigationDestination(icon: Icon(Icons.more_horiz),             label: 'More'),
      ];
    } else if (isInv) {
      children = [
        DashboardScreen(onTabChange: (i, {category}) {
          setState(() {
            _tab = i;
            _inventoryCategory = category;
          });
        }),
        InventoryScreen(initialCategory: _inventoryCategory),
        const MoreManagementScreen(), // They can access Suppliers/Loss here
      ];
      destinations = const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined),     label: 'Dashboard'),
        NavigationDestination(icon: Icon(Icons.inventory_2_outlined),   label: 'Inventory'),
        NavigationDestination(icon: Icon(Icons.more_horiz),             label: 'More'),
      ];
    } else {
      children = [
        const PosScreen(),
        const PreOrdersScreen(),
      ];
      destinations = const [
        NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'POS'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined),  label: 'Pre-Orders'),
      ];
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GDC ADMIN'),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getRoleColor(auth.role, context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_getRoleLabel(auth.role).toUpperCase(), 
                style: TextStyle(fontSize: 9, color: _getRoleColor(auth.role, context), fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(context.watch<ThemeProvider>().isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () => context.read<ThemeProvider>().toggleTheme(!context.read<ThemeProvider>().isDarkMode),
            tooltip: 'Toggle Theme',
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.logout_rounded, size: 20),
            tooltip: 'Logout',
            onPressed: () async {
              await auth.logout();
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        clipBehavior: Clip.antiAlias,
        child: IndexedStack(
          index: _tab >= children.length ? 0 : _tab,
          children: children,
        ),
      ),
      bottomNavigationBar: destinations.length > 1 ? NavigationBar(
        height: 65,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        indicatorColor: GdcColors.secondaryGreen.withValues(alpha: 0.15),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: destinations,
      ) : null,
    );
  }

  String _getRoleLabel(UserRole role) => switch (role) {
    UserRole.admin            => 'Administrator',
    UserRole.inventoryManager => 'Inventory Manager',
    UserRole.cashier          => 'Cashier Staff',
    UserRole.none             => 'Access Denied',
  };

  Color _getRoleColor(UserRole role, BuildContext context) {
    final semantic = Theme.of(context).semantic;
    return switch (role) {
      UserRole.admin            => semantic.success,
      UserRole.inventoryManager => semantic.warning,
      UserRole.cashier          => semantic.info,
      UserRole.none             => Theme.of(context).colorScheme.error,
    };
  }
}