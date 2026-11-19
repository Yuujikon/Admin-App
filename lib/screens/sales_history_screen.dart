import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/order.dart';
import '../models/refund_request.dart';
import '../providers/inventory_provider.dart';
import '../providers/printer_provider.dart';
import '../utils/format.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/return_swap_dialog.dart';

enum RefundHistoryFilter { all, approved, rejected }

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  RefundHistoryFilter _refundFilter = RefundHistoryFilter.all;
  String _salesSearch = '';
  String _refundSearch = '';

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final txs = inventory.transactions;
    final allRefunds = inventory.refundRequests;

    // Filter processed refunds (approved or rejected, or all for history)
    final processedRefunds =
        allRefunds.where((r) => r.status != RefundStatus.pending).toList();

    final approvedCount =
        allRefunds.where((r) => r.status == RefundStatus.approved).length;
    final rejectedCount =
        allRefunds.where((r) => r.status == RefundStatus.rejected).length;

    // Search filtered transactions
    final filteredTxs = txs.where((tx) {
      final q = _salesSearch.toLowerCase().trim();
      if (q.isEmpty) return true;
      return tx.id.toLowerCase().contains(q) ||
          (tx.customerEmail != null &&
              tx.customerEmail!.toLowerCase().contains(q)) ||
          tx.paymentMethod.name.toLowerCase().contains(q);
    }).toList();

    // Filtered refund history
    final filteredRefunds = processedRefunds.where((r) {
      final matchesFilter = switch (_refundFilter) {
        RefundHistoryFilter.all => true,
        RefundHistoryFilter.approved => r.status == RefundStatus.approved,
        RefundHistoryFilter.rejected => r.status == RefundStatus.rejected,
      };
      if (!matchesFilter) return false;

      final q = _refundSearch.toLowerCase().trim();
      if (q.isEmpty) return true;
      return r.transactionId.toLowerCase().contains(q) ||
          r.customerName.toLowerCase().contains(q) ||
          r.customerEmail.toLowerCase().contains(q) ||
          r.reason.toLowerCase().contains(q);
    }).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text('Sales & Refund History'),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.receipt_long_rounded, size: 20),
                text: 'Sales History',
              ),
              Tab(
                icon: Icon(Icons.history_edu_rounded, size: 20),
                text: 'Refund History',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ── TAB 1: SALES HISTORY ──────────────────────────────────────────
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText:
                                'Search sales by receipt ID, customer...',
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            suffixIcon: _salesSearch.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () =>
                                        setState(() => _salesSearch = ''),
                                  )
                                : null,
                          ),
                          onChanged: (v) => setState(() => _salesSearch = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () =>
                            _showReceiptLookupDialog(context, txs),
                        icon: const Icon(
                            Icons.published_with_changes_rounded,
                            size: 18),
                        label: const Text('Process Return / Swap'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filteredTxs.isEmpty
                      ? Center(
                          child: Text(
                            _salesSearch.isNotEmpty
                                ? 'No transactions matching "$_salesSearch"'
                                : 'No store transactions recorded yet.',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                          child: ResponsiveCardGrid(
                            children: filteredTxs.map((tx) {
                              return Card(
                                key: ValueKey(tx.id),
                                child: ListTile(
                                  onTap: () =>
                                      _showTxDetails(context, tx, inventory),
                                  leading: CircleAvatar(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      child: Icon(Icons.receipt,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary)),
                                  title: Text(formatPeso(tx.total),
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          decoration: tx.isRefunded
                                              ? TextDecoration.lineThrough
                                              : null)),
                                  subtitle: Text(DateFormat('MMM dd, hh:mm a')
                                      .format(tx.createdAt)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (tx.isRefunded)
                                        Container(
                                          margin:
                                              const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(4)),
                                          child: const Text('REFUNDED',
                                              style: TextStyle(
                                                  fontSize: 8,
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                ),
              ],
            ),

            // ── TAB 2: REFUND HISTORY ─────────────────────────────────────────
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search refund records...',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          suffixIcon: _refundSearch.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () =>
                                      setState(() => _refundSearch = ''),
                                )
                              : null,
                        ),
                        onChanged: (v) => setState(() => _refundSearch = v),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip(
                                'All Processed (${processedRefunds.length})',
                                RefundHistoryFilter.all),
                            const SizedBox(width: 8),
                            _filterChip('Approved ($approvedCount)',
                                RefundHistoryFilter.approved),
                            const SizedBox(width: 8),
                            _filterChip('Rejected ($rejectedCount)',
                                RefundHistoryFilter.rejected),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filteredRefunds.isEmpty
                      ? Center(
                          child: Text(
                            'No processed refund records found.',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                          child: ResponsiveCardGrid(
                            children: filteredRefunds.map((req) {
                              return _RefundHistoryCard(req: req);
                            }).toList(),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, RefundHistoryFilter filter) {
    final selected = _refundFilter == filter;
    return FilterChip(
      label: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      selected: selected,
      onSelected: (_) => setState(() => _refundFilter = filter),
    );
  }

  void _showTxDetails(
      BuildContext context, StoreTransaction tx, InventoryProvider inventory) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
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
                          Text('GDC SARI-SARI STORE',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1)),
                          Text('Transaction Receipt',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: tx.isRefunded
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(tx.isRefunded ? 'REFUNDED' : 'PAID',
                            style: TextStyle(
                                fontSize: 10,
                                color:
                                    tx.isRefunded ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _DashedDivider(),
                  const SizedBox(height: 16),
                  _infoRow(
                      Icons.calendar_today,
                      'Date',
                      DateFormat('MMM dd, yyyy • hh:mm a')
                          .format(tx.createdAt)),
                  _infoRow(Icons.receipt_outlined, 'Receipt #',
                      tx.id.toUpperCase().substring(0, 8)),
                  if (tx.customerEmail != null)
                    _infoRow(
                        Icons.person_outline, 'Customer', tx.customerEmail!),
                  _infoRow(
                      Icons.shopping_bag_outlined,
                      'Order Type',
                      tx.type == TransactionType.pickup
                          ? 'Pickup'
                          : 'In-store'),
                  _infoRow(Icons.payments_outlined, 'Payment Method',
                      tx.paymentMethod.name.toUpperCase()),
                  const SizedBox(height: 16),
                  const _DashedDivider(),
                  const SizedBox(height: 16),
                  const Text('ITEMS',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.grey,
                          letterSpacing: 1)),
                  const SizedBox(height: 12),
                  ..._buildItemizedReceiptRows(tx.items, context),
                  const SizedBox(height: 16),
                  const _DashedDivider(),
                  const SizedBox(height: 16),
                  _priceRow(
                      'Total Quantity',
                      tx.items
                          .fold(0, (sum, item) => sum + item.qty)
                          .toString()),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL AMOUNT',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w900)),
                        Text(formatPeso(tx.total),
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).colorScheme.primary)),
                      ]),
                  const SizedBox(height: 8),
                  _priceRow('Cash Tendered', formatPeso(tx.cash)),
                  _priceRow('Change Due', formatPeso(tx.change),
                      color: Colors.green),
                  const SizedBox(height: 16),
                  const _DashedDivider(),
                  const SizedBox(height: 24),
                  const Center(
                    child: Text('THANK YOU FOR SHOPPING!',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text('Ref: ${tx.id}',
                        style: const TextStyle(
                            fontSize: 7, color: Colors.black12)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  if (!tx.isRefunded) ...[
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ReturnSwapDialog.show(context, tx);
                      },
                      icon: const Icon(Icons.published_with_changes_rounded),
                      label: const Text('PROCESS RETURN / SWAP'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton.icon(
                    onPressed: tx.isRefunded
                        ? null
                        : () async {
                            final success = await context
                                .read<PrinterProvider>()
                                .printReceipt(
                                  items: tx.items,
                                  total: tx.total,
                                  cash: tx.cash,
                                  change: tx.change,
                                  orderId: tx.id,
                                  orderType: tx.type == TransactionType.pickup
                                      ? 'Pickup'
                                      : 'In-store',
                                );
                            if (!success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        "Failed to print receipt. Check printer.")),
                              );
                            }
                          },
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('PRINT RECEIPT'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
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

  void _confirmRefund(
      BuildContext context, StoreTransaction tx, InventoryProvider inventory) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund Transaction?'),
        content: const Text(
            'This will replenish stock and reverse the payment. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await inventory.refundTransaction(tx);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Refund processed successfully')));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Confirm Refund'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String val) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                val,
                textAlign: TextAlign.end,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  Widget _priceRow(String label, String val, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            Text(val,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      );

  List<Widget> _buildItemizedReceiptRows(
      List<CartItem> items, BuildContext context) {
    final List<Widget> widgets = [];
    final theme = Theme.of(context);

    for (final i in items) {
      final int retainedQty = i.qty - i.returnedQty;
      final int refundedQty = i.returnedQty;

      // 1. Non-refunded / retained units line item
      if (retainedQty > 0) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${retainedQty}x',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      if (i.variantName != null && i.variantName!.isNotEmpty)
                        Text('Variant: ${i.variantName}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.teal,
                                fontWeight: FontWeight.w600)),
                      Text(
                        'Barcode: ${i.barcode.isNotEmpty ? i.barcode : "N/A"} • ${formatPeso(i.price)} each',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatPeso(i.price * retainedQty),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      }

      // 2. Refunded units line item (separated into a distinct item row as "Item Name (Refunded)")
      if (refundedQty > 0) {
        widgets.add(
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${refundedQty}x',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.red.shade900),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${i.name} (Refunded)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'REFUNDED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (i.variantName != null && i.variantName!.isNotEmpty)
                        Text('Variant: ${i.variantName}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w600)),
                      Text(
                        'Barcode: ${i.barcode.isNotEmpty ? i.barcode : "N/A"} • ${formatPeso(i.price)} each',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.red.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatPeso(i.price * refundedQty),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.red.shade900,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return widgets;
  }

  void _showReceiptLookupDialog(
      BuildContext context, List<StoreTransaction> txs) {
    final searchCtrl = TextEditingController();
    String query = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cleanQuery = query.toLowerCase().trim();
          List<StoreTransaction> matchedTxs = [];
          if (cleanQuery.isNotEmpty) {
            matchedTxs = txs.where((tx) {
              return tx.id.toLowerCase().contains(cleanQuery) ||
                  (tx.customerEmail != null &&
                      tx.customerEmail!.toLowerCase().contains(cleanQuery));
            }).toList();
          }

          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 580,
              constraints: const BoxConstraints(maxHeight: 650),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.published_with_changes_rounded,
                              color: Colors.teal, size: 24),
                          SizedBox(width: 10),
                          Text(
                            'Process Return / Swap (Receipt Lookup)',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Receipt ID / Barcode Search Input
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText:
                          'Enter or scan Receipt ID (e.g. TX-1024 or scan thermal QR)...',
                      prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                searchCtrl.clear();
                                setDialogState(() => query = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setDialogState(() => query = val),
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: cleanQuery.isEmpty
                        ? SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'RECENT TRANSACTIONS AVAILABLE FOR RETURN:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.grey,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ...txs.take(5).map((tx) => _buildTxLookupCard(
                                    context, tx, ctx)),
                              ],
                            ),
                          )
                        : matchedTxs.isEmpty
                            ? Center(
                                child: Text(
                                  'No receipt or transaction found matching "$query"',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  children: matchedTxs
                                      .map((tx) => _buildTxLookupCard(
                                          context, tx, ctx))
                                      .toList(),
                                ),
                              ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTxLookupCard(
      BuildContext context, StoreTransaction tx, BuildContext dialogCtx) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(tx.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Receipt Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receipt #${tx.id.substring(0, tx.id.length > 12 ? 12 : tx.id.length).toUpperCase()}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      dateStr,
                      style: TextStyle(
                          fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tx.isRefunded
                        ? Colors.red.shade100
                        : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tx.isRefunded ? 'FULLY REFUNDED' : 'PAID',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: tx.isRefunded ? Colors.red : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Itemized Products Breakdown Table
            const Text(
              'PURCHASED PRODUCTS & RETURN STATUS:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.grey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),

            ..._buildItemizedReceiptRows(tx.items, context),

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Amount: ${formatPeso(tx.total)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (!tx.isRefunded)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      ReturnSwapDialog.show(context, tx);
                    },
                    icon: const Icon(Icons.published_with_changes_rounded,
                        size: 16),
                    label: const Text('Itemized Return / Swap'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── REFUND HISTORY CARD ──────────────────────────────────────────────────────

class _RefundHistoryCard extends StatelessWidget {
  final RefundRequest req;

  const _RefundHistoryCard({required this.req});

  void _showImageLightbox(BuildContext context, String photoBase64) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child:
                  Image.memory(base64Decode(photoBase64), fit: BoxFit.contain),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(req.createdAt);
    final isApproved = req.status == RefundStatus.approved;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (isApproved ? Colors.green : Colors.red)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isApproved ? Colors.green : Colors.red,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                req.customerName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            Text(
              formatPeso(req.total),
              style: TextStyle(
                color: isApproved ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text('Order #${req.transactionId}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isApproved ? Colors.green : Colors.red)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: (isApproved ? Colors.green : Colors.red)
                            .withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    isApproved
                        ? 'APPROVED${req.condition != null ? " (${req.condition!.name.toUpperCase()})" : ""}'
                        : 'REJECTED',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isApproved ? Colors.green : Colors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(dateStr,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Text('Refund Items:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                ...req.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text('${item.qty}x',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(item.name,
                                  style: const TextStyle(fontSize: 12))),
                          Text(formatPeso(item.price * item.qty),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
                if (req.reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Customer Reason: ${req.reason}',
                      style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
                if (req.photoBase64 != null && req.photoBase64!.isNotEmpty) ...[
                  const Divider(),
                  const Text('Photo Proof:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showImageLightbox(context, req.photoBase64!),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.memory(base64Decode(req.photoBase64!),
                              fit: BoxFit.cover, width: 80, height: 80),
                          Container(
                            color: Colors.black.withValues(alpha: 0.2),
                            child: const Icon(Icons.zoom_in_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
                  const Divider(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (isApproved ? Colors.green : Colors.red)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (isApproved ? Colors.green : Colors.red)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isApproved
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                              size: 16,
                              color: isApproved ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'STORE RESPONSE:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: isApproved
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          req.adminNotes!,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        30,
        (_) => Expanded(
          child: Container(
            height: 1,
            color: Colors.grey.shade300,
            margin: const EdgeInsets.symmetric(horizontal: 2),
          ),
        ),
      ),
    );
  }
}
