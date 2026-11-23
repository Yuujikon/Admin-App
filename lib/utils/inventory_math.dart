import '../models/batch.dart';
import '../models/order.dart';
import '../models/product.dart';

/// Result of computing FEFO/FIFO batch depletion for a product sale.
class BatchDepletionPlan {
  /// Batches still holding positive quantity after depletion.
  final List<ProductBatch> remainingBatches;

  /// Audit trail of batch segments consumed by this depletion.
  final List<BatchDepletionRecord> depletedBatches;

  /// Map of `batchId -> quantityDeducted` for real batches (excludes fallback).
  final Map<String, int> batchQuantitiesDeducted;

  /// Total cost of goods sold across all depleted segments.
  final double totalCogs;

  /// Weighted average unit cost across the requested quantity.
  final double weightedUnitCost;

  const BatchDepletionPlan({
    required this.remainingBatches,
    required this.depletedBatches,
    required this.batchQuantitiesDeducted,
    required this.totalCogs,
    required this.weightedUnitCost,
  });
}

/// Pure FEFO (First Expired, First Out) with FIFO tie-break batch depletion planner.
/// Does NOT mutate [product] or its batches.
BatchDepletionPlan planBatchDepletion(Product product, int qty) {
  if (qty <= 0) {
    return BatchDepletionPlan(
      remainingBatches: List<ProductBatch>.from(product.batches),
      depletedBatches: const [],
      batchQuantitiesDeducted: const {},
      totalCogs: 0.0,
      weightedUnitCost: product.effectiveUnitCost,
    );
  }

  final List<ProductBatch> sorted = List<ProductBatch>.from(product.batches)
    ..sort((a, b) {
      final aExp = a.expiryDate;
      final bExp = b.expiryDate;
      if (aExp != null && bExp != null) {
        final cmp = aExp.compareTo(bExp);
        if (cmp != 0) return cmp;
      } else if (aExp != null && bExp == null) {
        return -1; // Expiring batches consumed before non-expiring batches
      } else if (aExp == null && bExp != null) {
        return 1;
      }
      return a.createdAt.compareTo(b.createdAt); // FIFO tie-breaker
    });

  int remainingToDeduct = qty;
  final List<ProductBatch> remainingBatches = [];
  final List<BatchDepletionRecord> depletedBatches = [];
  final Map<String, int> batchQuantitiesDeducted = {};
  double totalCogs = 0.0;

  for (final batch in sorted) {
    if (batch.quantity <= 0) continue;

    if (remainingToDeduct <= 0) {
      remainingBatches.add(batch);
      continue;
    }

    if (batch.quantity > remainingToDeduct) {
      final int deducted = remainingToDeduct;
      totalCogs += deducted * batch.unitCost;
      depletedBatches.add(BatchDepletionRecord(
        batchId: batch.id,
        quantity: deducted,
        unitCost: batch.unitCost,
      ));
      if (batch.id.isNotEmpty) {
        batchQuantitiesDeducted[batch.id] =
            (batchQuantitiesDeducted[batch.id] ?? 0) + deducted;
      }
      remainingBatches.add(batch.copyWith(
        quantityRemaining: batch.quantity - deducted,
      ));
      remainingToDeduct = 0;
    } else {
      final int deducted = batch.quantity;
      totalCogs += deducted * batch.unitCost;
      depletedBatches.add(BatchDepletionRecord(
        batchId: batch.id,
        quantity: deducted,
        unitCost: batch.unitCost,
      ));
      if (batch.id.isNotEmpty) {
        batchQuantitiesDeducted[batch.id] =
            (batchQuantitiesDeducted[batch.id] ?? 0) + deducted;
      }
      remainingToDeduct -= deducted;
    }
  }

  if (remainingToDeduct > 0) {
    final double fallbackCost = product.effectiveUnitCost;
    totalCogs += remainingToDeduct * fallbackCost;
    depletedBatches.add(BatchDepletionRecord(
      batchId: 'fallback-unbatched',
      quantity: remainingToDeduct,
      unitCost: fallbackCost,
    ));
  }

  final double weightedUnitCost =
      qty > 0 ? (totalCogs / qty) : product.effectiveUnitCost;

  return BatchDepletionPlan(
    remainingBatches: remainingBatches,
    depletedBatches: depletedBatches,
    batchQuantitiesDeducted: batchQuantitiesDeducted,
    totalCogs: totalCogs,
    weightedUnitCost: weightedUnitCost,
  );
}

/// Resolves unit cost to record for an inventory loss/write-off (prefers COGS over retail price).
double computeRefundLossUnitCost({
  required double itemCostPrice,
  double? productCostPrice,
  required double retailPrice,
}) {
  if (itemCostPrice > 0) return itemCostPrice;
  if (productCostPrice != null && productCostPrice > 0) {
    return productCostPrice;
  }
  return retailPrice;
}

/// Computes the Firestore field deltas to restock (or deduct) physical inventory,
/// ensuring variant restocks always update BOTH variant stock and top-level `stock`.
Map<String, int> computeStockRestockDeltas({
  String? variantId,
  required int qty,
}) {
  if (variantId != null && variantId.isNotEmpty) {
    return {
      'variants.$variantId.stock': qty,
      'stock': qty,
    };
  }
  return {'stock': qty};
}

/// Safely truncates an ID string without risking a RangeError on short IDs.
String safeShortId(String id, [int maxLen = 5]) {
  if (id.length <= maxLen) return id;
  return id.substring(0, maxLen);
}
