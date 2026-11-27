import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/models/order.dart';
import 'package:gdc_admin_app/models/product.dart';
import 'package:gdc_admin_app/screens/pos_screen.dart';

void main() {
  Widget buildTile({
    required CartItem item,
    required Product? product,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 480,
          child: PosCartItemTile(
            item: item,
            product: product,
            onSetQty: (_, __, ___) {},
            onRemove: (_, __) {},
          ),
        ),
      ),
    );
  }

  group('PosCartItemTile — Available Stock Display', () {
    testWidgets('shows available stock with product unit for picked item',
        (tester) async {
      const product = Product(
        id: 'p1',
        name: 'Lucky Me Pancit Canton',
        category: 'Noodles',
        price: 16.0,
        costPrice: 12.0,
        stock: 20,
        reservedStock: 3,
        unit: 'pack',
      );
      const item = CartItem(
        productId: 'p1',
        name: 'Lucky Me Pancit Canton',
        price: 16.0,
        costPrice: 12.0,
        qty: 2,
      );

      await tester.pumpWidget(buildTile(item: item, product: product));

      expect(find.text('Available: 17 pack'), findsOneWidget);
    });

    testWidgets('shows (Max) when picked qty reaches available stock',
        (tester) async {
      const product = Product(
        id: 'p2',
        name: 'Sardines',
        category: 'Canned Goods',
        price: 25.0,
        costPrice: 20.0,
        stock: 5,
        unit: 'can',
      );
      const item = CartItem(
        productId: 'p2',
        name: 'Sardines',
        price: 25.0,
        costPrice: 20.0,
        qty: 5,
      );

      await tester.pumpWidget(buildTile(item: item, product: product));

      expect(find.text('Available: 5 can (Max)'), findsOneWidget);
    });

    testWidgets('shows variant available stock when item has a variantId',
        (tester) async {
      const product = Product(
        id: 'p3',
        name: 'Coca-Cola',
        category: 'Beverages',
        price: 20.0,
        stock: 0,
        unit: 'bottle',
        variants: [
          ProductVariant(
            id: 'v1',
            name: 'Mismo 295ml',
            price: 20.0,
            stock: 10,
            reservedStock: 2,
          ),
          ProductVariant(
            id: 'v2',
            name: '1.5L',
            price: 75.0,
            stock: 4,
          ),
        ],
      );
      const item = CartItem(
        productId: 'p3',
        variantId: 'v1',
        name: 'Coca-Cola (Mismo 295ml)',
        variantName: 'Mismo 295ml',
        price: 20.0,
        qty: 1,
      );

      await tester.pumpWidget(buildTile(item: item, product: product));

      expect(find.text('Available: 8 bottle'), findsOneWidget);
    });

    testWidgets('shows Available: 0 when picked item is out of stock',
        (tester) async {
      const product = Product(
        id: 'p4',
        name: 'Eggs',
        category: 'Fresh',
        price: 10.0,
        stock: 0,
        unit: 'pcs',
      );
      const item = CartItem(
        productId: 'p4',
        name: 'Eggs',
        price: 10.0,
        qty: 1,
      );

      await tester.pumpWidget(buildTile(item: item, product: product));

      expect(find.text('Available: 0 pcs'), findsOneWidget);
    });
  });
}
