import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/inventory_provider.dart';
import '../providers/order_provider.dart';
import '../providers/expense_provider.dart';
import '../models/order.dart';
import '../config/theme.dart';
import '../screens/admin_app.dart';

/// Categories for filtering global search results.
enum GlobalSearchDomain {
  all,
  products,
  orders,
  transactions,
  suppliers,
  customers,
  deliveryLogs,
  expenses,
  lossRecords,
  quickActions,
}

extension GlobalSearchDomainExt on GlobalSearchDomain {
  String get label => switch (this) {
        GlobalSearchDomain.all => 'All Results',
        GlobalSearchDomain.products => 'Products & Stock',
        GlobalSearchDomain.orders => 'Pre-orders',
        GlobalSearchDomain.transactions => 'Sales History',
        GlobalSearchDomain.suppliers => 'Suppliers',
        GlobalSearchDomain.customers => 'Customers',
        GlobalSearchDomain.deliveryLogs => 'Delivery Logs',
        GlobalSearchDomain.expenses => 'Expenses',
        GlobalSearchDomain.lossRecords => 'Loss & Spoilage',
        GlobalSearchDomain.quickActions => 'Quick Actions',
      };

  IconData get icon => switch (this) {
        GlobalSearchDomain.all => Icons.search_rounded,
        GlobalSearchDomain.products => Icons.inventory_2_outlined,
        GlobalSearchDomain.orders => Icons.assignment_outlined,
        GlobalSearchDomain.transactions => Icons.receipt_long_outlined,
        GlobalSearchDomain.suppliers => Icons.local_shipping_outlined,
        GlobalSearchDomain.customers => Icons.people_outline_rounded,
        GlobalSearchDomain.deliveryLogs => Icons.history_edu_rounded,
        GlobalSearchDomain.expenses => Icons.account_balance_wallet_outlined,
        GlobalSearchDomain.lossRecords => Icons.report_problem_outlined,
        GlobalSearchDomain.quickActions => Icons.bolt_rounded,
      };
}

/// Unified Result Item Model for Global Search Palette
class GlobalSearchResultItem {
  final String title;
  final String subtitle;
  final String domainLabel;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  const GlobalSearchResultItem({
    required this.title,
    required this.subtitle,
    required this.domainLabel,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });
}

/// Global Admin Command Palette & Automated Search/Filter Modal
class GlobalAdminSearchPalette extends StatefulWidget {
  final Function(AppTab tab, {String? category}) onNavigateTab;

  const GlobalAdminSearchPalette({
    super.key,
    required this.onNavigateTab,
  });

  /// Displays the Global Search Palette dialog
  static Future<void> show(
    BuildContext context, {
    required Function(AppTab tab, {String? category}) onNavigateTab,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => GlobalAdminSearchPalette(
        onNavigateTab: onNavigateTab,
      ),
    );
  }

  @override
  State<GlobalAdminSearchPalette> createState() =>
      _GlobalAdminSearchPaletteState();
}

