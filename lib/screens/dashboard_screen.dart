import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/order_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/restock_provider.dart';
import '../models/order.dart';
import '../models/expense.dart';
import '../models/loss_record.dart';
import '../models/transaction.dart';
import '../models/restock_inquiry.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../models/store_settings.dart';
import '../utils/format.dart';
import '../widgets/receive_delivery_sheet.dart';
import '../widgets/batch_expiration_widget.dart';
import 'admin_app.dart';
import 'supplier_detail_screen.dart';
import 'supplier_management_screen.dart';

class _DailyMetric {
  final DateTime date;
  final double grossSales;
  final double netProfit;

  const _DailyMetric({
    required this.date,
    required this.grossSales,
    required this.netProfit,
  });
}

class _DashboardData {
  final double todayGrossSales;
  final double todayLoss;
  final double todayCogs;
  final double todayNetProfit;
  final double todayExp;
  final int toProcessOrders;
  final int restockPending;
  final List<StoreTransaction> todayTx;
  final List<Product> lowStockProducts;
  final List<MapEntry<String, int>> fastMoving;
  final List<Product> slowMoving;
  final List<_DailyMetric> chartMetrics;

  const _DashboardData({
    required this.todayGrossSales,
    required this.todayLoss,
    required this.todayCogs,
    required this.todayNetProfit,
    required this.todayExp,
    required this.toProcessOrders,
    required this.restockPending,
    required this.todayTx,
    required this.lowStockProducts,
    required this.fastMoving,
    required this.slowMoving,
    required this.chartMetrics,
  });
}

class _IsolateComputationParams {
  final List<StoreTransaction> transactions;
  final List<PreOrder> orders;
  final List<Expense> expenses;
  final List<LossRecord> lossRecords;
  final List<Product> products;
  final List<RestockInquiry> inquiries;
  final List<MapEntry<String, int>> fastMoving;
  final List<Product> slowMoving;

  const _IsolateComputationParams({
    required this.transactions,
    required this.orders,
    required this.expenses,
    required this.lossRecords,
    required this.products,
    required this.inquiries,
    required this.fastMoving,
    required this.slowMoving,
  });
}

_DashboardData _computeDashboardData(_IsolateComputationParams params) {
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final currentMonth = DateFormat('yyyy-MM').format(DateTime.now());

  // Filter today's transactions for the recent transaction list
  final todayTx = params.transactions.where((t) {
    try {
      return DateFormat('yyyy-MM-dd').format(t.createdAt) == today;
    } catch (_) {
      return false;
    }
  }).toList();

  // Filter current month transactions for monthly metric aggregation
  final monthTx = params.transactions.where((t) {
    try {
      return DateFormat('yyyy-MM').format(t.createdAt) == currentMonth;
    } catch (_) {
      return false;
    }
  }).toList();

  final double gross = monthTx.fold(0.0, (sum, t) {
    final val = t.total;
    return sum + ((val.isNaN || val.isInfinite) ? 0.0 : val);
  });

  final double loss = params.lossRecords.where((l) {
    try {
      return DateFormat('yyyy-MM').format(l.createdAt) == currentMonth;
    } catch (_) {
      return false;
    }
  }).fold(0.0, (sum, l) {
    final unit = l.unitPrice;
    final safeUnit = (unit.isNaN || unit.isInfinite) ? 0.0 : unit;
    return sum + (safeUnit * l.qty);
  });

  final double cogs = monthTx.fold(0.0, (sum, t) {
    return sum +
        t.items.fold(0.0, (itemSum, item) {
          final cost = item.costPrice;
          final safeCost = (cost.isNaN || cost.isInfinite) ? 0.0 : cost;
          return itemSum + (safeCost * item.qty);
        });
  });

  final double rawNetProfit = gross - cogs - loss;
  final double netProfit =
      (rawNetProfit.isNaN || rawNetProfit.isInfinite) ? 0.0 : rawNetProfit;

  final double exp = params.expenses.where((e) {
    try {
      return DateFormat('yyyy-MM').format(e.createdAt) == currentMonth;
    } catch (_) {
      return false;
    }
  }).fold(0.0, (sum, e) {
    final amt = e.amount;
    return sum + ((amt.isNaN || amt.isInfinite) ? 0.0 : amt);
  });

  final int toProcess = params.orders
      .where((o) =>
          o.status == OrderStatus.pending || o.status == OrderStatus.staging)
      .length;

  final int pendingRestock = params.inquiries
      .where((ri) =>
          ri.status == RestockInquiryStatus.draft ||
          ri.status == RestockInquiryStatus.pending ||
          ri.status == RestockInquiryStatus.sent ||
          ri.status == RestockInquiryStatus.acknowledged ||
          ri.status == RestockInquiryStatus.partiallyFulfilled)
      .length;

  final lowStock = params.products
      .where((p) =>
          p.status == ProductStatus.published &&
          p.totalStock <= p.lowStockThreshold)
      .toList();

  final chartMetrics =
      _computeChartMetrics(params.transactions, params.lossRecords);

  return _DashboardData(
    todayGrossSales: gross,
    todayLoss: loss,
    todayCogs: cogs,
    todayNetProfit: netProfit,
    todayExp: exp,
    toProcessOrders: toProcess,
    restockPending: pendingRestock,
    todayTx: todayTx,
    lowStockProducts: lowStock,
    fastMoving: params.fastMoving,
    slowMoving: params.slowMoving,
    chartMetrics: chartMetrics,
  );
}

