import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/supplier.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../providers/auth_provider.dart';
import '../services/audit_log_service.dart';
import '../shared/services/admin_messaging_service.dart';
import '../utils/format.dart';
import '../utils/po_pdf_printer.dart';
import 'document_dispatch_widgets.dart';
import 'supplier_details_card.dart';
import 'supplier_quick_edit_sheet.dart';

/// Modal Bottom Sheet for creating, validating, previewing, and dispatching
/// a new Supplier Purchase Order (PO).
class PoBuilderSheet extends StatefulWidget {
  final Supplier? initialSupplier;

  const PoBuilderSheet({
    super.key,
    this.initialSupplier,
  });

  /// Displays the [PoBuilderSheet] modal.
  static Future<T?> show<T>({
    required BuildContext context,
    Supplier? initialSupplier,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PoBuilderSheet(initialSupplier: initialSupplier),
    );
  }

  @override
  State<PoBuilderSheet> createState() => _PoBuilderSheetState();
}

class _PoBuilderSheetState extends State<PoBuilderSheet> {
  final _formKey = GlobalKey<FormState>();

  Supplier? _selectedSupplier;
  SupplierSnapshot? _supplierSnapshot;
  bool _hydratingSupplier = false;
  String _storeEmail = '';

  late final TextEditingController _poNumberCtrl;
  DateTime? _requestedDeliveryDate;

  final List<PurchaseOrderItem> _items = [];
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _costControllers = {};

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final todayStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final randSuffix = (100 + (DateTime.now().millisecond % 900)).toString();
    _poNumberCtrl = TextEditingController(text: 'PO-$todayStr-$randSuffix');
    _requestedDeliveryDate = DateTime.now().add(const Duration(days: 3));
    _storeEmail = AdminMessagingService().storeEmailSync;

    AdminMessagingService().resolveStoreEmail().then((email) {
      if (mounted && email.isNotEmpty) {
        setState(() => _storeEmail = email);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final suppliers = context.read<InventoryProvider>().suppliers;
      if (widget.initialSupplier != null) {
        _setSupplier(widget.initialSupplier!);
      } else if (suppliers.isNotEmpty) {
        _setSupplier(suppliers.first);
      }
    });
  }

  Future<void> _setSupplier(Supplier supplier) async {
    final inventory = context.read<InventoryProvider>();

    setState(() {
      _selectedSupplier = supplier;
      _supplierSnapshot = supplier.toSnapshot();
      _hydratingSupplier = true;

      if (_items.isEmpty) {
        final supplierProds = inventory.products
            .where((p) => p.supplierId == supplier.id)
            .toList();
        for (var p in supplierProds) {
          _addItemInternal(p);
        }
      }
    });

    // Hydrate the authoritative latest supplier profile directly from Firestore
    final fresh = await inventory.fetchSupplierFresh(supplier.id);
    if (!mounted) return;
    if (_selectedSupplier?.id == supplier.id) {
      setState(() {
        if (fresh != null) {
          _selectedSupplier = fresh;
          _supplierSnapshot = fresh.toSnapshot();
        }
        _hydratingSupplier = false;
      });
    }
  }

