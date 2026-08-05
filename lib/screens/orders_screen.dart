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
              Tab(text: 'Sale History', icon: Icon(Icons.history)),
              Tab(text: 'Pre-Orders', icon: Icon(Icons.receipt_long)),
              Tab(text: 'Refund Req', icon: Icon(Icons.notifications_active)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _TransactionHistory(),
            _PreOrdersTab(),
            _RefundRequests(),
          ],
        ),
      ),
    );
  }
}

class _PreOrdersTab extends StatefulWidget {
  const _PreOrdersTab();
  @override State<_PreOrdersTab> createState() => _PreOrdersTabState();
}

class _PreOrdersTabState extends State<_PreOrdersTab> {
  OrderStatus? _filter;
  String?      _expanded;
  String       _search = '';

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.read<OrderProvider>();

    return StreamBuilder<List<PreOrder>>(
      stream: orderProvider.ordersStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snap.data ?? [];
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
            Expanded(
              child: visible.isEmpty
                ? Center(child: Text('No orders found.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final o = visible[i];
                      final isOpen = _expanded == o.id;
                      return _OrderCard(
                        order: o,
                        isOpen: isOpen,
                        onToggle: () => setState(() => _expanded = isOpen ? null : o.id),
                        onAdvance: () => orderProvider.advanceStatus(o.id),
                        onCancel: () => orderProvider.cancelOrder(o.id),
                      );
                    },
                  ),
            ),
          ],
        );
      }
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
}

class _OrderCard extends StatelessWidget {
  final PreOrder order;
  final bool isOpen;
  final VoidCallback onToggle;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;

  const _OrderCard({required this.order, required this.isOpen, required this.onToggle, required this.onAdvance, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        ListTile(
          onTap: onToggle,
          title: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${order.orderId} · ${order.items.length} items'),
          trailing: StatusBadge(order.status),
        ),
        if (isOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(children: [
              const Divider(),
              ...order.items.map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${i.qty}x ${i.name}'),
                  Text(formatPeso(i.price * i.qty)),
                ]),
              )),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(formatPeso(order.total), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                if (order.status != OrderStatus.collected && order.status != OrderStatus.cancelled)
                  Expanded(child: OutlinedButton(onPressed: onCancel, child: const Text('Cancel'))),
                if (order.status == OrderStatus.pending || order.status == OrderStatus.staging || order.status == OrderStatus.ready) ...[
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton(onPressed: onAdvance, child: const Text('Advance'))),
                ]
              ]),
            ]),
          ),
      ]),
    );
  }
}

class _TransactionHistory extends StatelessWidget {
  const _TransactionHistory();
  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final txs = inventory.transactions;
    if (txs.isEmpty) return const Center(child: Text('No transactions yet.'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: txs.length,
      itemBuilder: (_, i) => Card(
        child: ListTile(
          onTap: () => _showTxDetails(context, txs[i], inventory),
          leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(Icons.receipt, color: Theme.of(context).colorScheme.primary)),
          title: Text(formatPeso(txs[i].total), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(DateFormat('MMM dd, hh:mm a').format(txs[i].createdAt)),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  void _showTxDetails(BuildContext context, StoreTransaction tx, InventoryProvider inventory) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Transaction #${tx.id.substring(0, 8)}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date: ${DateFormat('MMMM dd, hh:mm a').format(tx.createdAt)}', style: const TextStyle(fontSize: 12)),
              if (tx.customerEmail != null) Text('Customer: ${tx.customerEmail}', style: const TextStyle(fontSize: 12)),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tx.items.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text(tx.items[i].name),
                    subtitle: Text('${tx.items[i].qty} x ${formatPeso(tx.items[i].price)}'),
                    trailing: Text(formatPeso(tx.items[i].price * tx.items[i].qty)),
                  ),
                ),
              ),
              const Divider(),
              _DetailRow('Total', formatPeso(tx.total), bold: true),
              _DetailRow('Cash', formatPeso(tx.cash)),
              _DetailRow('Change', formatPeso(tx.change)),
              if (tx.pointsRedeemed > 0) _DetailRow('Points Used', '${tx.pointsRedeemed} pts'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          TextButton(
            onPressed: () => _confirmRefund(context, tx, inventory),
            child: const Text('Issue Refund', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmRefund(BuildContext context, StoreTransaction tx, InventoryProvider inventory) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund Transaction?'),
        content: const Text('This will replenish stock and reverse loyalty points. Continue?'),
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

  Widget _DetailRow(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    ]),
  );
}

class _RefundRequests extends StatelessWidget {
  const _RefundRequests();
  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final reqs = inventory.refundRequests;
    if (reqs.isEmpty) return const Center(child: Text('No refund requests.'));
    
    final pending = reqs.where((r) => r.status == RefundStatus.pending).toList();
    final processed = reqs.where((r) => r.status != RefundStatus.pending).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (pending.isNotEmpty) ...[
          const Text('Pending Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...pending.map((r) => _RefundCard(req: r, inventory: inventory, isPending: true)),
          const SizedBox(height: 16),
        ],
        if (processed.isNotEmpty) ...[
          const Text('Past Requests', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          ...processed.map((r) => _RefundCard(req: r, inventory: inventory, isPending: false)),
        ],
      ],
    );
  }
}

class _RefundCard extends StatelessWidget {
  final RefundRequest req;
  final InventoryProvider inventory;
  final bool isPending;
  const _RefundCard({required this.req, required this.inventory, required this.isPending});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(req.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(formatPeso(req.total), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ]),
            Text('Reason: ${req.reason}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const Divider(),
            if (isPending) Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _handleRefund(context, req, inventory, false), child: const Text('Reject'))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: () => _handleRefund(context, req, inventory, true), child: const Text('Approve'))),
            ]) else Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: req.status == RefundStatus.approved ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(req.status.name.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: req.status == RefundStatus.approved ? Colors.green : Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  void _handleRefund(BuildContext context, RefundRequest req, InventoryProvider inventory, bool approve) async {
    if (approve) {
      // Show condition picker
      final condition = await showDialog<RefundCondition>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Item Condition'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, RefundCondition.damaged), child: const Text('Damaged / Waste')),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, RefundCondition.expired), child: const Text('Expired')),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, RefundCondition.restockable), child: const Text('Restockable (Return to shelf)')),
          ],
        ),
      );
      if (condition != null) {
        await inventory.approveRefundRequest(req, condition: condition);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refund approved')));
      }
    } else {
      // Show rejection reason
      final ctrl = TextEditingController();
      final res = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject Refund'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason for rejection')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
          ],
        ),
      );
      if (res == true && ctrl.text.isNotEmpty) {
        await inventory.rejectRefundRequest(req, ctrl.text.trim());
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refund rejected')));
      }
    }
  }
}
