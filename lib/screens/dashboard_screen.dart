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
import '../utils/format.dart';
import '../widgets/receive_delivery_sheet.dart';
import '../widgets/batch_expiration_widget.dart';
import 'admin_app.dart';

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

  final todayTx = params.transactions.where((t) {
    try {
      return DateFormat('yyyy-MM-dd').format(t.createdAt) == today;
    } catch (_) {
      return false;
    }
  }).toList();

  final double gross = todayTx.fold(0.0, (sum, t) {
    final val = t.total;
    return sum + ((val.isNaN || val.isInfinite) ? 0.0 : val);
  });

  final double loss = params.lossRecords.where((l) {
    try {
      return DateFormat('yyyy-MM-dd').format(l.createdAt) == today;
    } catch (_) {
      return false;
    }
  }).fold(0.0, (sum, l) {
    final unit = l.unitPrice;
    final safeUnit = (unit.isNaN || unit.isInfinite) ? 0.0 : unit;
    return sum + (safeUnit * l.qty);
  });

  final double cogs = todayTx.fold(0.0, (sum, t) {
    return sum + t.items.fold(0.0, (itemSum, item) {
      final cost = item.costPrice;
      final safeCost = (cost.isNaN || cost.isInfinite) ? 0.0 : cost;
      return itemSum + (safeCost * item.qty);
    });
  });

  final double rawNetProfit = gross - cogs - loss;
  final double netProfit = (rawNetProfit.isNaN || rawNetProfit.isInfinite) ? 0.0 : rawNetProfit;

  final double exp = params.expenses.where((e) {
    try {
      return DateFormat('yyyy-MM-dd').format(e.createdAt) == today;
    } catch (_) {
      return false;
    }
  }).fold(0.0, (sum, e) {
    final amt = e.amount;
    return sum + ((amt.isNaN || amt.isInfinite) ? 0.0 : amt);
  });

  final int toProcess = params.orders.where((o) =>
      o.status == OrderStatus.pending || o.status == OrderStatus.staging).length;

  final int pendingRestock = params.inquiries.where((ri) =>
      ri.status == RestockInquiryStatus.draft ||
      ri.status == RestockInquiryStatus.pending ||
      ri.status == RestockInquiryStatus.sent ||
      ri.status == RestockInquiryStatus.acknowledged ||
      ri.status == RestockInquiryStatus.partiallyFulfilled).length;

  final lowStock = params.products.where((p) =>
      p.status == ProductStatus.published && p.totalStock <= p.lowStockThreshold).toList();

  final chartMetrics = _computeChartMetrics(params.transactions, params.lossRecords);

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

Future<_DashboardData> _computeDashboardDataAsync(_IsolateComputationParams params) async {
  return Future.microtask(() => _computeDashboardData(params));
}

List<_DailyMetric> _computeChartMetrics(
  List<StoreTransaction> transactions,
  List<LossRecord> lossRecords,
) {
  final now = DateTime.now();
  final List<_DailyMetric> list = [];

  for (int i = 6; i >= 0; i--) {
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
    final cogs = dayTx.fold(0.0, (sum, t) => sum + t.items.fold(0.0, (iSum, item) => iSum + (item.costPrice * item.qty)));
    final profit = gross - cogs - dayLoss;

    final safeGross = (gross.isNaN || gross.isInfinite || gross < 0) ? 0.0 : gross;
    final safeProfit = (profit.isNaN || profit.isInfinite || profit < 0) ? 0.0 : profit;

    list.add(_DailyMetric(
      date: dayDate,
      grossSales: safeGross,
      netProfit: safeProfit,
    ));
  }

  return list;
}

