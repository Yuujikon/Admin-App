import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/printer_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../config/theme.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'inventory_screen.dart';
import 'orders_screen.dart';
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
        InventoryScreen(initialCategory: _inventoryCategory),
        const OrdersScreen(),
        const ExpensesScreen(),
        const MoreManagementScreen(),
      ];
      destinations = const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined),     label: 'Dashboard'),
        NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'POS'),
        NavigationDestination(icon: Icon(Icons.inventory_2_outlined),   label: 'Inventory'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined),  label: 'Orders'),
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
        const OrdersScreen(),
      ];
      destinations = const [
        NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'POS'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined),  label: 'Orders'),
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
          _PrinterAction(),
          const SizedBox(width: 8),
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
        indicatorColor: GdcColors.earthyGold.withValues(alpha: 0.15),
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

class _PrinterAction extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterProvider>();
    return IconButton(
      icon: printer.isConnecting 
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(
            printer.connected ? Icons.print_rounded : Icons.print_disabled_rounded,
            color: printer.connected ? Theme.of(context).colorScheme.primary : Theme.of(context).disabledColor,
          ),
      onPressed: () => _showPrinterDialog(context, printer),
      tooltip: 'Printer Settings',
    );
  }

  void _showPrinterDialog(BuildContext context, PrinterProvider printer) async {
    final devices = await printer.getDevices();
    
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bluetooth Printer'),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.isEmpty 
              ? const Text('No paired bluetooth devices found.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  itemBuilder: (context, i) {
                    final d = devices[i];
                    return ListTile(
                      title: Text(d.name),
                      subtitle: Text(d.macAdress),
                      trailing: printer.device?.macAdress == d.macAdress && printer.connected
                        ? Icon(Icons.check_circle, color: Theme.of(context).semantic.success)
                        : null,
                      onTap: () {
                        printer.connect(d);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
          ),
          actions: [
            if (printer.connected)
              TextButton(
                onPressed: () => printer.printTest(),
                child: Text('Test Print', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ),
            if (printer.connected)
              TextButton(
                onPressed: () {
                  printer.disconnect();
                  Navigator.pop(ctx);
                },
                child: Text('Disconnect', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    }
  }
}