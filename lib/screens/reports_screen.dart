import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/inventory_provider.dart';
import '../providers/expense_provider.dart';
import '../models/loss_record.dart';
import '../models/product.dart';
import '../utils/format.dart';
import '../config/theme.dart';
import '../shared/services/time_service.dart';

enum ReportPeriod { today, thisWeek, thisMonth, custom }

class ReportsScreen extends StatefulWidget {
  final int initialTab;
  const ReportsScreen({super.key, this.initialTab = 0});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ReportPeriod _selectedPeriod = ReportPeriod.thisMonth;
  DateTimeRange? _customRange;

  String _movementSearchQuery = '';
  String _movementSelectedCategory = 'All';
  _MovementFilterMode _movementFilterMode = _MovementFilterMode.fastMoving;

  String _itemsSoldSearchQuery = '';
  String _itemsSoldSelectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    TimeService.instance.addListener(_onTimeChanged);
  }

  void _onTimeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TimeService.instance.removeListener(_onTimeChanged);
    _tabController.dispose();
    super.dispose();
  }

  DateTimeRange get _activeDateRange {
    final now = TimeService.now;
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0, 0);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (_selectedPeriod) {
      case ReportPeriod.today:
        return DateTimeRange(start: todayStart, end: todayEnd);
      case ReportPeriod.thisWeek:
        final start = todayStart.subtract(const Duration(days: 6));
        return DateTimeRange(start: start, end: todayEnd);
      case ReportPeriod.thisMonth:
        final start = DateTime(now.year, now.month, 1, 0, 0, 0, 0);
        return DateTimeRange(start: start, end: todayEnd);
      case ReportPeriod.custom:
        return _customRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, 1, 0, 0, 0, 0),
              end: todayEnd,
            );
    }
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0, 0);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    DateTimeRange selectedRange = _customRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, 1, 0, 0, 0, 0),
          end: todayEnd,
        );

    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final startStr = DateFormat('MMM d, yyyy').format(selectedRange.start);
            final endStr = DateFormat('MMM d, yyyy').format(selectedRange.end);

            void setRange(DateTime s, DateTime e) {
              final safeStart = DateTime(s.year, s.month, s.day, 0, 0, 0, 0);
              var safeEnd = DateTime(e.year, e.month, e.day, 23, 59, 59, 999);
              if (safeEnd.isAfter(todayEnd)) {
                safeEnd = todayEnd;
              }
              if (safeStart.isAfter(safeEnd)) {
                return;
              }
              setDialogState(() {
                selectedRange = DateTimeRange(start: safeStart, end: safeEnd);
              });
            }

            final List<int> years = [];
            for (int y = now.year; y >= 2020; y--) {
              years.add(y);
            }

            final months = [
              'January', 'February', 'March', 'April', 'May', 'June',
              'July', 'August', 'September', 'October', 'November', 'December'
            ];

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Select Custom Date Range',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.date_range_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '$startStr  →  $endStr',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'QUICK PRESETS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Today', style: TextStyle(fontSize: 12)),
                            onPressed: () => setRange(todayStart, todayEnd),
                          ),
                          ActionChip(
                            label: const Text('Yesterday', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              final y = todayStart.subtract(const Duration(days: 1));
                              setRange(y, y);
                            },
                          ),
                          ActionChip(
                            label: const Text('Last 7 Days', style: TextStyle(fontSize: 12)),
                            onPressed: () => setRange(todayStart.subtract(const Duration(days: 6)), todayEnd),
                          ),
                          ActionChip(
                            label: const Text('This Month', style: TextStyle(fontSize: 12)),
                            onPressed: () => setRange(DateTime(now.year, now.month, 1), todayEnd),
                          ),
                          ActionChip(
                            label: const Text('Last Month', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              final prevMonth = DateTime(now.year, now.month - 1, 1);
                              final lastDayPrevMonth = DateTime(now.year, now.month, 0);
                              setRange(prevMonth, lastDayPrevMonth);
                            },
                          ),
                          ActionChip(
                            label: const Text('Last 90 Days', style: TextStyle(fontSize: 12)),
                            onPressed: () => setRange(todayStart.subtract(const Duration(days: 89)), todayEnd),
                          ),
                          ActionChip(
                            label: const Text('This Year', style: TextStyle(fontSize: 12)),
                            onPressed: () => setRange(DateTime(now.year, 1, 1), todayEnd),
                          ),
                        ],
                      ),
                      const Divider(height: 28),
                      Text(
                        'JUMP TO SPECIFIC MONTH',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<int>(
                              value: selectedRange.start.month,
                              decoration: InputDecoration(
                                labelText: 'Month',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: List.generate(12, (index) {
                                return DropdownMenuItem<int>(
                                  value: index + 1,
                                  child: Text(months[index], style: const TextStyle(fontSize: 13)),
                                );
                              }),
                              onChanged: (monthVal) {
                                if (monthVal != null) {
                                  final year = selectedRange.start.year;
                                  final start = DateTime(year, monthVal, 1);
                                  final end = DateTime(year, monthVal + 1, 0);
                                  setRange(start, end);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int>(
                              value: years.contains(selectedRange.start.year) ? selectedRange.start.year : now.year,
                              decoration: InputDecoration(
                                labelText: 'Year',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: years.map((y) {
                                return DropdownMenuItem<int>(
                                  value: y,
                                  child: Text('$y', style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (yearVal) {
                                if (yearVal != null) {
                                  final month = selectedRange.start.month;
                                  final start = DateTime(yearVal, month, 1);
                                  final end = DateTime(yearVal, month + 1, 0);
                                  setRange(start, end);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                        label: const Text(
                          'Open Calendar Picker...',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: todayEnd,
                            initialDateRange: selectedRange,
                            initialEntryMode: DatePickerEntryMode.calendar,
                            helpText: 'Select Custom Date Range',
                          );
                          if (picked != null) {
                            setRange(picked.start, picked.end);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Apply Range'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  onPressed: () => Navigator.pop(ctx, selectedRange),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customRange = picked;
        _selectedPeriod = ReportPeriod.custom;
      });
    }
  }

  void _selectSpecificMonth(int year, int month) {
    final start = DateTime(year, month, 1, 0, 0, 0);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);
    setState(() {
      _customRange = DateTimeRange(start: start, end: end);
      _selectedPeriod = ReportPeriod.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final expenses = context.watch<ExpenseProvider>().expenses;
    final range = _activeDateRange;

    // Filter transactions within selected range
    final filteredTx = inventory.transactions.where((t) {
      final txDate = t.createdAt.toLocal();
      return !txDate.isBefore(range.start) && !txDate.isAfter(range.end);
    }).toList();

    // Filter expenses within selected range
    final filteredExp = expenses.where((e) {
      final eDate = e.createdAt.toLocal();
      return !eDate.isBefore(range.start) && !eDate.isAfter(range.end);
    }).toList();

    // Filter loss records within selected range
    final filteredLoss = inventory.lossRecords.where((l) {
      final lDate = l.createdAt.toLocal();
      return !lDate.isBefore(range.start) && !lDate.isAfter(range.end);
    }).toList();

    // Calculate total valid non-refunded transaction count and total net units sold
    final int totalTxCount = filteredTx.where((t) => !t.isRefunded).length;
    int totalUnitsSold = 0;
    for (final tx in filteredTx) {
      if (tx.isRefunded) continue;
      for (final item in tx.items) {
        final int netQty = (item.qty - item.returnedQty).clamp(0, 999999);
        totalUnitsSold += netQty;
      }
    }

    // 1. Core Metrics Aggregation using netTotal and netCogs
    final double grossRevenue = filteredTx.fold(0.0, (sum, t) => sum + t.netTotal);
    final double trueCogs = filteredTx.fold(0.0, (sum, t) => sum + t.netCogs);
    final double grossProfit = grossRevenue - trueCogs;

    final double totalExpenses =
        filteredExp.fold(0.0, (sum, e) => sum + e.amount);
    final double totalLoss =
        filteredLoss.fold(0.0, (sum, l) => sum + l.totalLoss);

    final double netProfit = grossProfit - totalExpenses - totalLoss;
    final double profitMargin =
        grossRevenue > 0 ? (netProfit / grossRevenue) * 100 : 0.0;

    // 2. Category Performance Breakdown
    final Map<String, _CategoryPerformance> categoryPerformance = {};
    for (final tx in filteredTx) {
      if (tx.isRefunded) continue;
      for (final item in tx.items) {
        final int netQty = (item.qty - item.returnedQty).clamp(0, 999999);
        if (netQty <= 0) continue;

        String cat = 'Others';
        if (item.productId.isNotEmpty) {
          try {
            final p =
                inventory.products.firstWhere((p) => p.id == item.productId);
            if (p.category.trim().isNotEmpty) cat = p.category;
          } catch (_) {}
        }
        if (cat == 'Others') {
          try {
            final p = inventory.products.firstWhere((p) =>
                p.name.trim().toLowerCase() == item.name.trim().toLowerCase());
            if (p.category.trim().isNotEmpty) cat = p.category;
          } catch (_) {}
        }

        final rev = item.price * netQty;
        final double unitCogs = item.totalCogs > 0
            ? (item.totalCogs / item.qty)
            : item.costPrice;
        final cogs = unitCogs * netQty;

        if (!categoryPerformance.containsKey(cat)) {
          categoryPerformance[cat] = _CategoryPerformance(category: cat);
        }
        categoryPerformance[cat]!.grossSales += rev;
        categoryPerformance[cat]!.cogs += cogs;
        categoryPerformance[cat]!.quantitySold += netQty;
      }
    }

    final sortedCategories = categoryPerformance.values.toList()
      ..sort((a, b) => b.grossSales.compareTo(a.grossSales));

    // 3. Product Movement Aggregation across filteredTx and inventory.products
    final Map<String, _ProductMovementData> itemMovements = {};

    for (final p in inventory.products) {
      itemMovements[p.id] = _ProductMovementData(
        productId: p.id,
        name: p.name,
        category: p.category,
        currentStock: p.stock,
        qtySold: 0,
        totalRevenue: 0.0,
      );
    }

    for (final tx in filteredTx) {
      if (tx.isRefunded) continue;
      for (final item in tx.items) {
        final int netQty = (item.qty - item.returnedQty).clamp(0, 999999);
        if (netQty <= 0) continue;

        Product? matchingProduct;
        if (item.productId.isNotEmpty) {
          try {
            matchingProduct =
                inventory.products.firstWhere((p) => p.id == item.productId);
          } catch (_) {}
        }
        if (matchingProduct == null) {
          final normItemName = item.name.trim().toLowerCase();
          try {
            matchingProduct = inventory.products.firstWhere(
                (p) => p.name.trim().toLowerCase() == normItemName);
          } catch (_) {}
        }

        if (matchingProduct != null) {
          if (!itemMovements.containsKey(matchingProduct.id)) {
            itemMovements[matchingProduct.id] = _ProductMovementData(
              productId: matchingProduct.id,
              name: matchingProduct.name,
              category: matchingProduct.category,
              currentStock: matchingProduct.stock,
            );
          }
          itemMovements[matchingProduct.id]!.qtySold += netQty;
          itemMovements[matchingProduct.id]!.totalRevenue +=
              (item.price * netQty);
        } else {
          final key =
              item.productId.isNotEmpty ? item.productId : item.name.trim();
          if (!itemMovements.containsKey(key)) {
            itemMovements[key] = _ProductMovementData(
              productId: item.productId,
              name: item.name,
              category: 'Others',
              currentStock: 0,
            );
          }
          itemMovements[key]!.qtySold += netQty;
          itemMovements[key]!.totalRevenue += (item.price * netQty);
        }
      }
    }

    final allMovements = itemMovements.values.toList();

    final fastMovingList = allMovements.where((m) => m.qtySold > 0).toList()
      ..sort((a, b) => b.qtySold.compareTo(a.qtySold));

    final slowMovingList = allMovements.where((m) => m.qtySold <= 2).toList()
      ..sort((a, b) => a.qtySold.compareTo(b.qtySold));

    final categoriesList = inventory.products
        .map((p) => p.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    categoriesList.sort();

    final periodLabel = _getPeriodLabel(range);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Financial & Loss Reports',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          tabs: [
            const Tab(
              icon: Icon(Icons.analytics_rounded, size: 20),
              text: 'Financial Overview',
            ),
            Tab(
              icon: const Icon(Icons.shopping_bag_rounded, size: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Items Sold'),
                  if (totalUnitsSold > 0) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('$totalUnitsSold'),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              icon: const Icon(Icons.delete_sweep_rounded, size: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Loss & Waste'),
                  if (filteredLoss.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('${filteredLoss.length}'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              icon: const Icon(Icons.bolt_rounded, size: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Fast & Slow'),
                  if (fastMovingList.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('${fastMovingList.length}'),
                      backgroundColor: Colors.orange.shade800,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Date Range Selector Segmented Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ReportPeriod>(
                    style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                          value: ReportPeriod.today,
                          label: Text('Today',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold))),
                      ButtonSegment(
                          value: ReportPeriod.thisWeek,
                          label: Text('Week',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold))),
                      ButtonSegment(
                          value: ReportPeriod.thisMonth,
                          label: Text('Month',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold))),
                      ButtonSegment(
                          value: ReportPeriod.custom,
                          label: Text('Custom',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold))),
                    ],
                    selected: {_selectedPeriod},
                    onSelectionChanged: (set) async {
                      final period = set.first;
                      setState(() => _selectedPeriod = period);
                      if (period == ReportPeriod.custom) {
                        await _selectCustomDateRange();
                      }
                    },
                  ),
                ),
                if (_selectedPeriod == ReportPeriod.custom) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_customRange != null)
                        InkWell(
                          onTap: _selectCustomDateRange,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withAlpha(128),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withAlpha(80),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_month_rounded,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  '${DateFormat('MMM d, yyyy').format(_customRange!.start)} - ${DateFormat('MMM d, yyyy').format(_customRange!.end)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.edit_rounded,
                                    size: 14,
                                    color: Theme.of(context).colorScheme.primary),
                              ],
                            ),
                          ),
                        ),
                      _buildQuickMonthSelector(context),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: FINANCIAL OVERVIEW
                _buildFinancialTab(
                  context,
                  periodLabel: periodLabel,
                  profitMargin: profitMargin,
                  grossRevenue: grossRevenue,
                  trueCogs: trueCogs,
                  grossProfit: grossProfit,
                  totalExpenses: totalExpenses,
                  totalLoss: totalLoss,
                  netProfit: netProfit,
                  totalUnitsSold: totalUnitsSold,
                  totalTxCount: totalTxCount,
                  sortedCategories: sortedCategories,
                ),

                // TAB 2: ITEMS SOLD BREAKDOWN
                _buildItemsSoldTab(
                  context,
                  periodLabel: periodLabel,
                  allMovements: allMovements,
                  totalUnitsSold: totalUnitsSold,
                  totalTxCount: totalTxCount,
                  categories: categoriesList,
                ),

                // TAB 3: LOSS & WASTE DETAILS
                _buildLossWasteTab(
                  context,
                  periodLabel: periodLabel,
                  filteredLoss: filteredLoss,
                  allLossRecords: inventory.lossRecords,
                  totalLossInPeriod: totalLoss,
                ),

                // TAB 4: FAST & SLOW MOVING
                _buildProductMovementTab(
                  context,
                  periodLabel: periodLabel,
                  allMovements: allMovements,
                  fastMovingList: fastMovingList,
                  slowMovingList: slowMovingList,
                  categories: categoriesList,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialTab(
    BuildContext context, {
    required String periodLabel,
    required double profitMargin,
    required double grossRevenue,
    required double trueCogs,
    required double grossProfit,
    required double totalExpenses,
    required double totalLoss,
    required double netProfit,
    required int totalUnitsSold,
    required int totalTxCount,
    required List<_CategoryPerformance> sortedCategories,
  }) {
    final semantic = Theme.of(context).semantic;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── SUMMARY METRIC CARDS ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(periodLabel.toUpperCase(),
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 1.2)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: profitMargin >= 0
                          ? semantic.success.withValues(alpha: 0.15)
                          : Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Margin: ${profitMargin.toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          color: profitMargin >= 0
                              ? semantic.success
                              : Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shopping_bag_outlined,
                              size: 18, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Units Sold',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary),
                                ),
                                Text(
                                  '$totalUnitsSold items',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Theme.of(context).colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 18, color: Colors.teal.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Transactions',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade900),
                                ),
                                Text(
                                  '$totalTxCount sales',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.teal.shade900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _reportRow('Gross Revenue', formatPeso(grossRevenue),
                  Theme.of(context).colorScheme.onSurface),
              const SizedBox(height: 10),
              _reportRow('True COGS (Batch Cost)', '- ${formatPeso(trueCogs)}',
                  Colors.grey.shade700),
              const SizedBox(height: 10),
              _reportRow('Gross Trading Profit', formatPeso(grossProfit),
                  semantic.success),
              const SizedBox(height: 10),
              _reportRow('Operating Expenses', '- ${formatPeso(totalExpenses)}',
                  Theme.of(context).colorScheme.error),
              const SizedBox(height: 10),
              _reportRow('Inventory Loss / Waste', '- ${formatPeso(totalLoss)}',
                  Colors.orange.shade900),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(height: 1)),
              _reportRow(
                  'Net Profit',
                  formatPeso(netProfit),
                  netProfit >= 0
                      ? Colors.green.shade800
                      : Theme.of(context).colorScheme.error,
                  isBold: true),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── CATEGORY PERFORMANCE BREAKDOWN ──────────────────────────────
        Row(
          children: [
            Icon(Icons.category_rounded,
                size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Category Performance Breakdown',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),

        if (sortedCategories.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No transactions recorded for $periodLabel',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
              ),
            ),
          )
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedCategories.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final cat = sortedCategories[index];
                final margin = cat.grossSales > 0
                    ? (cat.netProfit / cat.grossSales) * 100
                    : 0.0;

                return ListTile(
                  title: Text(cat.category,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                      '${cat.quantitySold} items sold • COGS: ${formatPeso(cat.cogs)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatPeso(cat.grossSales),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 13)),
                      Text('${margin.toStringAsFixed(1)}% margin',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: margin >= 0 ? Colors.green : Colors.red)),
                    ],
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 24),

        // ── EXPORT PDF REPORT ──────────────────────────────────────────
        ElevatedButton.icon(
          onPressed: () => _exportToPdf(
            context,
            periodLabel: periodLabel,
            sales: grossRevenue,
            cogs: trueCogs,
            grossProfit: grossProfit,
            expenses: totalExpenses,
            loss: totalLoss,
            net: netProfit,
            margin: profitMargin,
            totalUnitsSold: totalUnitsSold,
            totalTxCount: totalTxCount,
            categories: sortedCategories,
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('EXPORT FINANCIAL REPORT AS PDF'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsSoldTab(
    BuildContext context, {
    required String periodLabel,
    required List<_ProductMovementData> allMovements,
    required int totalUnitsSold,
    required int totalTxCount,
    required List<String> categories,
  }) {
    List<_ProductMovementData> soldItems =
        allMovements.where((m) => m.qtySold > 0).toList()
          ..sort((a, b) => b.qtySold.compareTo(a.qtySold));

    if (_itemsSoldSelectedCategory != 'All') {
      soldItems = soldItems
          .where((m) => m.category == _itemsSoldSelectedCategory)
          .toList();
    }

    if (_itemsSoldSearchQuery.trim().isNotEmpty) {
      final q = _itemsSoldSearchQuery.trim().toLowerCase();
      soldItems = soldItems.where((m) {
        return m.name.toLowerCase().contains(q) ||
            m.category.toLowerCase().contains(q) ||
            m.productId.toLowerCase().contains(q);
      }).toList();
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // KPI Summary Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outline
                  .withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ITEMS SOLD SUMMARY ($periodLabel)'.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _movementStatBox(
                      context,
                      title: 'Units Sold',
                      value: '$totalUnitsSold',
                      icon: Icons.shopping_bag_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: _movementStatBox(
                      context,
                      title: 'Transactions',
                      value: '$totalTxCount',
                      icon: Icons.receipt_long_rounded,
                      color: Colors.teal.shade700,
                    ),
                  ),
                  Expanded(
                    child: _movementStatBox(
                      context,
                      title: 'Unique SKUs',
                      value: '${soldItems.length}',
                      icon: Icons.category_rounded,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Search & Category Filter
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search sold items...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (v) => setState(() => _itemsSoldSearchQuery = v),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _itemsSoldSelectedCategory,
                  items: ['All', ...categories].map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Text(c, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _itemsSoldSelectedCategory = val);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (soldItems.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No items sold recorded for $periodLabel',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Check date filters or Sales History tab for past orders.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: soldItems.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = soldItems[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.5),
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  title: Text(
                    item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    'Category: ${item.category} • Stock Remaining: ${item.currentStock}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${item.qtySold} sold',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Text(
                        formatPeso(item.totalRevenue),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildLossWasteTab(
    BuildContext context, {
    required String periodLabel,
    required List<LossRecord> filteredLoss,
    required List<LossRecord> allLossRecords,
    required double totalLossInPeriod,
  }) {
    final totalAllTimeLoss =
        allLossRecords.fold(0.0, (s, r) => s + r.totalLoss);

    // Group loss by type for distribution summary
    final Map<LossType, double> lossByType = {};
    for (final l in filteredLoss) {
      lossByType[l.type] = (lossByType[l.type] ?? 0) + l.totalLoss;
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── LOSS METRIC SUMMARY CARD ────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('ESTIMATED LOSS FOR $periodLabel'.toUpperCase(),
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 1.1)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${filteredLoss.length} Records',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                formatPeso(totalLossInPeriod),
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.error),
              ),
              if (allLossRecords.length != filteredLoss.length) ...[
                const SizedBox(height: 6),
                Text(
                  'All-Time Recorded Loss: ${formatPeso(totalAllTimeLoss)} (${allLossRecords.length} total entries)',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
              if (lossByType.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Text('Loss Breakdown by Reason',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: lossByType.entries.map((e) {
                    final typeName =
                        e.key.name.toUpperCase().replaceAll('_', ' ');
                    return Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: _typeIcon(e.key, context),
                      label: Text('$typeName: ${formatPeso(e.value)}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainer,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── LOSS RECORDS LIST ──────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.list_alt_rounded,
                size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Loss & Spoilage Log',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),

        if (filteredLoss.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 48, color: Theme.of(context).semantic.success),
                    const SizedBox(height: 12),
                    Text('No Loss & Waste Recorded',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text('There are no loss records logged for $periodLabel.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredLoss.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final r = filteredLoss[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainer,
                    child: _typeIcon(r.type, context),
                  ),
                  title: Text(r.productName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${r.type.name.toUpperCase().replaceAll('_', ' ')} • ${r.qty} items',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      if (r.notes.isNotEmpty)
                        Text('"${r.notes}"',
                            style: const TextStyle(
                                fontStyle: FontStyle.italic, fontSize: 11)),
                      Text(
                        '${DateFormat('MMM dd, yyyy • hh:mm a').format(r.createdAt)}${r.processedBy != null ? ' • By ${r.processedBy}' : ''}',
                        style: TextStyle(
                            fontSize: 10,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  trailing: Text(
                    '-${formatPeso(r.totalLoss)}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _typeIcon(LossType type, BuildContext context) {
    final semantic = Theme.of(context).semantic;
    return switch (type) {
      LossType.expired =>
        Icon(Icons.timer_off_rounded, color: semantic.warning, size: 20),
      LossType.damaged => Icon(Icons.broken_image_rounded,
          color: Theme.of(context).colorScheme.error, size: 20),
      LossType.lost => Icon(Icons.not_listed_location_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
      LossType.personalUse =>
        Icon(Icons.person_outline_rounded, color: semantic.info, size: 20),
      LossType.refundReturn => const Icon(Icons.assignment_return_rounded,
          color: Colors.deepOrange, size: 20),
    };
  }

  String _getPeriodLabel(DateTimeRange range) {
    switch (_selectedPeriod) {
      case ReportPeriod.today:
        return 'Today (${DateFormat('MMM d, yyyy').format(range.start)})';
      case ReportPeriod.thisWeek:
        return 'This Week (${DateFormat('MMM d').format(range.start)} - ${DateFormat('MMM d').format(range.end)})';
      case ReportPeriod.thisMonth:
        return DateFormat('MMMM yyyy').format(range.start);
      case ReportPeriod.custom:
        return '${DateFormat('MMM d, yyyy').format(range.start)} - ${DateFormat('MMM d, yyyy').format(range.end)}';
    }
  }

  Widget _buildQuickMonthSelector(BuildContext context) {
    final now = DateTime.now();
    final List<DateTime> pastMonths = [];
    for (int i = 0; i < 24; i++) {
      pastMonths.add(DateTime(now.year, now.month - i, 1));
    }

    return PopupMenuButton<DateTime>(
      tooltip: 'Pick Specific Month (e.g. October)',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_view_month_rounded,
                size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'Pick Month',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 18, color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
      onSelected: (date) {
        _selectSpecificMonth(date.year, date.month);
      },
      itemBuilder: (ctx) => pastMonths.map((m) {
        final label = DateFormat('MMMM yyyy').format(m);
        return PopupMenuItem<DateTime>(
          value: m,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        );
      }).toList(),
    );
  }

  Widget _reportRow(String label, String value, Color color,
      {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                fontSize: isBold ? 15 : 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          textAlign: TextAlign.end,
          style: TextStyle(
              fontWeight: FontWeight.w900,
              color: color,
              fontSize: isBold ? 18 : 14),
        ),
      ],
    );
  }

  Future<void> _exportToPdf(
    BuildContext context, {
    required String periodLabel,
    required double sales,
    required double cogs,
    required double grossProfit,
    required double expenses,
    required double loss,
    required double net,
    required double margin,
    required int totalUnitsSold,
    required int totalTxCount,
    required List<_CategoryPerformance> categories,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                  level: 0,
                  child: pw.Text('GDC Sari-Sari Store - Financial Report',
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 6),
              pw.Text('Period: $periodLabel',
                  style: const pw.TextStyle(fontSize: 14)),
              pw.Divider(height: 24),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Sales Transactions:'),
                    pw.Text('$totalTxCount',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ]),
              pw.SizedBox(height: 4),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Units Sold:'),
                    pw.Text('$totalUnitsSold items',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900)),
                  ]),
              pw.SizedBox(height: 4),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Gross Revenue:'),
                    pw.Text(formatPeso(sales),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ]),
              pw.SizedBox(height: 4),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('True COGS (Batch Cost):'),
                    pw.Text('- ${formatPeso(cogs)}',
                        style: const pw.TextStyle(color: PdfColors.grey700)),
                  ]),
              pw.SizedBox(height: 4),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Gross Trading Profit:',
                        style: const pw.TextStyle(color: PdfColors.green)),
                    pw.Text(formatPeso(grossProfit),
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.green)),
                  ]),
              pw.SizedBox(height: 4),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Operating Expenses:'),
                    pw.Text('- ${formatPeso(expenses)}',
                        style: const pw.TextStyle(color: PdfColors.red)),
                  ]),
              pw.SizedBox(height: 4),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Inventory Loss / Waste:'),
                    pw.Text('- ${formatPeso(loss)}',
                        style: const pw.TextStyle(color: PdfColors.orange)),
                  ]),
              pw.Divider(height: 20),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Net Profit:',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 16)),
                    pw.Text(formatPeso(net),
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 16,
                            color:
                                net >= 0 ? PdfColors.blue900 : PdfColors.red)),
                  ]),
              pw.SizedBox(height: 4),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Profit Margin Percentage:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('${margin.toStringAsFixed(2)}%',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            color:
                                margin >= 0 ? PdfColors.green : PdfColors.red)),
                  ]),
              pw.SizedBox(height: 32),
              pw.Text('Category Performance Breakdown',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              ...categories.map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${c.category} (${c.quantitySold} sold)'),
                        pw.Text(
                            '${formatPeso(c.grossSales)} (Margin: ${(c.grossSales > 0 ? (c.netProfit / c.grossSales) * 100 : 0.0).toStringAsFixed(1)}%)',
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  )),
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                    'Generated on ${DateFormat('MMMM dd, yyyy HH:mm').format(DateTime.now())}',
                    style: const pw.TextStyle(color: PdfColors.grey)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'GDC_Financial_Report_${periodLabel.replaceAll(' ', '_')}.pdf');
  }

  Widget _buildProductMovementTab(
    BuildContext context, {
    required String periodLabel,
    required List<_ProductMovementData> allMovements,
    required List<_ProductMovementData> fastMovingList,
    required List<_ProductMovementData> slowMovingList,
    required List<String> categories,
  }) {
    List<_ProductMovementData> baseList;
    switch (_movementFilterMode) {
      case _MovementFilterMode.fastMoving:
        baseList = fastMovingList;
        break;
      case _MovementFilterMode.slowMoving:
        baseList = slowMovingList;
        break;
      case _MovementFilterMode.allProducts:
        baseList = List.from(allMovements)
          ..sort((a, b) => b.qtySold.compareTo(a.qtySold));
        break;
    }

    if (_movementSelectedCategory != 'All') {
      baseList = baseList
          .where((m) => m.category == _movementSelectedCategory)
          .toList();
    }

    if (_movementSearchQuery.trim().isNotEmpty) {
      final q = _movementSearchQuery.trim().toLowerCase();
      baseList = baseList.where((m) {
        return m.name.toLowerCase().contains(q) ||
            m.category.toLowerCase().contains(q);
      }).toList();
    }

    final int totalUnitsSoldInPeriod =
        allMovements.fold(0, (sum, m) => sum + m.qtySold);
    final double totalMovementRevenue =
        allMovements.fold(0.0, (sum, m) => sum + m.totalRevenue);

    final warningColor = Colors.orange.shade700;
    final infoColor = Colors.blue.shade700;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── MOVEMENT KPI OVERVIEW ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PRODUCT MOVEMENT SUMMARY ($periodLabel)'.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _movementStatBox(
                      context,
                      title: 'Units Sold',
                      value: '$totalUnitsSoldInPeriod',
                      icon: Icons.shopping_bag_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _movementStatBox(
                      context,
                      title: 'Fast Moving',
                      value: '${fastMovingList.length}',
                      icon: Icons.bolt_rounded,
                      color: warningColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _movementStatBox(
                      context,
                      title: 'Slow Moving',
                      value: '${slowMovingList.length}',
                      icon: Icons.hourglass_bottom_rounded,
                      color: infoColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── SEGMENTED FILTER BUTTONS ─────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_MovementFilterMode>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            segments: [
              ButtonSegment(
                value: _MovementFilterMode.fastMoving,
                label: Text('Fast (${fastMovingList.length})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                icon: Icon(Icons.bolt, size: 16, color: warningColor),
              ),
              ButtonSegment(
                value: _MovementFilterMode.slowMoving,
                label: Text('Slow (${slowMovingList.length})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                icon: Icon(Icons.hourglass_bottom, size: 16, color: infoColor),
              ),
              ButtonSegment(
                value: _MovementFilterMode.allProducts,
                label: Text('All (${allMovements.length})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                icon: const Icon(Icons.inventory_2_rounded, size: 16),
              ),
            ],
            selected: {_movementFilterMode},
            onSelectionChanged: (set) {
              setState(() => _movementFilterMode = set.first);
            },
          ),
        ),

        const SizedBox(height: 16),

        // ── SEARCH BAR & CATEGORY FILTER ──────────────────────────────────
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search product or category...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _movementSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () =>
                              setState(() => _movementSearchQuery = ''),
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ),
                onChanged: (val) =>
                    setState(() => _movementSearchQuery = val),
              ),
            ),
            const SizedBox(width: 10),
            DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: DropdownButton<String>(
                  value: categories.contains(_movementSelectedCategory)
                      ? _movementSelectedCategory
                      : 'All',
                  icon: const Icon(Icons.filter_list_rounded, size: 18),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onChanged: (cat) {
                    if (cat != null) {
                      setState(() => _movementSelectedCategory = cat);
                    }
                  },
                  items: ['All', ...categories].map((c) {
                    return DropdownMenuItem<String>(
                      value: c,
                      child: Text(c == 'All' ? 'All Categories' : c),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── PRODUCT MOVEMENT LIST ───────────────────────────────────────
        if (baseList.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off_rounded,
                        size: 44,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text(
                      'No matching products found',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Try clearing search filters or changing the time period.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.3),
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: baseList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = baseList[index];
                final isFast = item.qtySold > 0;
                final badgeColor = isFast ? warningColor : infoColor;
                final rank = index + 1;

                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: badgeColor.withValues(alpha: 0.15),
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: badgeColor,
                      ),
                    ),
                  ),
                  title: Text(
                    item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.category,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Stock: ${item.currentStock}',
                        style: TextStyle(
                          fontSize: 11,
                          color: item.currentStock <= 5
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: item.currentStock <= 5
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.qtySold == 0 ? 'No sales' : '${item.qtySold} sold',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: isFast
                              ? badgeColor
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatPeso(item.totalRevenue),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 24),

        // ── EXPORT PDF BUTTON FOR MOVEMENT REPORT ─────────────────────
        ElevatedButton.icon(
          onPressed: () => _exportMovementToPdf(
            context,
            periodLabel: periodLabel,
            fastMoving: fastMovingList,
            slowMoving: slowMovingList,
            totalUnits: totalUnitsSoldInPeriod,
            totalRevenue: totalMovementRevenue,
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('EXPORT PRODUCT MOVEMENT REPORT AS PDF'),
          style: ElevatedButton.styleFrom(
            backgroundColor: warningColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _movementStatBox(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportMovementToPdf(
    BuildContext context, {
    required String periodLabel,
    required List<_ProductMovementData> fastMoving,
    required List<_ProductMovementData> slowMoving,
    required int totalUnits,
    required double totalRevenue,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                  level: 0,
                  child: pw.Text('GDC Sari-Sari Store - Product Movement Report',
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 4),
              pw.Text('Period: $periodLabel',
                  style: const pw.TextStyle(fontSize: 12)),
              pw.Divider(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Units Sold: $totalUnits'),
                  pw.Text('Total Movement Revenue: ${formatPeso(totalRevenue)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text('Fast Moving Products (${fastMoving.length})',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              ...fastMoving.take(20).map((m) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${m.name} (${m.category})'),
                        pw.Text('${m.qtySold} sold - ${formatPeso(m.totalRevenue)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  )),
              pw.SizedBox(height: 20),
              pw.Text('Slow Moving / Low Activity Products (${slowMoving.length})',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              ...slowMoving.take(20).map((m) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${m.name} (${m.category})'),
                        pw.Text('${m.qtySold} sold - Stock: ${m.currentStock}',
                            style: const pw.TextStyle(color: PdfColors.grey700)),
                      ],
                    ),
                  )),
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                    'Generated on ${DateFormat('MMMM dd, yyyy HH:mm').format(DateTime.now())}',
                    style: const pw.TextStyle(color: PdfColors.grey)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'GDC_Product_Movement_${periodLabel.replaceAll(' ', '_')}.pdf');
  }
}

enum _MovementFilterMode {
  fastMoving('Fast Moving'),
  slowMoving('Slow Moving'),
  allProducts('All Products');

  final String label;
  const _MovementFilterMode(this.label);
}

class _ProductMovementData {
  final String productId;
  final String name;
  final String category;
  int currentStock;
  int qtySold;
  double totalRevenue;

  _ProductMovementData({
    required this.productId,
    required this.name,
    required this.category,
    required this.currentStock,
    this.qtySold = 0,
    this.totalRevenue = 0.0,
  });
}

class _CategoryPerformance {
  final String category;
  double grossSales = 0.0;
  double cogs = 0.0;
  int quantitySold = 0;

  _CategoryPerformance({
    required this.category,
  });

  double get netProfit => grossSales - cogs;
}
