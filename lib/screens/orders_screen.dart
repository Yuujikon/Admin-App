import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/order.dart';
import '../../models/transaction.dart';
import '../../models/refund_request.dart';
import '../../providers/order_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/printer_provider.dart';
import '../../config/theme.dart';
import '../../widgets/status_badge.dart';
import '../../utils/format.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders & History'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pre-Orders', icon: Icon(Icons.receipt_long)),
              Tab(text: 'Sale History', icon: Icon(Icons.history)),
              Tab(text: 'Refund Req', icon: Icon(Icons.notifications_active)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PreOrdersTab(),
            _TransactionHistory(),
            _RefundRequests(),
          ],
        ),
      ),
    );
  }
}

// ── Pre-Orders Tab ─────────────────────────────────────────────────────────

class _PreOrdersTab extends StatefulWidget {
  const _PreOrdersTab();
  @override State<_PreOrdersTab> createState() => _PreOrdersTabState();
}

class _PreOrdersTabState extends State<_PreOrdersTab> {
  OrderStatus? _filter;
  String?      _expanded;
  String       _search = '';
  late Stream<List<PreOrder>> _ordersStream;

  @override
  void initState() {
    super.initState();
    _ordersStream = context.read<OrderProvider>().ordersStream;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PreOrder>>(
      stream: _ordersStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders  = snap.data ?? [];
        final filteredByStatus = _filter == null
            ? orders
            : orders.where((o) => o.status == _filter).toList();
            
        final visible = filteredByStatus.where((o) {
          final query = _search.toLowerCase();
          return o.orderId.toLowerCase().contains(query) || 
                 o.customerName.toLowerCase().contains(query);
        }).toList();

        final counts = {
          for (final s in OrderStatus.values)
            s: orders.where((o) => o.status == s).length,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search orders by ID or Name…',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Text('Incoming Orders',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Theme.of(context).semantic.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(50)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, size: 8, color: Theme.of(context).semantic.success),
                      const SizedBox(width: 4),
                      Text('Live', style: TextStyle(fontSize: 11,
                          color: Theme.of(context).semantic.success, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                          label: Text('All (${orders.length})'),
                          selected: _filter == null,
                          onSelected: (_) => setState(() => _filter = null))),
                  ...OrderStatus.values.map((s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                          label: Text('${_statusLabel(s)} (${counts[s]})'),
                          selected: _filter == s,
                          onSelected: (_) => setState(() => _filter = s)))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  context.read<OrderProvider>().initialize();
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: visible.isEmpty
                    ? SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Container(
                          height: MediaQuery.of(context).size.height * 0.5,
                          alignment: Alignment.center,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('No orders${_filter != null ? ' in this category' : ''}',
                                style: const TextStyle(color: Colors.grey)),
                          ]),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final o      = visible[i];
                          final isOpen = _expanded == o.id;
                          return _OrderCard(
                            order:    o,
                            isOpen:   isOpen,
                            onToggle: () => setState(() => _expanded = isOpen ? null : o.id),
                            onAdvance: () => _confirmAction(context, 'Advance Status', 
                              'Are you sure you want to move this order to the next stage?', () async {
                              final oldStatus = o.status;
                              await context.read<OrderProvider>().advanceStatus(o.id);
                              
                              if (oldStatus == OrderStatus.ready) {
                                final printer = context.read<PrinterProvider>();
                                if (printer.connected) {
                                  printer.printReceipt(
                                    items: o.items,
                                    total: o.total,
                                    cash: o.total,
                                    change: 0,
                                    orderId: o.orderId,
                                  );
                                }
                              }
                            }),
                            onCancel: () => _confirmAction(context, 'Cancel Order', 
                              'Are you sure you want to cancel this order? This will return items to stock.', () async {
                              await context.read<OrderProvider>().cancelOrder(o.id, isAuto: false);
                            }),
                          );
                        }),
              ),
            ),
          ],
        );
      },
    );
  }

  String _statusLabel(OrderStatus s) => switch (s) {
    OrderStatus.pending          => 'Pending',
    OrderStatus.staging          => 'Packing',
    OrderStatus.ready            => 'Ready',
    OrderStatus.collected        => 'Collected',
    OrderStatus.cancelled        => 'Cancelled',
    OrderStatus.refunded        => 'Refunded',
    OrderStatus.refundRequested => 'Refund Req',
    OrderStatus.refundRejected  => 'Rejected',
  };

  Future<void> _confirmAction(BuildContext context, String title, String msg, VoidCallback onConfirm) async {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Go Back')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
  }
}

// ── Transaction History Tab ────────────────────────────────────────────────

class _TransactionHistory extends StatelessWidget {
  const _TransactionHistory();

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final txs = inventory.transactions;
    final printer = context.watch<PrinterProvider>();

