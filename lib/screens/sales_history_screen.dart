import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../providers/inventory_provider.dart';
import '../providers/printer_provider.dart';
import '../utils/format.dart';

class SalesHistoryScreen extends StatelessWidget {
  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final txs = inventory.transactions;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Store Sales History')),
      body: txs.isEmpty 
        ? const Center(child: Text('No transactions yet.'))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: txs.length,
            itemBuilder: (_, i) => Card(
              child: ListTile(
                onTap: () => _showTxDetails(context, txs[i], inventory),
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer, 
                  child: Icon(Icons.receipt, color: Theme.of(context).colorScheme.primary)
                ),
                title: Text(formatPeso(txs[i].total), 
                  style: TextStyle(fontWeight: FontWeight.bold, decoration: txs[i].isRefunded ? TextDecoration.lineThrough : null)),
                subtitle: Text(DateFormat('MMM dd, hh:mm a').format(txs[i].createdAt)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (txs[i].isRefunded)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                        child: const Text('REFUNDED', style: TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold)),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _showTxDetails(BuildContext context, StoreTransaction tx, InventoryProvider inventory) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GDC SARI-SARI STORE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          Text('Transaction Receipt', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: tx.isRefunded ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                        child: Text(tx.isRefunded ? 'REFUNDED' : 'PAID', 
                          style: TextStyle(fontSize: 10, color: tx.isRefunded ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _DashedDivider(),
                  const SizedBox(height: 16),
                  _infoRow(Icons.calendar_today, 'Date', DateFormat('MMM dd, yyyy • hh:mm a').format(tx.createdAt)),
                  _infoRow(Icons.receipt_outlined, 'Receipt #', tx.id.toUpperCase().substring(0, 8)),
                  if (tx.customerEmail != null) _infoRow(Icons.person_outline, 'Customer', tx.customerEmail!),
                  _infoRow(Icons.shopping_bag_outlined, 'Order Type', tx.type == TransactionType.pickup ? 'Pickup' : 'In-store'),
                  _infoRow(Icons.payments_outlined, 'Payment Method', tx.paymentMethod.name.toUpperCase()),
                  const SizedBox(height: 16),
                  const _DashedDivider(),
                  const SizedBox(height: 16),
                  const Text('ITEMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  ...tx.items.map((i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text('${i.qty}x', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(i.name, style: const TextStyle(fontSize: 14))),
                        Text(formatPeso(i.price * i.qty), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),
                  const _DashedDivider(),
                  const SizedBox(height: 16),
                  _priceRow('Total Quantity', tx.items.fold(0, (sum, item) => sum + item.qty).toString()),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('TOTAL AMOUNT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    Text(formatPeso(tx.total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                  ]),
                  const SizedBox(height: 8),
                  _priceRow('Cash Tendered', formatPeso(tx.cash)),
                  _priceRow('Change Due', formatPeso(tx.change), color: Colors.green),
                  const SizedBox(height: 16),
                  const _DashedDivider(),
                  const SizedBox(height: 24),
                  const Center(
                    child: Text('THANK YOU FOR SHOPPING!', 
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text('Ref: ${tx.id}', style: const TextStyle(fontSize: 7, color: Colors.black12)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: tx.isRefunded ? null : () async {
                      final success = await context.read<PrinterProvider>().printReceipt(
                        items: tx.items, 
                        total: tx.total, 
                        cash: tx.cash, 
                        change: tx.change,
                        orderId: tx.id,
                        orderType: tx.type == TransactionType.pickup ? 'Pickup' : 'In-store',
                      );
                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Failed to print receipt. Check printer.")),
                        );
                      }
                    },
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('PRINT RECEIPT'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!tx.isRefunded)
                    OutlinedButton.icon(
                      onPressed: () => _confirmRefund(context, tx, inventory),
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('ISSUE REFUND'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRefund(BuildContext context, StoreTransaction tx, InventoryProvider inventory) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund Transaction?'),
        content: const Text('This will replenish stock and reverse the payment. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await inventory.refundTransaction(tx);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refund processed successfully')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Confirm Refund'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _priceRow(String label, String value, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 14, color: bold ? Colors.black : Colors.grey, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: color)),
    ]),
  );
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.grey)),
            );
          }),
        );
      },
    );
  }
}
