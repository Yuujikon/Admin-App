import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/utils/inventory_math.dart';

void main() {
  group('Refund math & variant restock helpers', () {
    test('computeRefundLossUnitCost prefers COGS over retail price', () {
      expect(
        computeRefundLossUnitCost(
          itemCostPrice: 14.5,
          productCostPrice: 15.0,
          retailPrice: 25.0,
        ),
        equals(14.5),
      );

      expect(
        computeRefundLossUnitCost(
          itemCostPrice: 0.0,
          productCostPrice: 15.0,
          retailPrice: 25.0,
        ),
        equals(15.0),
      );

      expect(
        computeRefundLossUnitCost(
          itemCostPrice: 0.0,
          productCostPrice: 0.0,
          retailPrice: 25.0,
        ),
        equals(25.0),
      );
    });

    test('computeStockRestockDeltas updates BOTH variant and top-level stock for variants', () {
      final variantDeltas = computeStockRestockDeltas(variantId: 'spicy', qty: 3);
      expect(variantDeltas, equals({
        'variants.spicy.stock': 3,
        'stock': 3,
      }));

      final baseDeltas = computeStockRestockDeltas(variantId: null, qty: 3);
      expect(baseDeltas, equals({'stock': 3}));

      final emptyVariantDeltas = computeStockRestockDeltas(variantId: '', qty: -2);
      expect(emptyVariantDeltas, equals({'stock': -2}));
    });

    test('safeShortId never throws RangeError on short or empty strings', () {
      expect(safeShortId(''), equals(''));
      expect(safeShortId('ABC'), equals('ABC'));
      expect(safeShortId('12345'), equals('12345'));
      expect(safeShortId('123456789'), equals('12345'));
      expect(safeShortId('123456789', 8), equals('12345678'));
    });
  });
}
