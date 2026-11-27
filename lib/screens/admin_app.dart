import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/order_provider.dart';
import '../providers/inventory_provider.dart';
import '../models/order.dart';
import '../models/refund_request.dart';
import '../models/admin_destination.dart';
import '../config/theme.dart';
import '../utils/responsive.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'inventory_screen.dart';
import 'pre_orders_screen.dart';
import 'shift_screen.dart';
import 'reports_screen.dart';
import 'sales_history_screen.dart';
import 'inventory_records_screen.dart';
import 'supplier_management_screen.dart';
import 'more_management_screen.dart';
import '../shared/services/time_service.dart';
import '../shared/widgets/common/time_travel_sheet.dart';
import '../widgets/global_admin_search_palette.dart';

enum AppTab {
  dashboard,
  pos,
  inventory,
  preOrders,
  shift,
  reports,
  salesHistory,
  inventoryRecords,
  suppliers,
  expenses,
  more
}

/// Primary application shell widget providing adaptive navigation rails and top bar controls.
class AdminApp extends StatefulWidget {
  const AdminApp({super.key});
  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  String _activeDestinationId = AdminDestination.dashboardId;
  String? _inventoryCategory;
  DateTime? _lastBackPressTime;

  /// Navigation history stack tracking visited tab destinations.
  final List<String> _navigationHistory = [AdminDestination.dashboardId];

  void _handleBackPop(bool didPop) {
    if (didPop) return;

    // Pop back to the previously visited tab/page in history
    if (_navigationHistory.length > 1) {
      setState(() {
        _navigationHistory.removeLast();
        _activeDestinationId = _navigationHistory.last;
      });
      return;
    }

    // Prompt exit when at root of navigation history
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit application'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  void _navigateToDestination(String destinationId, {String? category}) {
    final auth = context.read<AppAuthProvider>();
    if (auth.role != UserRole.admin &&
        (destinationId == AdminDestination.shiftId ||
            destinationId == AdminDestination.reportsId ||
            destinationId == AdminDestination.salesHistoryId ||
            destinationId == AdminDestination.inventoryRecordsId)) {
      destinationId = AdminDestination.dashboardId;
    }

    if (_activeDestinationId != destinationId) {
      if (_navigationHistory.isEmpty ||
          _navigationHistory.last != destinationId) {
        _navigationHistory.add(destinationId);
      }
    }

    setState(() {
      _activeDestinationId = destinationId;
      if (category != null) {
        _inventoryCategory = category;
      }
    });
  }

  void _navigateToTab(AppTab targetTab, {String? category}) {
    final String destId = switch (targetTab) {
      AppTab.dashboard => AdminDestination.dashboardId,
      AppTab.pos => AdminDestination.posId,
      AppTab.inventory => AdminDestination.inventoryId,
      AppTab.preOrders => AdminDestination.preOrdersId,
      AppTab.shift => AdminDestination.shiftId,
      AppTab.reports => AdminDestination.reportsId,
      AppTab.salesHistory => AdminDestination.salesHistoryId,
      AppTab.inventoryRecords => AdminDestination.inventoryRecordsId,
      AppTab.suppliers => AdminDestination.suppliersId,
      _ => AdminDestination.moreId,
    };
    _navigateToDestination(destId, category: category);
  }

