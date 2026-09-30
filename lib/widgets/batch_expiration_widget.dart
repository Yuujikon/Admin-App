import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';

class _ExpiringBatchItem {
  final Product product;
  final ProductBatch batch;
  final int daysUntilExpiry;

  _ExpiringBatchItem({
    required this.product,
    required this.batch,
    required this.daysUntilExpiry,
  });
}

/// Standalone Material 3 Dashboard Widget for FEFO (First Expire, First Out) Batch Expiration Alerts
class BatchExpirationWidget extends StatelessWidget {
  const BatchExpirationWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final products = inventory.products;
    final now = DateTime.now();

    final List<_ExpiringBatchItem> expiringBatches = [];

    try {
      for (final product in products) {
        if (product.status != ProductStatus.published) continue;

        for (final batch in product.batches) {
          final DateTime? expiry = batch.expiryDate;
          if (batch.quantity > 0 && expiry != null) {
            final days = expiry.difference(now).inDays;
            if (days <= 30) {
              expiringBatches.add(_ExpiringBatchItem(
                product: product,
                batch: batch,
                daysUntilExpiry: days,
              ));
            }
          }
        }
      }

      expiringBatches.sort((a, b) => a.daysUntilExpiry.compareTo(b.daysUntilExpiry));
    } catch (e) {
      debugPrint('BatchExpirationWidget error: $e');
    }

    if (expiringBatches.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.orange.shade50.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.orange.shade300.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_busy_rounded, color: Colors.orange.shade900, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚠️ FEFO Batch Expiration Warnings (< 30 Days)',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade800,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${expiringBatches.length} BATCHES',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: expiringBatches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = expiringBatches[index];
                final p = item.product;
                final b = item.batch;
                final days = item.daysUntilExpiry;

                final bool isCritical = days <= 7;
                final DateTime? batchExpiry = b.expiryDate;
                final String expiryText = batchExpiry != null
                    ? DateFormat('MMM d, yyyy').format(batchExpiry)
                    : 'No Expiry Date';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(
                    'Expires: $expiryText • Batch Qty: ${b.quantity} ${p.unit}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isCritical ? Colors.red.shade100 : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isCritical ? Colors.red : Colors.orange),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          days <= 0 ? 'EXPIRES TODAY!' : 'In $days days',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            color: isCritical ? Colors.red.shade900 : Colors.orange.shade900,
                          ),
                        ),
                        Text(
                          '${b.quantity} ${p.unit} at risk',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isCritical ? Colors.red.shade800 : Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
