import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/order.dart';
import '../providers/order_provider.dart';
import '../providers/printer_provider.dart';
import '../services/notification_service.dart';
import '../widgets/status_badge.dart';
import '../config/theme.dart';
import '../utils/format.dart';

class PreOrdersScreen extends StatefulWidget {
  const PreOrdersScreen({super.key});

  @override
  State<PreOrdersScreen> createState() => _PreOrdersScreenState();
}

class _PreOrdersScreenState extends State<PreOrdersScreen> {
  OrderStatus? _filter;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final orders = orderProvider.orders;

    if (orderProvider.isLoading && orders.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openQRScanner(context),
        child: const Icon(Icons.qr_code_scanner),
      ),
      appBar: AppBar(
        title: const Text('Customer Pre-Orders'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                    FilterChip(
                      label: const Text('All'),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                    ...OrderStatus.values.map((s) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text('${s.name.toUpperCase()} (${counts[s]})'),
                        selected: _filter == s,
                        onSelected: (_) => setState(() => _filter = s),
                      ),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: visible.isEmpty 
        ? const Center(child: Text('No orders found.'))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: visible.length,
            itemBuilder: (ctx, i) => _OrderCard(
              order: visible[i],
              onTap: () => _showOrderDetails(context, visible[i]),
            ),
          ),
    );
  }

  void _showOrderDetails(BuildContext context, PreOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OrderDetailsSheet(
        order: order, 
        onCancel: (ctx, id) => _handleCancel(ctx, id),
      ),
    );
  }

  void _handleCancel(BuildContext context, String orderId) async {
    final ctrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Reason for cancellation'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('BACK')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CANCEL', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (res == true && context.mounted) {
      await context.read<OrderProvider>().cancelOrder(orderId, reason: ctrl.text.trim());
      if (context.mounted) Navigator.pop(context);
    }
  }

  void _openQRScanner(BuildContext context) async {
    final orderId = await showDialog<String>(
      context: context,
      builder: (ctx) => const _PickupScannerDialog(),
    );

    if (orderId != null && context.mounted) {
      final orderProvider = context.read<OrderProvider>();
      try {
        final order = orderProvider.orders.firstWhere((o) => o.orderId == orderId || o.id == orderId);
        
        // Automatically complete the pickup
        await orderProvider.completePickup(order.id);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order ${order.orderId} marked as COLLECTED ✅'),
              backgroundColor: Colors.green,
            )
          );
          
          // Still open the sheet so they can see the details of what they just collected
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => _OrderDetailsSheet(
              order: orderProvider.orders.firstWhere((o) => o.id == order.id),
              onCancel: (ctx, id) => _handleCancel(ctx, id),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order $orderId not found.'))
          );
        }
      }
    }
  }
}

