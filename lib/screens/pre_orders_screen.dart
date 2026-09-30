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
import '../utils/barcode_routing.dart';
import '../widgets/pos_checkout_modal.dart';
import '../widgets/order_qr_scanner.dart';

class PreOrdersScreen extends StatefulWidget {
  const PreOrdersScreen({super.key});

  @override
  State<PreOrdersScreen> createState() => _PreOrdersScreenState();
}

enum PreOrderCategoryTab { active, finished, cancelled, all }

class _PreOrdersScreenState extends State<PreOrdersScreen> {
  PreOrderCategoryTab _categoryTab = PreOrderCategoryTab.active;
  OrderStatus? _filter;
  String _search = '';
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }
  
  // ── Bulk Selection State ──────────────────────────────────────────────────
  bool _isBulkMode = false;
  final Set<String> _selectedOrderIds = {};
  bool _isBulkProcessing = false;

  void _toggleBulkMode() {
    setState(() {
      _isBulkMode = !_isBulkMode;
      if (!_isBulkMode) {
        _selectedOrderIds.clear();
      }
    });
  }

  void _toggleSelectOrder(String id) {
    setState(() {
      if (_selectedOrderIds.contains(id)) {
        _selectedOrderIds.remove(id);
        if (_selectedOrderIds.isEmpty && _isBulkMode) {
          // Keep bulk mode on so user can keep selecting
        }
      } else {
        _selectedOrderIds.add(id);
      }
    });
  }

  void _selectAll(List<PreOrder> orders) {
    setState(() {
      _selectedOrderIds.addAll(orders.map((o) => o.id));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedOrderIds.clear();
    });
  }

  void _selectByStatus(List<PreOrder> orders, OrderStatus status) {
    setState(() {
      final matching = orders.where((o) => o.status == status).map((o) => o.id);
      _selectedOrderIds.addAll(matching);
    });
  }

  List<OrderStatus> _getAvailableSubStatuses() {
    return switch (_categoryTab) {
      PreOrderCategoryTab.active => [OrderStatus.pending, OrderStatus.staging, OrderStatus.ready],
      PreOrderCategoryTab.finished => [OrderStatus.collected],
      PreOrderCategoryTab.cancelled => [OrderStatus.cancelled, OrderStatus.refunded, OrderStatus.refundRequested, OrderStatus.refundRejected],
      PreOrderCategoryTab.all => OrderStatus.values,
    };
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final orders = orderProvider.orders;

    if (orderProvider.isLoading && orders.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final activeOrders = orders.where((o) =>
        o.status == OrderStatus.pending ||
        o.status == OrderStatus.staging ||
        o.status == OrderStatus.ready).toList();

    final finishedOrders = orders.where((o) =>
        o.status == OrderStatus.collected).toList();

    final cancelledOrders = orders.where((o) =>
        o.status == OrderStatus.cancelled ||
        o.status == OrderStatus.refunded ||
        o.status == OrderStatus.refundRequested ||
        o.status == OrderStatus.refundRejected).toList();

    final filteredByCategory = switch (_categoryTab) {
      PreOrderCategoryTab.active => activeOrders,
      PreOrderCategoryTab.finished => finishedOrders,
      PreOrderCategoryTab.cancelled => cancelledOrders,
      PreOrderCategoryTab.all => orders,
    };

    final filteredByStatus = _filter == null
        ? filteredByCategory
        : filteredByCategory.where((o) => o.status == _filter).toList();

    final visible = filteredByStatus.where((o) {
      final query = _search.toLowerCase();
      return o.orderId.toLowerCase().contains(query) || 
             o.customerName.toLowerCase().contains(query) ||
             o.customerEmail.toLowerCase().contains(query);
    }).toList();

    final counts = {
      for (final s in OrderStatus.values)
        s: orders.where((o) => o.status == s).length,
    };

    return BarcodeInterceptor(
      barcodeFocus: _searchFocus,
      onBarcodeDetected: (code) => _processScannedCode(context, code),
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton: _isBulkMode ? null : FloatingActionButton(
        onPressed: () => _openQRScanner(context),
        child: const Icon(Icons.qr_code_scanner),
      ),
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Expanded(
              child: Text(
                _isBulkMode ? '${_selectedOrderIds.length} Selected' : 'Pre-Orders',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'LIVE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_isBulkMode) ...[
            if (_selectedOrderIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: FilledButton.icon(
                  onPressed: _isBulkProcessing ? null : _handleBulkAdvance,
                  icon: const Icon(Icons.fast_forward_rounded, size: 14),
                  label: Text('ADVANCE (${_selectedOrderIds.length})'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            TextButton(
              onPressed: () {
                if (_selectedOrderIds.length == visible.length) {
                  _deselectAll();
                } else {
                  _selectAll(visible);
                }
              },
              child: Text(
                _selectedOrderIds.length == visible.length ? 'DESELECT' : 'SELECT ALL',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Exit Multi-Select',
              onPressed: _toggleBulkMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist_rtl_rounded),
              tooltip: 'Multi-Select Mode',
              onPressed: _toggleBulkMode,
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isBulkMode ? 180 : 150),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Search orders by ID, Name, Email…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<PreOrderCategoryTab>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: PreOrderCategoryTab.active,
                        label: Text('Active (${activeOrders.length})'),
                        icon: const Icon(Icons.pending_actions_rounded, size: 15),
                      ),
                      ButtonSegment(
                        value: PreOrderCategoryTab.finished,
                        label: Text('Finished (${finishedOrders.length})'),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
                      ),
                      ButtonSegment(
                        value: PreOrderCategoryTab.cancelled,
                        label: Text('Cancelled (${cancelledOrders.length})'),
                        icon: const Icon(Icons.cancel_outlined, size: 15),
                      ),
                      ButtonSegment(
                        value: PreOrderCategoryTab.all,
                        label: Text('All (${orders.length})'),
                        icon: const Icon(Icons.apps_rounded, size: 15),
                      ),
                    ],
                    selected: {_categoryTab},
                    onSelectionChanged: (newSelection) {
                      setState(() {
                        _categoryTab = newSelection.first;
                        _filter = null;
                      });
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    FilterChip(
                      label: const Text('All Sub-Statuses'),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                      visualDensity: VisualDensity.compact,
                    ),
                    ..._getAvailableSubStatuses().map((s) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FilterChip(
                        label: Text('${_formatStatusName(s)} (${counts[s] ?? 0})'),
                        selected: _filter == s,
                        onSelected: (_) => setState(() => _filter = s),
                        visualDensity: VisualDensity.compact,
                      ),
                    )),
                  ],
                ),
              ),
              if (_isBulkMode) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Quick Select: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ActionChip(
                          label: Text('Pending (${counts[OrderStatus.pending]})'),
                          onPressed: () => _selectByStatus(orders, OrderStatus.pending),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 4),
                        ActionChip(
                          label: Text('Packing (${counts[OrderStatus.staging]})'),
                          onPressed: () => _selectByStatus(orders, OrderStatus.staging),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 4),
                        ActionChip(
                          label: Text('Ready (${counts[OrderStatus.ready]})'),
                          onPressed: () => _selectByStatus(orders, OrderStatus.ready),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 4),
                        ActionChip(
                          label: const Text('Deselect All'),
                          onPressed: _deselectAll,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          visible.isEmpty 
            ? RefreshIndicator(
                onRefresh: () async {
                  context.read<OrderProvider>().initialize();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Container(
                    height: MediaQuery.of(context).size.height * 0.5,
                    alignment: Alignment.center,
                    child: const Text('No orders found.'),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  context.read<OrderProvider>().initialize();
                },
                child: ListView.builder(
                  cacheExtent: 1000,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(12, 12, 12, _isBulkMode && _selectedOrderIds.isNotEmpty ? 120 : 20),
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) {
                    final order = visible[i];
                    final isSelected = _selectedOrderIds.contains(order.id);

                    return _OrderCard(
                      key: ValueKey(order.id),
                      order: order,
                      isBulkMode: _isBulkMode,
                      isSelected: isSelected,
                      onSelectToggle: () => _toggleSelectOrder(order.id),
                      onLongPress: () {
                        if (!_isBulkMode) {
                          setState(() {
                            _isBulkMode = true;
                            _selectedOrderIds.add(order.id);
                          });
                        }
                      },
                      onTap: () {
                        if (_isBulkMode) {
                          _toggleSelectOrder(order.id);
                        } else {
                          _showOrderDetails(context, order);
                        }
                      },
                    );
                  },
                ),
              ),
          if (_isBulkMode && _selectedOrderIds.isNotEmpty)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _BulkActionBar(
                selectedCount: _selectedOrderIds.length,
                isProcessing: _isBulkProcessing,
                onBulkPack: _handleBulkAdvance,
                onBulkCollect: _handleBulkCollect,
                onBulkCancel: _handleBulkCancel,
                onBulkPrint: _handleBulkPrint,
              ),
            ),
        ],
      ),
    ),
  );
  }

  // ── Bulk Actions Handlers ──────────────────────────────────────────────────

  Future<void> _handleBulkAdvance() async {
    final orderProvider = context.read<OrderProvider>();
    final selectedIds = _selectedOrderIds.toList();
    if (selectedIds.isEmpty) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Advance Orders'),
        content: Text('Advance status for ${selectedIds.length} selected orders?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('ADVANCE ALL'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isBulkProcessing = true);
    final count = await orderProvider.bulkAdvanceStatus(selectedIds);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isBulkProcessing = false;
      _selectedOrderIds.clear();
      _isBulkMode = false;
    });

    if (count > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('Successfully advanced $count of ${selectedIds.length} orders! ✅'), backgroundColor: Colors.green),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('No selected orders could be advanced.'), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _handleBulkCollect() async {
    final orderProvider = context.read<OrderProvider>();
    final selectedIds = _selectedOrderIds.toList();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Complete / Collect Pickup'),
        content: Text('Mark ${selectedIds.length} orders as COLLECTED and generate transactions?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('COLLECT ALL'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isBulkProcessing = true);
    final count = await orderProvider.bulkCompletePickup(selectedIds);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isBulkProcessing = false;
      _selectedOrderIds.clear();
      _isBulkMode = false;
    });

    messenger.showSnackBar(
      SnackBar(content: Text('Successfully collected $count orders! 🛍️'), backgroundColor: Colors.green),
    );
  }

  Future<void> _handleBulkCancel() async {
    final orderProvider = context.read<OrderProvider>();
    final selectedIds = _selectedOrderIds.toList();
    final reasonCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Cancel Orders'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Are you sure you want to cancel ${selectedIds.length} orders? Stock will be replenished.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Cancellation reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('BACK')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CANCEL ORDERS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isBulkProcessing = true);
    final count = await orderProvider.bulkCancelOrders(selectedIds, reason: reasonCtrl.text.trim());
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isBulkProcessing = false;
      _selectedOrderIds.clear();
      _isBulkMode = false;
    });

    messenger.showSnackBar(
      SnackBar(content: Text('Cancelled $count orders.'), backgroundColor: Colors.red),
    );
  }

  Future<void> _handleBulkPrint() async {
    final orderProvider = context.read<OrderProvider>();
    final printer = context.read<PrinterProvider>();
    final selectedOrders = orderProvider.orders.where((o) => _selectedOrderIds.contains(o.id)).toList();

    if (!printer.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printer not connected. Please connect printer in settings.')),
      );
      return;
    }

    setState(() => _isBulkProcessing = true);
    int printedCount = 0;

    for (final order in selectedOrders) {
      final success = await printer.printReceipt(
        items: order.items,
        total: order.total,
        cash: order.total,
        change: 0,
        orderId: order.orderId,
        customerName: order.customerName,
        orderType: "Pickup",
      );
      if (success) {
        printedCount++;
      } else {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isBulkProcessing = false);

    messenger.showSnackBar(
      SnackBar(content: Text('Printed $printedCount of ${selectedOrders.length} order tickets! 🖨️')),
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
    await OrderQrScannerSheet.scanAndCheckout(context);
  }

  Future<void> _processScannedCode(BuildContext context, String rawCode) async {
    await processScannedOrderCode(context, rawCode);
  }
}