    if (txs.isEmpty) {
      return const Center(child: Text('No sale transactions found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: txs.length,
      itemBuilder: (_, i) {
        final tx = txs[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text('Sale #${tx.id.length > 8 ? tx.id.substring(0, 8) : tx.id}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(DateFormat('MMM dd, yyyy • hh:mm a').format(tx.createdAt)),
            trailing: Text(formatPeso(tx.total),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...tx.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${item.qty}x ${item.name}'),
                          Text(formatPeso(item.price * item.qty)),
                        ],
                      ),
                    )),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cash Received:'),
                        Text(formatPeso(tx.cash)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Change:'),
                        Text(formatPeso(tx.change)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (printer.connected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => printer.printReceipt(
                              items: tx.items, 
                              total: tx.total, 
                              cash: tx.cash, 
                              change: tx.change
                            ), 
                            icon: const Icon(Icons.print),
                            label: const Text('REPRINT RECEIPT'),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmRefund(context, tx),
                        icon: const Icon(Icons.undo, color: Colors.red),
                        label: const Text('Process Refund',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmRefund(BuildContext context, StoreTransaction tx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Refund'),
        content: Text('Are you sure you want to refund this sale (#${tx.id.length > 8 ? tx.id.substring(0, 8) : tx.id})?\n\n'
            'Items will be returned to stock and this record will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.read<InventoryProvider>().refundTransaction(tx);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Refund processed successfully.')),
              );
            },
            child: const Text('Yes, Refund', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ── Refund Requests Tab ───────────────────────────────────────────────────

class _RefundRequests extends StatelessWidget {
  const _RefundRequests();

  @override
  Widget build(BuildContext context) {
    final requests = context.watch<InventoryProvider>().refundRequests;

    if (requests.isEmpty) {
      return const Center(child: Text('No refund requests from customers.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: requests.length,
      itemBuilder: (_, i) {
        final req = requests[i];
        final isPending = req.status == RefundStatus.pending;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: _statusIcon(req.status),
            title: Text('Request for Sale #${req.transactionId.length > 8 ? req.transactionId.substring(0, 8) : req.transactionId}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${req.customerName} • ${DateFormat('MMM dd, hh:mm a').format(req.createdAt)}'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reason:', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text(req.reason, style: const TextStyle(fontStyle: FontStyle.italic)),
                    const Divider(height: 24),
                    ...req.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${item.qty}x ${item.name}'),
                          Text(formatPeso(item.price * item.qty)),
                        ],
                      ),
                    )),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total to Refund:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(formatPeso(req.total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    if (isPending) ...[
                      const SizedBox(height: 8),
                      _RefundActions(req: req),
                    ] else ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Status: ${req.status.name.toUpperCase()}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: req.status == RefundStatus.approved ? Colors.green : Colors.red,
                              ),
                            ),
                            if (req.processedByEmail != null)
                              Text('Processed by: ${req.processedByEmail}', 
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusIcon(RefundStatus status) {
    switch (status) {
      case RefundStatus.pending:  return const Icon(Icons.hourglass_empty, color: Colors.orange);
      case RefundStatus.approved: return const Icon(Icons.check_circle, color: Colors.green);
      case RefundStatus.rejected: return const Icon(Icons.cancel, color: Colors.red);
    }
  }

  void _handleAction(BuildContext context, RefundRequest req, bool approve) {
    // Legacy method - replaced by _RefundActions widget
  }
}

// ── Shared Widgets ─────────────────────────────────────────────────────────

class _OrderCard extends StatefulWidget {
  final PreOrder order;
  final bool isOpen;
  final VoidCallback onToggle;
  final Future<void> Function() onAdvance;
  final Future<void> Function() onCancel;
  const _OrderCard({
    required this.order, required this.isOpen,
    required this.onToggle, required this.onAdvance,
    required this.onCancel,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        ListTile(
          onTap: widget.onToggle,
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              widget.order.customerName.isNotEmpty
                  ? widget.order.customerName[0].toUpperCase() : '?',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold),
            ),
          ),
          title: Row(children: [
            Expanded(child: Text(widget.order.customerName,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            StatusBadge(widget.order.status),
          ]),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.order.orderId} · ${widget.order.items.length} items · '
                  '${DateFormat('hh:mm a').format(widget.order.createdAt)}'),
              if (widget.order.expiresAt != null && widget.order.status != OrderStatus.collected && widget.order.status != OrderStatus.cancelled)
                Text('Expires: ${DateFormat('MMM d, hh:mm a').format(widget.order.expiresAt!)}', 
                    style: TextStyle(color: Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
              if (widget.order.location.isNotEmpty && !widget.order.location.contains('Main Store'))
                Row(
                  children: [
                    Icon(Icons.location_on, size: 10, color: Colors.orange.shade800),
                    const SizedBox(width: 4),
                    Text(widget.order.location, style: TextStyle(color: Colors.orange.shade900, fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
            ],
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(formatPeso(widget.order.total),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Icon(widget.isOpen ? Icons.expand_less : Icons.expand_more),
          ]),
        ),
        if (widget.isOpen) 
          _OrderDetail(
            order: widget.order, 
            loading: _loading,
            onAdvance: () async {
              setState(() => _loading = true);
              try {
                await widget.onAdvance();
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order status updated'), backgroundColor: GdcColors.sageGreen));
                }
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            }, 
            onCancel: () async {
              setState(() => _loading = true);
              try {
                await widget.onCancel();
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order cancelled'), backgroundColor: Colors.orange));
                }
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            }
          ),
      ]),
    );
  }
}

class _OrderDetail extends StatelessWidget {
  final PreOrder order;
  final bool loading;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;
  const _OrderDetail({required this.order, required this.loading, required this.onAdvance, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final nextLabel = switch (order.status) {
      OrderStatus.pending  => 'Start Packing',
      OrderStatus.staging  => 'Mark Ready',
      OrderStatus.ready    => 'Mark Collected',
      _ => null,
    };
    final canCancel = order.status != OrderStatus.collected && order.status != OrderStatus.cancelled;
    final printer = context.watch<PrinterProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(),
        ...order.items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Row(
                children: [
                  Text('${item.name} × ${item.qty}', style: const TextStyle(fontSize: 13)),
                  if (item.isPerishable)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text('PERISHABLE', style: TextStyle(fontSize: 8, color: Colors.orange.shade900, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            Text(formatPeso(item.price * item.qty), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ]),
        )),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(formatPeso(order.total),
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        ]),
        const SizedBox(height: 12),
        if (printer.connected && order.status == OrderStatus.collected)
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ElevatedButton.icon(
                onPressed: () => printer.printReceipt(
                  items: order.items, 
                  total: order.total, 
                  cash: order.total, 
                  change: 0,
                  orderId: order.orderId,
                ),
                icon: const Icon(Icons.print),
                label: const Text('PRINT RECEIPT'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.email_outlined, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(order.customerEmail, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ]),
        if (order.location.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(child: Text(order.location, style: const TextStyle(fontSize: 13))),
          ]),
        ],
        if (order.pickupTime.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.access_time, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text('Pickup at ${order.pickupTime}', style: const TextStyle(fontSize: 13)),
          ]),
        ],
        if (order.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
              child: Text('Note: ${order.notes}', style: const TextStyle(fontSize: 13))),
        ],
        if (canCancel || nextLabel != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            if (canCancel)
              Expanded(child: OutlinedButton(
                onPressed: loading ? null : onCancel,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                child: const Text('Cancel Order'),
              )),
            if (canCancel && nextLabel != null) const SizedBox(width: 8),
            if (nextLabel != null)
              Expanded(child: ElevatedButton(
                onPressed: loading ? null : onAdvance, 
                child: loading 
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(nextLabel)
              )),
          ]),
        ],
      ]),
    );
  }
}

class _RefundActions extends StatefulWidget {
  final RefundRequest req;
  const _RefundActions({required this.req});

