import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/order_provider.dart';
import '../models/order.dart';
import '../config/theme.dart';
import '../utils/responsive.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'inventory_screen.dart';
import 'pre_orders_screen.dart';
import 'expenses_screen.dart';
import 'more_management_screen.dart';

enum AppTab { dashboard, pos, preOrders, inventory, expenses, more }

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});
  @override State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  int _tab = 0;
  String? _inventoryCategory;
  StreamSubscription<PreOrder>? _newOrderSub;

  void _navigateToTab(AppTab targetTab, {String? category}) {
    final role = context.read<AppAuthProvider>().role;
    int targetIndex = -1;

    if (role == UserRole.admin) {
      targetIndex = switch (targetTab) {
        AppTab.dashboard => 0,
        AppTab.pos       => 1,
        AppTab.preOrders => 2,
        AppTab.inventory => 3,
        AppTab.expenses  => 4,
        AppTab.more      => 5,
      };
    } else if (role == UserRole.inventoryManager) {
      targetIndex = switch (targetTab) {
        AppTab.dashboard => 0,
        AppTab.inventory => 1,
        AppTab.more      => 2,
        _                => -1,
      };
    } else if (role == UserRole.cashier) {
      targetIndex = switch (targetTab) {
        AppTab.pos       => 0,
        AppTab.preOrders => 1,
        AppTab.more      => 2,
        _                => -1,
      };
    }

    if (targetIndex != -1) {
      setState(() {
        _tab = targetIndex;
        if (category != null) {
          _inventoryCategory = category;
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _newOrderSub = context.read<OrderProvider>().onNewOrderReceived.listen((newOrder) {
        if (!mounted) return;
        HapticFeedback.vibrate();

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.shopping_bag_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🛍️ New Pre-Order #${newOrder.orderId} from ${newOrder.customerName} (₱${newOrder.total.toStringAsFixed(2)})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: GdcColors.primaryGreen,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                _navigateToTab(AppTab.preOrders);
              },
            ),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _newOrderSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final bool isAdmin = auth.role == UserRole.admin;
    final bool isInv   = auth.role == UserRole.inventoryManager;
    final bool isLandscape = Responsive.isLandscape(context);
    final bool isLargeScreen = Responsive.isLargeScreen(context);

    final orderProvider = context.watch<OrderProvider>();
    // Pre-orders still needing process (excluding ready to pick up, collected, etc.)
    final toProcessCount = orderProvider.orders.where((o) =>
      o.status == OrderStatus.pending || o.status == OrderStatus.staging
    ).length;

    final Widget preOrdersIcon = Badge.count(
      count: toProcessCount,
      isLabelVisible: toProcessCount > 0,
      backgroundColor: Theme.of(context).colorScheme.error,
      child: const Icon(Icons.receipt_long_outlined),
    );

    // Define tabs based on role
    late final List<Widget> children;
    late final List<NavigationDestination> destinations;

    if (isAdmin) {
      children = [
        DashboardScreen(onTabChange: (targetTab, {category}) {
          _navigateToTab(targetTab, category: category);
        }),
        const PosScreen(),
        const PreOrdersScreen(),
        InventoryScreen(initialCategory: _inventoryCategory),
        const ExpensesScreen(),
        const MoreManagementScreen(),
      ];
      destinations = [
        const NavigationDestination(icon: Icon(Icons.dashboard_outlined),     label: 'Dashboard'),
        const NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'POS'),
        NavigationDestination(icon: preOrdersIcon,                            label: 'Pre-Orders'),
        const NavigationDestination(icon: Icon(Icons.inventory_2_outlined),   label: 'Inventory'),
        const NavigationDestination(icon: Icon(Icons.attach_money_outlined),  label: 'Expenses'),
        const NavigationDestination(icon: Icon(Icons.more_horiz),             label: 'More'),
      ];
    } else if (isInv) {
      children = [
        DashboardScreen(onTabChange: (targetTab, {category}) {
          _navigateToTab(targetTab, category: category);
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
        const MoreManagementScreen(),
      ];
      destinations = [
        const NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'POS'),
        NavigationDestination(icon: preOrdersIcon,                            label: 'Pre-Orders'),
        const NavigationDestination(icon: Icon(Icons.more_horiz),             label: 'More'),
      ];
    }

    final int currentTab = _tab >= children.length ? 0 : _tab;
    final double appBarHeight = isLandscape ? 52.0 : 65.0;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: appBarHeight,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'GDC ADMIN',
                  style: TextStyle(
                    fontSize: isLandscape ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: _getRoleColor(auth.role, context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getRoleLabel(auth.role).toUpperCase(), 
                    style: TextStyle(
                      fontSize: 8, 
                      color: _getRoleColor(auth.role, context), 
                      fontWeight: FontWeight.w900, 
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(context.watch<ThemeProvider>().isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: isLandscape ? 20 : 24),
            onPressed: () => context.read<ThemeProvider>().toggleTheme(!context.read<ThemeProvider>().isDarkMode),
            tooltip: 'Toggle Theme',
          ),
          IconButton.filledTonal(
            icon: Icon(Icons.logout_rounded, size: isLandscape ? 18 : 20),
            tooltip: 'Logout',
            onPressed: () async {
              await auth.logout();
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          if (isLargeScreen && destinations.length > 1) ...[
            SingleChildScrollView(
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - appBarHeight - MediaQuery.of(context).padding.top,
                ),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: currentTab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    labelType: NavigationRailLabelType.all,
                    minWidth: 64,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    indicatorColor: GdcColors.secondaryGreen.withValues(alpha: 0.15),
                    selectedIconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
                    selectedLabelTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    unselectedLabelTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                    destinations: destinations.map((d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon ?? d.icon,
                      label: Text(d.label),
                    )).toList(),
                  ),
                ),
              ),
            ),
            VerticalDivider(
              thickness: 1,
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ],
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: isLargeScreen 
                    ? const BorderRadius.horizontal(left: Radius.circular(24))
                    : const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              clipBehavior: Clip.antiAlias,
              child: IndexedStack(
                index: currentTab,
                children: children,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: (isLargeScreen || destinations.length <= 1) ? null : Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          currentIndex: currentTab,
          onTap: (i) => setState(() => _tab = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
          selectedFontSize: 10,
          unselectedFontSize: 9,
          iconSize: 22,
          elevation: 8,
          items: destinations.map((d) => BottomNavigationBarItem(
            icon: d.icon,
            activeIcon: d.selectedIcon ?? d.icon,
            label: d.label,
          )).toList(),
        ),
      ),
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
