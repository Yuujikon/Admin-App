import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/inventory_provider.dart';
import '../providers/expense_provider.dart';
import '../utils/format.dart';
import '../config/theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _selectedMonth = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final expenses = context.watch<ExpenseProvider>().expenses;
    
    final monthStr = DateFormat('yyyy-MM').format(_selectedMonth);
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);

    final monthTx = inventory.transactions.where(
        (t) => DateFormat('yyyy-MM').format(t.createdAt) == monthStr && !t.isRefunded).toList();
    
    final monthExp = expenses.where(
        (e) => DateFormat('yyyy-MM').format(e.createdAt) == monthStr).toList();

    final totalSales = monthTx.fold(0.0, (s, t) => s + t.total);
    final grossProfit = monthTx.fold(0.0, (s, t) => s + t.items.fold(0.0, (isum, item) => isum + (item.price - item.costPrice) * item.qty));
    final totalExp = monthExp.fold(0.0, (s, e) => s + e.amount);
    final netIncome = grossProfit - totalExp;

    // Loss in selected month
    final monthLoss = inventory.lossRecords.where(
        (r) => DateFormat('yyyy-MM').format(r.createdAt) == monthStr);
    final totalLoss = monthLoss.fold(0.0, (s, r) => s + r.totalLoss);
    final netProfit = netIncome - totalLoss;
    final profitMargin = totalSales > 0 ? (netProfit / totalSales) * 100 : 0.0;

    final semantic = Theme.of(context).semantic;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton.filledTonal(
            icon: const Icon(Icons.calendar_month_rounded, size: 20),
            onPressed: _pickMonth,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.light 
                      ? Colors.black.withValues(alpha: 0.03) 
                      : Colors.transparent, 
                  blurRadius: 20, 
                  offset: const Offset(0, 10)
                )
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Text(monthLabel.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5), letterSpacing: 1.5)),
                  const SizedBox(height: 24),
                  _reportRow('Gross Sales', formatPeso(totalSales), Theme.of(context).colorScheme.onSurface),
                  const SizedBox(height: 12),
                  _reportRow('Gross Profit', formatPeso(grossProfit), semantic.success),
                  const SizedBox(height: 12),
                  _reportRow('Total Expenses', '- ${formatPeso(totalExp)}', Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  _reportRow('Inventory Loss', '- ${formatPeso(totalLoss)}', semantic.warning),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(height: 1),
                  ),
                  _reportRow('Net Profit', formatPeso(netProfit), 
                             netProfit >= 0 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error, isBold: true),
                  const SizedBox(height: 12),
                  _reportRow('Profit Margin', '${profitMargin.toStringAsFixed(2)}%', 
                             profitMargin >= 0 ? semantic.success : Theme.of(context).colorScheme.error),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          const Text('Daily Sales Trend', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: _DailySalesChart(transactions: monthTx, month: _selectedMonth),
          ),

          const SizedBox(height: 24),
          const Text('Top Performing Products', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._buildTopProducts(monthTx),
          
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _exportToPdf(
              context,
              monthLabel: monthLabel,
              sales: totalSales,
              profit: grossProfit,
              expenses: totalExp,
              loss: totalLoss,
              net: netProfit,
              margin: profitMargin,
              topProducts: _getTopProductsData(monthTx),
            ), 
            icon: const Icon(Icons.picture_as_pdf), 
            label: const Text('EXPORT AS PDF'),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, int>> _getTopProductsData(List transactions) {
    final counts = <String, int>{};
    for (var tx in transactions) {
      for (var item in tx.items) {
        counts[item.name] = (counts[item.name] ?? 0) + (item.qty as int);
      }
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  Future<void> _exportToPdf(
    BuildContext context, {
    required String monthLabel,
    required double sales,
    required double profit,
    required double expenses,
    required double loss,
    required double net,
    required double margin,
    required List<MapEntry<String, int>> topProducts,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(level: 0, child: pw.Text('GDC Sari-Sari Store - Monthly Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 8),
              pw.Text('Month: $monthLabel', style: const pw.TextStyle(fontSize: 18)),
              pw.Divider(height: 32),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Gross Sales:'),
                  pw.Text(formatPeso(sales), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Gross Profit:', style: const pw.TextStyle(color: PdfColors.green)),
                  pw.Text(formatPeso(profit), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Expenses:'),
                  pw.Text('- ${formatPeso(expenses)}', style: const pw.TextStyle(color: PdfColors.red)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Inventory Loss:'),
                  pw.Text('- ${formatPeso(loss)}', style: const pw.TextStyle(color: PdfColors.orange)),
                ],
              ),
              pw.Divider(height: 24),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Net Profit:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                  pw.Text(formatPeso(net), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: net >= 0 ? PdfColors.blue900 : PdfColors.red)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Profit Margin:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('${margin.toStringAsFixed(2)}%', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: margin >= 0 ? PdfColors.green : PdfColors.red)),
                ],
              ),
              
              pw.SizedBox(height: 40),
              pw.Text('Top Performing Products', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              ...topProducts.take(10).map((e) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(e.key),
                    pw.Text('${e.value} sold', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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

    // Save/Share directly without print dialog (Requirement 10)
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'GDC_Report_${monthLabel.replaceAll(' ', '_')}.pdf');
  }

  Widget _reportRow(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: isBold ? 18 : 14)),
        ],
      ),
    );
  }

  List<Widget> _buildTopProducts(List transactions) {
    final counts = <String, int>{};
    for (var tx in transactions) {
      for (var item in tx.items) {
        counts[item.name] = (counts[item.name] ?? 0) + (item.qty as int);
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.take(5).map((e) => ListTile(
      dense: true,
      title: Text(e.key),
      trailing: Text('${e.value} sold', style: const TextStyle(fontWeight: FontWeight.bold)),
    )).toList();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final res = await showDatePicker(
      context: context, 
      initialDate: _selectedMonth, 
      firstDate: DateTime(2023), 
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (res != null) {
      setState(() => _selectedMonth = res);
    }
  }
}

class _DailySalesChart extends StatelessWidget {
  final List transactions;
  final DateTime month;

  const _DailySalesChart({required this.transactions, required this.month});

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final dailyData = List.generate(daysInMonth, (index) => 0.0);

    for (var tx in transactions) {
      final day = tx.createdAt.day;
      if (day <= daysInMonth) {
        dailyData[day - 1] += tx.total;
      }
    }

    final maxVal = dailyData.isEmpty ? 100.0 : dailyData.reduce((a, b) => a > b ? a : b);
    final limit = (maxVal * 1.2).clamp(100.0, double.infinity);

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, meta) {
                if (val % 5 == 0 || val == 1 || val == daysInMonth) {
                  return Text(val.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey));
                }
                return const Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 1,
        maxX: daysInMonth.toDouble(),
        minY: 0,
        maxY: limit,
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(daysInMonth, (i) => FlSpot(i + 1.0, dailyData[i])),
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
