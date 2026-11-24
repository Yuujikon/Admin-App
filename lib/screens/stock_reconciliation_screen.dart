import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../services/inventory_batch_service.dart';
import '../utils/format.dart';
import '../widgets/action_warning_dialog.dart';
import '../widgets/premium_components.dart';

class StockReconciliationScreen extends StatefulWidget {
  final Product? initialProduct;

  const StockReconciliationScreen({super.key, this.initialProduct});

  @override
  State<StockReconciliationScreen> createState() =>
      _StockReconciliationScreenState();
}

class _StockReconciliationScreenState extends State<StockReconciliationScreen> {
  final InventoryBatchService _batchService = InventoryBatchService();
  Product? _selectedProduct;
  final Map<String, TextEditingController> _batchCountControllers = {};
  List<ProductBatch> _latestLiveBatches = const [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
  }

  void _clearControllers() {
    for (final controller in _batchCountControllers.values) {
      controller.dispose();
    }
    _batchCountControllers.clear();
  }

  void _resetControllersToLiveBatches(List<ProductBatch> batches) {
    _clearControllers();
    for (final b in batches) {
      _batchCountControllers[b.batchId] =
          TextEditingController(text: b.remainingQty.toString());
    }
  }

  void _ensureControllersForBatches(List<ProductBatch> batches) {
    final activeIds = batches.map((b) => b.batchId).toSet();
    final staleIds = _batchCountControllers.keys
        .where((id) => !activeIds.contains(id))
        .toList();
    for (final id in staleIds) {
      _batchCountControllers.remove(id)?.dispose();
    }
    for (final b in batches) {
      _batchCountControllers.putIfAbsent(
        b.batchId,
        () => TextEditingController(text: b.remainingQty.toString()),
      );
    }
  }