  String formatPeso(double amount) {
    return '₱${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final role = auth.role;

    final orderProvider = context.watch<OrderProvider>();
    final inventoryProvider = context.watch<InventoryProvider>();
    final pendingRefundsCount = inventoryProvider.refundRequests
        .where((r) => r.status == RefundStatus.pending)
        .length;

    final toProcessCount = orderProvider.orders
            .where((o) =>
                o.status == OrderStatus.pending ||
                o.status == OrderStatus.staging)
            .length +
        pendingRefundsCount;

    return LayoutBuilder(builder: (context, constraints) {
      final double availableWidth = constraints.maxWidth;
      final bool isCompact = availableWidth < Responsive.compactBreakpoint;
      final bool isExpanded = availableWidth >= Responsive.expandedBreakpoint;

      final destinations = AdminDestination.getPrimaryDestinations(
        role: role,
        isCompact: isCompact,
      );

      // Ensure active destination is fallback-safe for the role
      if (role == UserRole.none &&
          _activeDestinationId == AdminDestination.dashboardId) {
        _activeDestinationId = AdminDestination.posId;
      }

      // Security Guard: Prevent non-admin roles from accessing restricted destinations
      if (role != UserRole.admin &&
          (_activeDestinationId == AdminDestination.shiftId ||
              _activeDestinationId == AdminDestination.reportsId ||
              _activeDestinationId == AdminDestination.salesHistoryId ||
              _activeDestinationId == AdminDestination.inventoryRecordsId)) {
        _activeDestinationId = AdminDestination.dashboardId;
      }

      // Build navigation items with badge for pre-orders
      List<NavigationDestination> navDestinations = destinations.map((d) {
        Widget iconWidget = Icon(d.icon);
        Widget selectedIconWidget = Icon(d.selectedIcon ?? d.icon);

        if (d.id == AdminDestination.preOrdersId && toProcessCount > 0) {
          iconWidget = Badge.count(
            count: toProcessCount,
            backgroundColor: Theme.of(context).colorScheme.error,
            child: iconWidget,
          );
          selectedIconWidget = Badge.count(
            count: toProcessCount,
            backgroundColor: Theme.of(context).colorScheme.error,
            child: selectedIconWidget,
          );
        }

        return NavigationDestination(
          icon: iconWidget,
          selectedIcon: selectedIconWidget,
          label: d.label,
        );
      }).toList();

      int selectedRailIndex =
          destinations.indexWhere((d) => d.id == _activeDestinationId);
      if (selectedRailIndex == -1) {
        selectedRailIndex =
            destinations.indexWhere((d) => d.id == AdminDestination.moreId);
        if (selectedRailIndex == -1) selectedRailIndex = 0;
      }

      // Available page widgets
      Widget activePage = switch (_activeDestinationId) {
        AdminDestination.dashboardId => DashboardScreen(
            onTabChange: (targetTab, {category}) {
              _navigateToTab(targetTab, category: category);
            },
          ),
        AdminDestination.posId => const PosScreen(),
        AdminDestination.inventoryId =>
          InventoryScreen(initialCategory: _inventoryCategory),
        AdminDestination.preOrdersId => const PreOrdersScreen(),
        AdminDestination.shiftId => const ShiftScreen(),
        AdminDestination.reportsId => const ReportsScreen(),
        AdminDestination.salesHistoryId => const SalesHistoryScreen(),
        AdminDestination.inventoryRecordsId => const InventoryRecordsScreen(),
        AdminDestination.suppliersId => const SupplierManagementScreen(),
        _ => MoreManagementScreen(
            onNavigateToTab: (tab) => _navigateToTab(tab),
          ),
      };

      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
            GlobalAdminSearchPalette.show(
              context,
              onNavigateTab: (tab, {category}) =>
                  _navigateToTab(tab, category: category),
            );
          },
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
            GlobalAdminSearchPalette.show(
              context,
              onNavigateTab: (tab, {category}) =>
                  _navigateToTab(tab, category: category),
            );
          },
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            _handleBackPop(didPop);
          },
          child: Scaffold(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).scaffoldBackgroundColor
                : const Color(0xFFF1F5F9),
            body: SafeArea(
              child: Column(
                children: [
                  // Global Top Utility Header
                  _AdminTopBar(
                    auth: auth,
                    isCompact: isCompact,
                    onOpenSearch: () {
                      GlobalAdminSearchPalette.show(
                        context,
                        onNavigateTab: (tab, {category}) =>
                            _navigateToTab(tab, category: category),
                      );
                    },
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Persistent Side Navigation Bar for Tablet/Medium & Desktop/Expanded
                        if (!isCompact)
                          Container(
                            width: isExpanded ? 200 : 88,
                            margin: const EdgeInsets.only(
                                left: 12, top: 10, bottom: 12, right: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: destinations.map((d) {
                                        final isSelected =
                                            d.id == _activeDestinationId;
                                        final badgeCount =
                                            d.id == AdminDestination.preOrdersId
                                                ? toProcessCount
                                                : 0;

                                        return _SideNavItem(
                                          destination: d,
                                          isSelected: isSelected,
                                          isExpanded: isExpanded,
                                          badgeCount: badgeCount,
                                          onTap: () =>
                                              _navigateToDestination(d.id),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.3),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: _SideLogoutButton(
                                    isExpanded: isExpanded,
                                    onTap: () => _confirmLogout(context, auth),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Main Content Area Panel
                        Expanded(
                          child: Container(
                            margin: isCompact
                                ? EdgeInsets.zero
                                : const EdgeInsets.only(
                                    top: 10, bottom: 12, right: 12, left: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: isCompact
                                  ? BorderRadius.zero
                                  : BorderRadius.circular(24),
                              border: isCompact
                                  ? null
                                  : Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(alpha: 0.3),
                                    ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1280),
                                child: activePage,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Navigation Bar for Compact Screens (<600dp)
            bottomNavigationBar: isCompact
                ? SafeArea(
                    child: NavigationBar(
                      selectedIndex: selectedRailIndex,
                      onDestinationSelected: (idx) {
                        if (idx >= 0 && idx < destinations.length) {
                          _navigateToDestination(destinations[idx].id);
                        }
                      },
                      destinations: navDestinations,
                    ),
                  )
                : null,
          ),
        ),
      );
    });
  }
}

class _SideNavItem extends StatelessWidget {
  final AdminDestination destination;
  final bool isSelected;
  final bool isExpanded;
  final int badgeCount;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.destination,
    required this.isSelected,
    required this.isExpanded,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color activeBg = isDark
        ? GdcColors.darkEmerald.withValues(alpha: 0.25)
        : GdcColors.creamActiveBackground;
    final Color activeBorder =
        isDark ? GdcColors.emeraldPrimary : GdcColors.darkEmerald;
    final Color activeFg =
        isDark ? GdcColors.emeraldPrimary : GdcColors.darkEmerald;

    final Color inactiveFg =
        isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

    Widget iconWidget = Icon(
      isSelected
          ? (destination.selectedIcon ?? destination.icon)
          : destination.icon,
      size: 22,
      color: isSelected ? activeFg : inactiveFg,
    );

    if (badgeCount > 0) {
      iconWidget = Badge.count(
        count: badgeCount,
        backgroundColor: Theme.of(context).colorScheme.error,
        child: iconWidget,
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: isExpanded
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeBorder : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: isExpanded
            ? Row(
                children: [
                  iconWidget,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? activeFg : inactiveFg,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconWidget,
                  const SizedBox(height: 4),
                  Text(
                    destination.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? activeFg : inactiveFg,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  final AppAuthProvider auth;
  final bool isCompact;
  final VoidCallback onOpenSearch;

  const _AdminTopBar({
    required this.auth,
    required this.isCompact,
    required this.onOpenSearch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: isCompact ? 56 : 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'GDC ADMIN',
                style: TextStyle(
                  fontSize: isCompact ? 16 : 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: GdcColors.creamActiveBackground,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _getRoleLabel(auth.role).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    color: GdcColors.darkEmerald,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          // Automated Global Search & Filter Command Bar Trigger
          if (!isCompact) ...[
            const SizedBox(width: 24),
            InkWell(
              onTap: onOpenSearch,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 320,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHigh
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Search & filter anything…',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text(
                        'Ctrl+K',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const Spacer(),

          if (isCompact) ...[
            IconButton(
              icon: Icon(
                Icons.search_rounded,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              tooltip: 'Search & Filter Anything (Ctrl+K)',
              onPressed: onOpenSearch,
            ),
            const SizedBox(width: 4),
          ],
          // Time Travel / Fast-Forward Simulation Control Button
          Builder(
            builder: (context) {
              final timeService = context.watch<TimeService>();
              final isSimulated = timeService.isSimulated;

              return Tooltip(
                message: isSimulated
                    ? 'Time Simulation Active (${timeService.formattedOffset})'
                    : 'Time Simulation & Fast-Forward Controls',
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => TimeTravelSheet.show(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSimulated
                            ? Colors.amber.shade100
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSimulated
                              ? Colors.amber.shade700
                              : Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.6),
                          width: isSimulated ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSimulated
                                ? Icons.more_time_rounded
                                : Icons.access_time_rounded,
                            size: isCompact ? 16 : 18,
                            color: isSimulated
                                ? Colors.amber.shade900
                                : Theme.of(context).colorScheme.primary,
                          ),
                          if (isSimulated) ...[
                            const SizedBox(width: 4),
                            Text(
                              timeService.formattedOffset,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Real-Time Admin Notifications Bell (`admin_notifications`)
          Builder(
            builder: (context) {
              final inv = context.watch<InventoryProvider>();
              final unread = inv.unreadAdminNotificationCount;
              return Tooltip(
                message: unread > 0
                    ? '$unread Unread Inventory Alerts'
                    : 'Inventory Alerts',
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _showAdminNotificationsSheet(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: unread > 0
                            ? Colors.amber.shade800.withValues(alpha: 0.12)
                            : Colors.transparent,
                        border: Border.all(
                          color: unread > 0
                              ? Colors.amber.shade800
                              : Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.6),
                        ),
                      ),
                      child: Badge.count(
                        count: unread,
                        isLabelVisible: unread > 0,
                        backgroundColor: Theme.of(context).colorScheme.error,
                        child: Icon(
                          unread > 0
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_outlined,
                          size: isCompact ? 18 : 20,
                          color: unread > 0
                              ? Colors.amber.shade900
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Dark Mode Toggle Button (Relocated cleanly in top right)
          Tooltip(
            message: context.watch<ThemeProvider>().isDarkMode
                ? 'Switch to Light Mode'
                : 'Switch to Dark Mode',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context
                    .read<ThemeProvider>()
                    .toggleTheme(!context.read<ThemeProvider>().isDarkMode),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.6),
                    ),
                  ),
                  child: Icon(
                    context.watch<ThemeProvider>().isDarkMode
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_outlined,
                    size: isCompact ? 18 : 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          if (isCompact) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.logout_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: 'Log Out',
              onPressed: () => _confirmLogout(context, auth),
            ),
          ],
        ],
      ),
    );
  }

  String _getRoleLabel(UserRole role) => switch (role) {
        UserRole.admin => 'Administrator',
        UserRole.trustedPartner => 'Trusted Partner',
        UserRole.none => 'Access Denied',
      };
}

// ── SIDEBAR LOGOUT BUTTON WIDGET ──────────────────────────────────────────────

class _SideLogoutButton extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  const _SideLogoutButton({
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    if (!isExpanded) {
      return IconButton(
        icon: Icon(Icons.logout_rounded, color: errorColor, size: 20),
        tooltip: 'Log Out',
        onPressed: onTap,
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: errorColor.withValues(alpha: 0.12),
        highlightColor: errorColor.withValues(alpha: 0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.logout_rounded, color: errorColor, size: 20),
              const SizedBox(width: 12),
              Text(
                'Log Out',
                style: TextStyle(
                  color: errorColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmLogout(BuildContext context, AppAuthProvider auth) async {
  final theme = Theme.of(context);
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.all(20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.logout_rounded,
              color: Colors.red.shade700,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Confirm Logout',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
      content: Text(
        'Are you sure you want to log out of your account?',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 15,
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text(
            'Log Out',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  if (confirm == true) {
    await auth.logout();
  }
}

Future<void> _showAdminNotificationsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) {
          final theme = Theme.of(ctx);
          final inv = ctx.watch<InventoryProvider>();
          final notifications = inv.adminNotifications;
          final unreadCount = inv.unreadAdminNotificationCount;

          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inventory Alerts',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              unreadCount > 0
                                  ? '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}'
                                  : 'All caught up',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (unreadCount > 0)
                        TextButton.icon(
                          onPressed: () => inv.markAllAdminNotificationsRead(),
                          icon: const Icon(Icons.done_all_rounded, size: 16),
                          label: const Text('Mark all read'),
                        ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: notifications.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.notifications_none_rounded,
                                  size: 48,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No inventory alerts yet',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Store inventory notifications and system alerts appear here automatically.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: notifications.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final item = notifications[index];
                            final id = (item['id'] ?? '').toString();
                            final type = (item['type'] ?? '').toString();
                            final severity =
                                (item['severity'] ?? 'info').toString();
                            final title =
                                (item['title'] ?? 'Inventory Alert').toString();
                            final message =
                                (item['message'] ?? item['body'] ?? '')
                                    .toString();
                            final isRead = item['isRead'] == true;
                            final status = (item['status'] ?? '').toString();
                            final suggestedRestock = item['suggestedRestock'];

                            DateTime? createdAt;
                            final rawCreated = item['createdAt'];
                            if (rawCreated is Timestamp) {
                              createdAt = rawCreated.toDate();
                            } else if (rawCreated is DateTime) {
                              createdAt = rawCreated;
                            } else if (rawCreated is String) {
                              createdAt = DateTime.tryParse(rawCreated);
                            }

                            final Color accentColor;
                            final IconData iconData;
                            if (type == 'out_of_stock' ||
                                severity == 'critical') {
                              accentColor = theme.colorScheme.error;
                              iconData = Icons.error_outline_rounded;
                            } else if (type == 'physical_low_stock_alert' ||
                                severity == 'warning') {
                              accentColor = Colors.amber.shade800;
                              iconData = Icons.warning_amber_rounded;
                            } else if (type == 'daily_resupply_summary') {
                              accentColor = Colors.teal.shade700;
                              iconData = Icons.mark_email_read_rounded;
                            } else {
                              accentColor = theme.colorScheme.primary;
                              iconData = Icons.notifications_rounded;
                            }

                            return Material(
                              color: isRead
                                  ? theme.colorScheme.surfaceContainerLowest
                                  : accentColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  if (!isRead && id.isNotEmpty) {
                                    inv.markAdminNotificationRead(id);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isRead
                                          ? theme.colorScheme.outlineVariant
                                              .withValues(alpha: 0.5)
                                          : accentColor.withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: accentColor.withValues(
                                              alpha: 0.14),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          iconData,
                                          size: 18,
                                          color: accentColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    title,
                                                    style: theme
                                                        .textTheme.titleSmall
                                                        ?.copyWith(
                                                      fontWeight: isRead
                                                          ? FontWeight.w600
                                                          : FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                if (!isRead)
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    margin:
                                                        const EdgeInsets.only(
                                                            left: 8),
                                                    decoration: BoxDecoration(
                                                      color: accentColor,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            if (message.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                message,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                            if (status.isNotEmpty ||
                                                suggestedRestock != null) ...[
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  if (status.isNotEmpty)
                                                    _NotificationMetaChip(
                                                      label: status,
                                                      color: accentColor,
                                                    ),
                                                  if (suggestedRestock != null)
                                                    _NotificationMetaChip(
                                                      label:
                                                          'Restock: +$suggestedRestock',
                                                      color:
                                                          Colors.teal.shade700,
                                                    ),
                                                ],
                                              ),
                                            ],
                                            if (createdAt != null) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                DateFormat(
                                                        'MMM d, yyyy • h:mm a')
                                                    .format(createdAt),
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  color:
                                                      theme.colorScheme.outline,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _NotificationMetaChip extends StatelessWidget {
  final String label;
  final Color color;

  const _NotificationMetaChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
