import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/models/order.dart';
import 'package:gdc_admin_app/models/product.dart';
import 'package:gdc_admin_app/models/store_settings.dart';
import 'package:gdc_admin_app/models/transaction.dart';
import 'package:gdc_admin_app/utils/pricing_engine.dart';

void main() {
  group('1. Non-Breaking Schema Backward Compatibility', () {
    test('Product.fromMap falls back cleanly on legacy documents', () {
      final legacyDoc = <String, dynamic>{
        'name': 'Lucky Me Pancit Canton',
        'category': 'Basic Staples & Essentials',
        'price': 15.0,
        'costPrice': 12.0,
        'stock': 30,
      };

      final product = Product.fromMap(legacyDoc, id: 'legacy-1');

      expect(product.pricingMode, equals('auto'));
      expect(product.manualMarkupPercent, isNull);
      expect(product.salesVelocityScore, equals(0.5));
      // Staples range 5%–15% at default v=0.5 => 10.0%
      expect(product.computedMarkupPercent, equals(10.0));
      expect(product.price, equals(15.0));
      expect(product.sellingPrice, equals(15.0));
    });

    test('Product.fromMap clamps out-of-range velocity & invalid pricingMode',
        () {
      final doc = <String, dynamic>{
        'name': 'Test Item',
        'category': 'Others',
        'price': 25.0,
        'costPrice': 20.0,
        'stock': 10,
        'pricingMode': 'unknown_mode',
        'salesVelocityScore': 3.5,
      };

      final product = Product.fromMap(doc, id: 'p-clamp');

      expect(product.pricingMode, equals('auto'));
      expect(product.salesVelocityScore, equals(1.0));
      expect(product.computedMarkupPercent, equals(25.0));
    });

    test('CartItem locks unitPriceAtSale and parses legacy maps safely', () {
      final legacyCart = CartItem.fromMap({
        'productId': 'p1',
        'name': 'Coke Mismo',
        'price': 22.0,
        'costPrice': 16.0,
        'qty': 2,
      });

      expect(legacyCart.price, equals(22.0));
      expect(legacyCart.unitPriceAtSale, equals(22.0));

      final serialized = legacyCart.toMap();
      expect(serialized['unitPriceAtSale'], equals(22.0));
      expect(serialized['price'], equals(22.0));
    });
  });

  group('2. calculateItemMarkup Priority & Category Bounds', () {
    Product makeProduct({
      required String category,
      String pricingMode = 'auto',
      double? manualMarkupPercent,
      double salesVelocityScore = 0.5,
      double costPrice = 20.0,
    }) {
      return Product(
        id: 'p-1',
        name: 'Item',
        category: category,
        price: 0,
        costPrice: costPrice,
        stock: 10,
        pricingMode: pricingMode,
        manualMarkupPercent: manualMarkupPercent,
        salesVelocityScore: salesVelocityScore,
      );
    }

    test('Priority 1: Manual admin override wins over category & velocity', () {
      final item = makeProduct(
        category: 'Personal Care & Toiletries',
        pricingMode: 'manual',
        manualMarkupPercent: 18.5,
        salesVelocityScore: 1.0,
      );

      expect(calculateItemMarkup(item), equals(18.5));
      expect(
        calculateItemMarkup(item, useGlobalBenchmarkOnly: true),
        equals(18.5),
      );
    });

    test('Manual mode with null manualMarkupPercent falls back safely to auto',
        () {
      final item = makeProduct(
        category: 'Beverages & Cold Items',
        pricingMode: 'manual',
        manualMarkupPercent: null,
        salesVelocityScore: 0.5,
      );

      expect(calculateItemMarkup(item), equals(20.0));
    });

    test('Priority 2 & 3: All 8 category ranges scale linearly with velocity',
        () {
      final expectedBounds = <String, (double, double)>{
        'Basic Staples & Essentials': (5.0, 15.0),
        'Beverages & Cold Items': (15.0, 25.0),
        'Personal Care & Toiletries': (20.0, 30.0),
        'Household & Cleaning Supplies': (15.0, 25.0),
        'Snacks, Candies & Biscuits': (15.0, 25.0),
        'Condiments & Cooking Basics': (10.0, 20.0),
        'Alcohol & Cigarettes/Tobacco': (5.0, 15.0),
        'Others': (15.0, 25.0),
      };

      for (final entry in expectedBounds.entries) {
        final (minM, maxM) = entry.value;
        final midM = (minM + maxM) / 2.0;

        expect(
          calculateItemMarkup(
              makeProduct(category: entry.key, salesVelocityScore: 0.0)),
          equals(minM),
          reason: '${entry.key} slow-moving',
        );
        expect(
          calculateItemMarkup(
              makeProduct(category: entry.key, salesVelocityScore: 0.5)),
          equals(midM),
          reason: '${entry.key} moderate',
        );
        expect(
          calculateItemMarkup(
              makeProduct(category: entry.key, salesVelocityScore: 1.0)),
          equals(maxM),
          reason: '${entry.key} fast-moving',
        );
      }
    });

    test('Case-insensitive & legacy store category mapping works accurately',
        () {
      expect(
        calculateItemMarkup(
            makeProduct(category: 'canned goods', salesVelocityScore: 0.0)),
        equals(5.0),
      );
      expect(
        calculateItemMarkup(
            makeProduct(category: 'GRAINS', salesVelocityScore: 1.0)),
        equals(15.0),
      );
      expect(
        calculateItemMarkup(
            makeProduct(category: 'personal care', salesVelocityScore: 1.0)),
        equals(30.0),
      );
      expect(
        calculateItemMarkup(
            makeProduct(category: 'Condiments', salesVelocityScore: 0.0)),
        equals(10.0),
      );
      expect(
        calculateItemMarkup(
            makeProduct(category: 'Uncategorized', salesVelocityScore: 0.5)),
        equals(20.0),
      );
    });

    test('Pure global 15%–25% toggle applies uniformly across all categories',
        () {
      final stapleSlow = makeProduct(
        category: 'Basic Staples & Essentials',
        salesVelocityScore: 0.0,
      );
      final careFast = makeProduct(
        category: 'Personal Care & Toiletries',
        salesVelocityScore: 1.0,
      );

      expect(
        calculateItemMarkup(stapleSlow, useGlobalBenchmarkOnly: true),
        equals(15.0),
      );
      expect(
        calculateItemMarkup(careFast, useGlobalBenchmarkOnly: true),
        equals(25.0),
      );
    });

    test('Clamps negative, >1.0, and NaN velocity scores safely', () {
      expect(
        calculateItemMarkup(
            makeProduct(category: 'Others', salesVelocityScore: -2.0)),
        equals(15.0),
      );
      expect(
        calculateItemMarkup(
            makeProduct(category: 'Others', salesVelocityScore: 5.0)),
        equals(25.0),
      );
      expect(
        calculateItemMarkup(
            makeProduct(category: 'Others', salesVelocityScore: double.nan)),
        equals(20.0),
      );
    });
  });

  group('3. Philippine Rounding, Reverse Markup & Zero-Cost Safety', () {
    test('Applies standard Philippine sari-sari rounding steps', () {
      // Raw = 10.0 * 1.13 = 11.30
      expect(
        PricingEngine.calculateFinalSellingPrice(
          unitCost: 10.0,
          markupPercent: 13.0,
          roundingStep: 0.25,
        ),
        equals(11.25),
      );
      expect(
        PricingEngine.calculateFinalSellingPrice(
          unitCost: 10.0,
          markupPercent: 13.0,
          roundingStep: 0.50,
        ),
        equals(11.50),
      );
      expect(
        PricingEngine.calculateFinalSellingPrice(
          unitCost: 10.0,
          markupPercent: 13.0,
          roundingStep: 1.00,
        ),
        equals(11.00),
      );
    });

    test('Reverse-calculates manualMarkupPercent accurately', () {
      // ((23.70 - 20.00) / 20.00) * 100 = 18.5%
      final markup = PricingEngine.reverseCalculateMarkupPercent(
        sellingPrice: 23.70,
        unitCost: 20.00,
      );
      expect(markup, equals(18.5));
    });

    test('Zero-cost or negative-cost safely skips math without NaN', () {
      expect(
        PricingEngine.calculateFinalSellingPrice(
          unitCost: 0.0,
          markupPercent: 20.0,
        ),
        equals(0.0),
      );
      expect(
        PricingEngine.reverseCalculateMarkupPercent(
          sellingPrice: 25.0,
          unitCost: 0.0,
        ),
        isNull,
      );
      expect(
        PricingEngine.reverseCalculateMarkupPercent(
          sellingPrice: 25.0,
          unitCost: -10.0,
        ),
        isNull,
      );

      const zeroCostProduct = Product(
        id: 'z1',
        name: 'Zero Cost Item',
        category: 'Beverages & Cold Items',
        price: 0.0,
        costPrice: 0.0,
        stock: 5,
      );
      final eval = PricingEngine.evaluateProductPricing(zeroCostProduct);
      expect(eval.hasInvalidCost, isTrue);
      expect(eval.warningMessage, isNotNull);
      expect(eval.finalSellingPrice, equals(0.0));
      expect(eval.finalSellingPrice.isNaN, isFalse);
    });
  });

  group('4. FIFO Batch Transition & POS Price Locking Safety', () {
    const settings = StoreSettings(
      isClosed: false,
      priceRoundingStep: 0.25,
      useGlobalVelocityBenchmarkOnly: false,
    );

    test(
        'Recalculates sellingPrice when next FIFO batch with different cost activates (auto)',
        () {
      final batch1 = ProductBatch(
        id: 'b1',
        productId: 'p1',
        quantityRemaining: 2,
        unitCost: 20.0,
        dateReceived: DateTime(2026, 1, 1),
      );
      final batch2 = ProductBatch(
        id: 'b2',
        productId: 'p1',
        quantityRemaining: 10,
        unitCost: 25.0,
        dateReceived: DateTime(2026, 1, 10),
      );

      final product = Product(
        id: 'p1',
        name: 'Coke 1.5L',
        category: 'Beverages & Cold Items',
        price: 24.0,
        costPrice: 20.0,
        stock: 12,
        pricingMode: 'auto',
        salesVelocityScore: 0.5, // 20% markup
        computedMarkupPercent: 20.0,
        batches: [batch1, batch2],
      );

      // Batch 1 depleted -> only batch2 remains active with unitCost = 25.0
      final update = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: [batch2],
        settings: settings,
      );

      expect(update, isNotNull);
      expect(update!.hasInvalidCost, isFalse);
      expect(update.newActiveUnitCost, equals(25.0));
      expect(update.computedMarkupPercent, equals(20.0));
      // 25.0 * 1.20 = 30.00
      expect(update.newSellingPrice, equals(30.0));
    });

    test(
        'Recalculates sellingPrice using locked manualMarkupPercent when FIFO batch changes',
        () {
      final batch1 = ProductBatch(
        id: 'b1',
        productId: 'p2',
        quantityRemaining: 1,
        unitCost: 10.0,
        dateReceived: DateTime(2026, 1, 1),
      );
      final batch2 = ProductBatch(
        id: 'b2',
        productId: 'p2',
        quantityRemaining: 20,
        unitCost: 20.0,
        dateReceived: DateTime(2026, 1, 5),
      );

      final product = Product(
        id: 'p2',
        name: 'Shampoo Sachet',
        category: 'Personal Care & Toiletries',
        price: 11.75,
        costPrice: 10.0,
        stock: 21,
        pricingMode: 'manual',
        manualMarkupPercent: 18.5,
        computedMarkupPercent: 18.5,
        batches: [batch1, batch2],
      );

      final update = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: [batch2],
        settings: settings,
      );

      expect(update, isNotNull);
      expect(update!.computedMarkupPercent, equals(18.5));
      // 20.0 * 1.185 = 23.70 -> rounded to nearest 0.25 => 23.75
      expect(update.newSellingPrice, equals(23.75));
    });

    test('Does not change price while older FIFO batch still has remaining qty',
        () {
      final batch1 = ProductBatch(
        id: 'b1',
        productId: 'p1',
        quantityRemaining: 5,
        unitCost: 20.0,
        dateReceived: DateTime(2026, 1, 1),
      );
      final newArrival = ProductBatch(
        id: 'b2',
        productId: 'p1',
        quantityRemaining: 15,
        unitCost: 26.0,
        dateReceived: DateTime(2026, 1, 12),
      );

      final product = Product(
        id: 'p1',
        name: 'Coke',
        category: 'Beverages & Cold Items',
        price: 24.0,
        costPrice: 20.0,
        stock: 5,
        batches: [batch1],
      );

      final update = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: [batch1, newArrival],
        settings: settings,
      );

      expect(update, isNull);
    });

    test('Zero-cost next FIFO batch flags warning and preserves selling price',
        () {
      final batch1 = ProductBatch(
        id: 'b1',
        productId: 'p1',
        quantityRemaining: 1,
        unitCost: 20.0,
        dateReceived: DateTime(2026, 1, 1),
      );
      final badBatch = ProductBatch(
        id: 'b2',
        productId: 'p1',
        quantityRemaining: 10,
        unitCost: 0.0,
        dateReceived: DateTime(2026, 1, 10),
      );

      final product = Product(
        id: 'p1',
        name: 'Item',
        category: 'Others',
        price: 24.0,
        costPrice: 20.0,
        stock: 11,
        batches: [batch1, badBatch],
      );

      final update = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: [badBatch],
        settings: settings,
      );

      expect(update, isNotNull);
      expect(update!.hasInvalidCost, isTrue);
      expect(update.newSellingPrice, equals(24.0));
    });

    test('PricingEngine.calculate preserves locked unitPriceAtSale on orders',
        () {
      const updatedCatalogProduct = Product(
        id: 'p1',
        name: 'Sardines',
        category: 'Basic Staples & Essentials',
        price: 30.0, // Price increased later
        costPrice: 25.0,
        stock: 10,
      );

      const lockedOrderItem = CartItem(
        productId: 'p1',
        name: 'Sardines',
        price: 24.0,
        unitPriceAtSale: 24.0, // Locked at checkout
        qty: 2,
      );

      final breakdown = PricingEngine.calculate(
        items: const [lockedOrderItem],
        allProducts: const [updatedCatalogProduct],
      );

      // Total must remain locked at 24.0 * 2 = 48.0, never retroactively 60.0
      expect(breakdown.total, equals(48.0));
    });
  });

  group('5. Rolling Sales Velocity Score Normalization', () {
    test('Normalizes 7-day and 30-day unit sales velocity to 0.0–1.0', () {
      final now = DateTime(2026, 11, 24, 12, 0);
      final products = [
        const Product(
            id: 'fast', name: 'Fast', category: 'Others', price: 10, stock: 50),
        const Product(
            id: 'mid', name: 'Mid', category: 'Others', price: 10, stock: 50),
        const Product(
            id: 'slow', name: 'Slow', category: 'Others', price: 10, stock: 50),
      ];

      final transactions = [
        StoreTransaction(
          id: 'tx1',
          items: const [
            CartItem(productId: 'fast', name: 'Fast', price: 10, qty: 20),
            CartItem(productId: 'mid', name: 'Mid', price: 10, qty: 10),
          ],
          total: 300,
          cashTendered: 300,
          changeGiven: 0,
          createdAt: now.subtract(const Duration(days: 2)),
        ),
        // Older than 7 days, inside 30 days
        StoreTransaction(
          id: 'tx2',
          items: const [
            CartItem(productId: 'slow', name: 'Slow', price: 10, qty: 5),
          ],
          total: 50,
          cashTendered: 50,
          changeGiven: 0,
          createdAt: now.subtract(const Duration(days: 15)),
        ),
      ];

      final scores7d = PricingEngine.computeVelocityScores(
        products: products,
        transactions: transactions,
        windowDays: 7,
        referenceNow: now,
      );
      expect(scores7d['fast'], equals(1.0));
      expect(scores7d['mid'], equals(0.5));
      expect(scores7d['slow'], equals(0.0));
      expect(
          PricingEngine.getSpeedTag(scores7d['fast']!), equals('Fast Moving'));
      expect(PricingEngine.getSpeedTag(scores7d['mid']!), equals('Moderate'));
      expect(
          PricingEngine.getSpeedTag(scores7d['slow']!), equals('Slow Moving'));

      final scores30d = PricingEngine.computeVelocityScores(
        products: products,
        transactions: transactions,
        windowDays: 30,
        referenceNow: now,
      );
      expect(scores30d['fast'], equals(1.0));
      expect(scores30d['mid'], equals(0.5));
      expect(scores30d['slow'], equals(0.25));
    });
  });
}