Future<_DashboardData> _computeDashboardDataAsync(
    _IsolateComputationParams params) async {
  return Future.microtask(() => _computeDashboardData(params));
}

List<_DailyMetric> _computeChartMetrics(
  List<StoreTransaction> transactions,
  List<LossRecord> lossRecords, {
  int days = 7,
  int offsetDays = 0,
}) {
  final now = DateTime.now().subtract(Duration(days: offsetDays));
  final List<_DailyMetric> list = [];

  for (int i = days - 1; i >= 0; i--) {
    final dayDate = now.subtract(Duration(days: i));
    final dayStr = DateFormat('yyyy-MM-dd').format(dayDate);

    final dayTx = transactions.where((t) {
      try {
        return DateFormat('yyyy-MM-dd').format(t.createdAt) == dayStr;
      } catch (_) {
        return false;
      }
    }).toList();

    final dayLoss = lossRecords.where((l) {
      try {
        return DateFormat('yyyy-MM-dd').format(l.createdAt) == dayStr;
      } catch (_) {
        return false;
      }
    }).fold(0.0, (sum, l) => sum + (l.unitPrice * l.qty));

    final gross = dayTx.fold(0.0, (sum, t) => sum + t.total);
    final cogs = dayTx.fold(
        0.0,
        (sum, t) =>
            sum +
            t.items
                .fold(0.0, (iSum, item) => iSum + (item.costPrice * item.qty)));
    final profit = gross - cogs - dayLoss;

    final safeGross =
        (gross.isNaN || gross.isInfinite || gross < 0) ? 0.0 : gross;
    final safeProfit =
        (profit.isNaN || profit.isInfinite || profit < 0) ? 0.0 : profit;

    list.add(_DailyMetric(
      date: dayDate,
      grossSales: safeGross,
      netProfit: safeProfit,
    ));
  }

  return list;
}

/// Store executive dashboard screen displaying financial metrics, sales charts, and inventory stock alerts.
class DashboardScreen extends StatefulWidget {
  final Function(AppTab, {String? category}) onTabChange;
  const DashboardScreen({super.key, required this.onTabChange});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  _DashboardData? _cachedData;