  @override
  State<_RefundActions> createState() => _RefundActionsState();
}

class _RefundActionsState extends State<_RefundActions> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)));

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _handleAction(context, false),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _handleAction(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Approve'),
          ),
        ),
      ],
    );
  }

  void _handleAction(BuildContext context, bool approve) {
    final rejectCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${approve ? 'Approve' : 'Reject'} Refund: #${widget.req.transactionId.length > 8 ? widget.req.transactionId.substring(0, 8) : widget.req.transactionId}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customer: ${widget.req.customerEmail}'),
            Text('Total: ₱${widget.req.total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Customer Reason:', style: TextStyle(color: Colors.grey[700])),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5)),
              child: Text('"${widget.req.reason}"', style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
            if (!approve) ...[
              const SizedBox(height: 16),
              const Text('Rejection Reason:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              TextField(
                controller: rejectCtrl,
                decoration: const InputDecoration(hintText: 'e.g., No issue found, Item is used', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
            const Divider(height: 24),
            Text(approve ? 'Items to Restock:' : 'Items in request:', style: const TextStyle(fontWeight: FontWeight.bold)),
            ...widget.req.items.map((i) => Text('• ${i.name} x${i.qty}')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final provider = context.read<InventoryProvider>();
              if (approve) {
                Navigator.pop(ctx);
              } else {
                if (rejectCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide a rejection reason.')));
                  return;
                }
                Navigator.pop(ctx);
                setState(() => _loading = true);
                try {
                  await provider.rejectRefundRequest(widget.req, rejectCtrl.text.trim());
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refund Request Rejected'))
                    );
                  }
                } finally {
                  if (mounted) setState(() => _loading = false);
                }
              }
            },
            child: Text(approve ? 'Cancel' : 'Reject', style: const TextStyle(color: Colors.red)),
          ),
          if (approve)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                final provider = context.read<InventoryProvider>();
                Navigator.pop(ctx);
                setState(() => _loading = true);
                try {
                  await provider.approveRefundRequest(widget.req);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refund Approved & Items Restocked!'))
                    );
                  }
                } finally {
                  if (mounted) setState(() => _loading = false);
                }
              },
              child: const Text('Approve & Restock', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}