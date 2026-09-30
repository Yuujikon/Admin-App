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
import '../widgets/premium_components.dart';

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
        title: const Text('Shift & Cash Drawer',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
        child: MaxWidthContainer(
          maxWidth: MaxWidthContainer.formMaxWidth,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.point_of_sale_rounded,
                  size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                'No Register Shift Currently Open',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'An active register shift is required before processing POS transactions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                onPressed: () => _showOpenShiftDialog(context, auth),
                icon: Icons.play_arrow_rounded,
                backgroundColor: GdcColors.primaryGreen,
                foregroundColor: Colors.white,
                minWidth: 200,
                maxWidth: 350,
                child: const Text('OPEN REGISTER SHIFT'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOpenShiftDialog(BuildContext context, AppAuthProvider auth) {
    final floatCtrl = TextEditingController(text: '1000.00');
    final cashierNameCtrl =
        TextEditingController(text: auth.currentUser?.email ?? 'Cashier');

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Open Register Shift'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: double.infinity,
                child: TextField(
                  controller: cashierNameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Cashier Name / Email',
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextField(
                  controller: floatCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                  ],
                  decoration: const InputDecoration(
                      labelText: 'Opening Cash Float',
                      prefixText: 'P ',
                      border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3)),
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
                            Icon(Icons.point_of_sale_rounded,
                                color: theme.colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text('X-READING (ACTIVE SHIFT)',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: theme.colorScheme.primary)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(12)),
                          child: const Text('REGISTER ACTIVE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green)),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _row('Cashier:', shift.cashierName),
                    _row('Shift Started:',
                        DateFormat('MMM d, yyyy • hh:mm a').format(shift.openedAt)),
                    _row('Opening Float:', formatPeso(shift.openingFloat)),
                    _row('Cash Sales:', formatPeso(shift.cashSales),
                        Colors.green.shade800),
                    const Divider(height: 24),
                    _row(
                        'Expected Cash in Register:',
                        formatPeso(shift.expectedCash),
                        theme.colorScheme.primary,
                        true),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          final printer = context.read<PrinterProvider>();
                          final success = await printer.printZReading(
                              shift: shift, isXReading: true);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success
                                    ? "Mid-day X-Reading printed! 🖨️"
                                    : "Printer not connected or failed."),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('PRINT X-READING',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: PrimaryButton(
                onPressed: () => _showCloseShiftSheet(context, shift),
                icon: Icons.stop_circle_rounded,
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                minWidth: 200,
                maxWidth: 350,
                child: const Text('Z-READING (CLOSE SHIFT)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, [Color? color, bool isBold = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  fontSize: isBold ? 14 : 12)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isBold ? 16 : 13,
                  color: color)),
        ],
      ),
    );
  }

  void _showCloseShiftSheet(BuildContext context, ShiftSession shift) {
    final actualCashCtrl = TextEditingController(
      text: shift.expectedCash.toStringAsFixed(2),
    );
    double actualAmount = shift.expectedCash;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final variance = actualAmount - shift.expectedCash;
          final isMatch = variance.abs() < 0.01;
          final isShort = variance < -0.01;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: MaxWidthContainer(
                maxWidth: MaxWidthContainer.formMaxWidth,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.red.shade700, size: 28),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Confirm Close Shift & Z-Reading',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _dialogRow('Cashier:', shift.cashierName),
                        _dialogRow(
                            'Opening Float:', formatPeso(shift.openingFloat)),
                        _dialogRow('Cash Sales:', formatPeso(shift.cashSales)),
                        const Divider(height: 16),
                        _dialogRow(
                          'Expected Cash in Register:',
                          formatPeso(shift.expectedCash),
                          isBold: true,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Verify Cash Amount in Drawer:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: actualCashCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                    ],
                    onChanged: (val) {
                      setState(() {
                        actualAmount = double.tryParse(val) ?? 0.0;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Verified Cash Count *',
                      prefixText: 'P ',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          actualCashCtrl.clear();
                          setState(() {
                            actualAmount = 0.0;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMatch
                          ? Colors.green.shade50
                          : (isShort
                              ? Colors.red.shade50
                              : Colors.blue.shade50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isMatch
                            ? Colors.green.shade300
                            : (isShort
                                ? Colors.red.shade300
                                : Colors.blue.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isMatch
                              ? '✓ Cash matches expected amount'
                              : (isShort ? '⚠ Shortage' : 'ℹ Overage'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isMatch
                                ? Colors.green.shade900
                                : (isShort
                                    ? Colors.red.shade900
                                    : Colors.blue.shade900),
                          ),
                        ),
                        Text(
                          formatPeso(variance.abs()),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isMatch
                                ? Colors.green.shade900
                                : (isShort
                                    ? Colors.red.shade900
                                    : Colors.blue.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final closed = await context
                                .read<ShiftProvider>()
                                .closeShift(actualCashCounted: actualAmount);

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              _showZReadingDialog(context, closed);
                            }
                          },
                          icon:
                              const Icon(Icons.check_circle_rounded, size: 18),
                          label: const Text('CONFIRM & CLOSE SHIFT'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

  Widget _dialogRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
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
            Text('Cashier: ${closed.cashierName}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Expected Cash:'),
              Text(formatPeso(closed.expectedCash))
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Actual Counted:'),
              Text(formatPeso(closed.actualCashCounted ?? 0))
            ]),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cash Variance:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  formatPeso(closed.cashDifference),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: closed.isShortage
                        ? Colors.red
                        : (closed.isOverage ? Colors.green : Colors.blue),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ElevatedButton.icon(
            onPressed: () async {
              final printer = context.read<PrinterProvider>();
              final success = await printer.printZReading(shift: closed);
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? "Z-Reading printed successfully! 🖨️"
                        : "Printer not connected or failed."),
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