class _OrderCard extends StatelessWidget {
  final PreOrder order;
  final bool isBulkMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onSelectToggle;
  final VoidCallback onLongPress;

  const _OrderCard({
    super.key,
    required this.order,
    this.isBulkMode = false,
    this.isSelected = false,
    required this.onTap,
    required this.onSelectToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isNew = context.watch<OrderProvider>().isNewlyArrived(order.id);
    final dateStr = DateFormat('MMM d, h:mm a').format(order.createdAt);
    final itemPreview = order.items.map((i) => '${i.qty}x ${i.name}').join(', ');
    final canAdvance = !isBulkMode && (
      order.status == OrderStatus.pending || 
      order.status == OrderStatus.staging || 
      order.status == OrderStatus.ready
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected 
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) 
          : (isNew ? Colors.green.withValues(alpha: 0.12) : null),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected 
          ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
          : (isNew ? const BorderSide(color: Colors.green, width: 2) : BorderSide.none),
      ),
      child: InkWell(
        onTap: () {
          if (isNew) {
            context.read<OrderProvider>().clearNewlyArrived(order.id);
          }
          onTap();
        },
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isBulkMode) ...[
                    IgnorePointer(
                      child: Checkbox(
                        value: isSelected,
                        onChanged: null,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isNew) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                            Expanded(
                              child: Text(
                                order.orderId,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            StatusBadge(order.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.customerName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (itemPreview.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            itemPreview,
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${order.items.length} items • ${formatPeso(order.total)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              dateStr,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!isBulkMode && !canAdvance) const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              if (canAdvance) ...[
                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.5),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Next step: ${_nextStatusLabel(order.status)}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    _AdvanceButton(order: order),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AdvanceButton extends StatefulWidget {
  final PreOrder order;
  const _AdvanceButton({required this.order});

  @override
  State<_AdvanceButton> createState() => _AdvanceButtonState();
}

class _AdvanceButtonState extends State<_AdvanceButton> {
  bool _loading = false;

  IconData _advanceIcon(OrderStatus s) => switch (s) {
    OrderStatus.pending => Icons.inventory_2_outlined,
    OrderStatus.staging => Icons.check_circle_outline_rounded,
    OrderStatus.ready   => Icons.shopping_bag_outlined,
    _ => Icons.fast_forward_rounded,
  };

  String _advanceLabel(OrderStatus s) => switch (s) {
    OrderStatus.pending => 'START PACKING',
    OrderStatus.staging => 'MARK AS READY',
    OrderStatus.ready   => 'MARK AS COLLECTED',
    _ => 'ADVANCE',
  };

  Color _advanceColor(OrderStatus s) => switch (s) {
    OrderStatus.pending => Colors.blue.shade700,
    OrderStatus.staging => Colors.amber.shade800,
    OrderStatus.ready   => Colors.green.shade700,
    _ => Colors.blue,
  };

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return FilledButton.icon(
      onPressed: _loading ? null : () async {
        setState(() => _loading = true);
        final messenger = ScaffoldMessenger.of(context);
        try {
          final orderProvider = context.read<OrderProvider>();
          if (order.status == OrderStatus.ready) {
            await PosCheckoutModal.show(context, order);
          } else {
            await orderProvider.advanceStatus(order.id);
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Order #${order.orderId} updated! ✅'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text('Failed to update order: $e'), backgroundColor: Colors.red),
            );
          }
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      },
      icon: _loading
          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(_advanceIcon(order.status), size: 14),
      label: Text(_advanceLabel(order.status)),
      style: FilledButton.styleFrom(
        backgroundColor: _advanceColor(order.status),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

String _nextStatusLabel(OrderStatus s) => switch (s) {
  OrderStatus.pending => 'Packing',
  OrderStatus.staging => 'Ready for Pickup',
  OrderStatus.ready   => 'Complete Pickup',
  _ => '',
};

class _BulkActionBar extends StatelessWidget {
  final int selectedCount;
  final bool isProcessing;
  final VoidCallback onBulkPack;
  final VoidCallback onBulkCollect;
  final VoidCallback onBulkCancel;
  final VoidCallback onBulkPrint;

  const _BulkActionBar({
    required this.selectedCount,
    required this.isProcessing,
    required this.onBulkPack,
    required this.onBulkCollect,
    required this.onBulkCancel,
    required this.onBulkPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bulk Actions ($selectedCount selected)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              if (isProcessing)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isProcessing ? null : onBulkPack,
                  icon: const Icon(Icons.fast_forward_rounded, size: 18),
                  label: const Text('ADVANCE STATUS'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: isProcessing ? null : onBulkCollect,
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: const Text('COLLECT ALL'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : onBulkPrint,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('PRINT TICKETS'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : onBulkCancel,
                  icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                  label: const Text('CANCEL SELECTED', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ],
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
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.orderId, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
              Text(DateFormat('MMMM dd, yyyy • hh:mm a').format(order.createdAt), 
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        StatusBadge(order.status),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                  Text(
                    value, 
                    style: TextStyle(
                      fontSize: 14, 
                      fontWeight: FontWeight.w600,
                      color: onTap != null ? Colors.blue : null,
                      decoration: onTap != null ? TextDecoration.underline : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
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
    final canCancel = order.status == OrderStatus.pending || order.status == OrderStatus.staging || order.status == OrderStatus.ready;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                cash: order.total,
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
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('PRINT ORDER TICKET')),
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
                    child: const FittedBox(fit: BoxFit.scaleDown, child: Text('CANCEL ORDER', style: TextStyle(fontWeight: FontWeight.bold))),
                  ),
                ),
              if (canCancel && canAdvance) const SizedBox(width: 12),
              if (canAdvance)
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Confirm Action'),
                          content: Text('Are you sure you want to "${_advanceLabel(order.status)}" for Order #${order.orderId}?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('CONFIRM'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true && context.mounted) {
                        if (order.status == OrderStatus.ready) {
                          Navigator.pop(context);
                          await PosCheckoutModal.show(context, order);
                        } else {
                          await context.read<OrderProvider>().advanceStatus(order.id);
                          if (context.mounted) Navigator.pop(context);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: order.status == OrderStatus.ready ? Colors.green.shade700 : null,
                      foregroundColor: order.status == OrderStatus.ready ? Colors.white : null,
                      padding: const EdgeInsets.symmetric(vertical: 16), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: isProcessing 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_advanceLabel(order.status), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        ),
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

String _formatStatusName(OrderStatus s) => switch (s) {
  OrderStatus.pending => 'Pending',
  OrderStatus.staging => 'Staging',
  OrderStatus.ready => 'Ready',
  OrderStatus.collected => 'Collected',
  OrderStatus.cancelled => 'Cancelled',
  OrderStatus.refunded => 'Refunded',
  OrderStatus.refundRequested => 'Refund Requested',
  OrderStatus.refundRejected => 'Refund Rejected',
};

class _PickupScannerDialog extends StatefulWidget {
  const _PickupScannerDialog();

  @override
  State<_PickupScannerDialog> createState() => _PickupScannerDialogState();
}

class _PickupScannerDialogState extends State<_PickupScannerDialog> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Customer Pickup QR', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.amber);
                  default:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                }
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_scanned) return;
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final code = barcodes.first.rawValue;
                if (code != null && code.trim().isNotEmpty) {
                  _scanned = true;
                  Navigator.pop(context, code.trim());
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Center the customer\'s pickup QR code within the frame to automatically mark order as COLLECTED',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
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
