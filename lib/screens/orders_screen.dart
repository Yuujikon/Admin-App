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
    final txs = context.watch<InventoryProvider>().transactions;
    if (txs.isEmpty) return const Center(child: Text('No transactions yet.'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: txs.length,
      itemBuilder: (_, i) => Card(
        child: ListTile(
          title: Text(formatPeso(txs[i].total), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(DateFormat('MMM dd, hh:mm a').format(txs[i].createdAt)),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

class _RefundRequests extends StatelessWidget {
  const _RefundRequests();
  @override
  Widget build(BuildContext context) {
    final reqs = context.watch<InventoryProvider>().refundRequests;
    if (reqs.isEmpty) return const Center(child: Text('No refund requests.'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: reqs.length,
      itemBuilder: (_, i) => Card(
        child: ListTile(
          title: Text(reqs[i].customerName),
          subtitle: Text(reqs[i].reason),
          trailing: Text(formatPeso(reqs[i].total), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
