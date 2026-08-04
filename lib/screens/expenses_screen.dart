import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/expense_provider.dart';
import '../../utils/format.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final expenses   = context.watch<ExpenseProvider>().expenses;
    final today      = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayList  = expenses.where(
            (e) => DateFormat('yyyy-MM-dd').format(e.createdAt) == today).toList();
    final todayTotal = todayList.fold(0.0, (s, e) => s + e.amount);

    // Group by category for summary
    final byCategory = <String, double>{};
    for (final e in todayList) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expenses_fab',
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: () => _showAddSheet(context),
        icon:  const Icon(Icons.add_rounded),
        label: const Text('Log Expense'),
      ),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Expenses',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),

        // Today's total card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.money_off_rounded, color: Theme.of(context).colorScheme.error)),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("TODAY'S TOTAL",
                  style: TextStyle(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
              Text(formatPeso(todayTotal),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.error)),
            ]),
          ]),
        ),

        // Category breakdown (if any expenses today)
        if (byCategory.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Today by Category',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 16),
              ...byCategory.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(formatPeso(e.value),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              )),
            ]),
          ),
        ],

        const SizedBox(height: 32),
        Text('History',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),

        if (expenses.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1)),
                  const SizedBox(height: 16),
                  Text('No expenses logged yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),

        ...expenses.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1),
                child: Icon(Icons.receipt_outlined,
                    color: Theme.of(context).colorScheme.error, size: 18)),
            title: Text(e.description,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(
                '${e.category} · ${DateFormat('MMM d hh:mm a').format(e.createdAt)}',
                style: Theme.of(context).textTheme.labelSmall),
            trailing: Text(formatPeso(e.amount),
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.error)),
          ),
        )),

        const SizedBox(height: 80), // FAB clearance
      ])),
    );
  }

  void _showAddSheet(BuildContext ctx) {
    final descCtrl = TextEditingController();
    final amtCtrl  = TextEditingController();
    String category = 'Operations';

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSt) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24, right: 24, top: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2))),
            Text('Log New Expense',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            TextField(controller: descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.edit_note_rounded))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextField(
                  controller: amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Amount', prefixText: '₱ '))),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ['Operations','Supplies','Utilities','Transport','Others']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setSt(() => category = v!))),
            ]),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: () async {
                  final amt = double.tryParse(amtCtrl.text) ?? 0;
                  if (descCtrl.text.trim().isEmpty || amt <= 0) return;
                  await ctx.read<ExpenseProvider>().addExpense(
                      descCtrl.text.trim(), amt, category);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('SAVE EXPENSE')),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }
}
