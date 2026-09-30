import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/shift_session.dart';
import '../providers/shift_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/printer_provider.dart';
import '../utils/format.dart';
import '../config/theme.dart';

class ShiftScreen extends StatelessWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shiftProvider = context.watch<ShiftProvider>();
    final auth = context.watch<AppAuthProvider>();
    final shift = shiftProvider.currentShift;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Shift & Cash Drawer', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: shift == null
          ? _NoActiveShiftView(auth: auth)
          : _ActiveShiftView(shift: shift, auth: auth),
    );
  }
}

class _NoActiveShiftView extends StatelessWidget {
  final AppAuthProvider auth;
  const _NoActiveShiftView({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.point_of_sale_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              'No Register Shift Currently Open',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'An active register shift is required before processing POS transactions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => _showOpenShiftDialog(context, auth),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('OPEN REGISTER SHIFT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GdcColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOpenShiftDialog(BuildContext context, AppAuthProvider auth) {
    final floatCtrl = TextEditingController(text: '1000.00');
    final cashierNameCtrl = TextEditingController(text: auth.currentUser?.email ?? 'Cashier');

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Open Register Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: cashierNameCtrl,
              decoration: const InputDecoration(labelText: 'Cashier Name / Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: floatCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              decoration: const InputDecoration(labelText: 'Opening Cash Float', prefixText: '₱ ', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final float = double.tryParse(floatCtrl.text) ?? 0.0;
              final name = cashierNameCtrl.text.trim();

              await context.read<ShiftProvider>().openShift(
                cashierId: auth.currentUser?.uid ?? 'uid-1',
                cashierName: name.isEmpty ? 'Cashier' : name,
                openingFloat: float,
              );

              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Start Shift'),
          ),
        ],
      ),
    );
  }
}

class _ActiveShiftView extends StatelessWidget {
  final ShiftSession shift;
  final AppAuthProvider auth;

  const _ActiveShiftView({required this.shift, required this.auth});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          ),
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.point_of_sale_rounded, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('X-READING (ACTIVE SHIFT)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: theme.colorScheme.primary)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(12)),
                      child: const Text('REGISTER ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _row('Cashier:', shift.cashierName),
                _row('Shift Started:', DateFormat('MMM d, yyyy • hh:mm a').format(shift.openedAt)),
                _row('Opening Float:', formatPeso(shift.openingFloat)),
                _row('Cash Sales:', formatPeso(shift.cashSales), Colors.green.shade800),
                _row('GCash / Digital Sales:', formatPeso(shift.gcashSales), Colors.blue.shade800),
                _row('Mid-Shift Cash Drops:', '- ${formatPeso(shift.totalCashDrops)}', Colors.red),
                const Divider(height: 24),
                _row('Expected Cash in Register:', formatPeso(shift.expectedCash), theme.colorScheme.primary, true),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final printer = context.read<PrinterProvider>();
                      final success = await printer.printZReading(shift: shift, isXReading: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? "Mid-day X-Reading printed! 🖨️" : "Printer not connected or failed."),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text('PRINT X-READING', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showCashDropDialog(context),
                icon: const Icon(Icons.money_off_rounded, size: 18),
                label: const Text('CASH DROP'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showCloseShiftSheet(context, shift),
                icon: const Icon(Icons.stop_circle_rounded, size: 18),
                label: const Text('Z-READING (CLOSE)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        if (shift.cashDrops.isNotEmpty) ...[
          const Text('Mid-Shift Cash Removals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shift.cashDrops.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final drop = shift.cashDrops[index];
                return ListTile(
                  title: Text('- ${formatPeso(drop.amount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  subtitle: Text('${drop.reason} • ${DateFormat('hh:mm a').format(drop.createdAt)}'),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value, [Color? color, bool isBold = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 14 : 12)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isBold ? 16 : 13, color: color)),
        ],
      ),
    );
  }

  void _showCashDropDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: 'Transfer excess cash to safe');

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Mid-Shift Cash Drop'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              decoration: const InputDecoration(labelText: 'Amount Removed', prefixText: '₱ ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason / Note', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;

              await context.read<ShiftProvider>().recordCashDrop(
                amount: amount,
                reason: reasonCtrl.text.trim(),
              );

              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Confirm Cash Drop'),
          ),
        ],
      ),
    );
  }

  void _showCloseShiftSheet(BuildContext context, ShiftSession shift) {
    final actualCashCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 20, right: 20, top: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('End-of-Shift Z-Reading & Cash Count', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 4),
              Text('Expected Register Cash: ${formatPeso(shift.expectedCash)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: actualCashCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                decoration: const InputDecoration(
                  labelText: 'Physical Cash Counted in Register *',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final counted = double.tryParse(actualCashCtrl.text) ?? 0.0;
                    final closed = await context.read<ShiftProvider>().closeShift(actualCashCounted: counted);

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      _showZReadingDialog(context, closed);
                    }
                  },
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('FINALIZE & CLOSE SHIFT (Z-READING)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showZReadingDialog(BuildContext context, ShiftSession closed) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Z-Reading Summary (Final)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Cashier: ${closed.cashierName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Expected Cash:'), Text(formatPeso(closed.expectedCash))]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Actual Counted:'), Text(formatPeso(closed.actualCashCounted ?? 0))]),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cash Variance:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  formatPeso(closed.cashDifference),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: closed.isShortage ? Colors.red : (closed.isOverage ? Colors.green : Colors.blue),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ElevatedButton.icon(
            onPressed: () async {
              final printer = context.read<PrinterProvider>();
              final success = await printer.printZReading(shift: closed);
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? "Z-Reading printed successfully! 🖨️" : "Printer not connected or failed."),
                  ),
                );
              }
            },
            icon: const Icon(Icons.print_rounded, size: 16),
            label: const Text('PRINT Z-READING'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
