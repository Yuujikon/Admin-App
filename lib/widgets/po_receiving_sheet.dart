import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/purchase_order.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/format.dart';
import 'premium_components.dart';

class PoReceivingSheet extends StatefulWidget {
  final PurchaseOrder purchaseOrder;

  const PoReceivingSheet({
    super.key,
    required this.purchaseOrder,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required PurchaseOrder purchaseOrder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PoReceivingSheet(purchaseOrder: purchaseOrder),
    );
  }

  @override
  State<PoReceivingSheet> createState() => _PoReceivingSheetState();
}

class _PoReceivingSheetState extends State<PoReceivingSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _receiptNoCtrl;
  late final TextEditingController _notesCtrl;

  final Map<String, TextEditingController> _qtyReceivingControllers = {};
  final Map<String, TextEditingController> _costControllers = {};
  final Map<String, DateTime?> _expiryDates = {};

  bool _syncCostPrice = true;
  bool _submitting = false;
  bool _showCompletedSection = false;

  @override
  void initState() {
    super.initState();
    _receiptNoCtrl = TextEditingController();
    _notesCtrl = TextEditingController();

    final inventory = context.read<InventoryProvider>();

    for (var item in widget.purchaseOrder.items) {
      _qtyReceivingControllers[item.productId] = TextEditingController(text: '0');
      _costControllers[item.productId] = TextEditingController(
        text: item.unitCost > 0 ? item.unitCost.toStringAsFixed(2) : '',
      );

      // Check product shelf days for default expiry date
      final prodIndex =
          inventory.products.indexWhere((p) => p.id == item.productId);
      if (prodIndex >= 0) {
        final p = inventory.products[prodIndex];
        if (p.shelfDays != null) {
          _expiryDates[item.productId] =
              DateTime.now().add(Duration(days: p.shelfDays!));
        }
      }
    }
  }

  @override
  void dispose() {
    _receiptNoCtrl.dispose();
    _notesCtrl.dispose();
    for (var ctrl in _qtyReceivingControllers.values) {
      ctrl.dispose();
    }
    for (var ctrl in _costControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _fillRemaining(PurchaseOrderItem item) {
    setState(() {
      _qtyReceivingControllers[item.productId]?.text =
          item.remainingQty.toString();
    });
  }

  void _fillAllRemaining() {
    setState(() {
      for (var item in widget.purchaseOrder.items) {
        if (!item.isComplete) {
          _qtyReceivingControllers[item.productId]?.text =
              item.remainingQty.toString();
        }
      }
    });
  }

  Future<void> _submitDelivery({bool shortClose = false}) async {
    if (_submitting) return;

    if (!shortClose && _formKey.currentState?.validate() != true) return;
    if (_receiptNoCtrl.text.trim().isEmpty && !shortClose) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please enter the Supplier Delivery Receipt No. (DR/Invoice No.)')),
      );
      return;
    }

    // Extract quantities and costs
    final Map<String, int> receivedQtyMap = {};
    final Map<String, double> unitCostMap = {};
    int totalReceivingNow = 0;

    for (var item in widget.purchaseOrder.items) {
      final qtyText =
          _qtyReceivingControllers[item.productId]?.text.trim() ?? '0';
      final int qtyNow = int.tryParse(qtyText) ?? 0;

      if (qtyNow > item.remainingQty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Quantity for ${item.productName} cannot exceed remaining ${item.remainingQty} units.'),
          ),
        );
        return;
      }

      receivedQtyMap[item.productId] = qtyNow;
      totalReceivingNow += qtyNow;

      final costText = _costControllers[item.productId]?.text.trim() ?? '';
      final double cost = double.tryParse(costText) ?? item.unitCost;
      unitCostMap[item.productId] = cost;
    }

    if (totalReceivingNow == 0 && !shortClose) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please enter at least 1 unit to receive or choose Short-Close.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final auth = context.read<AppAuthProvider>();
      final String receivedBy = auth.currentUser?.email ?? 'Admin';
      final inventory = context.read<InventoryProvider>();
      final procurement = context.read<ProcurementProvider>();

      await procurement.processPoDeliveryAtomic(
        poId: widget.purchaseOrder.id,
        currentPo: widget.purchaseOrder,
        deliveryReceiptNo: _receiptNoCtrl.text.trim().isEmpty
            ? 'SHORT-CLOSED'
            : _receiptNoCtrl.text.trim(),
        receivedQtyMap: receivedQtyMap,
        expiryDateMap: _expiryDates,
        unitCostMap: unitCostMap,
        cachedProducts: inventory.products,
        receivedBy: receivedBy,
        discrepancyNote: _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        syncProductCostPrice: _syncCostPrice,
        shortCloseRemaining: shortClose,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(shortClose
                ? 'Purchase Order #${widget.purchaseOrder.poNumber} Short-Closed.'
                : 'Received $totalReceivingNow units! Stock & FIFO batches updated.'),
            backgroundColor: Colors.teal.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error receiving delivery: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingItems =
        widget.purchaseOrder.items.where((i) => !i.isComplete).toList();
    final completedItems =
        widget.purchaseOrder.items.where((i) => i.isComplete).toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Receive PO #${widget.purchaseOrder.poNumber}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.teal.shade300),
                              ),
                              child: Text(
                                widget.purchaseOrder.status.displayName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.teal.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Supplier: ${widget.purchaseOrder.supplierName}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const Divider(height: 20),

              // Delivery Receipt No. & Discrepancy Note Inputs
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _receiptNoCtrl,
                      decoration: InputDecoration(
                        labelText: 'Supplier DR / Invoice No. *',
                        hintText: 'e.g. DR-98412',
                        prefixIcon: const Icon(Icons.receipt_long_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'DR No. required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _notesCtrl,
                      decoration: InputDecoration(
                        labelText: 'Discrepancy / Delivery Note (Optional)',
                        hintText: 'Notes on condition or damage...',
                        prefixIcon: const Icon(Icons.note_alt_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Sync Cost Price Checkbox
              CheckboxListTile(
                value: _syncCostPrice,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Sync Product Base Cost Price (COGS) from PO unit cost',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onChanged: (val) {
                  setState(() => _syncCostPrice = val ?? true);
                },
              ),

              const SizedBox(height: 12),

              // Pending Line Items Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pending Deliveries (${pendingItems.length} items)',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  if (pendingItems.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.done_all_rounded, size: 16),
                      label: const Text('FILL ALL REMAINING'),
                      onPressed: _fillAllRemaining,
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Pending Line Items Cards
              if (pendingItems.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.green),
                      const SizedBox(width: 10),
                      Text(
                        'All line items on this Purchase Order have been received!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pendingItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = pendingItems[index];
                    final qtyCtrl = _qtyReceivingControllers[item.productId];
                    final costCtrl = _costControllers[item.productId];
                    final expiry = _expiryDates[item.productId];

                    return PremiumCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                    Text(
                                      'SKU: ${item.sku}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Ordered: ${item.orderedQty} | In: ${item.receivedQty} | Rem: ${item.remainingQty}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Controls Row: Receiving Qty, Unit Cost, Fill Remaining
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Qty Receiving Now',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10),
                                  ),
                                  validator: (val) {
                                    final n = int.tryParse(val ?? '');
                                    if (n == null || n < 0) return 'Invalid';
                                    if (n > item.remainingQty) {
                                      return 'Max ${item.remainingQty}';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: costCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d+\.?\d{0,2}')),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Unit Cost (₱)',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () => _fillRemaining(item),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text(
                                  'FILL MAX',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Expiry Date Picker for Perishable Goods
                          Row(
                            children: [
                              const Icon(Icons.calendar_month_rounded,
                                  size: 16, color: Colors.teal),
                              const SizedBox(width: 6),
                              Text(
                                expiry != null
                                    ? 'Expiry: ${DateFormat('MMM d, yyyy').format(expiry)}'
                                    : 'No Expiry Date',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: expiry != null
                                      ? Colors.teal.shade900
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: expiry ??
                                        DateTime.now()
                                            .add(const Duration(days: 30)),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 1095)),
                                  );
                                  if (picked != null) {
                                    setState(() =>
                                        _expiryDates[item.productId] = picked);
                                  }
                                },
                                child: Text(
                                  expiry != null
                                      ? 'Change Expiry'
                                      : 'Set Expiry',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              if (expiry != null)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    setState(() =>
                                        _expiryDates[item.productId] = null);
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),

              const SizedBox(height: 16),

              // Completed Items Collapsible Section
              if (completedItems.isNotEmpty) ...[
                InkWell(
                  onTap: () {
                    setState(() =>
                        _showCompletedSection = !_showCompletedSection);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Already Complete (${completedItems.length} items)',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900),
                            ),
                          ],
                        ),
                        Icon(
                          _showCompletedSection
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: Colors.green.shade900,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showCompletedSection) ...[
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: completedItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = completedItems[index];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: Colors.green, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.productName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                            Text(
                              '${item.receivedQty}/${item.orderedQty} received (${formatPeso(item.unitCost)})',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],

              const SizedBox(height: 24),

              // Action Buttons
              if (_submitting)
                const Center(child: CircularProgressIndicator())
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text(
                        'CONFIRM DELIVERY & STAMP BATCHES',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      onPressed: () => _submitDelivery(shortClose: false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    if (pendingItems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.close_fullscreen_rounded,
                            size: 16, color: Colors.red),
                        label: const Text(
                          'SHORT-CLOSE REMAINING BALANCE',
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _submitDelivery(shortClose: true),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
