import 'package:flutter/material.dart';
import '../providers/auth_provider.dart';

/// Navigation destination model representing screen targets in the admin application sidebar/navigation rail.
class AdminDestination {
  /// Unique identifier for the navigation item.
  final String id;

  /// Display text label shown in navigation UI components.
  final String label;

  /// Unselected icon representation.
  final IconData icon;

  /// Selected icon representation.
  final IconData? selectedIcon;

  /// Target route path for navigation.
  final String route;

  /// Indicates if destination appears in the primary navigation rail.
  final bool isPrimary;

  /// Priority index for ordering navigation items.
  final int priority;

  /// Creates a new instance of [AdminDestination].
  const AdminDestination({
    required this.id,
    required this.label,
    required this.icon,
    this.selectedIcon,
    required this.route,
    this.isPrimary = true,
    this.priority = 0,
  });

  static const String dashboardId = 'dashboard';
  static const String posId = 'pos';
  static const String inventoryId = 'inventory';
  static const String preOrdersId = 'pre_orders';
  static const String shiftId = 'shift';
  static const String reportsId = 'reports';
  static const String salesHistoryId = 'sales_history';
  static const String inventoryRecordsId = 'inventory_records';
  static const String suppliersId = 'suppliers';
  static const String moreId = 'more';

  /// Returns the list of primary navigation destinations available based on user [role].
  static List<AdminDestination> getPrimaryDestinations({
    required UserRole role,
    required bool isCompact,
  }) {
    if (role == UserRole.admin) {
      return const [
        AdminDestination(
          id: dashboardId,
          label: 'Dashboard',
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
          route: '/dashboard',
          priority: 1,
        ),
        AdminDestination(
          id: posId,
          label: 'Point of Sale',
          icon: Icons.shopping_cart_outlined,
          selectedIcon: Icons.shopping_cart_rounded,
          route: '/pos',
          priority: 2,
        ),
        AdminDestination(
          id: inventoryId,
          label: 'Inventory',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2_rounded,
          route: '/inventory',
          priority: 3,
        ),
        AdminDestination(
          id: preOrdersId,
          label: 'Pre-orders',
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment_rounded,
          route: '/pre_orders',
          priority: 4,
        ),
        AdminDestination(
          id: shiftId,
          label: 'Shift & Cash',
          icon: Icons.access_time_outlined,
          selectedIcon: Icons.access_time_filled,
          route: '/shift',
          priority: 5,
        ),
        AdminDestination(
          id: reportsId,
          label: 'Reports',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart_rounded,
          route: '/reports',
          priority: 6,
        ),
        AdminDestination(
          id: salesHistoryId,
          label: 'Sales History',
          icon: Icons.history_toggle_off_rounded,
          selectedIcon: Icons.history_rounded,
          route: '/sales_history',
          priority: 7,
        ),
        AdminDestination(
          id: inventoryRecordsId,
          label: 'Inventory Records',
          icon: Icons.article_outlined,
          selectedIcon: Icons.article_rounded,
          route: '/inventory_records',
          priority: 8,
        ),
        AdminDestination(
          id: suppliersId,
          label: 'Suppliers',
          icon: Icons.local_shipping_outlined,
          selectedIcon: Icons.local_shipping_rounded,
          route: '/suppliers',
          priority: 9,
        ),
        AdminDestination(
          id: moreId,
          label: 'More',
          icon: Icons.more_horiz_rounded,
          selectedIcon: Icons.more_horiz_rounded,
          route: '/more',
          priority: 10,
        ),
      ];
    } else if (role == UserRole.inventoryManager) {
      return const [
        AdminDestination(
          id: dashboardId,
          label: 'Dashboard',
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
          route: '/dashboard',
          priority: 1,
        ),
        AdminDestination(
          id: inventoryId,
          label: 'Inventory',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2_rounded,
          route: '/inventory',
          priority: 2,
        ),
        AdminDestination(
          id: inventoryRecordsId,
          label: 'Inventory Records',
          icon: Icons.article_outlined,
          selectedIcon: Icons.article_rounded,
          route: '/inventory_records',
          priority: 3,
        ),
        AdminDestination(
          id: suppliersId,
          label: 'Suppliers',
          icon: Icons.local_shipping_outlined,
          selectedIcon: Icons.local_shipping_rounded,
          route: '/suppliers',
          priority: 4,
        ),
        AdminDestination(
          id: shiftId,
          label: 'Shift & Cash',
          icon: Icons.access_time_outlined,
          selectedIcon: Icons.access_time_filled,
          route: '/shift',
          priority: 5,
        ),
        AdminDestination(
          id: reportsId,
          label: 'Reports',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart_rounded,
          route: '/reports',
          priority: 6,
        ),
        AdminDestination(
          id: moreId,
          label: 'More',
          icon: Icons.more_horiz_rounded,
          selectedIcon: Icons.more_horiz_rounded,
          route: '/more',
          priority: 7,
        ),
      ];
    } else {
      // Cashier
      return const [
        AdminDestination(
          id: posId,
          label: 'Point of Sale',
          icon: Icons.shopping_cart_outlined,
          selectedIcon: Icons.shopping_cart_rounded,
          route: '/pos',
          priority: 1,
        ),
        AdminDestination(
          id: preOrdersId,
          label: 'Pre-orders',
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment_rounded,
          route: '/pre_orders',
          priority: 2,
        ),
        AdminDestination(
          id: salesHistoryId,
          label: 'Sales History',
          icon: Icons.history_toggle_off_rounded,
          selectedIcon: Icons.history_rounded,
          route: '/sales_history',
          priority: 3,
        ),
        AdminDestination(
          id: shiftId,
          label: 'Shift & Cash',
          icon: Icons.access_time_outlined,
          selectedIcon: Icons.access_time_filled,
          route: '/shift',
          priority: 4,
        ),
        AdminDestination(
          id: moreId,
          label: 'More',
          icon: Icons.more_horiz_rounded,
          selectedIcon: Icons.more_horiz_rounded,
          route: '/more',
          priority: 5,
        ),
      ];
    }
  }
}
