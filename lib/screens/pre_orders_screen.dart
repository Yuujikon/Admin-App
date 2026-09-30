import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart';
import '../models/refund_request.dart';
import '../providers/order_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/printer_provider.dart';
import '../services/notification_service.dart';
import '../widgets/status_badge.dart';
import '../config/theme.dart';
import '../utils/format.dart';
import '../utils/barcode_routing.dart';
import '../widgets/pos_checkout_modal.dart';
import '../widgets/order_qr_scanner.dart';
import '../widgets/responsive_layout.dart';

enum PreOrderStage { pending, packing, ready, completed, refunds, all }

class PreOrdersScreen extends StatefulWidget {
  const PreOrdersScreen({super.key});

  @override
  State<PreOrdersScreen> createState() => _PreOrdersScreenState();
}

class _PreOrdersScreenState extends State<PreOrdersScreen> {
  PreOrderStage _activeStage = PreOrderStage.pending;
  String _search = '';
  final FocusNode _searchFocus = FocusNode();

  // Multi-Select / Multiple Orders Advancement state
  final Set<String> _selectedOrderIds = {};
  bool _isProcessing = false;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSelectOrder(String id) {
    setState(() {
      if (_selectedOrderIds.contains(id)) {
        _selectedOrderIds.remove(id);
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

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final inventory = context.watch<InventoryProvider>();
    final orders = orderProvider.orders;

    if (orderProvider.isLoading && orders.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Categorize orders by pipeline stage
    final pendingOrders =
        orders.where((o) => o.status == OrderStatus.pending).toList();
    final packingOrders =
        orders.where((o) => o.status == OrderStatus.staging).toList();
    final readyOrders =
        orders.where((o) => o.status == OrderStatus.ready).toList();
    final completedOrders =
        orders.where((o) => o.status == OrderStatus.collected).toList();

    // Categorize pending refund requests
    final pendingRefunds = inventory.refundRequests
        .where((r) => r.status == RefundStatus.pending)
        .toList();

    final filteredByStage = switch (_activeStage) {
      PreOrderStage.pending => pendingOrders,
      PreOrderStage.packing => packingOrders,
      PreOrderStage.ready => readyOrders,
      PreOrderStage.completed => completedOrders,
      PreOrderStage.refunds => <PreOrder>[],
      PreOrderStage.all => orders,
    };

    final visibleOrders = filteredByStage.where((o) {
      final query = _search.toLowerCase().trim();
      if (query.isEmpty) return true;
      return o.orderId.toLowerCase().contains(query) ||
          o.customerName.toLowerCase().contains(query) ||
          o.customerEmail.toLowerCase().contains(query);
    }).toList();

    final visiblePendingRefunds = pendingRefunds.where((r) {
      final query = _search.toLowerCase().trim();
      if (query.isEmpty) return true;
      return r.transactionId.toLowerCase().contains(query) ||
          r.customerName.toLowerCase().contains(query) ||
          r.customerEmail.toLowerCase().contains(query) ||
          r.reason.toLowerCase().contains(query);
    }).toList();

    return BarcodeInterceptor(
      barcodeFocus: _searchFocus,
      onBarcodeDetected: (code) => processScannedOrderCode(context, code),
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        floatingActionButton: FloatingActionButton(
          onPressed: () => OrderQrScannerSheet.scanAndCheckout(context),
          tooltip: 'Scan Pickup QR',
          child: const Icon(Icons.qr_code_scanner_rounded),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Header Title ──────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ORDER FULFILLMENT PIPELINE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Customer Pre-orders',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── 2. Pipeline Navigation Stage Tabs ────────────────────────
                _buildStageTabs(
                  pendingCount: pendingOrders.length,
                  packingCount: packingOrders.length,
                  readyCount: readyOrders.length,
                  completedCount: completedOrders.length,
                  pendingRefundsCount: pendingRefunds.length,
                  totalCount: orders.length,
                ),
                const SizedBox(height: 20),

                // ── 3. Main Content Card Container ───────────────────────────
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title & Subtitle
                        Text(
                          _getStageTitle(_activeStage),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: _activeStage == PreOrderStage.refunds
                                ? Colors.amber.shade900
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _activeStage == PreOrderStage.refunds
                              ? 'Review and approve customer return & refund claims.'
                              : 'Keep orders moving and customers updated.',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Search Field
                        TextField(
                          focusNode: _searchFocus,
                          decoration: InputDecoration(
                            hintText: _activeStage == PreOrderStage.refunds
                                ? 'Search refunds by ID, Customer Name, Email, Reason...'
                                : 'Search orders by ID, Customer Name, or Email...',
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            suffixIcon: _search.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () =>
                                        setState(() => _search = ''),
                                  )
                                : null,
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                        const SizedBox(height: 16),

                        // ── 4. Multiple Orders Advancement Banner ────────────
                        _buildBulkAdvancementBanner(context, visibleOrders),
                        const SizedBox(height: 20),

                        // ── 5. Orders Grid / List ────────────────────────────
                        if (_activeStage == PreOrderStage.refunds)
                          _buildRefundsList(visiblePendingRefunds, inventory)
                        else if (visibleOrders.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            alignment: Alignment.center,
                            child: Column(
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  size: 48,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No orders in ${_getStageTitle(_activeStage).toLowerCase()}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ResponsiveCardGrid(
                            children: visibleOrders.map((order) {
                              final isSelected =
                                  _selectedOrderIds.contains(order.id);
                              return _OrderCard(
                                key: ValueKey(order.id),
                                order: order,
                                isSelected: isSelected,
                                onSelectToggle: () =>
                                    _toggleSelectOrder(order.id),
                                onTap: () =>
                                    _showOrderDetails(context, order),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Pending Refunds List ──────────────────────────────────────────────────

  Widget _buildRefundsList(
      List<RefundRequest> refunds, InventoryProvider inventory) {
    if (refunds.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 48,
              color: Colors.green.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'No pending refund claims.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ResponsiveCardGrid(
      children: refunds.map((req) {
        return _PendingRefundCard(
          key: ValueKey(req.id),
          req: req,
          inventory: inventory,
        );
      }).toList(),
    );
  }

  // ── Stage Tabs Bar ─────────────────────────────────────────────────────────

  Widget _buildStageTabs({
    required int pendingCount,
    required int packingCount,
    required int readyCount,
    required int completedCount,
    required int pendingRefundsCount,
    required int totalCount,
  }) {
    final stages = [
      (PreOrderStage.pending, 'Pending', pendingCount),
      (PreOrderStage.packing, 'Packing', packingCount),
      (PreOrderStage.ready, 'Ready', readyCount),
      (PreOrderStage.completed, 'Completed', completedCount),
      (PreOrderStage.refunds, 'Pending Refunds', pendingRefundsCount),
      (PreOrderStage.all, 'All', totalCount),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: stages.map((item) {
          final stage = item.$1;
          final label = item.$2;
          final count = item.$3;
          final bool isSelected = _activeStage == stage;
          final bool isRefundStage = stage == PreOrderStage.refunds;

          final activeColor = isRefundStage
              ? Colors.orange.shade800
              : Theme.of(context).colorScheme.primary;

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () {
                setState(() {
                  _activeStage = stage;
                  _selectedOrderIds.clear();
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                            color: isSelected
                                ? activeColor
                                : (isRefundStage && count > 0
                                    ? Colors.amber.shade900
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? activeColor
                                : (isRefundStage && count > 0
                                    ? Colors.amber.shade100
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : (isRefundStage && count > 0
                                      ? Colors.amber.shade900
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Active underline indicator
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 3,
                    width: isSelected ? 64 : 0,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Multiple Orders Advancement Banner ────────────────────────────────────

  Widget _buildBulkAdvancementBanner(
      BuildContext context, List<PreOrder> visibleOrders) {
    if (_activeStage == PreOrderStage.refunds) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber.shade50.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                color: Colors.amber.shade900, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Refund claims require individual review, condition classification, and store response notes.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final selectedCount = _selectedOrderIds.length;
    final allVisibleSelected = visibleOrders.isNotEmpty &&
        _selectedOrderIds.length == visibleOrders.length;

    final String bulkActionText = switch (_activeStage) {
      PreOrderStage.pending => 'Start packing ($selectedCount)',
      PreOrderStage.packing => 'Mark ready ($selectedCount)',
      PreOrderStage.ready => 'Complete pickup ($selectedCount)',
      _ => 'Advance selected ($selectedCount)',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHigh
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.article_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$selectedCount Selected',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Select multiple orders to update them together',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              if (allVisibleSelected) {
                _deselectAll();
              } else {
                _selectAll(visibleOrders);
              }
            },
            child: Text(
              allVisibleSelected ? 'Deselect all' : 'Select all',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: (selectedCount == 0 || _isProcessing)
                ? null
                : () => _handleBulkAction(context),
            icon: _isProcessing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(
              bulkActionText,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: GdcColors.emeraldPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bulk Action Handler ───────────────────────────────────────────────────

  Future<void> _handleBulkAction(BuildContext context) async {
    final orderProvider = context.read<OrderProvider>();
    final selectedIds = _selectedOrderIds.toList();
    if (selectedIds.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      if (_activeStage == PreOrderStage.ready) {
        final count = await orderProvider.bulkCompletePickup(selectedIds);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully completed $count orders! 🛍️'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final count = await orderProvider.bulkAdvanceStatus(selectedIds);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully advanced $count orders! 🚀'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _selectedOrderIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error updating orders: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  String _getStageTitle(PreOrderStage stage) => switch (stage) {
        PreOrderStage.pending => 'Pending orders',
        PreOrderStage.packing => 'Packing orders',
        PreOrderStage.ready => 'Ready orders',
        PreOrderStage.completed => 'Completed orders',
        PreOrderStage.refunds => 'Pending refund requests',
        PreOrderStage.all => 'All orders',
      };

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
          decoration:
              const InputDecoration(labelText: 'Reason for cancellation'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('BACK')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CANCEL ORDER',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (res == true && context.mounted) {
      await context
          .read<OrderProvider>()
          .cancelOrder(orderId, reason: ctrl.text.trim());
      if (context.mounted) Navigator.pop(context);
    }
  }
}

// ── PENDING REFUND CARD ─────────────────────────────────────────────────────

class _PendingRefundCard extends StatelessWidget {
  final RefundRequest req;
  final InventoryProvider inventory;

  const _PendingRefundCard({
    super.key,
    required this.req,
    required this.inventory,
  });

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

  void _handleRefund(BuildContext context, RefundRequest req,
      InventoryProvider inventory, bool approve) async {
    final notesCtrl = TextEditingController();

    if (approve) {
      RefundCondition? condition;

      final res = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setSt) {
            final responseText = notesCtrl.text.trim();
            final bool isValid = condition != null && responseText.isNotEmpty;

            return AlertDialog(
              title: const Text('Approve Refund Request'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1. Select Item Condition (Required):',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      RadioListTile<RefundCondition>(
                        title: const Text('Restockable / Return to Shelf',
                            style: TextStyle(fontSize: 13)),
                        value: RefundCondition.restockable,
                        groupValue: condition,
                        onChanged: (v) => setSt(() => condition = v),
                      ),
                      RadioListTile<RefundCondition>(
                        title: const Text('Damaged Item',
                            style: TextStyle(fontSize: 13)),
                        value: RefundCondition.damaged,
                        groupValue: condition,
                        onChanged: (v) => setSt(() => condition = v),
                      ),
                      RadioListTile<RefundCondition>(
                        title: const Text('Expired Item',
                            style: TextStyle(fontSize: 13)),
                        value: RefundCondition.expired,
                        groupValue: condition,
                        onChanged: (v) => setSt(() => condition = v),
                      ),
                      const SizedBox(height: 16),
                      const Text('2. Store Response to Customer (Mandatory *):',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 3,
                        onChanged: (_) => setSt(() {}),
                        decoration: InputDecoration(
                          hintText:
                              'Enter store explanation or return instructions for customer...',
                          border: const OutlineInputBorder(),
                          errorText: responseText.isEmpty
                              ? 'Store response is mandatory to maintain store rating.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: isValid ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white),
                  child: const Text('APPROVE REFUND'),
                ),
              ],
            );
          },
        ),
      );

      if (res == true &&
          condition != null &&
          notesCtrl.text.trim().isNotEmpty) {
        await inventory.approveRefundRequest(req,
            condition: condition!, notes: notesCtrl.text.trim());
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Refund approved with store response ✅'),
                backgroundColor: Colors.green),
          );
        }
      }
    } else {
      final res = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setSt) {
            final responseText = notesCtrl.text.trim();
            final bool isValid = responseText.isNotEmpty;

            return AlertDialog(
              title: const Text('Decline / Reject Refund'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'Store Response / Rejection Reason (Mandatory *):',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 3,
                        onChanged: (_) => setSt(() {}),
                        decoration: InputDecoration(
                          hintText:
                              'Explain why the refund request is declined...',
                          border: const OutlineInputBorder(),
                          errorText:
                              responseText.isEmpty ? 'Reason is required' : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: isValid ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('REJECT REQUEST'),
                ),
              ],
            );
          },
        ),
      );

      if (res == true && notesCtrl.text.trim().isNotEmpty) {
        await inventory.rejectRefundRequest(req, notesCtrl.text.trim(),
            notes: notesCtrl.text.trim());
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Refund request rejected'),
                backgroundColor: Colors.orange),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(req.createdAt);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBg = isDark
        ? Colors.amber.shade900.withValues(alpha: 0.18)
        : Colors.amber.shade50.withValues(alpha: 0.8);
    final borderCol = isDark ? Colors.amber.shade700 : Colors.amber.shade600;

    return Card(
      elevation: 0,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderCol, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge Accent Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade800,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_return_rounded,
                          size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'PENDING REFUND REQUEST',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatPeso(req.total),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Customer Name & Transaction Ref
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.amber.shade200,
                  child: Text(
                    req.customerName.isNotEmpty
                        ? req.customerName[0].toUpperCase()
                        : 'C',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Order #${req.transactionId}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Date & Reason tag
            Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 13, color: Colors.amber.shade900),
                const SizedBox(width: 4),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.amber.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    req.reason,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Items Container
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Items to Refund (${req.items.length}):',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...req.items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text(
                              '${item.qty}x',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              formatPeso(item.price * item.qty),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),

            // Photo proof if present
            if (req.photoBase64 != null && req.photoBase64!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Photo Proof:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showImageLightbox(context, req.photoBase64!),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.memory(base64Decode(req.photoBase64!),
                          fit: BoxFit.cover),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            // Action Buttons Row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () =>
                        _handleRefund(context, req, inventory, false),
                    child: const Text('REJECT REQUEST',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GdcColors.emeraldPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () =>
                        _handleRefund(context, req, inventory, true),
                    child: const Text('APPROVE REFUND',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
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

// ── ORDER CARD ───────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final PreOrder order;
  final bool isSelected;
  final VoidCallback onSelectToggle;
  final VoidCallback onTap;

  const _OrderCard({
    super.key,
    required this.order,
    required this.isSelected,
    required this.onSelectToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatRelativeTime(order.createdAt);
    final initials = order.customerName.isNotEmpty
        ? order.customerName[0].toUpperCase()
        : 'C';

    final totalQty = order.items.fold(0, (sum, i) => sum + i.qty);
    final itemsSummaryNames = order.items.take(2).map((i) => i.name).join(', ');
    final remainingCount =
        order.items.length > 2 ? ' +${order.items.length - 2}' : '';
    final summaryText = '$totalQty items • $itemsSummaryNames$remainingCount';

    final canAdvance = order.status == OrderStatus.pending ||
        order.status == OrderStatus.staging ||
        order.status == OrderStatus.ready;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? GdcColors.emeraldPrimary
              : Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Checkbox, Avatar, Customer Name, Order ID & Status Badge
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onSelectToggle(),
                    activeColor: GdcColors.emeraldPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '#${order.orderId}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(order.status),
              ],
            ),
            const SizedBox(height: 12),

            // Timestamp (e.g. "Ordered 8 min ago")
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: Colors.amber.shade800,
                ),
                const SizedBox(width: 6),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Gray Order Summary Box
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHigh
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order summary',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summaryText,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Total Amount Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  formatPeso(order.total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Primary Card Action Button
            SizedBox(
              width: double.infinity,
              child: _CardActionButton(order: order, canAdvance: canAdvance),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) {
      return 'Ordered just now';
    } else if (diff.inMinutes < 60) {
      return 'Ordered ${diff.inMinutes} min ago';
    } else if (diff.inHours < 24) {
      return 'Ordered ${diff.inHours} ${diff.inHours == 1 ? "hr" : "hrs"} ago';
    } else {
      return 'Ordered ${diff.inDays} ${diff.inDays == 1 ? "day" : "days"} ago';
    }
  }
}

class _CardActionButton extends StatefulWidget {
  final PreOrder order;
  final bool canAdvance;

  const _CardActionButton({required this.order, required this.canAdvance});

  @override
  State<_CardActionButton> createState() => _CardActionButtonState();
}

class _CardActionButtonState extends State<_CardActionButton> {
  bool _loading = false;

  String _buttonText(OrderStatus s) => switch (s) {
        OrderStatus.pending => 'Start packing',
        OrderStatus.staging => 'Mark ready for pickup',
        OrderStatus.ready => 'Complete pickup',
        _ => 'View order details',
      };

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return ElevatedButton(
      onPressed: _loading
          ? null
          : () async {
              if (!widget.canAdvance) {
                _showOrderDetails(context, order);
                return;
              }

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
                    SnackBar(
                      content: Text('Failed to update order: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() => _loading = false);
                }
              }
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.canAdvance
            ? GdcColors.emeraldPrimary
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: widget.canAdvance
            ? Colors.white
            : Theme.of(context).colorScheme.onSurfaceVariant,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Text(
              _buttonText(order.status),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
    );
  }

  void _showOrderDetails(BuildContext context, PreOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OrderDetailsSheet(order: order),
    );
  }
}

// ── ORDER DETAILS MODAL SHEET ───────────────────────────────────────────────

class _OrderDetailsSheet extends StatelessWidget {
  final PreOrder order;
  final Function(BuildContext, String)? onCancel;

  const _OrderDetailsSheet({required this.order, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr =
        DateFormat('MMMM d, yyyy • h:mm a').format(order.createdAt);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Modal Title Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Order #${order.orderId}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(order.status),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Customer Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          order.customerName.isNotEmpty
                              ? order.customerName[0].toUpperCase()
                              : 'C',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.customerName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            if (order.customerEmail.isNotEmpty)
                              Text(
                                order.customerEmail,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (order.customerPhone != null &&
                                order.customerPhone!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                order.customerPhone!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (order.customerPhone != null &&
                          order.customerPhone!.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.phone_rounded),
                          color: theme.colorScheme.primary,
                          onPressed: () async {
                            final uri = Uri.parse('tel:${order.customerPhone}');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            }
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Order Items Section
                Text(
                  'ORDER ITEMS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ...order.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${item.qty}x',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                if (item.variantName != null &&
                                    item.variantName!.isNotEmpty)
                                  Text(
                                    item.variantName!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            formatPeso(item.price * item.qty),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                    )),
                const Divider(height: 32),

                // Price Summary
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL AMOUNT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      formatPeso(order.total),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                if (order.notes != null && order.notes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Customer Note:',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(order.notes!,
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Bottom Action Bar
          if (onCancel != null &&
              (order.status == OrderStatus.pending ||
                  order.status == OrderStatus.staging)) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: OutlinedButton.icon(
                onPressed: () => onCancel!(context, order.id),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('CANCEL THIS ORDER'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
