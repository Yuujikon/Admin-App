import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/models/product.dart';
import 'package:gdc_admin_app/utils/inventory_math.dart';

void main() {
  group('planBatchDepletion (FEFO + FIFO)', () {
    test('depletes earliest-expiring batch first (FEFO), regardless of createdAt', () {
      final batchLaterExpiryCreatedEarlier = ProductBatch(
        batchId: 'B-OLD-LONG',
        productId: 'prod-1',
        quantityRemaining: 5,
        unitCost: 10.0,
        dateReceived: DateTime(2026, 1, 1),
        expirationDate: DateTime(2026, 12, 31),
      );
      final batchSoonerExpiryCreatedLater = ProductBatch(
        batchId: 'B-NEW-SHORT',
        productId: 'prod-1',
        quantityRemaining: 2,
        unitCost: 12.0,
        dateReceived: DateTime(2026, 2, 1),
        expirationDate: DateTime(2026, 4, 1),
      );

      final product = Product(
        id: 'prod-1',
        name: 'Fresh Milk',
        category: 'Fresh',
        price: 20.0,
        costPrice: 11.0,
        stock: 7,
        batches: [batchLaterExpiryCreatedEarlier, batchSoonerExpiryCreatedLater],
      );

      final plan = planBatchDepletion(product, 3);

      // Should take 2 from B-NEW-SHORT (cost 12) + 1 from B-OLD-LONG (cost 10)
      expect(plan.depletedBatches.length, 2);
      expect(plan.depletedBatches[0].batchId, 'B-NEW-SHORT');
      expect(plan.depletedBatches[0].quantity, 2);
      expect(plan.depletedBatches[1].batchId, 'B-OLD-LONG');
      expect(plan.depletedBatches[1].quantity, 1);

      expect(plan.totalCogs, closeTo(34.0, 0.001));
      expect(plan.weightedUnitCost, closeTo(34.0 / 3, 0.001));

      // Exactly 4 units remain across batches (7 - 3 = 4, no double deduction)
      expect(plan.remainingBatches.length, 1);
      expect(plan.remainingBatches.first.id, 'B-OLD-LONG');
      expect(plan.remainingBatches.first.quantity, 4);

      // Pure function: original product batches unchanged
      expect(product.batches[0].quantity, 5);
      expect(product.batches[1].quantity, 2);
    });

    test('uses FIFO tie-breaker when batches have no expiryDate', () {
      final older = ProductBatch(
        batchId: 'B1',
        productId: 'p2',
        quantityRemaining: 4,
        unitCost: 8.0,
        dateReceived: DateTime(2026, 1, 5),
      );
      final newer = ProductBatch(
        batchId: 'B2',
        productId: 'p2',
        quantityRemaining: 6,
        unitCost: 9.0,
        dateReceived: DateTime(2026, 1, 20),
      );

      final product = Product(
        id: 'p2',
        name: 'Sardines',
        category: 'Canned Goods',
        price: 25.0,
        costPrice: 8.5,
        stock: 10,
        batches: [newer, older],
      );

      final plan = planBatchDepletion(product, 5);

      expect(plan.depletedBatches[0].batchId, 'B1');
      expect(plan.depletedBatches[0].quantity, 4);
      expect(plan.depletedBatches[1].batchId, 'B2');
      expect(plan.depletedBatches[1].quantity, 1);
      expect(plan.remainingBatches.single.quantity, 5);
      expect(plan.totalCogs, closeTo(41.0, 0.001));
    });

    test('falls back to effectiveUnitCost when sale exceeds tracked batches', () {
      final batch = ProductBatch(
        batchId: 'B1',
        productId: 'p3',
        quantityRemaining: 2,
        unitCost: 15.0,
        dateReceived: DateTime(2026, 1, 1),
      );

      final product = Product(
        id: 'p3',
        name: 'Soap',
        category: 'Personal Care',
        price: 30.0,
        costPrice: 18.0,
        stock: 5,
        batches: [batch],
      );

      final plan = planBatchDepletion(product, 4);

      expect(plan.depletedBatches.length, 2);
      expect(plan.depletedBatches[0].batchId, 'B1');
      expect(plan.depletedBatches[0].quantity, 2);
      expect(plan.depletedBatches[1].batchId, 'fallback-unbatched');
      expect(plan.depletedBatches[1].quantity, 2);
      expect(plan.depletedBatches[1].unitCost, 18.0);
      expect(plan.totalCogs, closeTo(66.0, 0.001));
      expect(plan.remainingBatches, isEmpty);
      expect(plan.batchQuantitiesDeducted, equals({'B1': 2}));
    });
  });
}