  @override
  Widget build(BuildContext context) {
    // 1. STATE HYDRATION GATE (THE PROCESS FLOW)
    final inventory = context.watch<InventoryProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final restockProvider = context.watch<RestockProvider>();
    final expenseProvider = context.watch<ExpenseProvider>();

    final bool isSyncing = inventory.isLoading ||
        orderProvider.isLoading ||
        restockProvider.isLoading;

    final auth = context.watch<AppAuthProvider>();
    final categoryCount =
        inventory.products.map((p) => p.category).toSet().length;

    // 2. ASYNCHRONOUS MATH PROCESSING
    final params = _IsolateComputationParams(
      transactions: inventory.transactions,
      orders: orderProvider.orders,
      expenses: expenseProvider.expenses,
      lossRecords: inventory.lossRecords,
      products: inventory.products,
      inquiries: restockProvider.inquiries,
      fastMoving: inventory.fastMovingItems,
      slowMoving: inventory.slowMovingItems,
    );

    return FutureBuilder<_DashboardData>(
      future: _computeDashboardDataAsync(params),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _cachedData = snapshot.data;
        }

        // Only show full loading spinner if we have no cached data at all
        if (_cachedData == null &&
            (isSyncing || snapshot.connectionState != ConnectionState.done)) {
          return Container(
            color: Theme.of(context).colorScheme.surface,
            alignment: Alignment.center,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(height: 16),
                Text(
                  'Loading Dashboard...',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        }

        final data = _cachedData!;
        final bool isRefreshing =
            isSyncing || snapshot.connectionState != ConnectionState.done;

        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  children: [
                    // Subtle linear progress bar during background refresh
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: isRefreshing ? 3.0 : 0.0,
                      child: isRefreshing
                          ? LinearProgressIndicator(
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.7),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          context.read<InventoryProvider>().initialize();
                          context.read<RestockProvider>().refresh();
                          await Future.delayed(
                              const Duration(milliseconds: 600));
                        },
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 20),
                          children: [
                            _buildHeader(context, inventory, isRefreshing),
                            const SizedBox(height: 20),
                            _buildKpiGrid(context, data, auth.role),
                            const SizedBox(height: 16),
                            _buildSummaryMetrics(
                              context,
                              data,
                              auth.role,
                              inventory.products.length,
                              categoryCount,
                            ),
                            const SizedBox(height: 24),
                            _buildLowStockWarnings(context, data, inventory),
                            const SizedBox(height: 16),
                            const BatchExpirationWidget(),
                            const SizedBox(height: 24),
                            _buildChartSection(
                              context,
                              data.chartMetrics,
                              inventory.transactions,
                              inventory.lossRecords,
                            ),
                            const SizedBox(height: 24),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildFastMovingSection(context, data)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildSlowMovingSection(context, data, inventory)),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _buildRecentTransactionsSection(context, data.todayTx),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── 3. MODULAR WIDGET COMPONENTS (BLAST DOORS) ─────────────────────────────

  Widget _buildHeader(BuildContext context, InventoryProvider inventory,
      [bool isSyncing = false]) {
    try {
      final statusLabel = inventory.settings.statusLabel;
      final Color successColor = Colors.green.shade700;
      final Color warningColor = Colors.orange.shade700;
      final Color errorColor = Theme.of(context).colorScheme.error;

      Color statusColor;
      IconData statusIcon;

      switch (statusLabel) {
        case 'MAINTENANCE':
        case 'CLOSED':
          statusColor = errorColor;
          statusIcon = Icons.warning_amber_rounded;
          break;
        case 'SCHEDULED':
          statusColor = warningColor;
          statusIcon = Icons.schedule;
          break;
        case 'OUT OF HOURS':
          statusColor = Colors.orange.shade700;
          statusIcon = Icons.access_time_rounded;
          break;
        case 'OPEN':
        default:
          statusColor = successColor;
          statusIcon = Icons.storefront;
          break;
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Admin Dashboard',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  if (isSyncing) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE, MMMM d').format(DateTime.now()),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          ActionChip(
            backgroundColor: statusColor.withValues(alpha: 0.12),
            side: BorderSide(color: statusColor.withValues(alpha: 0.25)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            avatar: Icon(statusIcon, size: 16, color: statusColor),
            label: Text(
              statusLabel,
              style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 11),
            ),
            onPressed: () => _showStatusDialog(context, inventory),
          ),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildKpiGrid(
      BuildContext context, _DashboardData data, UserRole role) {
    try {
      final Color successColor = Colors.green.shade700;
      final Color warningColor = Colors.orange.shade700;
      final Color infoColor = Colors.blue.shade700;
      final Color errorColor = Theme.of(context).colorScheme.error;

      final currentMonthName = DateFormat('MMMM').format(DateTime.now());
      final bool isAdmin = role == UserRole.admin;
      final items = isAdmin
          ? [
              _StatCard("Gross Sales ($currentMonthName)", formatPeso(data.todayGrossSales),
                  Icons.auto_graph_rounded, successColor),
              _StatCard("Net Profit ($currentMonthName)", formatPeso(data.todayNetProfit),
                  Icons.monetization_on_rounded, infoColor),
              _StatCard("Loss / Waste ($currentMonthName)", formatPeso(data.todayLoss),
                  Icons.delete_sweep_rounded, errorColor),
              _StatCard("Pre-Orders", "${data.toProcessOrders}",
                  Icons.pending_actions_rounded, warningColor,
                  onTap: () => widget.onTabChange(AppTab.preOrders, category: null)),
            ]
          : [
              _StatCard("Total Products", "${data.lowStockProducts.length}",
                  Icons.inventory_2_rounded, infoColor,
                  onTap: () => widget.onTabChange(AppTab.inventory, category: null)),
              _StatCard("Restock Needed", "${data.restockPending}",
                  Icons.add_shopping_cart_rounded, warningColor,
                  onTap: () =>
                      widget.onTabChange(AppTab.inventory, category: 'Low Stock')),
              _StatCard("Safety Warnings", "${data.lowStockProducts.length}",
                  Icons.warning_amber_rounded, errorColor,
                  onTap: () =>
                      widget.onTabChange(AppTab.inventory, category: 'Low Stock')),
              _StatCard(
                  "Categories", "Catalog", Icons.category_rounded, infoColor),
            ];

      return LayoutBuilder(
        builder: (context, constraints) {
          final double maxExtent = constraints.maxWidth > 700 ? 280 : 200;
          final double itemWidth = (constraints.maxWidth - 36) /
              (constraints.maxWidth > 700 ? 4 : 2);
          final double dynamicRatio = (itemWidth / 115).clamp(1.1, 1.8);

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxExtent,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: dynamicRatio,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => items[index],
          );
        },
      );
    } catch (_) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('KPI metrics unavailable.'),
        ),
      );
    }
  }

