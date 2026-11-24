import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/purchase_order.dart';
import '../models/receiving_record.dart';
import '../models/supplier.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../providers/auth_provider.dart';
import '../services/inventory_batch_service.dart';
import '../utils/format.dart';
import '../utils/notice_pdf_printer.dart';
import 'premium_components.dart';
import 'close_short_modal.dart';
import 'supplier_notice_dispatch_sheet.dart';

/// Helper model for managing local UI state of split batch rows during receiving verification.
class _LocalSplitBatchRow {
  final TextEditingController qtyCtrl;
  final TextEditingController tagCtrl;
  DateTime? expiryDate;

  _LocalSplitBatchRow({
    required String initialQty,
    required String initialTag,
    this.expiryDate,
  })  : qtyCtrl = TextEditingController(text: initialQty),
        tagCtrl = TextEditingController(text: initialTag);

  void dispose() {
    qtyCtrl.dispose();
    tagCtrl.dispose();
  }
}

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

  final Map<String, List<_LocalSplitBatchRow>> _itemSplitBatches = {};
  final Map<String, TextEditingController> _rejectedQtyCtrls = {};
  final Map<String, String> _rejectionReasons = {};
  final Map<String, TextEditingController> _actualPriceCtrls = {};

  bool _syncCostPrice = true;
  bool _submitting = false;
  bool _showCompletedSection = false;
  late DateTime _datePurchased;
  DateTime _dateArrived = DateTime.now();

  final List<String> _rejectionReasonOptions = [
    'Damaged',
    'Expired / Near-Expiry',
    'Wrong Item Delivered',
    'Shortage / Missing',
    'Other Quality Issue',
  ];

  @override
  void initState() {
    super.initState();
    _receiptNoCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _datePurchased = widget.purchaseOrder.orderDate;
    _dateArrived = DateTime.now();

    final inventory = context.read<InventoryProvider>();

    for (var item in widget.purchaseOrder.items) {
      final defaultTag = InventoryBatchService.generatePoBatchId(
        widget.purchaseOrder.poNumber,
        date: _dateArrived,
      );

      DateTime? defaultExpiry;
      final prodIndex =
          inventory.products.indexWhere((p) => p.id == item.productId);
      if (prodIndex >= 0) {
        final p = inventory.products[prodIndex];
        if (p.shelfDays != null) {
          defaultExpiry = DateTime.now().add(Duration(days: p.shelfDays!));
        }
      }

      _itemSplitBatches[item.productId] = [
        _LocalSplitBatchRow(
          initialQty: '0',
          initialTag: defaultTag,
          expiryDate: defaultExpiry,
        )
      ];

      _rejectedQtyCtrls[item.productId] = TextEditingController(text: '0');
      _rejectionReasons[item.productId] = 'Damaged';

      _actualPriceCtrls[item.productId] = TextEditingController(
        text: item.unitCost > 0 ? item.unitCost.toStringAsFixed(2) : '0.00',
      );
    }
  }

  @override
  void dispose() {
    _receiptNoCtrl.dispose();
    _notesCtrl.dispose();
    for (var list in _itemSplitBatches.values) {
      for (var row in list) {
        row.dispose();
      }
    }
    for (var ctrl in _rejectedQtyCtrls.values) {
      ctrl.dispose();
    }
    for (var ctrl in _actualPriceCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addSplitBatchRow(String productId) {
    final tag = InventoryBatchService.generatePoBatchId(
      widget.purchaseOrder.poNumber,
      date: _dateArrived,
    );

    setState(() {
      _itemSplitBatches[productId]?.add(
        _LocalSplitBatchRow(initialQty: '0', initialTag: tag),
      );
    });
  }

  Future<void> _pickBatchDate({required bool isPurchased}) async {
    final initial = isPurchased ? _datePurchased : _dateArrived;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isPurchased) {
          _datePurchased = picked;
        } else {
          _dateArrived = picked;
        }
      });
    }
  }

  void _removeSplitBatchRow(String productId, int index) {
    if ((_itemSplitBatches[productId]?.length ?? 0) <= 1) return;
    setState(() {
      final removed = _itemSplitBatches[productId]?.removeAt(index);
      removed?.dispose();
    });
  }

  void _fillRemaining(PurchaseOrderItem item) {
    if ((_itemSplitBatches[item.productId]?.length ?? 0) > 0) {
      setState(() {
        _itemSplitBatches[item.productId]!.first.qtyCtrl.text =
            item.remainingQty.toString();
      });
    }
  }

  void _fillAllRemaining() {
    setState(() {
      for (var item in widget.purchaseOrder.items) {
        if (!item.isComplete &&
            (_itemSplitBatches[item.productId]?.isNotEmpty ?? false)) {
          _itemSplitBatches[item.productId]!.first.qtyCtrl.text =
              item.remainingQty.toString();
        }
      }
    });
  }

  int _getItemAcceptedQty(String productId) {
    final rows = _itemSplitBatches[productId] ?? [];
    return rows.fold(
        0, (sum, r) => sum + (int.tryParse(r.qtyCtrl.text.trim()) ?? 0));
  }

  double _getItemActualPrice(PurchaseOrderItem item) {
    final text = _actualPriceCtrls[item.productId]?.text.trim() ?? '';
    return double.tryParse(text) ?? item.unitCost;
  }

  Future<void> _submitDelivery() async {
    if (_submitting) return;

    if (_formKey.currentState?.validate() != true) return;
    if (_receiptNoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please enter the Supplier Delivery Receipt No. (DR/Invoice No.)')),
      );
      return;
    }

    // Check Over-Delivery Edge Case
    String overDeliveryAction = 'cap';
    bool overDelivered = false;
    for (var item in widget.purchaseOrder.items) {
      final acceptedNow = _getItemAcceptedQty(item.productId);
      if (acceptedNow > item.remainingQty) {
        overDelivered = true;
        break;
      }
    }

    if (overDelivered) {
      final String? actionChoice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.add_shopping_cart_rounded,
                  color: Colors.orange.shade800),
              const SizedBox(width: 10),
              const Text('Over-Delivery Detected'),
            ],
          ),
          content: const Text(
            'Accepted quantity for one or more items exceeds the remaining expected order quantity. How would you like to handle the extra units?',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'cap'),
              child: const Text('Cap at Expected Qty'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, 'accept'),
              child: const Text('Accept Extra Units & Update Total'),
            ),
          ],
        ),
      );

      if (actionChoice == null) return;
      overDeliveryAction = actionChoice;
    }

    if (!mounted) return;

    // Prepare split batch maps & verification data
    final Map<String, List<SplitBatchEntry>> splitBatchesMap = {};
    final Map<String, int> receivedQtyMap = {};
    final Map<String, DateTime?> expiryDateMap = {};
    final Map<String, double> unitCostMap = {};
    final Map<String, int> rejectedQtyMap = {};
    final Map<String, String> rejectionReasonMap = {};

    int totalAcceptedNow = 0;

    for (var item in widget.purchaseOrder.items) {
      final pid = item.productId;
      final actualPrice = _getItemActualPrice(item);
      unitCostMap[pid] = actualPrice;

      final rows = _itemSplitBatches[pid] ?? [];
      final List<SplitBatchEntry> splits = [];

      for (var r in rows) {
        final q = int.tryParse(r.qtyCtrl.text.trim()) ?? 0;
        if (q > 0) {
          splits.add(SplitBatchEntry(
            acceptedQty: q,
            expiryDate: r.expiryDate,
            batchTag: r.tagCtrl.text.trim(),
          ));
        }
      }

      final itemAccepted = splits.fold(0, (acc, s) => acc + s.acceptedQty);
      splitBatchesMap[pid] = splits;
      receivedQtyMap[pid] = itemAccepted;
      expiryDateMap[pid] = splits.isNotEmpty ? splits.first.expiryDate : null;

      final rej = int.tryParse(_rejectedQtyCtrls[pid]?.text.trim() ?? '0') ?? 0;
      rejectedQtyMap[pid] = rej;
      if (rej > 0) {
        rejectionReasonMap[pid] = _rejectionReasons[pid] ?? 'Damaged / Expired';
      }

      totalAcceptedNow += itemAccepted;
    }

    if (totalAcceptedNow == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please enter at least 1 accepted unit to confirm delivery.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final auth = context.read<AppAuthProvider>();
      final String receivedBy = auth.currentUser?.email ?? 'Admin';
      final inventory = context.read<InventoryProvider>();
      final procurement = context.read<ProcurementProvider>();

      final PurchaseOrder updatedPo = await procurement.processPoDeliveryAtomic(
        poId: widget.purchaseOrder.id,
        currentPo: widget.purchaseOrder,
        deliveryReceiptNo: _receiptNoCtrl.text.trim(),
        receivedQtyMap: receivedQtyMap,
        expiryDateMap: expiryDateMap,
        unitCostMap: unitCostMap,
        cachedProducts: inventory.products,
        receivedBy: receivedBy,
        datePurchased: _datePurchased,
        dateArrived: _dateArrived,
        splitBatchesMap: splitBatchesMap,
        rejectedQtyMap: rejectedQtyMap,
        rejectionReasonMap: rejectionReasonMap,
        discrepancyNote:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        syncProductCostPrice: _syncCostPrice,
        overDeliveryAction: overDeliveryAction,
        settings: inventory.settings,
      );

      final bool isPartial =
          updatedPo.status == PurchaseOrderStatus.partiallyReceived ||
              updatedPo.totalRemainingQty > 0;

      final supplier =
          await inventory.fetchSupplierFresh(updatedPo.supplierId) ??
              inventory.suppliers.firstWhere(
                (s) => s.id == updatedPo.supplierId,
                orElse: () => Supplier(
                  id: updatedPo.supplierId,
                  name: updatedPo.effectiveSupplierName,
                ),
              );

      final receiptNo = _receiptNoCtrl.text.trim();

      if (!mounted) return;
      final parentContext = Navigator.of(context).context;
      Navigator.of(context).pop();

      if (!parentContext.mounted) return;
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(
          content: Text(
              'Received $totalAcceptedNow units! Stock & FIFO batches updated.'),
          backgroundColor: Colors.teal.shade800,
        ),
      );

      // Always open the unified Review, PDF Preview & Dual-Email Dispatch sheet
      // using the FRESHLY UPDATED PurchaseOrder (never stale pre-receiving quantities).
      if (isPartial) {
        await showBackOrderNoticePrompt(
          context: parentContext,
          po: updatedPo,
          supplier: supplier,
          actorEmail: receivedBy,
        );
      } else {
        await SupplierNoticeDispatchSheet.show(
          context: parentContext,
          po: updatedPo,
          supplier: supplier,
          noticeType: NoticeType.fullDelivery,
          deliveryReceiptNo: receiptNo,
          actorEmail: receivedBy,
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorRetryDialog(e.toString());
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Opens the redesigned Back-Order Review, PDF Preview & Dual-Email Dispatch sheet.
  static Future<void> showBackOrderNoticePrompt({
    required BuildContext context,
    required PurchaseOrder po,
    Supplier? supplier,
    required String actorEmail,
  }) async {
    final result = await SupplierNoticeDispatchSheet.show(
      context: context,
      po: po,
      supplier: supplier,
      noticeType: NoticeType.backorder,
      actorEmail: actorEmail,
    );

    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.summaryMessage),
          backgroundColor: result.isFullSuccess
              ? Colors.teal.shade800
              : Colors.orange.shade900,
        ),
      );
    }
  }

  void _showErrorRetryDialog(String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Transaction Failed'),
          ],
        ),
        content: Text(
            'The delivery verification could not be saved atomically. Network or server issue: $error'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _submitDelivery();
            },
            child: const Text('Retry Transaction'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingItems =
        widget.purchaseOrder.items.where((i) => !i.isComplete).toList();
    final completedItems =
        widget.purchaseOrder.items.where((i) => i.isComplete).toList();

    int totalAcceptedNow = 0;
    double actualDeliveryCostNow = 0.0;
    int itemsMovingToBackorder = 0;

    for (var item in widget.purchaseOrder.items) {
      final accepted = _getItemAcceptedQty(item.productId);
      final price = _getItemActualPrice(item);
      totalAcceptedNow += accepted;
      actualDeliveryCostNow += (accepted * price);

      final remAfter = item.remainingQty - accepted;
      if (remAfter > 0) itemsMovingToBackorder++;
    }

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
              // Header & Status Badge
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
                                color: widget.purchaseOrder.isBackOrder
                                    ? Colors.orange.shade50
                                    : Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: widget.purchaseOrder.isBackOrder
                                        ? Colors.orange.shade300
                                        : Colors.teal.shade300),
                              ),
                              child: Text(
                                widget.purchaseOrder.status.displayName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: widget.purchaseOrder.isBackOrder
                                      ? Colors.orange.shade900
                                      : Colors.teal.shade900,
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

              // DR No. & Notes Inputs
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

              const SizedBox(height: 10),

              // FIFO Batch Dates: Date Purchased (from PO) & Date Arrived (Primary FIFO Sort Key)
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickBatchDate(isPurchased: true),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.shopping_bag_outlined,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Date Purchased (PO)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('MMM dd, yyyy')
                                        .format(_datePurchased),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.edit_calendar_rounded, size: 15),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickBatchDate(isPurchased: false),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.teal.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.local_shipping_outlined,
                                size: 16, color: Colors.teal.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Date Arrived (FIFO Key)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.teal.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('MMM dd, yyyy')
                                        .format(_dateArrived),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.edit_calendar_rounded,
                                size: 15, color: Colors.teal.shade700),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Sync COGS Checkbox
              CheckboxListTile(
                value: _syncCostPrice,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Sync Product Base Cost Price (COGS) from Actual Delivery Price',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onChanged: (val) =>
                    setState(() => _syncCostPrice = val ?? true),
              ),

              const SizedBox(height: 12),

              // Pending Line Items Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Verification Items (${pendingItems.length} line items)',
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

              // Line Items Verification Cards
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
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.green),
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
                    final pid = item.productId;
                    final splitRows = _itemSplitBatches[pid] ?? [];
                    final acceptedNow = _getItemAcceptedQty(pid);
                    final actualPrice = _getItemActualPrice(item);
                    final priceVariance = actualPrice - item.unitCost;
                    final remainingAfter = item.remainingQty - acceptedNow;

                    return PremiumCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Item Name & Remaining Badge
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
                                      'SKU: ${item.sku.isNotEmpty ? item.sku : "N/A"}',
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

                          // Actual Unit Price Input + Price Variance Badge
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _actualPriceCtrls[pid],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d+\.?\d{0,2}')),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Actual Unit Price (₱)',
                                    isDense: true,
                                    prefixIcon: const Icon(
                                        Icons.monetization_on_outlined,
                                        size: 18),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (priceVariance != 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: priceVariance > 0
                                        ? Colors.red.shade50
                                        : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: priceVariance > 0
                                            ? Colors.red.shade300
                                            : Colors.green.shade300),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        priceVariance > 0
                                            ? Icons.trending_up_rounded
                                            : Icons.trending_down_rounded,
                                        size: 16,
                                        color: priceVariance > 0
                                            ? Colors.red.shade900
                                            : Colors.green.shade900,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${priceVariance > 0 ? "+" : ""}₱${priceVariance.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: priceVariance > 0
                                              ? Colors.red.shade900
                                              : Colors.green.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Spacer(),
                              OutlinedButton(
                                onPressed: () => _fillRemaining(item),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text(
                                  'FILL REMAINING',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // SPLIT BATCH ROWS SECTION
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Accepted Stock & FIFO Batches (${splitRows.length})',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('+ Add Batch / Expiry',
                                    style: TextStyle(fontSize: 11)),
                                onPressed: () => _addSplitBatchRow(pid),
                              ),
                            ],
                          ),

                          ...List.generate(splitRows.length, (sIdx) {
                            final row = splitRows[sIdx];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: TextFormField(
                                            controller: row.qtyCtrl,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly
                                            ],
                                            decoration: InputDecoration(
                                              labelText: 'Accepted Qty *',
                                              isDense: true,
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 8),
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          flex: 3,
                                          child: TextFormField(
                                            controller: row.tagCtrl,
                                            decoration: InputDecoration(
                                              labelText:
                                                  'Batch Ref (PO-linked)',
                                              isDense: true,
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 8),
                                            ),
                                          ),
                                        ),
                                        if (splitRows.length > 1)
                                          IconButton(
                                            icon: const Icon(
                                                Icons.remove_circle_outline,
                                                color: Colors.red,
                                                size: 20),
                                            onPressed: () =>
                                                _removeSplitBatchRow(pid, sIdx),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.calendar_month_rounded,
                                            size: 16, color: Colors.teal),
                                        const SizedBox(width: 4),
                                        Text(
                                          row.expiryDate != null
                                              ? 'Expiry: ${DateFormat('MMM d, yyyy').format(row.expiryDate!)}'
                                              : 'No Expiry Date Set',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: row.expiryDate ??
                                                  DateTime.now().add(
                                                      const Duration(days: 30)),
                                              firstDate: DateTime.now(),
                                              lastDate: DateTime.now().add(
                                                  const Duration(days: 1095)),
                                            );
                                            if (picked != null) {
                                              setState(() =>
                                                  row.expiryDate = picked);
                                            }
                                          },
                                          child: Text(
                                            row.expiryDate != null
                                                ? 'Change Date'
                                                : 'Set Expiry',
                                            style:
                                                const TextStyle(fontSize: 10),
                                          ),
                                        ),
                                        if (row.expiryDate != null)
                                          IconButton(
                                            icon: const Icon(Icons.clear,
                                                size: 14),
                                            onPressed: () {
                                              setState(
                                                  () => row.expiryDate = null);
                                            },
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),

                          const SizedBox(height: 8),

                          // REJECTED QTY & REASON ROW
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _rejectedQtyCtrls[pid],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Rejected Qty',
                                    isDense: true,
                                    prefixIcon: const Icon(Icons.block_rounded,
                                        size: 16, color: Colors.red),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _rejectionReasons[pid],
                                  decoration: InputDecoration(
                                    labelText: 'Rejection Reason',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                  ),
                                  items: _rejectionReasonOptions.map((r) {
                                    return DropdownMenuItem(
                                      value: r,
                                      child: Text(r,
                                          style: const TextStyle(fontSize: 11)),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(
                                          () => _rejectionReasons[pid] = val);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Live Remaining Balance Indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Accepted Now: $acceptedNow units',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal),
                              ),
                              Text(
                                remainingAfter > 0
                                    ? 'New Remaining: $remainingAfter units (Backorder)'
                                    : 'Line Item Fully Received!',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: remainingAfter > 0
                                      ? Colors.orange.shade900
                                      : Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),

              const SizedBox(height: 16),

              // Completed Section Collapsible
              if (completedItems.isNotEmpty) ...[
                InkWell(
                  onTap: () {
                    setState(
                        () => _showCompletedSection = !_showCompletedSection);
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
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLow,
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
                                    fontWeight: FontWeight.bold, fontSize: 13),
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

              const SizedBox(height: 16),

              // STICKY BOTTOM SUMMARY BAR
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Accepted Now:',
                            style: TextStyle(fontSize: 12)),
                        Text(
                          '$totalAcceptedNow units',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Actual Delivery Cost:',
                            style: TextStyle(fontSize: 12)),
                        Text(
                          formatCurrency(actualDeliveryCostNow),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade900,
                          ),
                        ),
                      ],
                    ),
                    if (itemsMovingToBackorder > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Moving to Backorder:',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.orange.shade900)),
                          Text(
                            '$itemsMovingToBackorder item line(s) remaining',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action Buttons: Confirm & Save Delivery vs Close Short
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
                      onPressed: _submitDelivery,
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
                          'CLOSE SHORT (CANCEL REMAINING)',
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          final bool? closed = await CloseShortModal.show(
                              context, widget.purchaseOrder);
                          if (closed == true && mounted) {
                            nav.pop();
                          }
                        },
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
