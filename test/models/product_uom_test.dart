import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/models/product.dart';

void main() {
  group('Product UOM (Unit of Measure) Conversion Tests', () {
    const defaultProduct = Product(
      id: 'prod-001',
      name: 'San Miguel Pale Pilsen 330ml',
      category: 'Beverages',
      price: 65.0,
      costPrice: 20.0,
      stock: 48,
      unit: 'pcs',
      bulkUnit: 'box',
      packCost: 480.0,
      itemsPerCase: 24,
    );

    group('hasBulkPacking', () {
      test('returns true when itemsPerCase is greater than 1', () {
        final product = defaultProduct;
        expect(product.hasBulkPacking, isTrue);
      });

      test('returns false when itemsPerCase is 1', () {
        final product = defaultProduct.copyWith(itemsPerCase: 1);
        expect(product.hasBulkPacking, isFalse);
      });

      test('returns false when itemsPerCase is null', () {
        const product = Product(
          id: 'prod-002',
          name: 'Single Apple',
          category: 'Fresh',
          price: 15.0,
          stock: 10,
          unit: 'pcs',
          itemsPerCase: null,
        );
        expect(product.hasBulkPacking, isFalse);
      });

      test('returns false when itemsPerCase is 0 or negative', () {
        final productWithZero = defaultProduct.copyWith(itemsPerCase: 0);
        expect(productWithZero.hasBulkPacking, isFalse);

        final productWithNegative = defaultProduct.copyWith(itemsPerCase: -5);
        expect(productWithNegative.hasBulkPacking, isFalse);
      });
    });

    group('convertBulkToUnits', () {
      test('converts 3 bulk boxes (piecesPerPack = 24) to exactly 72 base units', () {
        final product = defaultProduct; // itemsPerCase = 24
        final result = product.convertBulkToUnits(3);
        expect(result, equals(72));
      });

      test('returns 0 base units when converting 0 bulk boxes', () {
        final product = defaultProduct;
        expect(product.convertBulkToUnits(0), equals(0));
      });

      test('clamps negative bulk quantities to 0', () {
        final product = defaultProduct;
        expect(product.convertBulkToUnits(-3), equals(0));
      });

      test('defaults to piecesPerPack of 1 when itemsPerCase is null or 0', () {
        const productNull = Product(
          id: 'prod-003',
          name: 'Loose Candy',
          category: 'Snacks',
          price: 2.0,
          stock: 50,
          unit: 'pcs',
          itemsPerCase: null,
        );
        expect(productNull.piecesPerPack, equals(1));
        expect(productNull.convertBulkToUnits(5), equals(5));

        final productZero = defaultProduct.copyWith(itemsPerCase: 0);
        expect(productZero.piecesPerPack, equals(1));
        expect(productZero.convertBulkToUnits(5), equals(5));
      });
    });

    group('calculateUnitCostFromPack', () {
      test('calculates exact unit cost from bulk pack cost (₱480.00 / 24 = ₱20.00)', () {
        final product = defaultProduct; // itemsPerCase = 24
        final unitCost = product.calculateUnitCostFromPack(480.0);
        expect(unitCost, equals(20.00));
      });

      test('handles division resulting in decimal rounding (₱500.00 / 24 = ₱20.83)', () {
        final product = defaultProduct; // itemsPerCase = 24
        // 500 / 24 = 20.833333...
        final unitCost = product.calculateUnitCostFromPack(500.0);
        expect(unitCost, equals(20.83));
      });

      test('handles fractional division rounding up (₱100.00 / 6 = ₱16.67)', () {
        final product = defaultProduct.copyWith(itemsPerCase: 6);
        // 100 / 6 = 16.66666... -> rounds to 16.67
        final unitCost = product.calculateUnitCostFromPack(100.0);
        expect(unitCost, equals(16.67));
      });

      test('returns 0.0 if bulkCost is zero or negative', () {
        final product = defaultProduct;
        expect(product.calculateUnitCostFromPack(0.0), equals(0.0));
        expect(product.calculateUnitCostFromPack(-480.0), equals(0.0));
      });

      test('returns bulkCost unmodified when itemsPerCase is 0 or null (piecesPerPack defaults to 1)', () {
        final product = defaultProduct.copyWith(itemsPerCase: 0);
        expect(product.calculateUnitCostFromPack(500.0), equals(500.0));
      });
    });

    group('formattedBulkStock', () {
      test('formats exact box counts correctly (48 pcs = "2 boxes")', () {
        final product = defaultProduct.copyWith(stock: 48, itemsPerCase: 24, bulkUnit: 'box', unit: 'pcs');
        expect(product.formattedBulkStock, equals('2 boxes'));
      });

      test('formats single box count correctly (24 pcs = "1 box")', () {
        final product = defaultProduct.copyWith(stock: 24, itemsPerCase: 24, bulkUnit: 'box', unit: 'pcs');
        expect(product.formattedBulkStock, equals('1 box'));
      });

      test('formats loose pieces correctly when stock is less than a box (10 pcs = "10 pcs")', () {
        final product = defaultProduct.copyWith(stock: 10, itemsPerCase: 24, bulkUnit: 'box', unit: 'pcs');
        expect(product.formattedBulkStock, equals('10 pcs'));
      });

      test('formats mixed stock correctly with boxes and loose pieces (50 pcs = "2 boxes, 2 pcs")', () {
        final product = defaultProduct.copyWith(stock: 50, itemsPerCase: 24, bulkUnit: 'box', unit: 'pcs');
        expect(product.formattedBulkStock, equals('2 boxes, 2 pcs'));
      });

      test('formats single box with remainder correctly (29 pcs = "1 box, 5 pcs")', () {
        final product = defaultProduct.copyWith(stock: 29, itemsPerCase: 24, bulkUnit: 'box', unit: 'pcs');
        expect(product.formattedBulkStock, equals('1 box, 5 pcs'));
      });

      test('returns "0 pcs" when stock is zero or negative', () {
        final productZero = defaultProduct.copyWith(stock: 0, itemsPerCase: 24, bulkUnit: 'box', unit: 'pcs');
        expect(productZero.formattedBulkStock, equals('0 pcs'));

        final productNegative = defaultProduct.copyWith(stock: -5, itemsPerCase: 24, bulkUnit: 'box', unit: 'pcs');
        expect(productNegative.formattedBulkStock, equals('0 pcs'));
      });

      test('returns base stock string for products without bulk packing', () {
        const product = Product(
          id: 'prod-004',
          name: 'Loose Bread',
          category: 'Fresh',
          price: 10.0,
          stock: 15,
          unit: 'pcs',
          itemsPerCase: null,
        );
        expect(product.formattedBulkStock, equals('15 pcs'));
      });
    });
  });
}
