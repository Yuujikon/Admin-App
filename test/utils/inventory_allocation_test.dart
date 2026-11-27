import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/models/daily_resupply_log.dart';
import 'package:gdc_admin_app/models/product.dart';
import 'package:gdc_admin_app/models/store_settings.dart';
import 'package:gdc_admin_app/utils/inventory_allocation.dart';

void main() {
  group('InventoryAllocation — Fixed 100% POS / 75% Online (25% Reserve)', () {
    test('calculates 25% physical reserve rounding up on odd quantities', () {
      expect(InventoryAllocation.calculatePhysicalReserve(0), 0);
      expect(InventoryAllocation.calculatePhysicalReserve(-5), 0);
      expect(InventoryAllocation.calculatePhysicalReserve(1), 1);
      expect(InventoryAllocation.calculatePhysicalReserve(4), 1);
      expect(InventoryAllocation.calculatePhysicalReserve(5), 2);
      expect(InventoryAllocation.calculatePhysicalReserve(10), 3);
      expect(InventoryAllocation.calculatePhysicalReserve(100), 25);
    });

    test('Scenario 1: Restocking 100 units -> 100 POS, 75 Online, 25 Reserve',
        () {
      const int totalStock = 100;
      final int reserve =
          InventoryAllocation.calculatePhysicalReserve(totalStock);
      expect(reserve, 25);

      final product = Product(
        id: 'p_rice',
        name: 'Sinandomeng Rice 1kg',
        category: 'Grains',
        price: 58.0,
        stock: totalStock,
        physicalReserve: reserve,
      );

      expect(product.totalStock, 100);
      expect(product.totalAvailableStock, 100);
      expect(product.effectivePhysicalReserve, 25);
      expect(product.onlineAvailableStock, 75);
      expect(product.maxPurchasableStock, 75);
      expect(product.isOnlineOutOfStock, isFalse);
      expect(product.isOutOfStockForCustomer, isFalse);
    });

    test('Scenario 2: Buying 75 units online leaves 0 (OOS) Online and 25 POS',
        () {
      // Phase A: Pending pickup (reservedStock = 75, stock = 100, reserve = 25)
      const pendingPickup = Product(
        id: 'p_rice',
        name: 'Sinandomeng Rice 1kg',
        category: 'Grains',
        price: 58.0,
        stock: 100,
        reservedStock: 75,
        physicalReserve: 25,
      );

      expect(pendingPickup.totalAvailableStock, 25);
      expect(pendingPickup.onlineAvailableStock, 0);
      expect(pendingPickup.isOnlineOutOfStock, isTrue);
      expect(pendingPickup.isOutOfStockForCustomer, isTrue);

      // Phase B: After online order collected (FIFO deducted: stock = 25, reserved = 0, reserve preserved at 25)
      const collected = Product(
        id: 'p_rice',
        name: 'Sinandomeng Rice 1kg',
        category: 'Grains',
        price: 58.0,
        stock: 25,
        reservedStock: 0,
        physicalReserve: 25,
      );

      expect(collected.totalStock, 25);
      expect(collected.totalAvailableStock, 25);
      expect(collected.effectivePhysicalReserve, 25);
      expect(collected.onlineAvailableStock, 0);
      expect(collected.isOnlineOutOfStock, isTrue);
      expect(collected.isOutOfStockForCustomer, isTrue);
    });

    test('Scenario 3: POS sells remaining 25 reserved units all the way to 0',
        () {
      var stock = 25;
      const reserve = 25;

      // POS sells 10 of the reserved 25 units -> 15 left for POS, still 0 online
      stock -= 10;
      final afterFirstPosSale = Product(
        id: 'p_rice',
        name: 'Sinandomeng Rice 1kg',
        category: 'Grains',
        price: 58.0,
        stock: stock,
        physicalReserve: reserve,
      );
      expect(afterFirstPosSale.totalAvailableStock, 15);
      expect(afterFirstPosSale.onlineAvailableStock, 0);
      expect(afterFirstPosSale.isOnlineOutOfStock, isTrue);

      // POS sells remaining 15 units -> 0 left for POS, 0 online
      stock -= 15;
      final soldOutEverywhere = Product(
        id: 'p_rice',
        name: 'Sinandomeng Rice 1kg',
        category: 'Grains',
        price: 58.0,
        stock: stock,
        physicalReserve: reserve,
      );
      expect(soldOutEverywhere.totalStock, 0);
      expect(soldOutEverywhere.totalAvailableStock, 0);
      expect(soldOutEverywhere.onlineAvailableStock, 0);
      expect(soldOutEverywhere.isOnlineOutOfStock, isTrue);
    });

    test(
        'Online order cancellation / refund restores onlineAvailable automatically',
        () {
      // Suppose 75 were sold online -> stock=25, reserve=25 -> online=0.
      // Customer cancels/refunds 10 units -> stock=35, reserve preserved at 25.
      const refunded = Product(
        id: 'p_rice',
        name: 'Sinandomeng Rice 1kg',
        category: 'Grains',
        price: 58.0,
        stock: 35,
        physicalReserve: 25,
      );

      expect(refunded.totalAvailableStock, 35);
      expect(refunded.onlineAvailableStock, 10);
      expect(refunded.isOnlineOutOfStock, isFalse);

      // Pre-pickup cancellation: reservedStock drops from 75 to 60 -> online=15.
      const cancelledPrePickup = Product(
        id: 'p_rice',
        name: 'Sinandomeng Rice 1kg',
        category: 'Grains',
        price: 58.0,
        stock: 100,
        reservedStock: 60,
        physicalReserve: 25,
      );
      expect(cancelledPrePickup.totalAvailableStock, 40);
      expect(cancelledPrePickup.onlineAvailableStock, 15);
    });

    test(
        'Legacy product without stored physicalReserve safely falls back to 25% ceil',
        () {
      final legacyProduct = Product.fromMap(
        {
          'name': 'Legacy Sardines',
          'category': 'Canned Goods',
          'price': 28.0,
          'stock': 10,
          // Legacy percentage fields should be safely ignored
          'onlineAllocationPercent': 50,
          'physicalAllocationPercent': 50,
        },
        id: 'legacy_1',
      );

      expect(legacyProduct.physicalReserve, isNull);
      expect(legacyProduct.effectivePhysicalReserve, 3); // ceil(10 * 0.25) = 3
      expect(legacyProduct.totalAvailableStock, 10);
      expect(legacyProduct.onlineAvailableStock, 7); // 10 - 3 = 7
    });

    test('Multi-variant product aggregates POS, Online, and Reserve correctly',
        () {
      const product = Product(
        id: 'p_noodles',
        name: 'Instant Noodles',
        category: 'Noodles',
        price: 15.0,
        stock: 100,
        variants: [
          ProductVariant(
            id: 'beef',
            name: 'Beef',
            price: 15.0,
            stock: 60,
            physicalReserve: 15, // 25% of 60 -> 45 online
          ),
          ProductVariant(
            id: 'chicken',
            name: 'Chicken',
            price: 15.0,
            stock: 10,
            physicalReserve: 10, // Remaining 25% walk-in reserve -> 0 online
          ),
        ],
      );

      expect(product.totalStock, 70);
      expect(product.totalAvailableStock, 70);
      expect(product.effectivePhysicalReserve, 25);
      expect(product.variants[0].onlineAvailableStock, 45);
      expect(product.variants[1].onlineAvailableStock, 0);
      expect(product.variants[1].isOnlineOutOfStock, isTrue);
      expect(product.onlineAvailableStock, 45);
      expect(product.isOnlineOutOfStock, isFalse);
    });
  });

  group('Automatic 30% Low-Stock Alert & Store-Closing Email Trigger', () {
    test('calculates 30% low-stock trigger rounding up from original stock',
        () {
      expect(InventoryAllocation.calculateLowStockTrigger(0), 0);
      expect(InventoryAllocation.calculateLowStockTrigger(1), 1);
      expect(InventoryAllocation.calculateLowStockTrigger(10), 3);
      expect(InventoryAllocation.calculateLowStockTrigger(29), 9);
      expect(InventoryAllocation.calculateLowStockTrigger(50), 15);
      expect(InventoryAllocation.calculateLowStockTrigger(100), 30);
    });

    test(
        'triggers low-stock alert at <= 30% of original stock without affecting 75%/25% split',
        () {
      // Original stock 100 -> 25% reserve = 25, 75% online = 75, 30% alert = 30.
      const above30 = Product(
        id: 'p_sardines',
        name: '555 Sardines',
        category: 'Canned Goods',
        price: 25.0,
        stock: 31,
        initialStock: 100,
        physicalReserve: 25,
      );
      expect(above30.lowStockAlertThreshold, 30);
      expect(above30.isPhysicalThresholdHit, isFalse);
      expect(above30.totalAvailableStock, 31); // 100% physical POS
      expect(above30.onlineAvailableStock, 6); // 31 - 25 reserve

      const at30 = Product(
        id: 'p_sardines',
        name: '555 Sardines',
        category: 'Canned Goods',
        price: 25.0,
        stock: 30,
        initialStock: 100,
        physicalReserve: 25,
      );
      expect(at30.lowStockAlertThreshold, 30);
      expect(at30.isPhysicalThresholdHit, isTrue);
      expect(at30.totalAvailableStock, 30);
      expect(at30.onlineAvailableStock, 5); // 75%/25% untouched!

      // Legacy manual lowStockThreshold in Firestore is ignored in favor of 30%.
      final legacyDoc = Product.fromMap(
        {
          'name': '555 Sardines',
          'category': 'Canned Goods',
          'price': 25.0,
          'stock': 9,
          'initialStock': 29,
          'physicalReserve': 8,
          'lowStockThreshold': 2, // legacy manual limit must be ignored
        },
        id: 'p_555',
      );
      expect(legacyDoc.lowStockAlertThreshold, 9); // ceil(29 * 0.30) = 9
      expect(legacyDoc.isPhysicalThresholdHit, isTrue);
      expect(legacyDoc.onlineAvailableStock, 1); // 9 - 8 reserve = 1
    });

    test('StoreSettings.hasStoreClosedForDayAt triggers only when store closes',
        () {
      const openSettings = StoreSettings(
        isClosed: false,
        operatingHoursEnabled: true,
        dailyOpenTime: '08:00',
        dailyCloseTime: '21:00',
      );

      // Morning before opening: NOT closed for the day yet
      expect(
        openSettings.hasStoreClosedForDayAt(DateTime(2026, 5, 10, 6, 30)),
        isFalse,
      );
      // Midday while open: NOT closed
      expect(
        openSettings.hasStoreClosedForDayAt(DateTime(2026, 5, 10, 14, 0)),
        isFalse,
      );
      // At regular daily close time (21:00): CLOSED for the day
      expect(
        openSettings.hasStoreClosedForDayAt(DateTime(2026, 5, 10, 21, 0)),
        isTrue,
      );

      // Manual store close immediately triggers store-closing summary
      final manualClosed = openSettings.copyWith(isClosed: true);
      expect(
        manualClosed.hasStoreClosedForDayAt(DateTime(2026, 5, 10, 11, 0)),
        isTrue,
      );

      // Special hours override closing early at 3:00 PM (15:00)
      final specialHoursSettings = openSettings.copyWith(
        overrides: [
          ScheduleOverride(
            id: 'ov_1',
            startDate: DateTime(2026, 5, 10),
            endDate: DateTime(2026, 5, 10),
            type: OverrideType.customOpenHours,
            startMinutes: 13 * 60,
            endMinutes: 15 * 60,
            reason: 'Half-day inventory',
          ),
        ],
      );
      expect(
        specialHoursSettings
            .hasStoreClosedForDayAt(DateTime(2026, 5, 10, 14, 30)),
        isFalse,
      );
      expect(
        specialHoursSettings
            .hasStoreClosedForDayAt(DateTime(2026, 5, 10, 15, 0)),
        isTrue,
      );
    });

    test(
        'legacy product without initialStock recovers baseline from physicalReserve without false positives',
        () {
      expect(InventoryAllocation.minOriginalStockFromReserve(0), 0);
      expect(InventoryAllocation.minOriginalStockFromReserve(1), 1);
      expect(InventoryAllocation.minOriginalStockFromReserve(2), 5);
      expect(InventoryAllocation.minOriginalStockFromReserve(3), 9);
      expect(InventoryAllocation.minOriginalStockFromReserve(25), 97);

      // Fresh stock of 5 (reserve=2): 5 > ceil(5*0.30)=2 -> NOT low stock!
      const freshSmall = Product(
        id: 'p_small',
        name: 'Small Pack',
        category: 'Snacks',
        price: 10.0,
        stock: 5,
        physicalReserve: 2,
      );
      expect(freshSmall.effectiveOriginalStock, 5);
      expect(freshSmall.isPhysicalThresholdHit, isFalse);

      // Legacy 100-unit product (reserve=25, no initialStock) sold down to 25 -> MUST trigger <= 30%!
      const legacyLow = Product(
        id: 'p_legacy',
        name: 'Legacy Rice',
        category: 'Grains',
        price: 58.0,
        stock: 25,
        physicalReserve: 25,
      );
      expect(legacyLow.effectiveOriginalStock, 97);
      expect(legacyLow.lowStockAlertThreshold, 30);
      expect(legacyLow.isPhysicalThresholdHit, isTrue);

      // Legacy variant product without initialStock sold down to 5 of ~20 (reserve=5 -> minOriginal=17, 30%=6)
      const variantLow = Product(
        id: 'p_var',
        name: 'Noodles',
        category: 'Noodles',
        price: 15.0,
        stock: 5,
        variants: [
          ProductVariant(
            id: 'beef',
            name: 'Beef',
            price: 15.0,
            stock: 5,
            physicalReserve: 5,
          ),
        ],
      );
      expect(variantLow.variants.first.effectiveOriginalStock, 17);
      expect(variantLow.variants.first.lowStockAlertThreshold, 6);
      expect(variantLow.variants.first.isPhysicalThresholdHit, isTrue);
      expect(variantLow.isPhysicalThresholdHit, isTrue);
    });

    test(
        'depleted batch product with stock=0 and missing initialStock still triggers 30% / OOS alert',
        () {
      final depleted = Product(
        id: 'p_depleted',
        name: 'Depleted Milk',
        category: 'Dairy',
        price: 45.0,
        stock: 0,
        batches: [
          ProductBatch(
            batchId: 'BATCH-1',
            productId: 'p_depleted',
            initialQty: 20,
            remainingQty: 0,
            status: BatchStatus.depleted,
          ),
        ],
      );

      expect(depleted.totalStock, 0);
      expect(depleted.effectiveOriginalStock, 20);
      expect(depleted.lowStockAlertThreshold, 6);
      expect(depleted.isPhysicalThresholdHit, isTrue);
    });

    test('DailyResupplyLog parses summaryEmailClaimedAt for stale-lock checks',
        () {
      final claimedIso = DateTime(2026, 5, 10, 21, 0).toIso8601String();
      final log = DailyResupplyLog.fromMap(
        {
          'dateKey': '2026-05-10',
          'storeEmail': 'gdcstore.ph@gmail.com',
          'items': {},
          'summaryEmailSent': false,
          'summaryEmailStatus': 'sending',
          'summaryEmailClaimedAt': claimedIso,
        },
        dateKey: '2026-05-10',
      );
      expect(log.summaryEmailStatus, 'sending');
      expect(log.summaryEmailClaimedAt, DateTime(2026, 5, 10, 21, 0));
    });
  });
}