class _OrderCard extends StatelessWidget {
  final PreOrder order;
  final VoidCallback onTap;
  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        title: Row(
          children: [
            Expanded(child: Text(order.orderId, style: const TextStyle(fontWeight: FontWeight.bold))),
            StatusBadge(order.status),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(order.customerName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('${order.items.length} items • ${formatPeso(order.total)}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _OrderDetailsSheet extends StatelessWidget {
  final PreOrder order;
  final Function(BuildContext, String) onCancel;

  const _OrderDetailsSheet({required this.order, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          _buildHandle(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
              children: [
                _buildHeader(context),
                const SizedBox(height: 24),
                _OrderTimeline(order: order),
                const SizedBox(height: 32),
                _buildCustomerInfo(context),
                const SizedBox(height: 32),
                _buildItemsList(context),
                const SizedBox(height: 32),
                _buildPriceSummary(context),
                if (order.notes.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildNotes(context),
                ],
                if (order.status == OrderStatus.cancelled && order.rejectionReason != null) ...[
                  const SizedBox(height: 32),
                  _buildCancellationReason(context),
                ],
              ],
            ),
          ),
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      width: 40, height: 4,
      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.orderId, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                Text(DateFormat('MMMM dd, yyyy • hh:mm a').format(order.createdAt), 
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
              ],
            ),
            StatusBadge(order.status),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomerInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CUSTOMER INFO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
        const SizedBox(height: 12),
        _infoRow(Icons.person_outline, 'Name', order.customerName),
        _infoRow(Icons.email_outlined, 'Email', order.customerEmail),
        if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
          _infoRow(
            Icons.phone_outlined, 
            'Call Customer', 
            order.customerPhone!, 
            onTap: () => launchUrl(Uri.parse('tel:${order.customerPhone}')),
          ),
          _infoRow(
            Icons.message_outlined, 
            'Send Direct SMS', 
            order.customerPhone!, 
            onTap: () async {
              final msg = 'Hello ${order.customerName}, regarding your GDC Store order ${order.orderId}: status is ${order.status.name.toUpperCase()}.';
              await NotificationService.showSmsNotificationPopUp(
                title: '💬 SMS to ${order.customerPhone}',
                body: msg,
              );
              try {
                final uri = Uri.parse('sms:${order.customerPhone}?body=${Uri.encodeComponent(msg)}');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              } catch (_) {}
            },
          ),
        ],
        _infoRow(Icons.location_on_outlined, 'Location', order.location),
        _infoRow(Icons.access_time_outlined, 'Pickup Slot', order.pickupTime),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 18, color: onTap != null ? Colors.blue : Colors.grey),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                Text(value, style: TextStyle(
                  fontSize: 14, 
                  fontWeight: FontWeight.w600,
                  color: onTap != null ? Colors.blue : null,
                  decoration: onTap != null ? TextDecoration.underline : null,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ORDER ITEMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
        const SizedBox(height: 12),
        ...order.items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text('${item.qty}x', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (item.notes != null && item.notes!.isNotEmpty)
                      Text('Note: ${item.notes}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
                    Text(formatPeso(item.price), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Text(formatPeso(item.price * item.qty), style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildPriceSummary(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _priceRow('Total Quantity', order.items.fold(0, (sum, item) => sum + item.qty).toString()),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              Text(formatPeso(order.total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Theme.of(context).colorScheme.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildNotes(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('NOTES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade200)),
          child: Text(order.notes, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
        ),
      ],
    );
  }

  Widget _buildCancellationReason(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CANCELLATION REASON', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.red, letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
          child: Text(order.rejectionReason ?? 'No reason provided', style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final isProcessing = orderProvider.isOrderProcessing(order.id);
    final canAdvance = order.status == OrderStatus.pending || order.status == OrderStatus.staging || order.status == OrderStatus.ready;
    final canCancel = order.status == OrderStatus.pending;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: isProcessing ? null : () async {
              final success = await context.read<PrinterProvider>().printReceipt(
                items: order.items, 
                total: order.total, 
                cash: order.total, // Assume exact cash for pre-orders for now
                change: 0,
                orderId: order.orderId,
                customerName: order.customerName,
                orderType: "Pickup",
              );
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Failed to print ticket. Check printer.")),
                );
              }
            },
            icon: const Icon(Icons.print_rounded),
            label: const Text('PRINT ORDER TICKET'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              backgroundColor: Colors.blueGrey.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (canCancel)
                Expanded(
                  child: OutlinedButton(
                    onPressed: isProcessing ? null : () => onCancel(context, order.id),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('CANCEL ORDER', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              if (canCancel && canAdvance) const SizedBox(width: 12),
              if (canAdvance)
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () async {
                      await context.read<OrderProvider>().advanceStatus(order.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: isProcessing 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_advanceLabel(order.status), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _advanceLabel(OrderStatus s) => switch (s) {
    OrderStatus.pending => 'START PACKING',
    OrderStatus.staging => 'MARK AS READY',
    OrderStatus.ready   => 'MARK AS COLLECTED',
    _ => 'ADVANCE',
  };
}

class _PickupScannerDialog extends StatelessWidget {
  const _PickupScannerDialog();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Pickup QR')),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final code = barcodes.first.rawValue;
            if (code != null) {
              Navigator.pop(context, code);
            }
          }
        },
      ),
    );
  }
}

class _OrderTimeline extends StatelessWidget {
  final PreOrder order;
  const _OrderTimeline({required this.order});

  @override
  Widget build(BuildContext context) {
    final statuses = [OrderStatus.pending, OrderStatus.staging, OrderStatus.ready, OrderStatus.collected];
    final semantic = Theme.of(context).semantic;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: statuses.map((s) {
        final isDone = _isStatusReached(order.status, s);
        final timestamp = order.statusTimeline[s.name];
        
        return Expanded(
          child: Column(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? semantic.success : Colors.grey.shade200,
                ),
                child: isDone ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
              ),
              const SizedBox(height: 8),
              Text(s.name.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isDone ? semantic.success : Colors.grey)),
              if (timestamp != null)
                Text(DateFormat('hh:mm a').format(timestamp), style: const TextStyle(fontSize: 8, color: Colors.grey)),
            ],
          ),
        );
      }).toList(),
    );
  }

  bool _isStatusReached(OrderStatus current, OrderStatus target) {
    final order = [OrderStatus.pending, OrderStatus.staging, OrderStatus.ready, OrderStatus.collected];
    return order.indexOf(current) >= order.indexOf(target);
  }
}
