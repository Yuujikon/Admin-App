import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/inventory_provider.dart';
import '../providers/expense_provider.dart';
import '../models/loss_record.dart';
import '../utils/format.dart';
import '../config/theme.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTimeRange get _activeDateRange {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case ReportPeriod.today:
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return DateTimeRange(start: start, end: end);
      case ReportPeriod.thisWeek:
        final start = now.subtract(Duration(days: now.weekday - 1));
        final startDay = DateTime(start.year, start.month, start.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return DateTimeRange(start: startDay, end: end);
      case ReportPeriod.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return DateTimeRange(start: start, end: end);
      case ReportPeriod.custom:
        return _customRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: DateTime(now.year, now.month, now.day, 23, 59, 59),
            );
    }
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    DateTimeRange initialRange;
    if (_customRange != null) {
      final start = _customRange!.start.isAfter(todayEnd) ? todayEnd : _customRange!.start;
      final end = _customRange!.end.isAfter(todayEnd) ? todayEnd : _customRange!.end;
      initialRange = DateTimeRange(
        start: start.isAfter(end) ? end : start,
        end: end,
      );
    } else {
      final start = DateTime(now.year, now.month, 1);
      final end = todayEnd;
      initialRange = DateTimeRange(
        start: start.isAfter(end) ? end : start,
        end: end,
      );
    }

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: todayEnd,
      initialDateRange: initialRange,
      helpText: 'Select Custom Date Range',
    );

    if (picked != null) {
      final normalizedStart = DateTime(picked.start.year, picked.start.month, picked.start.day);
      final normalizedEnd = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      setState(() {
        _customRange = DateTimeRange(start: normalizedStart, end: normalizedEnd);
        _selectedPeriod = ReportPeriod.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final expenses = context.watch<ExpenseProvider>().expenses;
    final range = _activeDateRange;

    // Filter transactions within selected range
    final filteredTx = inventory.transactions.where((t) {
      if (t.isRefunded) return false;
      return t.createdAt
              .isAfter(range.start.subtract(const Duration(seconds: 1))) &&
          t.createdAt.isBefore(range.end.add(const Duration(seconds: 1)));
    }).toList();

    // Filter expenses within selected range
    final filteredExp = expenses.where((e) {
      return e.createdAt
              .isAfter(range.start.subtract(const Duration(seconds: 1))) &&
          e.createdAt.isBefore(range.end.add(const Duration(seconds: 1)));
    }).toList();

    // Filter loss records within selected range
    final filteredLoss = inventory.lossRecords.where((l) {
      return l.createdAt
              .isAfter(range.start.subtract(const Duration(seconds: 1))) &&
          l.createdAt.isBefore(range.end.add(const Duration(seconds: 1)));
    }).toList();

    // 1. Core Metrics Aggregation
    final double grossRevenue = filteredTx.fold(0.0, (sum, t) => sum + t.total);
    final double trueCogs = filteredTx.fold(
        0.0,
        (sum, t) =>
            sum +
            t.items.fold(0.0, (iSum, item) {
              final double itemCogs = item.totalCogs > 0
                  ? item.totalCogs
                  : (item.costPrice * item.qty);
              return iSum + itemCogs;
            }));
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
      for (final item in tx.items) {
        String cat = 'Others';
        try {
          final p =
              inventory.products.firstWhere((p) => p.id == item.productId);
          cat = p.category;
        } catch (_) {}

        final rev = item.price * item.qty;
        final cogs =
            item.totalCogs > 0 ? item.totalCogs : (item.costPrice * item.qty);

        if (!categoryPerformance.containsKey(cat)) {
          categoryPerformance[cat] = _CategoryPerformance(category: cat);
        }
        categoryPerformance[cat]!.grossSales += rev;
        categoryPerformance[cat]!.cogs += cogs;
        categoryPerformance[cat]!.quantitySold += item.qty;
      }
    }

    final sortedCategories = categoryPerformance.values.toList()
      ..sort((a, b) => b.grossSales.compareTo(a.grossSales));

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
                      if (period == ReportPeriod.custom) {
                        await _selectCustomDateRange();
                      } else {
                        setState(() => _selectedPeriod = period);
                      }
                    },
                  ),
                ),
                if (_selectedPeriod == ReportPeriod.custom && _customRange != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _selectCustomDateRange,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withAlpha(128),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withAlpha(80),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_month_rounded,
                              size: 16, color: Theme.of(context).colorScheme.primary),
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
                              size: 14, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
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
                  sortedCategories: sortedCategories,
                ),

                // TAB 2: LOSS & WASTE DETAILS
                _buildLossWasteTab(
                  context,
                  periodLabel: periodLabel,
                  filteredLoss: filteredLoss,
                  allLossRecords: inventory.lossRecords,
                  totalLossInPeriod: totalLoss,
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
