import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/loss_record.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../services/inventory_batch_service.dart';
import '../utils/format.dart';
import 'premium_components.dart';
import 'action_warning_dialog.dart';

class BatchAuditSheet extends StatefulWidget {
  final Product product;
  const BatchAuditSheet({super.key, required this.product});

  @override
  State<BatchAuditSheet> createState() => _BatchAuditSheetState();
}

class _BatchAuditSheetState extends State<BatchAuditSheet> {
  final InventoryBatchService _batchService = InventoryBatchService();
  bool _showDepleted = false;
  bool _ensuredLegacy = false;

  @override
  void initState() {
    super.initState();
    _initLegacyFallback();
  }

  Future<void> _initLegacyFallback() async {
    if (_ensuredLegacy) return;
    _ensuredLegacy = true;
    if (widget.product.stock > 0 && !widget.product.hasVariants) {
      try {
        await _batchService.ensureLegacyBatchIfNeeded(widget.product.id);
      } catch (e) {
        debugPrint('Legacy batch auto-init skipped: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final procurement = context.watch<ProcurementProvider>();
    Product p = widget.product;
    try {
      p = inventory.products.firstWhere((prod) => prod.id == widget.product.id);
    } catch (_) {}

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: StreamBuilder<List<ProductBatch>>(
        stream: _batchService.batchesStream(p.id),
        builder: (context, snapshot) {
          // Use authoritative subcollection stream once loaded; only fall back
          // to embedded mirror while waiting for initial snapshot.
          final List<ProductBatch> allBatches = snapshot.hasData
              ? List<ProductBatch>.from(snapshot.data!)
              : List<ProductBatch>.from(p.batches);
          allBatches.sort(ProductBatch.compareFifo);

          final DateTime now = DateTime.now();
          final List<ProductBatch> activeBatches =
              allBatches.where((b) => b.isSellableAt(now)).toList();
          final List<ProductBatch> expiredBatches = allBatches
              .where((b) =>
                  !b.isSellableAt(now) &&
                  b.isExpiredAt(now) &&
                  b.remainingQty > 0)
              .toList();
          final List<ProductBatch> depletedBatches = allBatches
              .where((b) =>
                  !b.isSellableAt(now) &&
                  !(b.isExpiredAt(now) && b.remainingQty > 0))
              .toList();
          final List<ProductBatch> inactiveBatches = [
            ...expiredBatches,
            ...depletedBatches,
          ];

          final List<ProductBatch> visibleBatches = _showDepleted
              ? [...activeBatches, ...inactiveBatches]
              : activeBatches;

          final int totalActiveStock =
              ProductBatch.sumSellableStock(allBatches, now: now);
          final int totalExpiredUnits =
              expiredBatches.fold<int>(0, (sum, b) => sum + b.remainingQty);
          final bool hasUnmarkedExpired =
              expiredBatches.any((b) => b.status == BatchStatus.active);
          final bool isStockOutOfSync = snapshot.hasData &&
              !p.hasVariants &&
              (p.stock != totalActiveStock ||
                  p.reservedStock < 0 ||
                  hasUnmarkedExpired);
          final String? oldestActiveId =
              activeBatches.isNotEmpty ? activeBatches.first.batchId : null;

          return SingleChildScrollView(
            child: MaxWidthContainer(
              maxWidth: MaxWidthContainer.formMaxWidth,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'FIFO Batch Queue • ${activeBatches.length} Active'
                              '${expiredBatches.isNotEmpty ? ', ${expiredBatches.length} Expired ($totalExpiredUnits ${p.unit})' : ''}'
                              ', ${depletedBatches.length} Depleted'
                              '${p.totalReservedStock > 0 ? ' • ${p.totalReservedStock} Reserved' : ''}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$totalActiveStock ${p.unit} Sellable',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Toggleable Depleted/Expired Filter Chip + Legend
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _legendChip(
                        'SELLING NOW (OLDEST)',
                        Colors.green.shade700,
                      ),
                      _legendChip(
                        'QUEUED (NEWER)',
                        Colors.blue.shade700,
                      ),
                      if (expiredBatches.isNotEmpty)
                        _legendChip(
                          'EXPIRED (${expiredBatches.length})',
                          Colors.red.shade700,
                        ),
                      if (inactiveBatches.isNotEmpty)
                        FilterChip(
                          label: Text(
                            _showDepleted
                                ? 'Hide Inactive (${inactiveBatches.length})'
                                : 'Show Expired/Depleted (${inactiveBatches.length})',
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: _showDepleted,
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) =>
                              setState(() => _showDepleted = val),
                        ),
                    ],
                  ),
                  const Divider(height: 20),

                  if (isStockOutOfSync)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                Colors.orange.shade700.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.sync_problem_rounded,
                              color: Colors.orange.shade800, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p.reservedStock < 0
                                  ? 'Stored stock (${p.stock}) or reserved (${p.reservedStock}) is out of sync with valid active batches ($totalActiveStock ${p.unit}).'
                                  : hasUnmarkedExpired
                                      ? 'Stored stock (${p.stock} ${p.unit}) or expired batch statuses need reconciliation (valid sellable: $totalActiveStock ${p.unit}).'
                                      : 'Stored parent stock (${p.stock} ${p.unit}) is out of sync with valid active batches ($totalActiveStock ${p.unit}).',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: () async {
                              final res =
                                  await inventory.reconcileProductStock(p.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Reconciled "${p.name}": ${res.newStock} ${p.unit} sellable, ${res.newReservedStock} reserved ✅'),
                                    backgroundColor: Colors.green.shade700,
                                  ),
                                );
                              }
                            },
                            child: const Text('Sync Now',
                                style: TextStyle(fontSize: 11.5)),
                          ),
                        ],
                      ),
                    ),

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      allBatches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (visibleBatches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.layers_clear_outlined,
                                size: 36, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              activeBatches.isEmpty &&
                                      inactiveBatches.isNotEmpty
                                  ? 'No valid sellable batches. Toggle "Show Expired/Depleted" above to inspect ${inactiveBatches.length} inactive batch(es).'
                                  : 'No inventory batches recorded yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visibleBatches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final b = visibleBatches[index];
                        final bool isSellable = b.isSellableAt(now);
                        final bool isOldestActive =
                            isSellable && b.batchId == oldestActiveId;
                        final bool isDepleted = !isSellable;
                        final String? resolvedPo =
                            procurement.resolvePoNumberForBatch(b);
                        final String? resolvedSupplier =
                            procurement.resolveSupplierNameForBatch(
                          b,
                          suppliers: inventory.suppliers,
                          fallbackProductSupplierId: p.supplierId,
                        );
                        final bool hasValidSupplierDoc = b.hasValidSupplier &&
                            inventory.suppliers
                                .any((s) => s.id == b.supplierId!.trim());

                        return _buildBatchCard(
                          context: context,
                          product: p,
                          batch: b,
                          isOldestActive: isOldestActive,
                          isDepleted: isDepleted,
                          resolvedPoNumber: resolvedPo,
                          resolvedSupplierName: resolvedSupplier,
                          hasValidSupplierLink: hasValidSupplierDoc,
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _legendChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildBatchCard({
    required BuildContext context,
    required Product product,
    required ProductBatch batch,
    required bool isOldestActive,
    required bool isDepleted,
    String? resolvedPoNumber,
    String? resolvedSupplierName,
    bool hasValidSupplierLink = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final bool isExpired = batch.isExpiredAt(now);
    final bool isExpiredWithQty = isExpired && batch.remainingQty > 0;
    final bool isNearExpiry = batch.expiryDate != null &&
        !isExpired &&
        batch.expiryDate!.difference(now).inDays <= 30;

    final Color badgeColor = isExpiredWithQty
        ? Colors.red.shade700
        : (isDepleted
            ? Colors.grey.shade600
            : (isOldestActive ? Colors.green.shade700 : Colors.blue.shade700));
    final String badgeLabel = isExpiredWithQty
        ? 'EXPIRED'
        : (isDepleted
            ? 'DEPLETED'
            : (isOldestActive ? 'SELLING NOW (OLDEST)' : 'QUEUED (NEWER)'));

    final String? formattedPo =
        (resolvedPoNumber != null && resolvedPoNumber.trim().isNotEmpty)
            ? ProductBatch.formatPoNumber(resolvedPoNumber)
            : null;
    final String primaryRef =
        batch.primaryReference(resolvedPoNumber: resolvedPoNumber);
    final String displayCode = batch.displayBatchId;
    final bool hasSeparateBatchCode =
        formattedPo != null && displayCode != formattedPo;

    final String supplierLabel =
        (resolvedSupplierName != null && resolvedSupplierName.trim().isNotEmpty)
            ? resolvedSupplierName.trim()
            : 'Unlinked Supplier';

    final String? drRef = (batch.invoiceNumber != null &&
            batch.invoiceNumber!.trim().isNotEmpty &&
            batch.invoiceNumber!.trim() != 'LEGACY-INIT')
        ? batch.invoiceNumber!.trim()
        : null;

    final int denomInitial = batch.initialQty >= batch.remainingQty
        ? batch.initialQty
        : batch.remainingQty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOldestActive
            ? Colors.green.withValues(alpha: 0.06)
            : (isDepleted
                ? colorScheme.surfaceContainerLowest
                : colorScheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOldestActive
              ? Colors.green.shade600.withValues(alpha: 0.55)
              : colorScheme.outline.withValues(alpha: isDepleted ? 0.2 : 0.35),
          width: isOldestActive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (formattedPo != null) ...[
                          Icon(
                            Icons.receipt_long_rounded,
                            size: 14,
                            color: isDepleted
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          primaryRef,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: isDepleted
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: badgeColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (!hasValidSupplierLink)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.orange.shade700
                                  .withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          'UNLINKED SUPPLIER',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${batch.remainingQty} / $denomInitial ${product.unit}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: isDepleted ? Colors.grey : Colors.green.shade800,
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (val) {
                  if (val == 'spoil') {
                    _logBatchLossDialog(
                      context,
                      product,
                      batch,
                      displayRef: primaryRef,
                    );
                  } else if (val == 'link_supplier') {
                    _linkSupplierDialog(context, product, batch);
                  } else if (val == 'delete') {
                    _deleteBatchDialog(
                      context,
                      product,
                      batch,
                      displayRef: primaryRef,
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'link_supplier',
                    child: Row(
                      children: [
                        Icon(Icons.storefront_outlined,
                            size: 16, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Link / Change Supplier'),
                      ],
                    ),
                  ),
                  if (!isDepleted)
                    const PopupMenuItem(
                      value: 'spoil',
                      child: Row(
                        children: [
                          Icon(Icons.remove_circle_outline,
                              size: 16, color: Colors.orange),
                          SizedBox(width: 8),
                          Text('Mark Loss / Spoiled'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete Batch'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (hasSeparateBatchCode || formattedPo == null || drRef != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                if (hasSeparateBatchCode)
                  Text(
                    'Batch ID: $displayCode',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (formattedPo == null)
                  Text(
                    batch.isLegacyUuidId
                        ? 'Legacy Initial / Direct Stock (No PO)'
                        : 'Direct / Manual Stock (No PO)',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (drRef != null)
                  Text(
                    'DR/Ref: $drRef',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _metaItem(
                Icons.storefront_outlined,
                'Supplier: $supplierLabel',
                colorScheme.onSurfaceVariant,
              ),
              _metaItem(
                Icons.payments_outlined,
                'Unit Cost: ${formatPeso(batch.costPrice)}',
                colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _metaItem(
                Icons.shopping_bag_outlined,
                'Purchased: ${DateFormat('MMM d, yyyy').format(batch.datePurchased)}',
                colorScheme.onSurfaceVariant,
              ),
              _metaItem(
                Icons.local_shipping_outlined,
                'Arrived: ${DateFormat('MMM d, yyyy').format(batch.dateArrived)}',
                isOldestActive
                    ? Colors.green.shade800
                    : colorScheme.onSurfaceVariant,
                bold: isOldestActive,
              ),
              if (batch.expiryDate != null)
                _metaItem(
                  Icons.event_outlined,
                  isExpired
                      ? 'Expired ${DateFormat('MMM d, yyyy').format(batch.expiryDate!)}'
                      : 'Exp: ${DateFormat('MMM d, yyyy').format(batch.expiryDate!)}',
                  isExpired
                      ? Colors.red
                      : (isNearExpiry
                          ? Colors.orange.shade800
                          : colorScheme.onSurfaceVariant),
                  bold: isExpired || isNearExpiry,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaItem(IconData icon, String label, Color color,
      {bool bold = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _logBatchLossDialog(
    BuildContext context,
    Product product,
    ProductBatch batch, {
    String? displayRef,
  }) {
    final qtyCtrl = TextEditingController(text: '1');
    final refLabel = displayRef ?? batch.displayBatchId;
    LossType lossType = LossType.expired;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Text('Mark Batch Stock Write-off'),
          content: Container(
            width: 440,
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Product: ${product.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    'Ref: $refLabel • Available: ${batch.remainingQty} ${product.unit}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Quantity Lost/Spoiled',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<LossType>(
                  initialValue: lossType,
                  decoration: const InputDecoration(
                      labelText: 'Reason for Loss',
                      border: OutlineInputBorder()),
                  items: LossType.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(t.name.toUpperCase())))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setSt(() => lossType = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final qty = int.tryParse(qtyCtrl.text) ?? 0;
                if (qty <= 0 || qty > batch.remainingQty) return;

                final confirm = await ActionWarningDialog.show(
                  context,
                  title: 'Confirm Stock Write-off?',
                  message:
                      'Are you sure you want to write off $qty ${product.unit} of "${product.name}" from $refLabel?',
                  confirmLabel: 'Write-off Stock',
                  cancelLabel: 'Cancel',
                  severity: ActionWarningSeverity.danger,
                  icon: Icons.inventory_2_outlined,
                  details: [
                    'Product: ${product.name}',
                    'Batch Ref: $refLabel',
                    'Quantity to write off: $qty ${product.unit}',
                    'Reason: ${lossType.name}',
                  ],
                );
                if (!confirm) return;
                if (!context.mounted) return;

                await _batchService.writeOffFromBatch(
                  productId: product.id,
                  productName: product.name,
                  batchId: batch.batchId,
                  qtyLost: qty,
                  lossType: lossType.name,
                  notes: 'Write-off from $refLabel (${batch.batchId})',
                );

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
              child: const Text('Confirm Write-off'),
            ),
          ],
        ),
      ),
    );
  }

  void _linkSupplierDialog(
    BuildContext context,
    Product product,
    ProductBatch batch,
  ) {
    final inventory = context.read<InventoryProvider>();
    final suppliers = inventory.suppliers;
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No suppliers registered. Please add a supplier first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String? selectedSupplierId = suppliers.any((s) => s.id == batch.supplierId)
        ? batch.supplierId
        : (suppliers.any((s) => s.id == product.supplierId)
            ? product.supplierId
            : suppliers.first.id);

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Text('Link Supplier to Batch'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Batch: ${batch.displayBatchId} (${product.name})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedSupplierId,
                  decoration: const InputDecoration(
                    labelText: 'Supplier *',
                    border: OutlineInputBorder(),
                  ),
                  items: suppliers
                      .map((s) => DropdownMenuItem<String>(
                            value: s.id,
                            child:
                                Text(s.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) => setSt(() => selectedSupplierId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedSupplierId == null || selectedSupplierId!.isEmpty) {
                  return;
                }
                await _batchService.updateBatchAtomic(
                  productId: product.id,
                  batchId: batch.batchId,
                  supplierId: selectedSupplierId,
                  settings: inventory.settings,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('Batch supplier updated & stock synced ✅'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Save Link'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteBatchDialog(
    BuildContext context,
    Product product,
    ProductBatch batch, {
    required String displayRef,
  }) async {
    final inventory = context.read<InventoryProvider>();
    final confirm = await ActionWarningDialog.show(
      context,
      title: 'Delete Inventory Batch?',
      message:
          'Deleting $displayRef will permanently remove this batch and deduct ${batch.remainingQty} ${product.unit} from "${product.name}" main inventory stock.',
      confirmLabel: 'Delete Batch',
      cancelLabel: 'Cancel',
      severity: ActionWarningSeverity.danger,
      icon: Icons.delete_forever_rounded,
      details: [
        'Product: ${product.name}',
        'Batch Ref: $displayRef',
        'Remaining Qty Removed: ${batch.remainingQty} ${product.unit}',
      ],
    );
    if (!confirm) return;
    final syncedStock = await _batchService.deleteBatchAtomic(
      productId: product.id,
      batchId: batch.batchId,
      reason: 'Admin deleted batch from View Batches',
      settings: inventory.settings,
    );
    if (mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
              'Deleted batch $displayRef. Synced stock: $syncedStock ${product.unit}'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }
}