class DashboardScreen extends StatelessWidget {
  final Function(AppTab, {String? category}) onTabChange;
  const DashboardScreen({super.key, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    // 1. STATE HYDRATION GATE (THE PROCESS FLOW)
    final inventory = context.watch<InventoryProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final restockProvider = context.watch<RestockProvider>();
    final expenseProvider = context.watch<ExpenseProvider>();

    final bool isSyncing = inventory.isLoading || orderProvider.isLoading || restockProvider.isLoading;

    if (isSyncing) {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Synchronizing Store Data...',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    final auth = context.watch<AppAuthProvider>();
    final categoryCount = inventory.products.map((p) => p.category).toSet().length;
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
        if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
          return Container(
            color: Theme.of(context).colorScheme.surface,
            alignment: Alignment.center,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Synchronizing Store Data...',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        final data = snapshot.data!;

        // 4. LAYOUT STRICTNESS (Root is Container + SafeArea + Bounded ListView)
        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  children: [
                    // 3. WIDGET ISOLATION (BLAST DOORS)
                    _buildHeader(context, inventory),
                    const SizedBox(height: 20),
                    _buildKpiGrid(context, data, auth.role),
                    const SizedBox(height: 16),
                    _buildSummaryMetrics(context, data, auth.role, inventory.products.length, categoryCount),
                    const SizedBox(height: 24),
                    _buildChartSection(context, data.chartMetrics),
                    const SizedBox(height: 24),

                    // TABLET LANDSCAPE 2-COLUMN OPTIMIZATION
                    if (isLandscape)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildActionAlertsSection(context, data, inventory),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 2,
                            child: _buildRecentTransactionsSection(context, data.todayTx),
                          ),
                        ],
                      )
                    else ...[
                      _buildActionAlertsSection(context, data, inventory),
                      const SizedBox(height: 24),
                      _buildRecentTransactionsSection(context, data.todayTx),
                    ],
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

  Widget _buildHeader(BuildContext context, InventoryProvider inventory) {
    try {
      final statusLabel = inventory.settings.statusLabel;
      final Color successColor = Colors.green.shade700;
      final Color warningColor = Colors.orange.shade700;
      final Color errorColor = Theme.of(context).colorScheme.error;

      Color statusColor;
      IconData statusIcon;

      switch (statusLabel) {
        case 'CLOSED':
          statusColor = errorColor;
          statusIcon = Icons.storefront_outlined;
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
              Text(
                'Admin Dashboard',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            avatar: Icon(statusIcon, size: 16, color: statusColor),
            label: Text(
              statusLabel,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 11),
            ),
            onPressed: () => _showStatusDialog(context, inventory),
          ),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildKpiGrid(BuildContext context, _DashboardData data, UserRole role) {
    try {
      final Color successColor = Colors.green.shade700;
      final Color warningColor = Colors.orange.shade700;
      final Color infoColor = Colors.blue.shade700;
      final Color errorColor = Theme.of(context).colorScheme.error;

      final bool isAdmin = role == UserRole.admin;
      final items = isAdmin
          ? [
              _StatCard("Gross Sales", formatPeso(data.todayGrossSales), Icons.auto_graph_rounded, successColor),
              _StatCard("Net Profit", formatPeso(data.todayNetProfit), Icons.monetization_on_rounded, infoColor),
              _StatCard("Loss / Waste", formatPeso(data.todayLoss), Icons.delete_sweep_rounded, errorColor),
              _StatCard("Pre-Orders", "${data.toProcessOrders}", Icons.pending_actions_rounded, warningColor,
                  onTap: () => onTabChange(AppTab.preOrders, category: null)),
            ]
          : [
              _StatCard("Total Products", "${data.lowStockProducts.length}", Icons.inventory_2_rounded, infoColor,
                  onTap: () => onTabChange(AppTab.inventory, category: null)),
              _StatCard("Restock Needed", "${data.restockPending}", Icons.add_shopping_cart_rounded, warningColor,
                  onTap: () => onTabChange(AppTab.inventory, category: 'Low Stock')),
              _StatCard("Safety Warnings", "${data.lowStockProducts.length}", Icons.warning_amber_rounded, errorColor,
                  onTap: () => onTabChange(AppTab.inventory, category: 'Low Stock')),
              _StatCard("Categories", "Catalog", Icons.category_rounded, infoColor),
            ];

      return LayoutBuilder(
        builder: (context, constraints) {
          final double maxExtent = constraints.maxWidth > 700 ? 280 : 200;
          final double itemWidth = (constraints.maxWidth - 36) / (constraints.maxWidth > 700 ? 4 : 2);
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
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
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
                      onTap: () => onTabChange(AppTab.preOrders, category: null),
                      child: _MiniStat('Sales Count', '${data.todayTx.length}'),
                    ),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _MiniStat('Units Sold', '${data.todayTx.fold(0, (s, t) => s + t.items.fold(0, (a, i) => a + i.qty))}'),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _MiniStat('Avg Basket', data.todayTx.isEmpty ? '—' : formatPeso(data.todayGrossSales / data.todayTx.length)),
                  ),
                ]
              : [
                  Expanded(child: _MiniStat('Total Items', '$totalProducts')),
                  const _Divider(),
                  Expanded(child: _MiniStat('Low Stock', '${data.lowStockProducts.length}')),
                  const _Divider(),
                  Expanded(child: _MiniStat('Categories', '$categoryCount')),
                ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildChartSection(BuildContext context, List<_DailyMetric> metrics) {
    try {
      return _RevenueProfitChart(metrics: metrics);
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

  Widget _buildActionAlertsSection(BuildContext context, _DashboardData data, InventoryProvider inventory) {
    try {
      final Color errorColor = Theme.of(context).colorScheme.error;
      final Color warningColor = Colors.orange.shade700;
      final Color infoColor = Colors.blue.shade700;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Safety Stock Warnings (Low Stock)
          if (data.lowStockProducts.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: errorColor),
                const SizedBox(width: 8),
                Text(
                  'Safety Stock Warnings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: errorColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              color: errorColor.withValues(alpha: 0.08),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: errorColor.withValues(alpha: 0.2)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: data.lowStockProducts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = data.lowStockProducts[index];
                  return ListTile(
                    dense: true,
                    onTap: () => onTabChange(AppTab.inventory, category: 'Low Stock'),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Threshold: ${p.lowStockThreshold} ${p.unit} • Current: ${p.stock} ${p.unit}', style: const TextStyle(fontSize: 10)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Marked "${p.name}" as Ordered (In Transit / Awaiting Delivery) 🚚'),
                                backgroundColor: Colors.blue,
                              ),
                            );
                          },
                          icon: const Icon(Icons.local_shipping_outlined, size: 14),
                          label: const Text('ORDERED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton.icon(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => ReceiveDeliverySheet(initialProduct: p),
                            );
                          },
                          icon: const Icon(Icons.move_to_inbox_rounded, size: 14),
                          label: const Text('RECEIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.green.shade800,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 2. FEFO Batch Expiration Warnings (< 30 Days)
          const BatchExpirationWidget(),
          const SizedBox(height: 16),

          // 3. Fast Moving Items
          Row(
            children: [
              Icon(Icons.bolt, size: 20, color: warningColor),
              const SizedBox(width: 8),
              Text('Fast Moving Items (30d)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          if (data.fastMoving.isEmpty)
            _buildEmptyStateCard(
              context,
              icon: Icons.bolt_outlined,
              message: 'No fast-moving item sales recorded yet.',
            )
          else
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: data.fastMoving.take(10).length,
                itemBuilder: (context, index) {
                  final entry = data.fastMoving[index];
                  return Card(
                    margin: const EdgeInsets.only(right: 12),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${entry.value} sold', style: TextStyle(fontSize: 11, color: warningColor)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 16),

          // 4. Slow Moving Items
          Row(
            children: [
              Icon(Icons.hourglass_bottom, size: 20, color: infoColor),
              const SizedBox(width: 8),
              Text('Slow Moving Items (30d)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          if (data.slowMoving.isEmpty)
            _buildEmptyStateCard(
              context,
              icon: Icons.auto_awesome_rounded,
              message: 'Everything is moving smoothly!',
            )
          else
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: data.slowMoving.take(10).length,
                itemBuilder: (context, index) {
                  final p = data.slowMoving[index];
                  final sold = inventory.recentMovementCounts[p.name] ?? 0;
                  return Card(
                    margin: const EdgeInsets.only(right: 12),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(sold == 0 ? 'No sales' : '$sold sold', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildRecentTransactionsSection(BuildContext context, List<StoreTransaction> todayTx) {
    try {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Transactions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (todayTx.isEmpty)
            _buildEmptyStateCard(
              context,
              icon: Icons.receipt_long_outlined,
              message: 'No sales transactions recorded today.',
            )
          else
            ...todayTx.take(5).map((tx) {
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
            }),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildEmptyStateCard(BuildContext context, {required IconData icon, required String message}) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
    final settings = inventory.settings;
    final isClosed = settings.isClosed;
    final controller = TextEditingController(text: settings.closureMessage);

    DateTime? schedClose = settings.scheduledCloseAt;
    DateTime? schedOpen = settings.scheduledOpenAt;

    bool operatingEnabled = settings.operatingHoursEnabled;
    TimeOfDay openTime = _parseTimeOfDay(settings.dailyOpenTime, const TimeOfDay(hour: 8, minute: 0));
    TimeOfDay closeTime = _parseTimeOfDay(settings.dailyCloseTime, const TimeOfDay(hour: 21, minute: 0));

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isEffectivelyClosed = settings.effectivelyClosed;
          final closureReason = settings.closureReason;

          final Color errColor = Theme.of(context).colorScheme.error;
          final Color succColor = Colors.green.shade700;

          return AlertDialog(
            title: const Text('Store Management'),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.7,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isEffectivelyClosed
                            ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.15)
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
                            isEffectivelyClosed ? Icons.lock_clock_rounded : Icons.storefront_rounded,
                            color: isEffectivelyClosed ? errColor : succColor,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEffectivelyClosed ? 'Store is CLOSED' : 'Store is OPEN',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isEffectivelyClosed ? errColor : succColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  closureReason,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Manual Store Control', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Closure Notice',
                        hintText: 'Optional message for customers when closed',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isClosed ? succColor : errColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        try {
                          await inventory.toggleStoreStatus(!isClosed, message: controller.text.trim());
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Store status updated successfully')),
                          );
                        } catch (e) {
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: errColor),
                          );
                        }
                      },
                      icon: Icon(isClosed ? Icons.play_arrow_rounded : Icons.power_settings_new_rounded),
                      label: Text(isClosed ? 'Open Store Now' : 'Close Store Now'),
                    ),

                    const Divider(height: 36),
                    Text('Daily Operating Hours', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text('Automatically open and close every day.', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 8),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Daily Schedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      value: operatingEnabled,
                      onChanged: (val) async {
                        setDialogState(() => operatingEnabled = val);
                        final openStr = _formatTimeOfDay(openTime);
                        final closeStr = _formatTimeOfDay(closeTime);
                        await inventory.saveStoreSettings(settings.copyWith(
                          operatingHoursEnabled: val,
                          dailyOpenTime: openStr,
                          dailyCloseTime: closeStr,
                        ));
                      },
                    ),

                    if (operatingEnabled) ...[
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Opening Time', style: TextStyle(fontSize: 12)),
                              subtitle: Text(_formatTimeOfDayDisplay(openTime), style: const TextStyle(fontWeight: FontWeight.bold)),
                              trailing: const Icon(Icons.access_time, size: 18),
                              onTap: () async {
                                final picked = await showTimePicker(context: context, initialTime: openTime);
                                if (picked != null && context.mounted) {
                                  setDialogState(() => openTime = picked);
                                  await inventory.saveStoreSettings(settings.copyWith(
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
                              title: const Text('Closing Time', style: TextStyle(fontSize: 12)),
                              subtitle: Text(_formatTimeOfDayDisplay(closeTime), style: const TextStyle(fontWeight: FontWeight.bold)),
                              trailing: const Icon(Icons.access_time_filled, size: 18),
                              onTap: () async {
                                final picked = await showTimePicker(context: context, initialTime: closeTime);
                                if (picked != null && context.mounted) {
                                  setDialogState(() => closeTime = picked);
                                  await inventory.saveStoreSettings(settings.copyWith(
                                    dailyOpenTime: _formatTimeOfDay(openTime),
                                    dailyCloseTime: _formatTimeOfDay(picked),
                                  ));
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],

                    const Divider(height: 36),
                    Text('Scheduled Outing / Vacation', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text('Temporarily close the store for a specific date range.', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 12),

                    Builder(
                      builder: (context) {
                        final DateTime? sClose = schedClose;
                        final DateTime? sOpen = schedOpen;

                        return Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Starts At', style: TextStyle(fontSize: 13)),
                              subtitle: Text(sClose == null ? 'Not set' : DateFormat('MMM d, yyyy, h:mm a').format(sClose)),
                              trailing: const Icon(Icons.calendar_today, size: 18),
                              onTap: () async {
                                final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
                                if (date != null && context.mounted) {
                                  final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                                  if (time != null) {
                                    setDialogState(() => schedClose = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                                  }
                                }
                              },
                            ),

                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Reopens At', style: TextStyle(fontSize: 13)),
                              subtitle: Text(sOpen == null ? 'Not set' : DateFormat('MMM d, yyyy, h:mm a').format(sOpen)),
                              trailing: const Icon(Icons.restore, size: 18),
                              onTap: () async {
                                final date = await showDatePicker(context: context, initialDate: schedClose ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
                                if (date != null && context.mounted) {
                                  final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
                                  if (time != null) {
                                    setDialogState(() => schedOpen = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                                  }
                                }
                              },
                            ),
                          ],
                        );
                      },
                    ),

                    if (schedClose != null && schedOpen != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save_rounded, size: 18),
                          label: const Text('Save Schedule'),
                          onPressed: () async {
                            final DateTime? sClose = schedClose;
                            final DateTime? sOpen = schedOpen;
                            if (sClose == null || sOpen == null) return;

                            try {
                              await inventory.toggleStoreStatus(
                                isClosed,
                                message: 'Scheduled Outage: ${DateFormat('MMM d').format(sClose)} – ${DateFormat('MMM d').format(sOpen)}',
                                closeAt: sClose,
                                openAt: sOpen,
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Schedule saved successfully')),
                              );
                            } catch (e) {
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: errColor),
                              );
                            }
                          },
                        ),
                      ),

                    if (settings.scheduledCloseAt != null || settings.scheduledOpenAt != null)
                      TextButton.icon(
                        icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                        label: const Text('Clear Outage Schedule'),
                        onPressed: () async {
                          await inventory.toggleStoreStatus(isClosed, closeAt: null, openAt: null);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),

                    const Divider(height: 36),
                    Text('Order Expiration Windows', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text('Time customers have to pick up their orders.', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 12),

                    _WindowInput(
                      label: 'Perishables Only',
                      hint: 'e.g. 2 hours',
                      value: settings.perishableWindowHours,
                      onChanged: (v) => inventory.saveStoreSettings(settings.copyWith(perishableWindowHours: v)),
                    ),
                    const SizedBox(height: 12),
                    _WindowInput(
                      label: 'Mixed Orders',
                      hint: 'e.g. 24 hours',
                      value: settings.mixedWindowHours,
                      onChanged: (v) => inventory.saveStoreSettings(settings.copyWith(mixedWindowHours: v)),
                    ),
                    const SizedBox(height: 12),
                    _WindowInput(
                      label: 'Non-Perishables',
                      hint: 'e.g. 72 hours',
                      value: settings.standardWindowHours,
                      onChanged: (v) => inventory.saveStoreSettings(settings.copyWith(standardWindowHours: v)),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
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

class _RevenueProfitChart extends StatelessWidget {
  final List<_DailyMetric> metrics;
  const _RevenueProfitChart({required this.metrics});

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.show_chart_rounded, size: 36, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 8),
                Text(
                  'No 7-day revenue trend data available yet.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final maxY = metrics.fold<double>(0.0, (max, m) => m.grossSales > max ? m.grossSales : max);
    final ceilingY = (maxY <= 0 || maxY.isNaN || maxY.isInfinite) ? 1000.0 : (maxY * 1.25);
    final double maxX = metrics.length > 1 ? (metrics.length - 1).toDouble() : 1.0;

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

    final greenColor = Colors.green.shade700;
    final blueColor = Colors.blue.shade700;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Revenue vs Net Profit (7 Days)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  _chartLegend(greenColor, 'Revenue'),
                  const SizedBox(width: 16),
                  _chartLegend(blueColor, 'Net Profit'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => Theme.of(context).colorScheme.surfaceContainerHighest,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final label = spot.barIndex == 0 ? 'Revenue' : 'Net Profit';
                        final color = spot.barIndex == 0 ? greenColor : blueColor;
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
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        final int index = val.toInt();
                        if (index >= 0 && index < metrics.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              DateFormat('E').format(metrics[index].date),
                              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
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
                maxY: ceilingY,
                lineBarsData: [
                  LineChartBarData(
                    spots: grossSpots,
                    isCurved: true,
                    color: greenColor,
                    barWidth: 3.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 4,
                        color: greenColor,
                        strokeWidth: 2,
                        strokeColor: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          greenColor.withValues(alpha: 0.3),
                          greenColor.withValues(alpha: 0.02),
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
                    barWidth: 3.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
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
                          blueColor.withValues(alpha: 0.3),
                          blueColor.withValues(alpha: 0.02),
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
      ),
    );
  }

  Widget _chartLegend(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _WindowInput extends StatefulWidget {
  final String label, hint;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _WindowInput({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_WindowInput> createState() => _WindowInputState();
}

class _WindowInputState extends State<_WindowInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _WindowInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final newText = widget.value?.toString() ?? '';
      if (_controller.text != newText) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      keyboardType: TextInputType.number,
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) => widget.onChanged(int.tryParse(v)),
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
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
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
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
                        maxLines: 1),
                  ),
                  const SizedBox(height: 2),
                  Text(label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
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
        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
    Text(label,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
  ]);
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
    height: 24, width: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4));
}