  void _addItemInternal(Product product) {
    if (_items.any((i) => i.productId == product.id)) return;

    final suggested = product.calculateSuggestedRestock();
    final int qty = suggested > 0 ? suggested : 1;
    final double cost = product.costPrice > 0 ? product.costPrice : 0.0;

    _items.add(PurchaseOrderItem(
      productId: product.id,
      productName: product.name,
      sku: product.barcode ?? '',
      orderedQty: qty,
      unitCost: cost,
    ));
    _qtyControllers[product.id] = TextEditingController(text: qty.toString());
    _costControllers[product.id] =
        TextEditingController(text: cost > 0 ? cost.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _poNumberCtrl.dispose();
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    for (var ctrl in _costControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addItem(Product product) {
    if (_items.any((i) => i.productId == product.id)) return;
    setState(() => _addItemInternal(product));
  }

  void _removeItem(String productId) {
    setState(() {
      _items.removeWhere((i) => i.productId == productId);
      _qtyControllers[productId]?.dispose();
      _qtyControllers.remove(productId);
      _costControllers[productId]?.dispose();
      _costControllers.remove(productId);
    });
  }

  List<PurchaseOrderItem> _collectFinalItems() {
    final List<PurchaseOrderItem> finalItems = [];
    for (var item in _items) {
      final qtyText = _qtyControllers[item.productId]?.text.trim() ?? '1';
      final costText = _costControllers[item.productId]?.text.trim() ?? '0';

      final int qty = int.tryParse(qtyText) ?? item.orderedQty;
      final double cost = double.tryParse(costText) ?? item.unitCost;

      finalItems.add(item.copyWith(
        orderedQty: qty > 0 ? qty : 1,
        unitCost: cost >= 0 ? cost : 0.0,
      ));
    }
    return finalItems;
  }

  Future<void> _openQuickEditSupplier() async {
    final currentSnapshot =
        _supplierSnapshot ?? _selectedSupplier?.toSnapshot();
    if (currentSnapshot == null) return;

    final updated = await SupplierQuickEditSheet.show(
      context: context,
      initialSnapshot: currentSnapshot,
      initialAutoNotifyLowStock: _selectedSupplier?.autoNotifyLowStock ?? true,
    );

    if (updated != null && mounted) {
      setState(() {
        _supplierSnapshot = updated;
        if (_selectedSupplier != null &&
            _selectedSupplier!.id == updated.supplierId) {
          _selectedSupplier = updated.toSupplier(
            autoNotifyLowStock: _selectedSupplier!.autoNotifyLowStock,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Supplier details updated for this Purchase Order.'),
          backgroundColor: Colors.teal.shade800,
        ),
      );
    }
  }

  Future<void> _previewPoPdf() async {
    final snapshot = _supplierSnapshot;
    if (snapshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a supplier first.')),
      );
      return;
    }

    final validation = snapshot.validateForDispatch();
    if (!validation.isValid) {
      await _showValidationGateBlockedDialog(validation);
      return;
    }

    final finalItems = _collectFinalItems();
    if (finalItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Add at least one product item before previewing PDF.')),
      );
      return;
    }

    final previewPo = PurchaseOrder(
      id: 'preview',
      poNumber: _poNumberCtrl.text.trim().isNotEmpty
          ? _poNumberCtrl.text.trim()
          : 'PO-PREVIEW',
      rfqId: '',
      supplierId: snapshot.supplierId,
      supplierName: snapshot.supplierName,
      supplierSnapshot: snapshot,
      status: PurchaseOrderStatus.sent,
      orderDate: DateTime.now(),
      requestedDeliveryDate: _requestedDeliveryDate,
      items: finalItems,
    );

    await showDocumentPdfPreviewModal(
      context: context,
      title: 'Purchase Order PDF Preview',
      fileName: 'Purchase_Order_${previewPo.poNumber}.pdf',
      buildPdf: () => PoPdfPrinter.generatePoPdf(
        previewPo,
        _selectedSupplier,
        supplierSnapshot: snapshot,
        enforceValidation: true,
      ),
    );
  }

  Future<void> _showValidationGateBlockedDialog(
    SupplierValidationResult validation,
  ) async {
    final fixNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.gpp_bad_rounded, color: Colors.red.shade800),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Supplier Details Incomplete',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PDF generation and email dispatch are blocked until these required supplier fields are fixed:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...validation.blockingIssues.map(
              (issue) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        issue.message,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text('Complete Supplier Details'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (fixNow == true && mounted) {
      await _openQuickEditSupplier();
    }
  }

  void _showAddProductsDialog() {
    final inventory = context.read<InventoryProvider>();
    List<Product> availableProducts = inventory.products;

    if (_selectedSupplier != null) {
      final supplierProducts = availableProducts
          .where((p) => p.supplierId == _selectedSupplier!.id)
          .toList();
      if (supplierProducts.isNotEmpty) {
        availableProducts = supplierProducts;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = availableProducts.where((p) {
              return query.isEmpty ||
                  p.name.toLowerCase().contains(query.toLowerCase()) ||
                  (p.barcode != null && p.barcode!.contains(query));
            }).toList();

            return AlertDialog(
              title: const Text('Add Products to PO'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search products by name or barcode...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (val) => setDialogState(() => query = val),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 300,
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching products.'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, idx) {
                                final p = filtered[idx];
                                final isAdded =
                                    _items.any((i) => i.productId == p.id);
                                return ListTile(
                                  dense: true,
                                  title: Text(p.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                    'Stock: ${p.totalStock} | Cost: ${formatCurrency(p.costPrice)}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: isAdded
                                      ? const Icon(Icons.check_circle_rounded,
                                          color: Colors.green)
                                      : IconButton(
                                          icon: const Icon(
                                              Icons.add_circle_outline_rounded,
                                              color: Colors.teal),
                                          onPressed: () {
                                            _addItem(p);
                                            setDialogState(() {});
                                          },
                                        ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitPo({bool saveAsDraft = false}) async {
    if (_formKey.currentState?.validate() != true) return;
    if (_selectedSupplier == null || _supplierSnapshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a supplier.')),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please add at least one product item to the PO.')),
      );
      return;
    }

    final SupplierSnapshot activeSnapshot = _supplierSnapshot!;

    // Pre-Flight Validation Gate for non-draft PDF generation & email dispatch
    if (!saveAsDraft) {
      final validation = activeSnapshot.validateForDispatch();
      if (!validation.isValid) {
        await _showValidationGateBlockedDialog(validation);
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final finalItems = _collectFinalItems();
      final procurement = context.read<ProcurementProvider>();
      final auth = context.read<AppAuthProvider>();
      final userId = auth.currentUser?.email ?? 'Admin';

      bool isDuplicateOverride = false;

      // Soft Guard Pre-Flight Check (if committing active order, not draft)
      if (!saveAsDraft) {
        final cutoff = DateTime.now().subtract(const Duration(hours: 72));
        final activePos = procurement.purchaseOrders.where((p) {
          return p.supplierId == activeSnapshot.supplierId &&
              p.status != PurchaseOrderStatus.draft &&
              p.status != PurchaseOrderStatus.cancelled &&
              p.orderDate.isAfter(cutoff);
        }).toList();

        if (activePos.isNotEmpty) {
          final confirmed = await _checkSoftGuardAndConfirm(
            activePos: activePos,
            newItems: finalItems,
            supplierName: activeSnapshot.supplierName,
          );

          if (!confirmed) {
            setState(() => _saving = false);
            return;
          }
          isDuplicateOverride = true;
        }
      }

      final draftPo = PurchaseOrder(
        id: const Uuid().v4(),
        poNumber: _poNumberCtrl.text.trim(),
        rfqId: '',
        supplierId: activeSnapshot.supplierId,
        supplierName: activeSnapshot.supplierName,
        supplierSnapshot:
            activeSnapshot.copyWith(snapshottedAt: DateTime.now()),
        status:
            saveAsDraft ? PurchaseOrderStatus.draft : PurchaseOrderStatus.sent,
        orderDate: DateTime.now(),
        requestedDeliveryDate: _requestedDeliveryDate,
        items: finalItems,
        duplicateOverride: isDuplicateOverride,
        overrideByUserId: isDuplicateOverride ? userId : null,
      );

      final PurchaseOrder persistedPo =
          await procurement.createPurchaseOrder(draftPo);

      if (isDuplicateOverride) {
        await AuditLogService().logAction(
          module: 'Procurement',
          action: 'OVERRIDE_DUPLICATE_PO',
          targetId: persistedPo.id,
          targetName: 'PO ${persistedPo.poNumber}',
          summary:
              'User $userId overrode duplicate order soft guard warning for PO #${persistedPo.poNumber} (${activeSnapshot.supplierName}).',
        );
      }

      if (!mounted) return;

      if (saveAsDraft) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PO #${persistedPo.poNumber} saved as Draft.'),
            backgroundColor: Colors.teal.shade800,
          ),
        );
        return;
      }

      // Unified step-by-step dispatch pipeline:
      // Validating Data -> Generating PO PDF -> Sending to Supplier & Store
      final dispatchResult = await DispatchProgressDialog.run(
        context: context,
        documentTitle: 'Dispatch PO #${persistedPo.poNumber}',
        onExecute: (onStage) =>
            AdminMessagingService().dispatchPurchaseOrderWithPdf(
          po: persistedPo,
          supplier: _selectedSupplier,
          supplierSnapshot: persistedPo.supplierSnapshot ?? activeSnapshot,
          storeEmailOverride: _storeEmail,
          onStageChanged: onStage,
        ),
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (dispatchResult != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(dispatchResult.summaryMessage),
            backgroundColor: dispatchResult.isFullSuccess
                ? Colors.teal.shade800
                : Colors.orange.shade900,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create Purchase Order: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _checkSoftGuardAndConfirm({
    required List<PurchaseOrder> activePos,
    required List<PurchaseOrderItem> newItems,
    required String supplierName,
  }) async {
    final newProductIds = newItems.map((i) => i.productId).toSet();
    final conflictingPos = <PurchaseOrder>[];
    final overlappingProductsMap = <String, List<PurchaseOrderItem>>{};

    for (var po in activePos) {
      final overlaps =
          po.items.where((i) => newProductIds.contains(i.productId)).toList();
      if (overlaps.isNotEmpty) {
        conflictingPos.add(po);
        overlappingProductsMap[po.poNumber] = overlaps;
      }
    }

    if (conflictingPos.isEmpty) {
      if (activePos.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Notice: An active order was placed with $supplierName in the last 72h (No item overlaps detected).'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return true;
    }

    final bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded,
                  color: Colors.amber.shade900, size: 24),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Overlapping Order Warning',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active order(s) for $supplierName already exist with matching products placed within the last 72 hours:',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...conflictingPos.map((po) {
                final overlaps = overlappingProductsMap[po.poNumber] ?? [];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('PO #${po.poNumber}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                          Text(po.status.displayName,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900)),
                        ],
                      ),
                      Text(
                        'Sent: ${DateFormat('MMM d, h:mm a').format(po.orderDate)}',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      const Divider(height: 10),
                      ...overlaps.map((item) => Text(
                            '• ${item.productName}: ${item.orderedQty} units ordered (${item.remainingQty} pending)',
                            style: const TextStyle(fontSize: 11),
                          )),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel Order'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade900,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Send Anyway'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    return proceed == true;
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final procurement = context.watch<ProcurementProvider>();
    final suppliers = inventory.suppliers;

    // Ensure Dropdown selected value matches current provider list instance by id
    final Supplier? dropdownValue = _selectedSupplier == null
        ? null
        : suppliers.cast<Supplier?>().firstWhere(
              (s) => s?.id == _selectedSupplier!.id,
              orElse: () => null,
            );

    final SupplierSnapshot? activeSnapshot = _supplierSnapshot;
    final SupplierValidationResult? validation =
        activeSnapshot?.validateForDispatch();
    final bool canDispatch = activeSnapshot != null &&
        (validation?.isValid ?? false) &&
        _items.isNotEmpty;

    final List<PurchaseOrder> activeDuplicatePos = _selectedSupplier != null
        ? procurement.purchaseOrders
            .where((po) =>
                po.supplierId == _selectedSupplier!.id && po.status.isActive)
            .toList()
        : [];

    double totalValue = 0.0;
    for (var item in _items) {
      final qtyText = _qtyControllers[item.productId]?.text ?? '1';
      final costText = _costControllers[item.productId]?.text ?? '0';
      final q = int.tryParse(qtyText) ?? item.orderedQty;
      final c = double.tryParse(costText) ?? item.unitCost;
      totalValue += (q * c);
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.shopping_bag_rounded,
                        color: Colors.teal.shade800, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create Purchase Order (PO)',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(
                            'Verify supplier snapshot, preview PDF & dispatch to supplier + store',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
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

            // Main Form Fields
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // DUPLICATE PO GUARD WARNING BANNER
                  if (activeDuplicatePos.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.amber.shade900, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Duplicate Order Warning!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Active ${activeDuplicatePos.first.status.displayName} PO #${activeDuplicatePos.first.poNumber} already exists for ${activeSnapshot?.supplierName ?? "this supplier"} (${activeDuplicatePos.first.totalRemainingQty} units pending).',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Supplier Selector Dropdown
                  DropdownButtonFormField<Supplier>(
                    key: ValueKey(dropdownValue?.id ?? 'none'),
                    initialValue: dropdownValue,
                    decoration: const InputDecoration(
                      labelText: 'Select Supplier *',
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.store_rounded),
                    ),
                    items: suppliers.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text('${s.name} (${s.category})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) _setSupplier(val);
                    },
                    validator: (v) =>
                        v == null ? 'Please select supplier' : null,
                  ),

                  // Structured Supplier Details Card + Inline Missing-Data Warnings + Quick-Edit
                  if (activeSnapshot != null) ...[
                    const SizedBox(height: 14),
                    SupplierDetailsCard(
                      snapshot: activeSnapshot,
                      isHydrating: _hydratingSupplier,
                      title: 'Snapshotted Vendor Profile',
                      onQuickEdit: _openQuickEditSupplier,
                    ),
                    const SizedBox(height: 12),
                    RecipientsPreviewBanner(
                      snapshot: activeSnapshot,
                      storeEmail: _storeEmail,
                      previewButtonLabel: 'Preview PO PDF',
                      onPreviewPdf: _previewPoPdf,
                      onFixSupplier: _openQuickEditSupplier,
                    ),
                  ],

                  const SizedBox(height: 16),

                  // PO Number & Requested Delivery Date Row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _poNumberCtrl,
                          decoration: const InputDecoration(
                            labelText: 'PO Number *',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _requestedDeliveryDate ??
                                  DateTime.now().add(const Duration(days: 3)),
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 180)),
                            );
                            if (picked != null) {
                              setState(() => _requestedDeliveryDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Requested Delivery Date',
                              isDense: true,
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_month_rounded),
                            ),
                            child: Text(
                              _requestedDeliveryDate != null
                                  ? DateFormat('MMM dd, yyyy')
                                      .format(_requestedDeliveryDate!)
                                  : 'Select Date',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Line Items Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Requested Products (${_items.length})',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: _showAddProductsDialog,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Items'),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.teal.shade800),
                      ),
                    ],
                  ),

                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Center(
                        child: Text(
                          'No products added yet. Click "Add Items" above to select products for this PO.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, idx) {
                        final item = _items[idx];
                        final qtyCtrl = _qtyControllers[item.productId]!;
                        final costCtrl = _costControllers[item.productId]!;

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.productName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red, size: 20),
                                    onPressed: () =>
                                        _removeItem(item.productId),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: qtyCtrl,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'Ordered Qty *',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: costCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Est. Unit Price (₱)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            // Bottom Action Footer
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Est. Total Cost:',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(
                        formatCurrency(totalValue),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade800,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed:
                        _saving ? null : () => _submitPo(saveAsDraft: true),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Save Draft'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canDispatch
                          ? Colors.teal.shade800
                          : Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        _saving ? null : () => _submitPo(saveAsDraft: false),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(canDispatch
                            ? Icons.send_rounded
                            : Icons.warning_amber_rounded),
                    label: Text(
                      _saving
                          ? 'Processing...'
                          : (canDispatch
                              ? 'Generate & Dispatch PO'
                              : 'Fix Supplier to Send'),
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
}
