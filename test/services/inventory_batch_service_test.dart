import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/models/order.dart';
import 'package:gdc_admin_app/models/product.dart';
import 'package:gdc_admin_app/services/inventory_batch_service.dart';

void main() {
  group('ProductBatch model & FIFO comparator', () {
    test('parses canonical FIFO fields and serializes cleanly', () {
      final purchased = DateTime(2026, 11, 10, 9, 0);
      final arrived = DateTime(2026, 11, 12, 14, 30);
      final expiry = DateTime(2027, 5, 1);

      final batch = ProductBatch.fromMap({
        'batchId': 'BATCH-20261112-A1B2',
        'productId': 'prod-1',
        'productName': 'Lucky Me Pancit Canton',
        'supplierId': 'sup-1',
        'supplierName': 'Monde Nissin',
        'poId': 'po-1',
        'poNumber': 'PO-2026-001',
        'datePurchased': Timestamp.fromDate(purchased),
        'dateArrived': Timestamp.fromDate(arrived),
        'expiryDate': Timestamp.fromDate(expiry),
        'costPrice': 11.5,
        'initialQty': 50,
        'remainingQty': 12,
        'status': BatchStatus.active,
      });

      expect(batch.batchId, 'BATCH-20261112-A1B2');
      expect(batch.productId, 'prod-1');
      expect(batch.productName, 'Lucky Me Pancit Canton');
      expect(batch.supplierName, 'Monde Nissin');
      expect(batch.poNumber, 'PO-2026-001');
      expect(batch.datePurchased, purchased);
      expect(batch.dateArrived, arrived);
      expect(batch.costPrice, 11.5);
      expect(batch.initialQty, 50);
      expect(batch.remainingQty, 12);
      expect(batch.status, BatchStatus.active);
      expect(batch.isActive, isTrue);
      expect(batch.isDepleted, isFalse);

      final map = batch.toFirestore();
      expect(map['batchId'], 'BATCH-20261112-A1B2');
      expect(map['remainingQty'], 12);
      expect(map['initialQty'], 50);
      expect(map['costPrice'], 11.5);
      expect(map['status'], BatchStatus.active);
    });

    test('falls back gracefully for legacy embedded batch payloads', () {
      final received = DateTime(2026, 10, 1);
      final legacy = ProductBatch.fromMap({
        'id': 'legacy-uuid-1',
        'productId': 'prod-legacy',
        'quantity': 20,
        'unitCost': 18.0,
        'createdAt': Timestamp.fromDate(received),
      });

      expect(legacy.batchId, 'legacy-uuid-1');
      expect(legacy.remainingQty, 20);
      expect(legacy.initialQty, 20);
      expect(legacy.costPrice, 18.0);
      expect(legacy.dateArrived, received);
      expect(legacy.datePurchased, received);
      expect(legacy.status, BatchStatus.active);
    });

    test('sorts by dateArrived ASC then batchId ASC tie-breaker', () {
      final t1 = DateTime(2026, 11, 1);
      final t2 = DateTime(2026, 11, 5);
      final batches = [
        ProductBatch(
          batchId: 'BATCH-20261105-CCCC',
          productId: 'p1',
          datePurchased: t2,
          dateArrived: t2,
          costPrice: 15,
          initialQty: 10,
          remainingQty: 10,
        ),
        ProductBatch(
          batchId: 'BATCH-20261101-BBBB',
          productId: 'p1',
          datePurchased: t1,
          dateArrived: t1,
          costPrice: 12,
          initialQty: 10,
          remainingQty: 10,
        ),
        ProductBatch(
          batchId: 'BATCH-20261101-AAAA',
          productId: 'p1',
          datePurchased: t1,
          dateArrived: t1,
          costPrice: 10,
          initialQty: 10,
          remainingQty: 10,
        ),
      ]..sort(ProductBatch.compareFifo);

      expect(batches.map((b) => b.batchId).toList(), [
        'BATCH-20261101-AAAA',
        'BATCH-20261101-BBBB',
        'BATCH-20261105-CCCC',
      ]);
    });

    test('uses PO order number as primary reference and formats legacy UUIDs',
        () {
      const legacyUuid = '68ecdea5-4500-43c5-9418-f12f98197f6f';
      expect(ProductBatch.isLegacyUuid(legacyUuid), isTrue);
      expect(ProductBatch.isLegacyUuid('BATCH-20261124-A1B2'), isFalse);
      expect(
          ProductBatch.formatBatchIdForDisplay(legacyUuid), 'LEGACY-68ECDEA5');

      final legacyNoPo = ProductBatch(
        batchId: legacyUuid,
        productId: 'p1',
        remainingQty: 5,
      );
      expect(legacyNoPo.primaryReference(), 'LEGACY-68ECDEA5');
      expect(
        legacyNoPo.primaryReference(resolvedPoNumber: 'PO-20261124-418'),
        'PO-20261124-418',
      );

      final poBatchId =
          InventoryBatchService.generatePoBatchId('PO-20261124-418');
      expect(poBatchId, startsWith('PO-20261124-418-'));
      expect(poBatchId.length, 'PO-20261124-418-'.length + 4);

      final sanitizedPoBatchId =
          InventoryBatchService.generatePoBatchId('#2026/11/418');
      expect(sanitizedPoBatchId, startsWith('PO-2026-11-418-'));
    });
  });

  group('InventoryBatchService.computeFifoDeduction', () {
    final batchOld = ProductBatch(
      batchId: 'BATCH-20261101-OLD1',
      productId: 'p1',
      productName: 'Sardines',
      datePurchased: DateTime(2026, 10, 30),
      dateArrived: DateTime(2026, 11, 1),
      costPrice: 20.0,
      initialQty: 10,
      remainingQty: 4,
      status: BatchStatus.active,
    );

    final batchNew = ProductBatch(
      batchId: 'BATCH-20261110-NEW2',
      productId: 'p1',
      productName: 'Sardines',
      datePurchased: DateTime(2026, 11, 9),
      dateArrived: DateTime(2026, 11, 10),
      costPrice: 24.0,
      initialQty: 20,
      remainingQty: 20,
      status: BatchStatus.active,
    );

    test('deducts oldest batch first within a single batch', () {
      final plan = InventoryBatchService.computeFifoDeduction(
        batches: [batchNew, batchOld], // intentionally unsorted input
        requestedQty: 3,
        productName: 'Sardines',
      );

      expect(plan.allocations.length, 1);
      expect(plan.allocations.first.batchId, 'BATCH-20261101-OLD1');
      expect(plan.allocations.first.qtyDeducted, 3);
      expect(plan.allocations.first.costPrice, 20.0);
      expect(plan.totalCogs, 60.0);
      expect(plan.newlyDepletedBatches, isEmpty);

      final updatedOld = plan.updatedBatches
          .firstWhere((b) => b.batchId == 'BATCH-20261101-OLD1');
      expect(updatedOld.remainingQty, 1);
      expect(updatedOld.status, BatchStatus.active);
      expect(
          InventoryBatchService.sumActiveBatchStock(plan.updatedBatches), 21);
    });

    test('spans multiple batches and marks exhausted batch DEPLETED', () {
      final plan = InventoryBatchService.computeFifoDeduction(
        batches: [batchNew, batchOld],
        requestedQty: 7,
        productName: 'Sardines',
      );

      expect(plan.allocations.length, 2);
      expect(plan.allocations[0].batchId, 'BATCH-20261101-OLD1');
      expect(plan.allocations[0].qtyDeducted, 4);
      expect(plan.allocations[1].batchId, 'BATCH-20261110-NEW2');
      expect(plan.allocations[1].qtyDeducted, 3);
      expect(plan.totalCogs, (4 * 20.0) + (3 * 24.0));

      expect(plan.newlyDepletedBatches.length, 1);
      expect(plan.newlyDepletedBatches.first.batchId, 'BATCH-20261101-OLD1');
      expect(plan.newlyDepletedBatches.first.status, BatchStatus.depleted);
      expect(plan.newlyDepletedBatches.first.remainingQty, 0);

      final updatedNew = plan.updatedBatches
          .firstWhere((b) => b.batchId == 'BATCH-20261110-NEW2');
      expect(updatedNew.remainingQty, 17);
      expect(updatedNew.status, BatchStatus.active);
      expect(
          InventoryBatchService.sumActiveBatchStock(plan.updatedBatches), 17);
    });

    test('throws clean insufficient stock error without partial mutation', () {
      expect(
        () => InventoryBatchService.computeFifoDeduction(
          batches: [batchOld, batchNew],
          requestedQty: 30,
          productName: 'Sardines',
        ),
        throwsException,
      );
    });
  });

  group('InventoryBatchService.computeRefundBacktrack', () {
    final allocs = [
      BatchAllocation(
        batchId: 'BATCH-20261101-OLD1',
        quantity: 4,
        unitCost: 20.0,
        datePurchased: DateTime(2026, 10, 30),
        dateArrived: DateTime(2026, 11, 1),
      ),
      BatchAllocation(
        batchId: 'BATCH-20261110-NEW2',
        quantity: 3,
        unitCost: 24.0,
        datePurchased: DateTime(2026, 11, 9),
        dateArrived: DateTime(2026, 11, 10),
      ),
    ];

    test('full refund restores all exact allocated batches', () {
      final result = InventoryBatchService.computeRefundBacktrack(
        batchAllocations: allocs,
        refundQty: 7,
      );

      expect(result.length, 2);
      expect(result[0].batchId, 'BATCH-20261110-NEW2');
      expect(result[0].qtyReturned, 3);
      expect(result[1].batchId, 'BATCH-20261101-OLD1');
      expect(result[1].qtyReturned, 4);
    });

    test('partial refund restores in reverse allocation order by default', () {
      final result = InventoryBatchService.computeRefundBacktrack(
        batchAllocations: allocs,
        refundQty: 2,
      );

      expect(result.length, 1);
      expect(result.first.batchId, 'BATCH-20261110-NEW2');
      expect(result.first.qtyReturned, 2);
    });

    test('respects admin-selected preferredBatchId on partial refund', () {
      final result = InventoryBatchService.computeRefundBacktrack(
        batchAllocations: allocs,
        refundQty: 2,
        preferredBatchId: 'BATCH-20261101-OLD1',
      );

      expect(result.length, 1);
      expect(result.first.batchId, 'BATCH-20261101-OLD1');
      expect(result.first.qtyReturned, 2);
    });

    test('accounts for alreadyReturnedQty across consecutive partial refunds',
        () {
      // Suppose 3 units (all of NEW2) were already returned earlier; next 2 units must unwind OLD1
      final result = InventoryBatchService.computeRefundBacktrack(
        batchAllocations: allocs,
        refundQty: 2,
        alreadyReturnedQty: 3,
      );

      expect(result.length, 1);
      expect(result.first.batchId, 'BATCH-20261101-OLD1');
      expect(result.first.qtyReturned, 2);
    });

    test('returns empty list for legacy orders without batchAllocations', () {
      final result = InventoryBatchService.computeRefundBacktrack(
        batchAllocations: const [],
        refundQty: 2,
      );
      expect(result, isEmpty);
    });
  });

  group('Supplier linkage & single-source-of-truth helpers', () {
    test('ProductBatch validates supplierId and PO linkage flags', () {
      final linked = ProductBatch(
        batchId: 'PO-20261124-001-ABCD',
        productId: 'p1',
        supplierId: 'sup-123',
        supplierName: 'Purefoods Distributors',
        poId: 'po-1',
        poNumber: 'PO-20261124-001',
        remainingQty: 15,
      );
      expect(linked.hasValidSupplier, isTrue);
      expect(linked.hasPoLink, isTrue);

      final orphan = ProductBatch(
        batchId: 'BATCH-20261124-EFGH',
        productId: 'p1',
        supplierId: '   ',
        remainingQty: 5,
      );
      expect(orphan.hasValidSupplier, isFalse);
      expect(orphan.hasPoLink, isFalse);
    });

    test('mergeBatchesById deduplicates duplicate IDs without double-counting',
        () {
      final t1 = DateTime(2026, 11, 1);
      final t2 = DateTime(2026, 11, 2);

      final stale = ProductBatch(
        batchId: 'BATCH-DUP',
        productId: 'p1',
        supplierId: 'sup-1',
        dateArrived: t1,
        initialQty: 10,
        remainingQty: 10,
      );
      final updated = stale.copyWith(remainingQty: 6);
      final newer = ProductBatch(
        batchId: 'BATCH-NEW',
        productId: 'p1',
        supplierId: 'sup-2',
        dateArrived: t2,
        initialQty: 8,
        remainingQty: 8,
      );

      final merged = InventoryBatchService.mergeBatchesById([
        newer,
        stale,
        updated,
      ]);

      expect(merged.length, 2);
      expect(merged[0].batchId, 'BATCH-DUP');
      expect(merged[0].remainingQty, 6);
      expect(merged[1].batchId, 'BATCH-NEW');
      expect(InventoryBatchService.sumActiveBatchStock(merged), 14);
    });

    test('resolveUniqueBatchId prevents overwriting an existing batch ID', () {
      final existing = {'BATCH-20261124-ABCD'};
      final unique = InventoryBatchService.resolveUniqueBatchId(
        'BATCH-20261124-ABCD',
        existing,
      );

      expect(unique, isNot('BATCH-20261124-ABCD'));
      expect(unique, startsWith('BATCH-20261124-ABCD-'));
      expect(
        InventoryBatchService.resolveUniqueBatchId(
          'BATCH-20261124-WXYZ',
          existing,
        ),
        'BATCH-20261124-WXYZ',
      );
    });

    test('buildInventoryBatchMirror preserves full supplier and PO metadata',
        () {
      final arrived = DateTime(2026, 11, 20, 10, 0);
      final purchased = DateTime(2026, 11, 18, 8, 0);
      final batch = ProductBatch(
        batchId: 'PO-2026-009-1234',
        productId: 'prod-9',
        productName: 'Argentina Corned Beef',
        supplierId: 'sup-9',
        supplierName: 'Century Pacific',
        poId: 'po-doc-9',
        poNumber: 'PO-2026-009',
        datePurchased: purchased,
        dateArrived: arrived,
        costPrice: 38.5,
        initialQty: 48,
        remainingQty: 40,
        status: BatchStatus.active,
      );

      final mirror = InventoryBatchService.buildInventoryBatchMirror(
        batch,
        receiptId: 'rec-9',
      );

      expect(mirror['batchId'], 'PO-2026-009-1234');
      expect(mirror['productId'], 'prod-9');
      expect(mirror['productName'], 'Argentina Corned Beef');
      expect(mirror['supplierId'], 'sup-9');
      expect(mirror['supplierName'], 'Century Pacific');
      expect(mirror['poId'], 'po-doc-9');
      expect(mirror['poNumber'], 'PO-2026-009');
      expect(mirror['receiptId'], 'rec-9');
      expect(mirror['initialQty'], 48);
      expect(mirror['quantityRemaining'], 40);
      expect(mirror['remainingQty'], 40);
      expect(mirror['status'], BatchStatus.active);
    });
  });

  group('Unified sellable stock rule & Vita Coco desync regression', () {
    final now = DateTime(2026, 11, 24, 12, 0);

    test(
        'isSellableAt enforces active status, remainingQty > 0, and non-expired',
        () {
      final activeFuture = ProductBatch(
        batchId: 'B-ACTIVE-FUTURE',
        productId: 'vita-coco',
        remainingQty: 25,
        expiryDate: now.add(const Duration(days: 30)),
        status: 'active', // lowercase legacy value
      );
      final activeNoExpiry = ProductBatch(
        batchId: 'B-ACTIVE-NO-EXP',
        productId: 'vita-coco',
        remainingQty: 15,
        expiryDate: null,
        status: BatchStatus.active,
      );
      final expiredWithQty = ProductBatch(
        batchId: 'B-EXPIRED-STALE-STATUS',
        productId: 'vita-coco',
        remainingQty: 100,
        expiryDate: now.subtract(const Duration(days: 1)),
        status: BatchStatus.active,
      );
      final depleted = ProductBatch(
        batchId: 'B-DEPLETED',
        productId: 'vita-coco',
        remainingQty: 0,
        expiryDate: now.add(const Duration(days: 60)),
        status: BatchStatus.active,
      );
      final archived = ProductBatch(
        batchId: 'B-ARCHIVED',
        productId: 'vita-coco',
        remainingQty: 40,
        expiryDate: now.add(const Duration(days: 60)),
        status: BatchStatus.archived,
      );

      expect(activeFuture.isSellableAt(now), isTrue);
      expect(activeNoExpiry.isSellableAt(now), isTrue);
      expect(expiredWithQty.isExpiredAt(now), isTrue);
      expect(expiredWithQty.isSellableAt(now), isFalse);
      expect(expiredWithQty.effectiveStatusAt(now), BatchStatus.expired);
      expect(depleted.isSellableAt(now), isFalse);
      expect(depleted.effectiveStatusAt(now), BatchStatus.depleted);
      expect(archived.isSellableAt(now), isFalse);

      expect(
        ProductBatch.sumSellableStock(
          [activeFuture, activeNoExpiry, expiredWithQty, depleted, archived],
          now: now,
        ),
        40,
      );
    });

    test('compareFifo prioritizes earliest expiryDate before dateArrived', () {
      final earlierArrivedLaterExpiry = ProductBatch(
        batchId: 'B-LATER-EXP',
        productId: 'p1',
        dateArrived: DateTime(2026, 10, 1),
        expiryDate: DateTime(2027, 6, 1),
        remainingQty: 10,
      );
      final laterArrivedEarlierExpiry = ProductBatch(
        batchId: 'B-EARLIER-EXP',
        productId: 'p1',
        dateArrived: DateTime(2026, 11, 1),
        expiryDate: DateTime(2027, 1, 15),
        remainingQty: 10,
      );
      final noExpiry = ProductBatch(
        batchId: 'B-NO-EXP',
        productId: 'p1',
        dateArrived: DateTime(2026, 9, 1),
        expiryDate: null,
        remainingQty: 10,
      );

      final sorted = [
        noExpiry,
        earlierArrivedLaterExpiry,
        laterArrivedEarlierExpiry,
      ]..sort(ProductBatch.compareFifo);

      expect(sorted.map((b) => b.batchId).toList(), [
        'B-EARLIER-EXP',
        'B-LATER-EXP',
        'B-NO-EXP',
      ]);
    });

    test(
        'computeFifoDeduction skips expired batches, marks them EXPIRED, and prevents negative stock',
        () {
      final expiredBatch = ProductBatch(
        batchId: 'B-EXPIRED',
        productId: 'vita-coco',
        dateArrived: DateTime(2026, 8, 1),
        expiryDate: now.subtract(const Duration(days: 5)),
        costPrice: 35.0,
        initialQty: 100,
        remainingQty: 100,
        status: BatchStatus.active,
      );
      final soonExpiringBatch = ProductBatch(
        batchId: 'B-SOON',
        productId: 'vita-coco',
        dateArrived: DateTime(2026, 11, 10),
        expiryDate: now.add(const Duration(days: 20)),
        costPrice: 38.0,
        initialQty: 50,
        remainingQty: 30,
        status: BatchStatus.active,
      );
      final laterExpiringBatch = ProductBatch(
        batchId: 'B-LATER',
        productId: 'vita-coco',
        dateArrived: DateTime(2026, 10, 10),
        expiryDate: now.add(const Duration(days: 90)),
        costPrice: 40.0,
        initialQty: 60,
        remainingQty: 58,
        status: BatchStatus.active,
      );

      final plan = InventoryBatchService.computeFifoDeduction(
        batches: [laterExpiringBatch, expiredBatch, soonExpiringBatch],
        requestedQty: 35,
        productName: 'Vita Coco Strawberries & Creme',
        now: now,
      );

      expect(plan.newlyExpiredBatches.length, 1);
      expect(plan.newlyExpiredBatches.first.batchId, 'B-EXPIRED');
      expect(plan.newlyExpiredBatches.first.status, BatchStatus.expired);

      expect(plan.allocations.length, 2);
      expect(plan.allocations[0].batchId, 'B-SOON');
      expect(plan.allocations[0].qtyDeducted, 30);
      expect(plan.allocations[1].batchId, 'B-LATER');
      expect(plan.allocations[1].qtyDeducted, 5);

      expect(plan.newlyDepletedBatches.length, 1);
      expect(plan.newlyDepletedBatches.first.batchId, 'B-SOON');
      expect(plan.newlyDepletedBatches.first.status, BatchStatus.depleted);

      expect(
        ProductBatch.sumSellableStock(plan.updatedBatches, now: now),
        53,
      );

      // Requesting more than valid sellable stock (88) must throw even though
      // expired batch holds 100 units (188 raw total).
      expect(
        () => InventoryBatchService.computeFifoDeduction(
          batches: [expiredBatch, soonExpiringBatch, laterExpiringBatch],
          requestedQty: 90,
          productName: 'Vita Coco Strawberries & Creme',
          now: now,
        ),
        throwsException,
      );
    });

    test(
        'Vita Coco regression: Inventory, POS, and View Batches derive identical sellable stock despite drifted parent stock and negative reservedStock',
        () {
      final futureExpiry = DateTime.now().add(const Duration(days: 60));
      final pastExpiry = DateTime.now().subtract(const Duration(days: 10));

      final vitaCoco = Product(
        id: 'vita-coco-id',
        name: 'Vita Coco Strawberries & Creme Coconutmilk Beverages',
        category: 'Beverages',
        price: 65.0,
        stock: 44, // drifted parent field
        reservedStock: -18, // corrupted negative reservation (44 - (-18) = 62)
        batches: [
          ProductBatch(
            batchId: 'B-OLD-EXP',
            productId: 'vita-coco-id',
            remainingQty: 100,
            initialQty: 100,
            expiryDate: pastExpiry,
            status: BatchStatus.active,
          ),
          ProductBatch(
            batchId: 'B-VALID-1',
            productId: 'vita-coco-id',
            remainingQty: 50,
            initialQty: 50,
            expiryDate: futureExpiry,
            status: BatchStatus.active,
          ),
          ProductBatch(
            batchId: 'B-VALID-2',
            productId: 'vita-coco-id',
            remainingQty: 38,
            initialQty: 40,
            expiryDate: futureExpiry.add(const Duration(days: 30)),
            status: BatchStatus.active,
          ),
        ],
      );

      // All screens now derive 88 from live sellable batches, clamping negative reservedStock to 0.
      expect(vitaCoco.effectiveReservedStock, 0);
      expect(vitaCoco.totalReservedStock, 0);
      expect(vitaCoco.sellableStock, 88);
      expect(vitaCoco.totalStock, 88);
      expect(vitaCoco.availableStock, 88);
      expect(vitaCoco.totalAvailableStock, 88);
      expect(ProductBatch.sumSellableStock(vitaCoco.batches), 88);

      // With active pending pickup reservations (10 pcs), Inventory shows 88 (10 res)
      // and POS available stock is consistently 78.
      final withReservations = vitaCoco.copyWith(reservedStock: 10);
      expect(withReservations.totalStock, 88);
      expect(withReservations.totalReservedStock, 10);
      expect(withReservations.availableStock, 78);
      expect(withReservations.totalAvailableStock, 78);

      // Over-reservation clamps availableStock to 0 (never negative).
      final overReserved = vitaCoco.copyWith(reservedStock: 120);
      expect(overReserved.availableStock, 0);
      expect(overReserved.totalAvailableStock, 0);
    });
  });
}
