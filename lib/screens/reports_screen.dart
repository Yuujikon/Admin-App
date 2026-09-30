import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/inventory_provider.dart';
import '../providers/expense_provider.dart';
import '../utils/format.dart';
import '../config/theme.dart';

enum ReportPeriod { today, thisWeek, thisMonth, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _selectedPeriod = ReportPeriod.thisMonth;
  DateTimeRange? _customRange;

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
        return _customRange ?? DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
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
      return t.createdAt.isAfter(range.start.subtract(const Duration(seconds: 1))) &&
             t.createdAt.isBefore(range.end.add(const Duration(seconds: 1)));
    }).toList();

    // Filter expenses within selected range
    final filteredExp = expenses.where((e) {
      return e.createdAt.isAfter(range.start.subtract(const Duration(seconds: 1))) &&
             e.createdAt.isBefore(range.end.add(const Duration(seconds: 1)));
    }).toList();

    // Filter loss records within selected range
    final filteredLoss = inventory.lossRecords.where((l) {
      return l.createdAt.isAfter(range.start.subtract(const Duration(seconds: 1))) &&
             l.createdAt.isBefore(range.end.add(const Duration(seconds: 1)));
    }).toList();

    // 1. Core Metrics Aggregation (Line-Item True COGS from Split Batches)
    final double grossRevenue = filteredTx.fold(0.0, (sum, t) => sum + t.total);
    final double trueCogs = filteredTx.fold(0.0, (sum, t) => sum + t.items.fold(0.0, (iSum, item) {
      final double itemCogs = item.totalCogs > 0
          ? item.totalCogs
          : (item.costPrice * item.qty);
      return iSum + itemCogs;
    }));
    final double grossProfit = grossRevenue - trueCogs;

    final double totalExpenses = filteredExp.fold(0.0, (sum, e) => sum + e.amount);
    final double totalLoss = filteredLoss.fold(0.0, (sum, l) => sum + (l.unitPrice * l.qty));

    final double netProfit = grossProfit - totalExpenses - totalLoss;
    final double profitMargin = grossRevenue > 0 ? (netProfit / grossRevenue) * 100 : 0.0;

    // 2. Category Performance Breakdown
    final Map<String, _CategoryPerformance> categoryPerformance = {};
    for (final tx in filteredTx) {
      for (final item in tx.items) {
        String cat = 'Others';
        try {
          final p = inventory.products.firstWhere((p) => p.id == item.productId);
          cat = p.category;
        } catch (_) {}

        final rev = item.price * item.qty;
        final cogs = item.totalCogs > 0
            ? item.totalCogs
            : (item.costPrice * item.qty);

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

    final semantic = Theme.of(context).semantic;
    final periodLabel = _getPeriodLabel(range);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Financial & Batch Reports', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Date Range Selector Segmented Button
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ReportPeriod>(
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: ReportPeriod.today, label: Text('Today', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                ButtonSegment(value: ReportPeriod.thisWeek, label: Text('Week', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                ButtonSegment(value: ReportPeriod.thisMonth, label: Text('Month', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                ButtonSegment(value: ReportPeriod.custom, label: Text('Custom', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              ],
              selected: {_selectedPeriod},
              onSelectionChanged: (set) async {
                final period = set.first;
                if (period == ReportPeriod.custom) {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                    initialDateRange: _customRange ?? _activeDateRange,
                  );
                  if (picked != null) {
                    setState(() {
                      _customRange = picked;
                      _selectedPeriod = ReportPeriod.custom;
                    });
                  }
                } else {
                  setState(() => _selectedPeriod = period);
                }
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── SUMMARY METRIC CARDS ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(periodLabel.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: profitMargin >= 0 ? semantic.success.withValues(alpha: 0.15) : Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Margin: ${profitMargin.toStringAsFixed(1)}%',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: profitMargin >= 0 ? semantic.success : Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _reportRow('Gross Revenue', formatPeso(grossRevenue), Theme.of(context).colorScheme.onSurface),
                const SizedBox(height: 10),
                _reportRow('True COGS (Batch Cost)', '- ${formatPeso(trueCogs)}', Colors.grey.shade700),
                const SizedBox(height: 10),
                _reportRow('Gross Trading Profit', formatPeso(grossProfit), semantic.success),
                const SizedBox(height: 10),
                _reportRow('Operating Expenses', '- ${formatPeso(totalExpenses)}', Theme.of(context).colorScheme.error),
                const SizedBox(height: 10),
                _reportRow('Inventory Loss / Waste', '- ${formatPeso(totalLoss)}', Colors.orange.shade900),
                const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1)),
                _reportRow('Net Profit', formatPeso(netProfit), netProfit >= 0 ? Colors.green.shade800 : Theme.of(context).colorScheme.error, isBold: true),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── CATEGORY PERFORMANCE BREAKDOWN ──────────────────────────────
          Row(
            children: [
              Icon(Icons.category_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Category Performance Breakdown', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),

          if (sortedCategories.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('No transactions recorded for $periodLabel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
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
                  final margin = cat.grossSales > 0 ? (cat.netProfit / cat.grossSales) * 100 : 0.0;

                  return ListTile(
                    title: Text(cat.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('${cat.quantitySold} items sold • COGS: ${formatPeso(cat.cogs)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatPeso(cat.grossSales), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                        Text('${margin.toStringAsFixed(1)}% margin', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: margin >= 0 ? Colors.green : Colors.red)),
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
      ),
    );
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

  Widget _reportRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w500, fontSize: isBold ? 15 : 13)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: isBold ? 18 : 14)),
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
              pw.Header(level: 0, child: pw.Text('GDC Sari-Sari Store - Financial Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 6),
              pw.Text('Period: $periodLabel', style: const pw.TextStyle(fontSize: 14)),
              pw.Divider(height: 24),

              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Gross Revenue:'),
                pw.Text(formatPeso(sales), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ]),
              pw.SizedBox(height: 4),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('True COGS (Batch Cost):'),
                pw.Text('- ${formatPeso(cogs)}', style: const pw.TextStyle(color: PdfColors.grey700)),
              ]),
              pw.SizedBox(height: 4),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Gross Trading Profit:', style: const pw.TextStyle(color: PdfColors.green)),
                pw.Text(formatPeso(grossProfit), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
              ]),
              pw.SizedBox(height: 4),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Operating Expenses:'),
                pw.Text('- ${formatPeso(expenses)}', style: const pw.TextStyle(color: PdfColors.red)),
              ]),
              pw.SizedBox(height: 4),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Inventory Loss / Waste:'),
                pw.Text('- ${formatPeso(loss)}', style: const pw.TextStyle(color: PdfColors.orange)),
              ]),
              pw.Divider(height: 20),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Net Profit:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                pw.Text(formatPeso(net), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: net >= 0 ? PdfColors.blue900 : PdfColors.red)),
              ]),
              pw.SizedBox(height: 4),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Profit Margin Percentage:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('${margin.toStringAsFixed(2)}%', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: margin >= 0 ? PdfColors.green : PdfColors.red)),
              ]),

              pw.SizedBox(height: 32),
              pw.Text('Category Performance Breakdown', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              ...categories.map((c) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${c.category} (${c.quantitySold} sold)'),
                    pw.Text('${formatPeso(c.grossSales)} (Margin: ${(c.grossSales > 0 ? (c.netProfit / c.grossSales) * 100 : 0.0).toStringAsFixed(1)}%)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              )),

              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('Generated on ${DateFormat('MMMM dd, yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(color: PdfColors.grey)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'GDC_Financial_Report_${periodLabel.replaceAll(' ', '_')}.pdf');
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
