import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  void _navigateToDestination(String destinationId, {String? category}) {
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
                o.status == OrderStatus.pending || o.status == OrderStatus.staging)
            .length +
        pendingRefundsCount;

    return LayoutBuilder(
      builder: (context, constraints) {
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

        return Scaffold(
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
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
                                        onTap: () {
                                          setState(() {
                                            _activeDestinationId = d.id;
                                          });
                                        },
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
                              constraints: const BoxConstraints(maxWidth: 1280),
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
                        setState(() {
                          _activeDestinationId = destinations[idx].id;
                        });
                      }
                    },
                    destinations: navDestinations,
                  ),
                )
              : null,
        );
      },
    );
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
    final Color activeBorder = isDark
        ? GdcColors.emeraldPrimary
        : GdcColors.darkEmerald;
    final Color activeFg = isDark
        ? GdcColors.emeraldPrimary
        : GdcColors.darkEmerald;

    final Color inactiveFg = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF64748B);

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
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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

  const _AdminTopBar({
    required this.auth,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: isCompact ? 56 : 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.4),
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
                  color: Theme.of(context).colorScheme.onSurface,
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
          const Spacer(),
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

