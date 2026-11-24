import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../config/theme.dart';
import '../utils/format.dart';

/// Material 3 Data Table Widget displaying all active & historical FIFO batches
/// for a selected product in the Admin Inventory Management view.
class BatchDetailsTable extends StatefulWidget {
  final Product product;
  final List<ProductBatch> batches;
  final bool showOnlyActive;
  final Function(ProductBatch batch)? onBatchTap;
  final String? Function(ProductBatch batch)? poNumberResolver;
  final String? Function(ProductBatch batch)? supplierNameResolver;

  const BatchDetailsTable({
    super.key,
    required this.product,
    required this.batches,
    this.showOnlyActive = true,
    this.onBatchTap,
    this.poNumberResolver,
    this.supplierNameResolver,
  });

  @override
  State<BatchDetailsTable> createState() => _BatchDetailsTableState();
}

class _BatchDetailsTableState extends State<BatchDetailsTable> {
  int _sortColumnIndex = 2; // Default sort by Date Arrived (Primary FIFO Key)
  bool _sortAscending = true;
  bool _filterActiveOnly = true;

  @override
  void initState() {
    super.initState();
    _filterActiveOnly = widget.showOnlyActive;
  }

  List<ProductBatch> _getProcessedBatches() {
    List<ProductBatch> list = List.from(widget.batches);

    if (_filterActiveOnly) {
      list = list.where((b) => b.isActive).toList();
    }

    list.sort((a, b) {
      int comparison = 0;
      switch (_sortColumnIndex) {
        case 0: // Batch ID
          comparison = a.batchId.compareTo(b.batchId);
          break;
        case 1: // Date Purchased
          comparison = a.datePurchased.compareTo(b.datePurchased);
          break;
        case 2: // Date Arrived (FIFO)
          comparison = ProductBatch.compareFifo(a, b);
          break;
        case 3: // Remaining / Initial Qty
          comparison = a.remainingQty.compareTo(b.remainingQty);
          break;
        case 4: // Unit Cost
          comparison = a.costPrice.compareTo(b.costPrice);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;

    final DateTime now = DateTime.now();
    final activeSorted = widget.batches
        .where((b) => b.isSellableAt(now))
        .toList()
      ..sort(ProductBatch.compareFifo);
    final String? oldestActiveBatchId =
        activeSorted.isNotEmpty ? activeSorted.first.batchId : null;

    final processedBatches = _getProcessedBatches();
    final totalActiveStock =
        ProductBatch.sumSellableStock(widget.batches, now: now);
    final expiredWithQtyCount = widget.batches
        .where((b) => b.isExpiredAt(now) && b.remainingQty > 0)
        .length;
    final depletedCount = widget.batches
        .where((b) =>
            !b.isSellableAt(now) && !(b.isExpiredAt(now) && b.remainingQty > 0))
        .length;

    final totalNearExpiryCount =
        activeSorted.where((b) => b.isNearExpiration).length;
    final totalExpiredCount = expiredWithQtyCount;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side:
            BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Total Sellable FIFO Stock: $totalActiveStock ${widget.product.unit} • ${activeSorted.length} Active'
                        '${totalExpiredCount > 0 ? ', $totalExpiredCount Expired' : ''}'
                        ', $depletedCount Depleted',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                FilterChip(
                  label: Text(_filterActiveOnly
                      ? 'Active Only'
                      : 'All (Incl. Depleted)'),
                  selected: _filterActiveOnly,
                  onSelected: (val) => setState(() => _filterActiveOnly = val),
                  avatar: Icon(
                    _filterActiveOnly ? Icons.filter_alt : Icons.filter_alt_off,
                    size: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (totalNearExpiryCount > 0 || totalExpiredCount > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: totalExpiredCount > 0
                      ? theme.colorScheme.error.withValues(alpha: 0.1)
                      : semantic.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: totalExpiredCount > 0
                        ? theme.colorScheme.error.withValues(alpha: 0.3)
                        : semantic.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      totalExpiredCount > 0
                          ? Icons.error_outline
                          : Icons.warning_amber_rounded,
                      color: totalExpiredCount > 0
                          ? theme.colorScheme.error
                          : semantic.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        totalExpiredCount > 0
                            ? 'Warning: $totalExpiredCount batch(es) already expired! $totalNearExpiryCount batch(es) expiring soon (< 30 days).'
                            : 'Attention: $totalNearExpiryCount batch(es) expiring within 30 days.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: totalExpiredCount > 0
                              ? theme.colorScheme.error
                              : semantic.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (processedBatches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.layers_clear_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No batches found for this product.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  headingRowColor: WidgetStateProperty.all(
                    theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                  ),
                  dataRowMinHeight: 54,
                  dataRowMaxHeight: 64,
                  horizontalMargin: 16,
                  columnSpacing: 20,
                  columns: [
                    DataColumn(
                      label: const Text('PO / Batch Ref & Supplier'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('Date Purchased'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('Date Arrived (FIFO)'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(
                      numeric: true,
                      label: const Text('Remaining / Initial'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(
                      numeric: true,
                      label: const Text('Unit Cost'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    const DataColumn(label: Text('FIFO Queue Status')),
                  ],
                  rows: processedBatches.map((batch) {
                    return _buildDataRow(
                      context,
                      batch,
                      theme,
                      isOldestActive: batch.isActive &&
                          batch.batchId == oldestActiveBatchId,
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  DataRow _buildDataRow(
    BuildContext context,
    ProductBatch batch,
    ThemeData theme, {
    required bool isOldestActive,
  }) {
    final purchasedStr = DateFormat('MMM dd, yyyy').format(batch.datePurchased);
    final arrivedStr = DateFormat('MMM dd, yyyy').format(batch.dateArrived);
    final denomInitial = batch.initialQty >= batch.remainingQty
        ? batch.initialQty
        : batch.remainingQty;

    return DataRow(
      color: isOldestActive
          ? WidgetStateProperty.all(Colors.green.withValues(alpha: 0.06))
          : null,
      onSelectChanged:
          widget.onBatchTap != null ? (_) => widget.onBatchTap!(batch) : null,
      cells: [
        DataCell(
          Builder(builder: (_) {
            final resolvedPo =
                widget.poNumberResolver?.call(batch) ?? batch.poNumber;
            final resolvedSupplier =
                widget.supplierNameResolver?.call(batch) ?? batch.supplierName;
            final primaryRef =
                batch.primaryReference(resolvedPoNumber: resolvedPo);
            final subLabel =
                (resolvedSupplier != null && resolvedSupplier.trim().isNotEmpty)
                    ? resolvedSupplier.trim()
                    : (resolvedPo != null && resolvedPo.trim().isNotEmpty
                        ? 'Batch: ${batch.displayBatchId}'
                        : 'Unlinked Supplier');
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primaryRef,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                Text(
                  subLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          }),
        ),
        DataCell(Text(purchasedStr, style: const TextStyle(fontSize: 12))),
        DataCell(
          Text(
            arrivedStr,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isOldestActive ? FontWeight.bold : FontWeight.normal,
              color: isOldestActive ? Colors.green.shade800 : null,
            ),
          ),
        ),
        DataCell(
          Text(
            '${batch.remainingQty} / $denomInitial ${widget.product.unit}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
              color: !batch.isActive
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
          ),
        ),
        DataCell(
          Text(
            formatPeso(batch.costPrice),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(_buildFifoBadge(batch, isOldestActive: isOldestActive)),
      ],
    );
  }

  Widget _buildFifoBadge(ProductBatch batch, {required bool isOldestActive}) {
    final bool isExpiredWithQty = batch.isExpired && batch.remainingQty > 0;
    final bool isDepleted = !batch.isSellable;
    final Color color = isExpiredWithQty
        ? Colors.red.shade700
        : (isDepleted
            ? Colors.grey.shade600
            : (isOldestActive ? Colors.green.shade700 : Colors.blue.shade700));
    final String label = isExpiredWithQty
        ? 'EXPIRED'
        : (isDepleted
            ? 'DEPLETED'
            : (isOldestActive ? 'SELLING NOW (OLDEST)' : 'QUEUED (NEWER)'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