  @override
  void dispose() {
    _clearControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final procurement = context.watch<ProcurementProvider>();
    final products = inventory.products;

    if (_selectedProduct != null) {
      try {
        _selectedProduct =
            products.firstWhere((p) => p.id == _selectedProduct!.id);
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Audit & Reconciliation'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.sync_problem_rounded, size: 18),
            label: const Text('Sync & Orphan Audit'),
            onPressed: () => _showGlobalAuditDialog(context, inventory),
          ),
          if (_selectedProduct != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reset Physical Counts',
              onPressed: () => setState(
                () => _resetControllersToLiveBatches(_latestLiveBatches),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthContainer(
          maxWidth: 900,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Selector
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Product for Shelf Count Audit',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return Autocomplete<Product>(
                            displayStringForOption: (Product p) => p.name,
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) {
                                return products;
                              }
                              final q = textEditingValue.text.toLowerCase();
                              return products.where((p) =>
                                  p.name.toLowerCase().contains(q) ||
                                  (p.barcode?.toLowerCase().contains(q) ??
                                      false) ||
                                  p.category.toLowerCase().contains(q));
                            },
                            onSelected: (Product p) {
                              setState(() {
                                _selectedProduct = p;
                                _latestLiveBatches = const [];
                                _clearControllers();
                              });
                            },
                            fieldViewBuilder: (context, textController,
                                focusNode, onFieldSubmitted) {
                              if (_selectedProduct != null &&
                                  !focusNode.hasFocus &&
                                  (textController.text.isEmpty ||
                                      textController.text !=
                                          _selectedProduct!.name)) {
                                textController.text = _selectedProduct!.name;
                              }
                              return TextFormField(
                                controller: textController,
                                focusNode: focusNode,
                                decoration: InputDecoration(
                                  hintText: 'Search or choose product...',
                                  prefixIcon:
                                      const Icon(Icons.inventory_2_outlined),
                                  suffixIcon: _selectedProduct != null ||
                                          textController.text.isNotEmpty
                                      ? IconButton(
                                          icon:
                                              const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            textController.clear();
                                            setState(() {
                                              _selectedProduct = null;
                                              _latestLiveBatches = const [];
                                              _clearControllers();
                                            });
                                          },
                                        )
                                      : const Icon(Icons.arrow_drop_down),
                                ),
                                onChanged: (val) {
                                  if (_selectedProduct != null &&
                                      val != _selectedProduct!.name) {
                                    setState(() {
                                      _selectedProduct = null;
                                      _latestLiveBatches = const [];
                                      _clearControllers();
                                    });
                                  }
                                },
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 8,
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: Container(
                                    width: constraints.maxWidth,
                                    constraints:
                                        const BoxConstraints(maxHeight: 280),
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(
                                              height: 1,
                                              indent: 12,
                                              endIndent: 12),
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                        final Product option =
                                            options.elementAt(index);
                                        final bool isSelected =
                                            option.id == _selectedProduct?.id;
                                        return ListTile(
                                          dense: true,
                                          selected: isSelected,
                                          selectedTileColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withValues(alpha: 0.2),
                                          leading: Icon(
                                            Icons.inventory_2_outlined,
                                            size: 20,
                                            color: isSelected
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : Colors.grey.shade600,
                                          ),
                                          title: Text(
                                            option.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                          ),
                                          subtitle: Text(
                                            '${option.category} • Stock: ${option.totalStock} ${option.unit}${option.barcode != null ? " • Barcode: ${option.barcode}" : ""}',
                                            style:
                                                const TextStyle(fontSize: 11),
                                          ),
                                          trailing: Text(
                                            formatPeso(option.price),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                          onTap: () => onSelected(option),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (_selectedProduct == null)
                const Expanded(
                  child: PremiumEmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'No Product Selected',
                    subtitle:
                        'Choose a product above to inspect expected batches and reconcile physical counts.',
                  ),
                )
              else
                Expanded(
                  child: StreamBuilder<List<ProductBatch>>(
                    stream: _batchService.batchesStream(_selectedProduct!.id),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final liveBatches = List<ProductBatch>.from(
                        snapshot.hasData
                            ? snapshot.data!
                            : _selectedProduct!.batches,
                      )..sort(ProductBatch.compareFifo);

                      _latestLiveBatches = liveBatches;
                      _ensureControllersForBatches(liveBatches);

                      return Column(
                        children: [
                          Expanded(
                            child: ListView(
                              children: [
                                _buildProductSummaryHeader(
                                  _selectedProduct!,
                                  liveBatches,
                                  inventory,
                                ),
                                const SizedBox(height: 16),
                                _buildBatchesAuditList(
                                  _selectedProduct!,
                                  liveBatches,
                                  inventory,
                                  procurement,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildActionFooter(
                            _selectedProduct!,
                            liveBatches,
                            inventory,
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductSummaryHeader(
    Product p,
    List<ProductBatch> batches,
    InventoryProvider inventory,
  ) {
    final int systemTotal = InventoryBatchService.sumActiveBatchStock(batches);
    int physicalTotal = 0;

    for (final b in batches) {
      final ctrl = _batchCountControllers[b.batchId];
      final val = int.tryParse(ctrl?.text ?? '') ?? b.remainingQty;
      physicalTotal += val;
    }

    final int discrepancy = physicalTotal - systemTotal;
    final Color discColor = discrepancy == 0
        ? Colors.green.shade700
        : (discrepancy < 0
            ? Theme.of(context).colorScheme.error
            : Colors.orange.shade800);
    final bool hasParentDrift = p.variants.isEmpty &&
        (p.stock != systemTotal ||
            p.reservedStock < 0 ||
            batches.any((b) => b.isExpired && b.status == BatchStatus.active));

    return Column(
      children: [
        if (hasParentDrift)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.shade400),
            ),
            child: Row(
              children: [
                Icon(Icons.sync_problem_rounded,
                    color: Colors.amber.shade900, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Parent stock (${p.stock} ${p.unit}, reserved ${p.reservedStock}) is out of sync with valid sellable batches ($systemTotal ${p.unit}).',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final res =
                                await inventory.reconcileProductStock(p.id);
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Reconciled "${p.name}": ${res.newStock} ${p.unit} sellable, ${res.newReservedStock} reserved (${res.expiredBatchesMarked} expired marked).'),
                                  backgroundColor: Colors.green.shade700,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Sync failed: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: const Text('Sync Now'),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryColumn('Expected Batch Qty', '$systemTotal ${p.unit}',
                  Colors.blue.shade800),
              Container(
                  width: 1,
                  height: 36,
                  color: Theme.of(context).colorScheme.outlineVariant),
              _summaryColumn('Actual Physical Qty', '$physicalTotal ${p.unit}',
                  Theme.of(context).colorScheme.onSurface),
              Container(
                  width: 1,
                  height: 36,
                  color: Theme.of(context).colorScheme.outlineVariant),
              _summaryColumn(
                  'Discrepancy Variance',
                  '${discrepancy > 0 ? '+' : ''}$discrepancy ${p.unit}',
                  discColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _buildBatchesAuditList(
    Product p,
    List<ProductBatch> batches,
    InventoryProvider inventory,
    ProcurementProvider procurement,
  ) {
    if (batches.isEmpty) {
      return const PremiumEmptyState(
        icon: Icons.assignment_late_outlined,
        title: 'No Batches Found',
        subtitle: 'This product has no delivery batches recorded.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Live Batches (FIFO Sorted • ${batches.length} total)',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: batches.length,
          itemBuilder: (context, index) {
            final b = batches[index];
            final ctrl = _batchCountControllers[b.batchId] ??=
                TextEditingController(text: b.remainingQty.toString());
            final int physicalVal = int.tryParse(ctrl.text) ?? b.remainingQty;
            final int batchDiff = physicalVal - b.remainingQty;

            final now = DateTime.now();
            final bool isExpired =
                b.expiryDate != null && b.expiryDate!.isBefore(now);
            final int daysRemaining =
                b.expiryDate?.difference(now).inDays ?? 999;
            final resolvedPo = procurement.resolvePoNumberForBatch(b);
            final supplierName = procurement.resolveSupplierNameForBatch(
                  b,
                  suppliers: inventory.suppliers,
                  fallbackProductSupplierId: p.supplierId,
                ) ??
                'Unlinked Supplier';
            final bool isUnlinkedSupplier = !b.hasValidSupplier;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: batchDiff != 0
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isExpired
                                ? Colors.red
                                : (b.isDepleted ? Colors.grey : Colors.green))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isExpired
                            ? Icons.event_busy_rounded
                            : Icons.inventory_2_rounded,
                        color: isExpired
                            ? Colors.red
                            : (b.isDepleted
                                ? Colors.grey.shade600
                                : Colors.green.shade700),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  b.primaryReference(
                                      resolvedPoNumber: resolvedPo),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isUnlinkedSupplier) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'UNLINKED',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Supplier: $supplierName • System: ${b.remainingQty} ${p.unit}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isUnlinkedSupplier
                                  ? Colors.orange.shade900
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ),
                          Text(
                            'Received: ${DateFormat('MMM d, yyyy').format(b.dateArrived)} • Cost: ${formatPeso(b.costPrice)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                          if (b.expiryDate != null)
                            Text(
                              isExpired
                                  ? 'EXPIRED on ${DateFormat('MMM d, yyyy').format(b.expiryDate!)}'
                                  : 'Expires in $daysRemaining days (${DateFormat('MMM d, yyyy').format(b.expiryDate!)})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isExpired
                                    ? Colors.red
                                    : (daysRemaining <= 30
                                        ? Colors.orange.shade800
                                        : Colors.grey),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        textAlign: TextAlign.center,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Shelf Count',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          suffixText: p.unit,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionFooter(
    Product p,
    List<ProductBatch> batches,
    InventoryProvider inventory,
  ) {
    int totalDiff = 0;
    for (final b in batches) {
      final ctrl = _batchCountControllers[b.batchId];
      final val = int.tryParse(ctrl?.text ?? '') ?? b.remainingQty;
      totalDiff += (val - b.remainingQty);
    }

    return Center(
      child: PrimaryButton(
        onPressed: (_isProcessing || totalDiff == 0)
            ? null
            : () => _reconcileStock(p, batches, inventory),
        isLoading: _isProcessing,
        icon: Icons.check_circle_rounded,
        backgroundColor: totalDiff < 0
            ? Theme.of(context).colorScheme.error
            : Colors.green.shade700,
        foregroundColor: Colors.white,
        minWidth: 200,
        maxWidth: 350,
        child: Text(_isProcessing
            ? 'Processing Reconciliation...'
            : (totalDiff == 0
                ? 'PHYSICAL COUNT MATCHES SYSTEM'
                : 'RESOLVE & ADJUST STOCK (${totalDiff > 0 ? '+' : ''}$totalDiff ${p.unit})')),
      ),
    );
  }

  Future<void> _reconcileStock(
    Product product,
    List<ProductBatch> liveBatches,
    InventoryProvider inventory,
  ) async {
    final Map<String, int> physicalQtyByBatchId = {};
    final int systemTotal =
        InventoryBatchService.sumActiveBatchStock(liveBatches);
    int previewNetAdj = 0;

    for (final b in liveBatches) {
      final ctrl = _batchCountControllers[b.batchId];
      final newQty = int.tryParse(ctrl?.text ?? '') ?? b.remainingQty;
      physicalQtyByBatchId[b.batchId] = newQty;
      previewNetAdj += (newQty - b.remainingQty);
    }

    final confirm = await ActionWarningDialog.show(
      context,
      title: 'Confirm Stock Reconciliation?',
      message:
          'You are about to atomically reconcile batches for "${product.name}" by ${previewNetAdj > 0 ? '+' : ''}$previewNetAdj ${product.unit}.',
      confirmLabel: 'Reconcile Stock',
      cancelLabel: 'Cancel',
      severity: previewNetAdj < 0
          ? ActionWarningSeverity.danger
          : ActionWarningSeverity.warning,
      icon: Icons.inventory_2_rounded,
      details: [
        'Product: ${product.name}',
        'Current Active Batch Total: $systemTotal ${product.unit}',
        'New Reconciled Total: ${(systemTotal + previewNetAdj).clamp(0, 999999)} ${product.unit}',
        'All supplier & PO metadata on every batch will be preserved.',
        if (previewNetAdj < 0)
          'Shortage of ${previewNetAdj.abs()} ${product.unit} will be logged atomically as inventory loss.',
      ],
    );

    if (!confirm || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      final syncedTotal = await inventory.reconcileProductBatches(
        productId: product.id,
        physicalQtyByBatchId: physicalQtyByBatchId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reconciled "${product.name}" atomically (Stock: $syncedTotal ${product.unit}).',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error reconciling stock: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _showGlobalAuditDialog(
    BuildContext context,
    InventoryProvider inventory,
  ) async {
    InventoryReconciliationReport? report;
    String? error;
    bool loading = true;
    bool applying = false;
    String? fallbackSupplierId;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (loading && report == null && error == null) {
              inventory.auditAndReconcileInventory(dryRun: true).then((r) {
                if (ctx.mounted) {
                  setDialogState(() {
                    report = r;
                    loading = false;
                  });
                }
              }).catchError((Object e) {
                if (ctx.mounted) {
                  setDialogState(() {
                    error = e.toString();
                    loading = false;
                  });
                }
              });
            }

            final currentReport = report;
            final suppliers = inventory.suppliers;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.sync_problem_rounded, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Global Batch & Supplier Audit'),
                  ),
                ],
              ),
              content: SizedBox(
                width: 560,
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text(
                                'Scanning suppliers, batches, and inventory stock...'),
                          ],
                        ),
                      )
                    : error != null
                        ? Text('Audit failed: $error',
                            style: const TextStyle(color: Colors.red))
                        : currentReport == null
                            ? const SizedBox.shrink()
                            : SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Scanned ${currentReport.productsScanned} products and ${currentReport.batchesScanned} batches.',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                    ),
                                    const SizedBox(height: 12),
                                    if (!currentReport.hasIssues)
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.green.shade300),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.check_circle_rounded,
                                                color: Colors.green.shade700),
                                            const SizedBox(width: 10),
                                            const Expanded(
                                              child: Text(
                                                'All batches have valid supplier links and all inventory stock counts match active batch totals.',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else ...[
                                      Text(
                                        'Out-of-Sync Products (${currentReport.stockDrifts.length})',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                      const SizedBox(height: 6),
                                      if (currentReport.stockDrifts.isEmpty)
                                        const Text(
                                          'No stock count mismatches found.',
                                          style: TextStyle(
                                              fontSize: 12, color: Colors.grey),
                                        )
                                      else
                                        ...currentReport.stockDrifts
                                            .take(20)
                                            .map(
                                              (d) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 3),
                                                child: Text(
                                                  '• ${d.productName}: stock ${d.storedStock} → ${d.activeBatchSum} (${d.delta >= 0 ? '+' : ''}${d.delta})'
                                                  '${d.hasReservedDrift ? ', reserved ${d.storedReservedStock} → ${d.expectedReservedStock}' : ''}'
                                                  '${d.expiredBatchesDetected > 0 ? ', ${d.expiredBatchesDetected} expired' : ''}'
                                                  '${d.embeddedMirrorOutOfSync ? ' [mirror stale]' : ''}',
                                                  style: const TextStyle(
                                                      fontSize: 12),
                                                ),
                                              ),
                                            ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'Orphan / Unlinked Batches (${currentReport.orphanBatches.length})',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                      const SizedBox(height: 6),
                                      if (currentReport.orphanBatches.isEmpty)
                                        const Text(
                                          'All batches are linked to valid suppliers.',
                                          style: TextStyle(
                                              fontSize: 12, color: Colors.grey),
                                        )
                                      else ...[
                                        ...currentReport.orphanBatches
                                            .take(20)
                                            .map(
                                              (o) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 3),
                                                child: Text(
                                                  '• ${o.productName} [${o.batchId}] (qty ${o.remainingQty}): ${o.reason}'
                                                  '${o.suggestedSupplierName != null ? ' → Auto-link: ${o.suggestedSupplierName}' : ''}',
                                                  style: const TextStyle(
                                                      fontSize: 12),
                                                ),
                                              ),
                                            ),
                                        if (suppliers.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          DropdownButtonFormField<String?>(
                                            initialValue: fallbackSupplierId,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Optional Fallback Supplier (for unresolvable orphans)',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                            items: [
                                              const DropdownMenuItem<String?>(
                                                value: null,
                                                child: Text(
                                                    'None (only auto-link via PO/Product)'),
                                              ),
                                              ...suppliers.map(
                                                (s) =>
                                                    DropdownMenuItem<String?>(
                                                  value: s.id,
                                                  child: Text(s.name),
                                                ),
                                              ),
                                            ],
                                            onChanged: applying
                                                ? null
                                                : (val) => setDialogState(() {
                                                      fallbackSupplierId = val;
                                                    }),
                                          ),
                                        ],
                                      ],
                                    ],
                                    if (!currentReport.dryRun) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        'Applied fixes: ${currentReport.productsStockFixed} stock resynced, ${currentReport.reservedStockFixed} reserved repaired, ${currentReport.expiredBatchesMarked} expired marked, ${currentReport.batchesSupplierFixed} suppliers linked.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
              ),
              actions: [
                TextButton(
                  onPressed: applying ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Close'),
                ),
                if (currentReport != null &&
                    currentReport.hasIssues &&
                    currentReport.dryRun)
                  FilledButton.icon(
                    icon: applying
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: Text(
                        applying ? 'Applying...' : 'Apply Fixes Atomically'),
                    onPressed: applying
                        ? null
                        : () async {
                            setDialogState(() => applying = true);
                            try {
                              final applied =
                                  await inventory.auditAndReconcileInventory(
                                dryRun: false,
                                defaultFallbackSupplierId: fallbackSupplierId,
                              );
                              if (ctx.mounted) {
                                setDialogState(() {
                                  report = applied;
                                  applying = false;
                                });
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setDialogState(() {
                                  error = e.toString();
                                  applying = false;
                                });
                              }
                            }
                          },
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
