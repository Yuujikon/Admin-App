import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/refund_request.dart';
import '../providers/inventory_provider.dart';
import '../providers/printer_provider.dart';
import '../utils/format.dart';
import '../widgets/responsive_layout.dart';

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
    final processedRefunds = allRefunds
        .where((r) => r.status != RefundStatus.pending)
        .toList();

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
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search sales by receipt ID, customer...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
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
                  ...tx.items.map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text('${i.qty}x',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(i.name,
                                    style: const TextStyle(fontSize: 14))),
                            Text(formatPeso(i.price * i.qty),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )),
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
            const Spacer(),
            Text(val,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
      );
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
            isApproved
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
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
            Row(
              children: [
                Text('Order #${req.transactionId}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                const SizedBox(width: 8),
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