  Widget _buildSummaryMetrics(
    BuildContext context,
    _DashboardData data,
    UserRole role,
    int totalProducts,
    int categoryCount,
  ) {
    try {
      final bool isAdmin = role == UserRole.admin;

      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.black.withValues(alpha: 0.02)
                  : Colors.transparent,
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: isAdmin
              ? [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          widget.onTabChange(AppTab.preOrders, category: null),
                      child: _MiniStat('Sales Count', '${data.todayTx.length}'),
                    ),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _MiniStat('Units Sold',
                        '${data.todayTx.fold(0, (s, t) => s + t.items.fold(0, (a, i) => a + i.qty))}'),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _MiniStat(
                        'Avg Basket',
                        data.todayTx.isEmpty
                            ? '—'
                            : formatPeso(
                                data.todayGrossSales / data.todayTx.length)),
                  ),
                ]
              : [
                  Expanded(child: _MiniStat('Total Items', '$totalProducts')),
                  const _Divider(),
                  Expanded(
                      child: _MiniStat(
                          'Low Stock', '${data.lowStockProducts.length}')),
                  const _Divider(),
                  Expanded(child: _MiniStat('Categories', '$categoryCount')),
                ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildChartSection(
    BuildContext context,
    List<_DailyMetric> metrics,
    List<StoreTransaction> transactions,
    List<LossRecord> lossRecords,
  ) {
    try {
      return _RevenueProfitChart(
        initialMetrics: metrics,
        transactions: transactions,
        lossRecords: lossRecords,
      );
    } catch (_) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Chart Unavailable',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildLowStockWarnings(
      BuildContext context, _DashboardData data, InventoryProvider inventory) {
    try {
      final Color errorColor = Theme.of(context).colorScheme.error;

      if (data.lowStockProducts.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: errorColor),
              const SizedBox(width: 8),
              Text(
                'Low Stock Warnings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: errorColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Card(
              color: errorColor.withValues(alpha: 0.08),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: errorColor.withValues(alpha: 0.2)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: data.lowStockProducts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = data.lowStockProducts[index];
                  return ListTile(
                    dense: true,
                    onTap: () =>
                        widget.onTabChange(AppTab.inventory, category: 'Low Stock'),
                    title: Text(p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        'Threshold: ${p.lowStockThreshold} ${p.unit} • Current: ${p.stock} ${p.unit}',
                        style: const TextStyle(fontSize: 10)),
                    trailing: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            if (p.supplierId != null &&
                                p.supplierId!.isNotEmpty) {
                              final supplier = inventory.suppliers.firstWhere(
                                (s) => s.id == p.supplierId,
                                orElse: () => Supplier(id: '', name: ''),
                              );
                              if (supplier.id.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => SupplierDetailScreen(
                                          supplier: supplier)),
                                );
                                return;
                              }
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const SupplierManagementScreen()),
                            );
                          },
                          icon: const Icon(Icons.local_shipping_outlined,
                              size: 14),
                          label: const Text('SUPPLIER',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            RestockInquiry? matchingInquiry;
                            if (p.supplierId != null &&
                                p.supplierId!.isNotEmpty) {
                              final inquiries =
                                  context.read<RestockProvider>().inquiries;
                              try {
                                matchingInquiry = inquiries.firstWhere(
                                  (ri) =>
                                      ri.supplierId == p.supplierId &&
                                      (ri.status ==
                                              RestockInquiryStatus.pending ||
                                          ri.status ==
                                              RestockInquiryStatus.sent ||
                                          ri.status ==
                                              RestockInquiryStatus
                                                  .acknowledged ||
                                          ri.status ==
                                              RestockInquiryStatus
                                                  .partiallyFulfilled) &&
                                      ri.items.any(
                                          (item) => item.productId == p.id),
                                );
                              } catch (_) {}
                            }

                            ReceiveDeliverySheet.show(
                              context: context,
                              initialProduct: p,
                              inquiry: matchingInquiry,
                            );
                          },
                          icon:
                              const Icon(Icons.move_to_inbox_rounded, size: 14),
                          label: const Text('RECEIVE',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.green.shade800,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildFastMovingSection(BuildContext context, _DashboardData data) {
    try {
      final Color warningColor = Colors.orange.shade700;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, size: 20, color: warningColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Fast Moving (30d)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (data.fastMoving.isEmpty)
              _buildEmptyStateCard(
                context,
                icon: Icons.bolt_outlined,
                message: 'No sales yet.',
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: data.fastMoving.length,
                  itemBuilder: (context, index) {
                    final entry = data.fastMoving[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: warningColor.withValues(alpha: 0.15),
                              child: Icon(Icons.bolt_rounded, size: 14, color: warningColor),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(entry.key,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            Text('${entry.value} sold',
                                style: TextStyle(fontSize: 11, color: warningColor, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildSlowMovingSection(
      BuildContext context, _DashboardData data, InventoryProvider inventory) {
    try {
      final Color infoColor = Colors.blue.shade700;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_bottom, size: 20, color: infoColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Slow Moving (30d)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (data.slowMoving.isEmpty)
              _buildEmptyStateCard(
                context,
                icon: Icons.auto_awesome_rounded,
                message: 'All good!',
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: data.slowMoving.length,
                  itemBuilder: (context, index) {
                    final p = data.slowMoving[index];
                    final sold = inventory.recentMovementCounts[p.name] ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: infoColor.withValues(alpha: 0.15),
                              child: Icon(Icons.hourglass_bottom_rounded, size: 14, color: infoColor),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(p.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            Text(sold == 0 ? 'No sales' : '$sold sold',
                                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildRecentTransactionsSection(
      BuildContext context, List<StoreTransaction> todayTx) {
    try {
      return StatefulBuilder(
        builder: (context, setState) {
          return Material(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.4)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                expansionTileTheme: const ExpansionTileThemeData(
                  backgroundColor: Colors.transparent,
                  collapsedBackgroundColor: Colors.transparent,
                ),
              ),
              child: ExpansionTile(
                initiallyExpanded: false,
                title: Row(
                  children: [
                    Icon(Icons.receipt_long, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Recent Transactions', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: todayTx.isEmpty
                      ? _buildEmptyStateCard(context, icon: Icons.receipt_long_outlined, message: 'No sales transactions recorded today.')
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: todayTx.take(10).length,
                          itemBuilder: (context, index) {
                            final tx = todayTx[index];
                            String timeStr = '';
                            try {
                              timeStr = DateFormat('hh:mm a').format(tx.createdAt);
                            } catch (_) {
                              timeStr = 'Just now';
                            }
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: Theme.of(context).colorScheme.surfaceContainerLow,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  child: Icon(Icons.receipt, color: Theme.of(context).colorScheme.primary),
                                ),
                                title: Text(formatPeso(tx.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${tx.items.length} item${tx.items.length != 1 ? 's' : ''} · $timeStr'),
                                trailing: Text(formatPeso(tx.change), style: Theme.of(context).textTheme.labelSmall),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildEmptyStateCard(BuildContext context,
      {required IconData icon, required String message}) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 28,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.4)),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatusDialog(BuildContext context, InventoryProvider inventory) {
    final controller =
        TextEditingController(text: inventory.settings.closureMessage);
    final reasonCtrl = TextEditingController();

    DateTimeRange? selectedDateRange;
    OverrideType selectedType = OverrideType.customOpenHours;
    TimeOfDay customStart =
        const TimeOfDay(hour: 13, minute: 0); // 1:00 PM default
    TimeOfDay customEnd =
        const TimeOfDay(hour: 15, minute: 0); // 3:00 PM default

    TimeOfDay openTime = _parseTimeOfDay(
        inventory.settings.dailyOpenTime, const TimeOfDay(hour: 8, minute: 0));
    TimeOfDay closeTime = _parseTimeOfDay(
        inventory.settings.dailyCloseTime, const TimeOfDay(hour: 21, minute: 0));

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final settings = inventory.settings;
          final isClosed = settings.isClosed;
          final isEffectivelyClosed = settings.effectivelyClosed;
          final closureReason = settings.closureReason;

          final Color errColor = Theme.of(context).colorScheme.error;
          final Color succColor = Colors.green.shade700;

          String formatTime(TimeOfDay t) => t.format(context);
          String formatDate(DateTime d) => DateFormat('MMM d, yyyy').format(d);

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              'Schedule & Holiday Hours',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Container(
              width: 520,
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isEffectivelyClosed
                            ? Theme.of(context)
                                .colorScheme
                                .errorContainer
                                .withValues(alpha: 0.15)
                            : succColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isEffectivelyClosed
                              ? errColor.withValues(alpha: 0.3)
                              : succColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isEffectivelyClosed
                                ? Icons.lock_clock_rounded
                                : Icons.storefront_rounded,
                            color: isEffectivelyClosed ? errColor : succColor,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEffectivelyClosed
                                      ? 'Store is CLOSED'
                                      : 'Store is OPEN',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isEffectivelyClosed
                                        ? errColor
                                        : succColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  closureReason,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Regular Operating Hours',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Opening Time',
                                style: TextStyle(fontSize: 12)),
                            subtitle: Text(_formatTimeOfDayDisplay(openTime),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.access_time, size: 18),
                            onTap: () async {
                              final picked = await showTimePicker(
                                  context: context, initialTime: openTime);
                              if (picked != null && context.mounted) {
                                setDialogState(() => openTime = picked);
                                await inventory
                                    .saveStoreSettings(settings.copyWith(
                                  operatingHoursEnabled: true,
                                  dailyOpenTime: _formatTimeOfDay(picked),
                                  dailyCloseTime: _formatTimeOfDay(closeTime),
                                ));
                              }
                            },
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Closing Time',
                                style: TextStyle(fontSize: 12)),
                            subtitle: Text(_formatTimeOfDayDisplay(closeTime),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.access_time_filled,
                                size: 18),
                            onTap: () async {
                              final picked = await showTimePicker(
                                  context: context, initialTime: closeTime);
                              if (picked != null && context.mounted) {
                                setDialogState(() => closeTime = picked);
                                await inventory
                                    .saveStoreSettings(settings.copyWith(
                                  operatingHoursEnabled: true,
                                  dailyOpenTime: _formatTimeOfDay(openTime),
                                  dailyCloseTime: _formatTimeOfDay(picked),
                                ));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    const Text(
                      'Custom Date / Holiday Schedule',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),

                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month, size: 18),
                      label: Text(
                        selectedDateRange == null
                            ? 'Select Custom Date Range (e.g. Dec 20 - Dec 23)'
                            : '${formatDate(selectedDateRange!.start)}  →  ${formatDate(selectedDateRange!.end)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(now.year, now.month, 1),
                          lastDate: DateTime(now.year + 2, 12, 31),
                          initialDateRange: selectedDateRange,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDateRange = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    SegmentedButton<OverrideType>(
                      segments: const [
                        ButtonSegment(
                          value: OverrideType.customOpenHours,
                          label: Text('Custom Hours', style: TextStyle(fontSize: 11)),
                          icon: Icon(Icons.schedule, size: 15),
                        ),
                        ButtonSegment(
                          value: OverrideType.fullClosure,
                          label: Text('Closed All Day', style: TextStyle(fontSize: 11)),
                          icon: Icon(Icons.block, size: 15),
                        ),
                        ButtonSegment(
                          value: OverrideType.maintenanceWindow,
                          label: Text('Maintenance', style: TextStyle(fontSize: 11)),
                          icon: Icon(Icons.build, size: 15),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (val) {
                        setDialogState(() => selectedType = val.first);
                      },
                    ),
                    const SizedBox(height: 10),

                    if (selectedType != OverrideType.fullClosure) ...[
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: customStart,
                                );
                                if (t != null) setDialogState(() => customStart = t);
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: selectedType == OverrideType.maintenanceWindow
                                      ? 'Maintenance From'
                                      : 'Available From',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: Text(formatTime(customStart)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: customEnd,
                                );
                                if (t != null) setDialogState(() => customEnd = t);
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: selectedType == OverrideType.maintenanceWindow
                                      ? 'Maintenance Until'
                                      : 'Until Time',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: Text(formatTime(customEnd)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    TextField(
                      controller: selectedType == OverrideType.maintenanceWindow
                          ? controller
                          : reasonCtrl,
                      decoration: InputDecoration(
                        labelText: selectedType == OverrideType.maintenanceWindow
                            ? 'Maintenance Reason / Notice'
                            : 'Reason / Notice',
                        hintText: selectedType == OverrideType.fullClosure
                            ? 'e.g. Holidays'
                            : selectedType == OverrideType.maintenanceWindow
                                ? 'Reason displayed to customers during maintenance'
                                : 'e.g. Preparing for Holidays',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (selectedType == OverrideType.customOpenHours) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.event_available_rounded, size: 18),
                        label: const Text(
                          'Save Custom Hours',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: () async {
                          if (selectedDateRange == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please select a date range first.')),
                            );
                            return;
                          }
                          await _saveOverrideHelper(
                            context,
                            inventory,
                            settings,
                            selectedDateRange!,
                            selectedType,
                            customStart,
                            customEnd,
                            reasonCtrl.text,
                            setDialogState,
                          );
                        },
                      ),
                    ] else if (selectedType == OverrideType.fullClosure) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: errColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.block_rounded, size: 18),
                        label: const Text(
                          'Close Store',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: () async {
                          if (selectedDateRange == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please select a date range first.')),
                            );
                            return;
                          }
                          await _saveOverrideHelper(
                            context,
                            inventory,
                            settings,
                            selectedDateRange!,
                            selectedType,
                            customStart,
                            customEnd,
                            reasonCtrl.text,
                            setDialogState,
                          );
                        },
                      ),
                    ] else if (selectedType == OverrideType.maintenanceWindow) ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.build_rounded, size: 16),
                              label: const Text('Maintenance',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                if (selectedDateRange == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Please select a date range first.')),
                                  );
                                  return;
                                }
                                await _saveOverrideHelper(
                                  context,
                                  inventory,
                                  settings,
                                  selectedDateRange!,
                                  selectedType,
                                  customStart,
                                  customEnd,
                                  controller.text,
                                  setDialogState,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: errColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.warning_amber_rounded, size: 16),
                              label: const Text('Emergency Maint.',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (confirmCtx) => AlertDialog(
                                    title: Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded,
                                            color: errColor, size: 24),
                                        const SizedBox(width: 8),
                                        const Text('Confirm Emergency Maintenance'),
                                      ],
                                    ),
                                    content: const Text(
                                      'Are you sure you want to activate Emergency Maintenance?\n\n'
                                      'This will immediately close the store and broadcast the emergency notice to all customers.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(confirmCtx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: errColor,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => Navigator.pop(confirmCtx, true),
                                        icon: const Icon(Icons.warning_amber_rounded, size: 18),
                                        label: const Text('Confirm & Activate'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm != true) return;

                                try {
                                  final msg = controller.text.trim().isNotEmpty
                                      ? controller.text.trim()
                                      : 'Emergency Maintenance - Will be back to you soon';
                                  await inventory.toggleStoreStatus(true, message: msg);
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Emergency Maintenance activated!'),
                                    ),
                                  );
                                } catch (e) {
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: errColor,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _saveOverrideHelper(
    BuildContext context,
    InventoryProvider inventory,
    StoreSettings settings,
    DateTimeRange dateRange,
    OverrideType type,
    TimeOfDay customStart,
    TimeOfDay customEnd,
    String reasonText,
    void Function(void Function()) setDialogState,
  ) async {
    final startDay = DateTime(
      dateRange.start.year,
      dateRange.start.month,
      dateRange.start.day,
    );
    final endDay = DateTime(
      dateRange.end.year,
      dateRange.end.month,
      dateRange.end.day,
      23, 59, 59,
    );

    final newOverride = ScheduleOverride(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startDate: startDay,
      endDate: endDay,
      type: type,
      startMinutes: type == OverrideType.fullClosure
          ? null
          : customStart.hour * 60 + customStart.minute,
      endMinutes: type == OverrideType.fullClosure
          ? null
          : customEnd.hour * 60 + customEnd.minute,
      reason: reasonText.trim().isEmpty
          ? (type == OverrideType.fullClosure
              ? 'Closed All Day'
              : type == OverrideType.maintenanceWindow
                  ? 'Scheduled Maintenance'
                  : 'Special Operating Hours')
          : reasonText.trim(),
    );

    final updatedList = List<ScheduleOverride>.from(settings.overrides)
      ..add(newOverride);
    await inventory.saveStoreSettings(
      settings.copyWith(overrides: updatedList),
    );

    setDialogState(() {});

    if (context.mounted) {
      final String snackMsg = type == OverrideType.fullClosure
          ? 'Store closed for selected dates.'
          : type == OverrideType.customOpenHours
              ? 'Custom hours saved for selected dates.'
              : 'Maintenance window scheduled.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(snackMsg)),
      );
    }
  }

  static TimeOfDay _parseTimeOfDay(String? timeStr, TimeOfDay fallback) {
    if (timeStr == null || !timeStr.contains(':')) return fallback;
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return fallback;
    }
  }

  static String _formatTimeOfDay(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _formatTimeOfDayDisplay(TimeOfDay time) {
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final h12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final mStr = time.minute.toString().padLeft(2, '0');
    return '$h12:$mStr $period';
  }
}

enum ChartPeriod {
  thisWeek('This week', 7),
  thisMonth('This month', 30),
  last90Days('Last 90 days', 90);

  final String label;
  final int days;
  const ChartPeriod(this.label, this.days);
}

class _RevenueProfitChart extends StatefulWidget {
  final List<_DailyMetric> initialMetrics;
  final List<StoreTransaction> transactions;
  final List<LossRecord> lossRecords;

  const _RevenueProfitChart({
    required this.initialMetrics,
    required this.transactions,
    required this.lossRecords,
  });

  @override
  State<_RevenueProfitChart> createState() => _RevenueProfitChartState();
}

class _RevenueProfitChartState extends State<_RevenueProfitChart> {
  ChartPeriod _selectedPeriod = ChartPeriod.thisWeek;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final List<_DailyMetric> metrics = _selectedPeriod == ChartPeriod.thisWeek
        ? widget.initialMetrics
        : _computeChartMetrics(widget.transactions, widget.lossRecords,
            days: _selectedPeriod.days);

    if (metrics.isEmpty) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.show_chart_rounded,
                    size: 36,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.4)),
                const SizedBox(height: 8),
                Text(
                  'No revenue trend data available yet.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final totalGross =
        metrics.fold<double>(0.0, (sum, m) => sum + m.grossSales);

    final priorMetrics = _computeChartMetrics(
      widget.transactions,
      widget.lossRecords,
      days: _selectedPeriod.days,
      offsetDays: _selectedPeriod.days,
    );
    final priorTotalGross =
        priorMetrics.fold<double>(0.0, (sum, m) => sum + m.grossSales);

    double percentChange;
    if (priorTotalGross > 0) {
      percentChange =
          ((totalGross - priorTotalGross) / priorTotalGross) * 100;
    } else if (totalGross > 0) {
      percentChange = 100.0;
    } else {
      percentChange = 0.0;
    }

    final isPositive = percentChange >= 0;
    final percentText =
        '${isPositive ? '+' : ''}${percentChange.toStringAsFixed(1)}%';

    final maxY = metrics.fold<double>(
        0.0, (max, m) => m.grossSales > max ? m.grossSales : max);
    final rawCeilingY =
        (maxY <= 0 || maxY.isNaN || maxY.isInfinite) ? 10000.0 : (maxY * 1.2);

    double roundedCeiling = rawCeilingY;
    if (rawCeilingY > 10000) {
      roundedCeiling = ((rawCeilingY / 5000).ceil() * 5000).toDouble();
    } else if (rawCeilingY > 1000) {
      roundedCeiling = ((rawCeilingY / 1000).ceil() * 1000).toDouble();
    }
    final intervalY = (roundedCeiling / 4).clamp(100.0, double.infinity);

    final double maxX =
        metrics.length > 1 ? (metrics.length - 1).toDouble() : 1.0;

    final grossSpots = metrics.asMap().entries.map((e) {
      final val = e.value.grossSales;
      final safeY = (val.isNaN || val.isInfinite || val < 0) ? 0.0 : val;
      return FlSpot(e.key.toDouble(), safeY);
    }).toList();

    final profitSpots = metrics.asMap().entries.map((e) {
      final val = e.value.netProfit;
      final safeY = (val.isNaN || val.isInfinite || val < 0) ? 0.0 : val;
      return FlSpot(e.key.toDouble(), safeY);
    }).toList();

    final greenColor = const Color(0xFF10B981);
    final blueColor = const Color(0xFF3B82F6);

    final double titleInterval = _selectedPeriod == ChartPeriod.thisWeek
        ? 1
        : (_selectedPeriod == ChartPeriod.thisMonth ? 5 : 15);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.black.withValues(alpha: 0.03)
                : Colors.transparent,
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERFORMANCE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sales Overview',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (!_isExpanded) ...[
                        const SizedBox(width: 12),
                        Text(
                          formatPeso(totalGross),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isPositive ? Colors.green : Colors.red)
                                .shade500
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPositive
                                    ? Icons.north_east_rounded
                                    : Icons.south_east_rounded,
                                size: 10,
                                color: isPositive
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                percentText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isPositive
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<ChartPeriod>(
                    initialValue: _selectedPeriod,
                    onSelected: (ChartPeriod period) {
                      setState(() {
                        _selectedPeriod = period;
                      });
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<ChartPeriod>>[
                      for (final period in ChartPeriod.values)
                        PopupMenuItem<ChartPeriod>(
                          value: period,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (period == _selectedPeriod) ...[
                                Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                              ] else ...[
                                const SizedBox(width: 24),
                              ],
                              Text(
                                period.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: period == _selectedPeriod
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.6),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedPeriod.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    icon: Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gross sales',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatPeso(totalGross),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isPositive ? Colors.green : Colors.red)
                              .shade500
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPositive
                                  ? Icons.north_east_rounded
                                  : Icons.south_east_rounded,
                              size: 12,
                              color: isPositive
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              percentText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isPositive
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _chartLegend(greenColor, 'Revenue'),
                  const SizedBox(width: 14),
                  _chartLegend(blueColor, 'Net Profit'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final label =
                            spot.barIndex == 0 ? 'Revenue' : 'Net Profit';
                        final color =
                            spot.barIndex == 0 ? greenColor : blueColor;
                        return LineTooltipItem(
                          '$label\n${formatPeso(spot.y)}',
                          TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  drawHorizontalLine: true,
                  horizontalInterval: intervalY,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.35),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      interval: intervalY,
                      getTitlesWidget: (value, meta) {
                        if (value < 0 || value > roundedCeiling + 0.1) {
                          return const SizedBox.shrink();
                        }
                        String label;
                        if (value >= 1000000) {
                          label = '₱${(value / 1000000).toStringAsFixed(1)}M';
                        } else if (value >= 1000) {
                          final kVal = value / 1000;
                          final isWhole = kVal % 1 == 0;
                          label = '₱${kVal.toStringAsFixed(isWhole ? 0 : 1)}k';
                        } else {
                          label = '₱${value.toInt()}';
                        }
                        return SideTitleWidget(
                          meta: meta,
                          space: 6,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: titleInterval,
                      getTitlesWidget: (val, meta) {
                        final int index = val.toInt();
                        if (index >= 0 &&
                            index < metrics.length &&
                            (val - index).abs() < 0.1) {
                          final date = metrics[index].date;
                          final labelStr = _selectedPeriod == ChartPeriod.thisWeek
                              ? DateFormat('E').format(date)
                              : DateFormat('MMM d').format(date);
                          return SideTitleWidget(
                            meta: meta,
                            space: 8,
                            child: Text(
                              labelStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: maxX,
                minY: 0,
                maxY: roundedCeiling,
                lineBarsData: [
                  LineChartBarData(
                    spots: grossSpots,
                    isCurved: true,
                    color: greenColor,
                    barWidth: 3.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: _selectedPeriod == ChartPeriod.thisWeek,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4.5,
                        color: greenColor,
                        strokeWidth: 2,
                        strokeColor: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          greenColor.withValues(alpha: 0.25),
                          greenColor.withValues(alpha: 0.01),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  LineChartBarData(
                    spots: profitSpots,
                    isCurved: true,
                    color: blueColor,
                    barWidth: 3.0,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: _selectedPeriod == ChartPeriod.thisWeek,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: blueColor,
                        strokeWidth: 2,
                        strokeColor: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          blueColor.withValues(alpha: 0.18),
                          blueColor.withValues(alpha: 0.01),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
                    )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _chartLegend(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _StatCard(this.label, this.value, this.icon, this.color, {this.onTap});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.black.withValues(alpha: 0.03)
                  : Colors.transparent,
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          splashColor: color.withValues(alpha: 0.12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5),
                            maxLines: 1),
                      ),
                      const SizedBox(height: 2),
                      Text(label,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  const _MiniStat(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text(label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]);
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
      height: 24,
      width: 1,
      color:
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4));
}