class _GlobalAdminSearchPaletteState extends State<GlobalAdminSearchPalette> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  GlobalSearchDomain _selectedDomain = GlobalSearchDomain.all;

  // Quick Filter Toggles
  bool _lowStockOnly = false;
  bool _pendingOrdersOnly = false;
  bool _restrictedCustomersOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String formatPeso(double amount) => '₱${amount.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final inventoryProvider = context.watch<InventoryProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final expenseProvider = context.watch<ExpenseProvider>();

    final results = _buildSearchResults(
      inventoryProvider,
      orderProvider,
      expenseProvider,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          }
        },
        child: Container(
          width: 760,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Input Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _focusNode,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Search anything (products, orders, customers, logs, actions)…',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.45),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.cancel_rounded, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? theme.colorScheme.surfaceContainerHigh
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'ESC to close',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),

              // Domain Selector Filter Chips & Quick Toggles
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isDark
                    ? theme.colorScheme.surfaceContainerLow
                    : const Color(0xFFF8FAFC),
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: GlobalSearchDomain.values.map((domain) {
                          final isSelected = _selectedDomain == domain;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              selected: isSelected,
                              avatar: Icon(
                                domain.icon,
                                size: 14,
                                color: isSelected
                                    ? (isDark
                                        ? GdcColors.darkEmerald
                                        : Colors.white)
                                    : theme.colorScheme.primary,
                              ),
                              label: Text(domain.label),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? (isDark
                                        ? GdcColors.darkEmerald
                                        : Colors.white)
                                    : theme.colorScheme.onSurface,
                              ),
                              backgroundColor: isDark
                                  ? theme.colorScheme.surfaceContainerHigh
                                  : Colors.white,
                              selectedColor: isDark
                                  ? GdcColors.emeraldPrimary
                                  : GdcColors.darkEmerald,
                              onSelected: (_) {
                                setState(() => _selectedDomain = domain);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Quick Smart Toggles Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            selected: _lowStockOnly,
                            avatar: Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: _lowStockOnly
                                  ? Colors.white
                                  : Colors.amber.shade800,
                            ),
                            label: const Text('Low Stock Only'),
                            selectedColor: Colors.amber.shade800,
                            onSelected: (v) =>
                                setState(() => _lowStockOnly = v),
                          ),
                          const SizedBox(width: 6),
                          FilterChip(
                            selected: _pendingOrdersOnly,
                            avatar: Icon(
                              Icons.pending_actions_rounded,
                              size: 14,
                              color: _pendingOrdersOnly
                                  ? Colors.white
                                  : Colors.blue.shade700,
                            ),
                            label: const Text('Pending Pre-Orders Only'),
                            selectedColor: Colors.blue.shade700,
                            onSelected: (v) =>
                                setState(() => _pendingOrdersOnly = v),
                          ),
                          const SizedBox(width: 6),
                          FilterChip(
                            selected: _restrictedCustomersOnly,
                            avatar: Icon(
                              Icons.block_rounded,
                              size: 14,
                              color: _restrictedCustomersOnly
                                  ? Colors.white
                                  : Colors.red.shade700,
                            ),
                            label: const Text('Restricted Customers Only'),
                            selectedColor: Colors.red.shade700,
                            onSelected: (v) =>
                                setState(() => _restrictedCustomersOnly = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),

              // Search Results List
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _query.isEmpty
                                    ? 'Start typing to automatically search & filter across all admin areas…'
                                    : 'No items or records matched your query "$_query"',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.25),
                        ),
                        itemBuilder: (ctx, idx) {
                          final item = results[idx];
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: item.iconColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(item.icon,
                                  size: 20, color: item.iconColor),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (item.badge != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (item.badgeColor ??
                                              theme.colorScheme.primary)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: (item.badgeColor ??
                                                theme.colorScheme.primary)
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Text(
                                      item.badge!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: item.badgeColor ??
                                            theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              '${item.domainLabel} • ${item.subtitle}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              item.onTap();
                            },
                          );
                        },
                      ),
              ),

              // Bottom Status Bar Footer
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerLow
                      : const Color(0xFFF1F5F9),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Found ${results.length} item(s) across admin modules',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Global Search & Smart Filtering active',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<GlobalSearchResultItem> _buildSearchResults(
    InventoryProvider inventory,
    OrderProvider order,
    ExpenseProvider expense,
  ) {
    final list = <GlobalSearchResultItem>[];
    final q = _query.toLowerCase();

    // 1. QUICK ACTIONS & NAVIGATION
    if (_selectedDomain == GlobalSearchDomain.all ||
        _selectedDomain == GlobalSearchDomain.quickActions) {
      final actions = [
        (
          'Inventory Screen',
          'Manage stock levels, prices, and categories',
          AppTab.inventory,
          Icons.inventory_2_rounded
        ),
        (
          'Point of Sale Terminal',
          'Process manual walk-in sales',
          AppTab.pos,
          Icons.point_of_sale_rounded
        ),
        (
          'Customer Pre-Orders',
          'Fulfill and stage pending online orders',
          AppTab.preOrders,
          Icons.assignment_rounded
        ),
        (
          'Shift & Cash Drawer',
          'View register shifts and cash balances',
          AppTab.shift,
          Icons.access_time_filled
        ),
        (
          'Reports & Financial Analytics',
          'View revenue, profit, and inventory metrics',
          AppTab.reports,
          Icons.bar_chart_rounded
        ),
        (
          'Sales History & Receipts',
          'Audit previous transactions and customer receipts',
          AppTab.salesHistory,
          Icons.receipt_long_rounded
        ),
        (
          'Inventory Records & Batches',
          'Delivery logs, active lots, spoilage, and shift history',
          AppTab.inventoryRecords,
          Icons.history_edu_rounded
        ),
        (
          'Supplier Management',
          'Manage supplier contacts, catalog, and restock orders',
          AppTab.suppliers,
          Icons.local_shipping_rounded
        ),
        (
          'Operational Expenses',
          'Track utility bills, maintenance, and store expenses',
          AppTab.more,
          Icons.account_balance_wallet_rounded
        ),
        (
          'Customer Restrictions & Appeals',
          'Manage customer offenses and unblock requests',
          AppTab.more,
          Icons.block_rounded
        ),
      ];

      for (final a in actions) {
        if (q.isEmpty ||
            a.$1.toLowerCase().contains(q) ||
            a.$2.toLowerCase().contains(q)) {
          list.add(
            GlobalSearchResultItem(
              title: a.$1,
              subtitle: a.$2,
              domainLabel: 'Quick Navigation',
              icon: a.$4,
              iconColor: Colors.teal,
              onTap: () => widget.onNavigateTab(a.$3),
              badge: 'ACTION',
              badgeColor: Colors.teal,
            ),
          );
        }
      }
    }

    // 2. PRODUCTS & STOCK
    if (_selectedDomain == GlobalSearchDomain.all ||
        _selectedDomain == GlobalSearchDomain.products) {
      for (final p in inventory.products) {
        final isLow = p.totalStock <= p.lowStockThreshold;
        if (_lowStockOnly && !isLow) continue;

        final matchesName = p.name.toLowerCase().contains(q);
        final matchesBrand = p.brand?.toLowerCase().contains(q) ?? false;
        final matchesBarcode = p.barcode?.toLowerCase().contains(q) ?? false;
        final matchesCategory = p.category.toLowerCase().contains(q);

        if (q.isEmpty ||
            matchesName ||
            matchesBrand ||
            matchesBarcode ||
            matchesCategory ||
            (q == 'low stock' && isLow)) {
          list.add(
            GlobalSearchResultItem(
              title: p.name,
              subtitle:
                  'Brand: ${p.brand ?? "N/A"} • Stock: ${p.totalStock} • Price: ${formatPeso(p.price)}',
              domainLabel: 'Product (${p.category})',
              icon: Icons.inventory_2_rounded,
              iconColor: isLow ? Colors.amber.shade800 : Colors.teal.shade700,
              badge: isLow ? 'LOW STOCK' : 'IN STOCK',
              badgeColor: isLow ? Colors.amber.shade800 : Colors.teal.shade700,
              onTap: () {
                widget.onNavigateTab(AppTab.inventory, category: p.category);
              },
            ),
          );
        }
      }
    }

    // 3. PRE-ORDERS
    if (_selectedDomain == GlobalSearchDomain.all ||
        _selectedDomain == GlobalSearchDomain.orders) {
      for (final o in order.orders) {
        final isPending = o.status == OrderStatus.pending;
        if (_pendingOrdersOnly && !isPending) continue;

        final matchesId = o.id.toLowerCase().contains(q);
        final matchesOrderId = o.orderId.toLowerCase().contains(q);
        final matchesName = o.customerName.toLowerCase().contains(q);
        final matchesPhone =
            o.customerPhone?.toLowerCase().contains(q) ?? false;
        final matchesStatus = o.status.name.toLowerCase().contains(q);

        if (q.isEmpty ||
            matchesId ||
            matchesOrderId ||
            matchesName ||
            matchesPhone ||
            matchesStatus) {
          list.add(
            GlobalSearchResultItem(
              title: 'Order #${o.orderId} (${o.customerName})',
              subtitle:
                  'Phone: ${o.customerPhone ?? "N/A"} • Total: ${formatPeso(o.total)} • Status: ${o.status.name.toUpperCase()}',
              domainLabel: 'Pre-Order',
              icon: Icons.assignment_rounded,
              iconColor:
                  isPending ? Colors.blue.shade700 : Colors.purple.shade700,
              badge: o.status.name.toUpperCase(),
              badgeColor:
                  isPending ? Colors.blue.shade700 : Colors.purple.shade700,
              onTap: () {
                widget.onNavigateTab(AppTab.preOrders);
              },
            ),
          );
        }
      }
    }

    // 4. SALES HISTORY & TRANSACTIONS
    if (_selectedDomain == GlobalSearchDomain.all ||
        _selectedDomain == GlobalSearchDomain.transactions) {
      for (final tx in inventory.transactions) {
        final matchesId = tx.id.toLowerCase().contains(q);
        final matchesCustomer =
            tx.customerEmail?.toLowerCase().contains(q) ?? false;
        final matchesPayment = tx.paymentMethod.name.toLowerCase().contains(q);

        if (q.isEmpty || matchesId || matchesCustomer || matchesPayment) {
          list.add(
            GlobalSearchResultItem(
              title:
                  'Tx #${tx.id.substring(0, tx.id.length > 8 ? 8 : tx.id.length)} - ${formatPeso(tx.total)}',
              subtitle:
                  'Customer: ${tx.customerEmail ?? "Walk-in"} • Method: ${tx.paymentMethod.name.toUpperCase()}',
              domainLabel: 'Sales Receipt',
              icon: Icons.receipt_long_rounded,
              iconColor: Colors.indigo.shade700,
              badge: tx.paymentMethod.name.toUpperCase(),
              badgeColor: Colors.indigo.shade700,
              onTap: () {
                widget.onNavigateTab(AppTab.salesHistory);
              },
            ),
          );
        }
      }
    }

    // 5. SUPPLIERS
    if (_selectedDomain == GlobalSearchDomain.all ||
        _selectedDomain == GlobalSearchDomain.suppliers) {
      for (final s in inventory.suppliers) {
        final matchesName = s.name.toLowerCase().contains(q);
        final matchesContact = s.contactName.toLowerCase().contains(q);
        final matchesPhone = s.phone.toLowerCase().contains(q);

        if (q.isEmpty || matchesName || matchesContact || matchesPhone) {
          list.add(
            GlobalSearchResultItem(
              title: s.name,
              subtitle:
                  'Contact: ${s.contactName.isNotEmpty ? s.contactName : "N/A"} • Phone: ${s.phone.isNotEmpty ? s.phone : "N/A"}',
              domainLabel: 'Supplier',
              icon: Icons.local_shipping_rounded,
              iconColor: Colors.deepOrange.shade700,
              badge: 'SUPPLIER',
              badgeColor: Colors.deepOrange.shade700,
              onTap: () {
                widget.onNavigateTab(AppTab.suppliers);
              },
            ),
          );
        }
      }
    }

    // 6. CUSTOMERS
    if (_selectedDomain == GlobalSearchDomain.all ||
        _selectedDomain == GlobalSearchDomain.customers) {
      for (final c in inventory.customers) {
        final isRestricted = c.offenseCount > 0 || c.isPermanentlyLocked;
        if (_restrictedCustomersOnly && !isRestricted) continue;

        final matchesName = c.name.toLowerCase().contains(q);
        final matchesEmail = c.email?.toLowerCase().contains(q) ?? false;
        final matchesPhone = c.phone.toLowerCase().contains(q);

        if (q.isEmpty || matchesName || matchesEmail || matchesPhone) {
          list.add(
            GlobalSearchResultItem(
              title: c.name,
              subtitle:
                  'Email: ${c.email ?? "N/A"} • Total Spent: ${formatPeso(c.totalSpent)} • Offenses: ${c.offenseCount}',
              domainLabel: 'Customer Profile',
              icon: Icons.people_alt_rounded,
              iconColor:
                  isRestricted ? Colors.red.shade700 : Colors.cyan.shade700,
              badge: isRestricted ? 'OFFENSES: ${c.offenseCount}' : 'ACTIVE',
              badgeColor:
                  isRestricted ? Colors.red.shade700 : Colors.cyan.shade700,
              onTap: () {
                widget.onNavigateTab(AppTab.more);
              },
            ),
          );
        }
      }
    }

    // 7. DELIVERY LOGS
    if (_selectedDomain == GlobalSearchDomain.all ||
        _selectedDomain == GlobalSearchDomain.deliveryLogs) {
      for (final dl in inventory.deliveryLogs) {
        final matchesInvoice =
            dl.invoiceNumber?.toLowerCase().contains(q) ?? false;
        final matchesSupplier =
            dl.supplierName?.toLowerCase().contains(q) ?? false;
        final matchesReceiver = dl.receivedBy.toLowerCase().contains(q);

        if (q.isEmpty || matchesInvoice || matchesSupplier || matchesReceiver) {
          list.add(
            GlobalSearchResultItem(
              title:
                  'Delivery Invoice #${dl.invoiceNumber ?? "N/A"} (${dl.supplierName ?? "General"})',
              subtitle:
                  'Received By: ${dl.receivedBy} • Total Value: ${formatPeso(dl.totalValue)} • Qty: ${dl.qtyReceived}',
              domainLabel: 'Delivery Log',
              icon: Icons.history_edu_rounded,
              iconColor: Colors.brown.shade700,
              badge: 'DELIVERY LOG',
              badgeColor: Colors.brown.shade700,
              onTap: () {
                widget.onNavigateTab(AppTab.inventoryRecords);
              },
            ),
          );
        }
      }
    }

    // 8. EXPENSES
    if (_selectedDomain == GlobalSearchDomain.all ||
        _selectedDomain == GlobalSearchDomain.expenses) {
      for (final e in expense.expenses) {
        final matchesDesc = e.description.toLowerCase().contains(q);
        final matchesCategory = e.category.toLowerCase().contains(q);

        if (q.isEmpty || matchesDesc || matchesCategory) {
          list.add(
            GlobalSearchResultItem(
              title: e.description,
              subtitle:
                  'Category: ${e.category} • Amount: ${formatPeso(e.amount)} • Date: ${DateFormat("MMM d, yyyy").format(e.createdAt)}',
              domainLabel: 'Expense Record',
              icon: Icons.account_balance_wallet_rounded,
              iconColor: Colors.teal.shade800,
              badge: formatPeso(e.amount),
              badgeColor: Colors.teal.shade800,
              onTap: () {
                widget.onNavigateTab(AppTab.more);
              },
            ),
          );
        }
      }
    }

    // 9. LOSS & SPOILAGE RECORDS
    if (_selectedDomain == GlobalSearchDomain.all ||
        _selectedDomain == GlobalSearchDomain.lossRecords) {
      for (final loss in inventory.lossRecords) {
        final matchesProduct = loss.productName.toLowerCase().contains(q);
        final matchesType = loss.type.name.toLowerCase().contains(q);
        final matchesNotes = loss.notes.toLowerCase().contains(q);

        if (q.isEmpty || matchesProduct || matchesType || matchesNotes) {
          list.add(
            GlobalSearchResultItem(
              title: '${loss.productName} (Qty: ${loss.qty})',
              subtitle:
                  'Reason: ${loss.type.name.toUpperCase()} (${loss.notes}) • Cost: ${formatPeso(loss.totalLoss)} • Date: ${DateFormat("MMM d, yyyy").format(loss.createdAt)}',
              domainLabel: 'Spoilage / Write-off',
              icon: Icons.report_problem_rounded,
              iconColor: Colors.red.shade800,
              badge: loss.type.name.toUpperCase(),
              badgeColor: Colors.red.shade800,
              onTap: () {
                widget.onNavigateTab(AppTab.inventoryRecords);
              },
            ),
          );
        }
      }
    }

    return list;
  }
}
