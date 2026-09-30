import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../config/theme.dart';

/// Material 3 Data Table Widget displaying all active & historical FEFO batches
/// for a selected product in the Admin Inventory Management view.
class BatchDetailsTable extends StatefulWidget {
  final Product product;
  final List<ProductBatch> batches;
  final bool showOnlyActive;
  final Function(ProductBatch batch)? onBatchTap;

  const BatchDetailsTable({
    super.key,
    required this.product,
    required this.batches,
    this.showOnlyActive = true,
    this.onBatchTap,
  });

  @override
  State<BatchDetailsTable> createState() => _BatchDetailsTableState();
}

class _BatchDetailsTableState extends State<BatchDetailsTable> {
  int _sortColumnIndex = 1; // Default sort by Expiration Date
  bool _sortAscending = true;
  bool _filterActiveOnly = true;

  @override
  void initState() {
    super.initState();
    _filterActiveOnly = widget.showOnlyActive;
  }

  List<ProductBatch> _getProcessedBatches() {
    List<ProductBatch> list = List.from(widget.batches);

    // Filter zero quantity batches if requested
    if (_filterActiveOnly) {
      list = list.where((b) => b.quantityRemaining > 0).toList();
    }

    // Sort according to selected column
    list.sort((a, b) {
      int comparison = 0;
      switch (_sortColumnIndex) {
        case 0: // Batch ID / Date Received
          comparison = a.dateReceived.compareTo(b.dateReceived);
          break;
        case 1: // Expiration Date (FEFO Primary)
          if (a.expirationDate == null && b.expirationDate == null) {
            comparison = 0;
          } else if (a.expirationDate == null) {
            comparison = 1;
          } else if (b.expirationDate == null) {
            comparison = -1;
          } else {
            comparison = a.expirationDate!.compareTo(b.expirationDate!);
          }
          break;
        case 2: // Quantity Remaining
          comparison = a.quantityRemaining.compareTo(b.quantityRemaining);
          break;
        case 3: // Status / Days Left
          final daysA = a.daysUntilExpiration ?? 99999;
          final daysB = b.daysUntilExpiration ?? 99999;
          comparison = daysA.compareTo(daysB);
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
    final processedBatches = _getProcessedBatches();
    final totalActiveStock = widget.batches
        .where((b) => b.quantityRemaining > 0)
        .fold<int>(0, (sum, b) => sum + b.quantityRemaining);

    final totalNearExpiryCount = widget.batches
        .where((b) => b.quantityRemaining > 0 && b.isNearExpiration)
        .length;

    final totalExpiredCount = widget.batches
        .where((b) => b.quantityRemaining > 0 && b.isExpired)
        .length;

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
            // Header Bar & Product Summary
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
                        'Total FEFO Tracked Stock: $totalActiveStock ${widget.product.unit}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                FilterChip(
                  label:
                      Text(_filterActiveOnly ? 'Active Only' : 'All Batches'),
                  selected: _filterActiveOnly,
                  onSelected: (val) {
                    setState(() {
                      _filterActiveOnly = val;
                    });
                  },
                  avatar: Icon(
                    _filterActiveOnly ? Icons.filter_alt : Icons.filter_alt_off,
                    size: 16,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Expiration Quick Alert Summary Banner (if warnings exist)
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

            // Empty State
            if (processedBatches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.no_photography_outlined,
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
              // Material 3 Data Table
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  headingRowColor: WidgetStateProperty.all(
                    theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                  ),
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 60,
                  horizontalMargin: 16,
                  columnSpacing: 24,
                  columns: [
                    DataColumn(
                      label: const Text('Batch ID / Received'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(
                      label: const Row(
                        children: [
                          Icon(Icons.event, size: 16),
                          SizedBox(width: 4),
                          Text('Expiration Date'),
                        ],
                      ),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(
                      numeric: true,
                      label: const Text('Qty Remaining'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('FEFO Status'),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                  ],
                  rows: processedBatches.map((batch) {
                    return _buildDataRow(context, batch, theme, semantic);
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
    ThemeData theme,
    GdcSemanticColors semantic,
  ) {
    final dateStr = batch.expirationDate != null
        ? DateFormat('MMM dd, yyyy').format(batch.expirationDate!)
        : 'N/A (No Expiry)';

    final receivedStr = DateFormat('MMM dd, yyyy').format(batch.dateReceived);
    final batchDisplayId = batch.batchId.length > 8
        ? batch.batchId.substring(0, 8)
        : (batch.batchId.isEmpty ? 'BATCH-00' : batch.batchId);

    final statusWidget = _buildStatusBadge(batch, theme, semantic);

    return DataRow(
      onSelectChanged:
          widget.onBatchTap != null ? (_) => widget.onBatchTap!(batch) : null,
      cells: [
        // Batch ID & Received Date
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '#$batchDisplayId',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                'Rec: $receivedStr',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Expiration Date
        DataCell(
          Text(
            dateStr,
            style: TextStyle(
              fontWeight: batch.isNearExpiration || batch.isExpired
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: batch.isExpired
                  ? theme.colorScheme.error
                  : (batch.isNearExpiration
                      ? semantic.warning
                      : theme.colorScheme.onSurface),
            ),
          ),
        ),

        // Quantity Remaining
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: batch.quantityRemaining == 0
                  ? theme.colorScheme.outline.withValues(alpha: 0.1)
                  : theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${batch.quantityRemaining} ${widget.product.unit}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: batch.quantityRemaining == 0
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ),

        // Status Visual Indicator
        DataCell(statusWidget),
      ],
    );
  }

  Widget _buildStatusBadge(
      ProductBatch batch, ThemeData theme, GdcSemanticColors semantic) {
    if (batch.quantityRemaining == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_outlined,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              'Depleted',
              style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    final days = batch.daysUntilExpiration;

    if (days == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: semantic.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.all_inclusive, size: 14, color: semantic.info),
            const SizedBox(width: 4),
            Text(
              'Non-perishable',
              style: TextStyle(
                  fontSize: 11,
                  color: semantic.info,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    if (days <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: theme.colorScheme.error.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_outlined,
                size: 14, color: theme.colorScheme.error),
            const SizedBox(width: 4),
            Text(
              'Expired ($days d)',
              style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    if (days <= 30) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: semantic.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: semantic.warning.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 14, color: semantic.warning),
            const SizedBox(width: 4),
            Text(
              'Expires in $days d',
              style: TextStyle(
                  fontSize: 11,
                  color: semantic.warning,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    // Safe / Healthy Batch
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: semantic.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 14, color: semantic.success),
          const SizedBox(width: 4),
          Text(
            'Safe ($days d left)',
            style: TextStyle(
                fontSize: 11,
                color: semantic.success,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
