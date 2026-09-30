import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gdc_admin_app/models/product.dart';
import 'package:gdc_admin_app/models/order.dart';
import 'package:gdc_admin_app/utils/pricing_engine.dart';
import 'package:gdc_admin_app/utils/barcode_generator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End System Integration Test Suite', () {
    testWidgets('Full Loop: Intake -> Multi-Batch -> POS FEFO Checkout -> COGS Audit', (WidgetTester tester) async {
      // ----------------------------------------------------------------------
      // Step 1: Ingest Mock Product with Initial Batch #1
      // ----------------------------------------------------------------------
      final String testBarcode = BarcodeGenerator.generateInternalBarcode();
      expect(testBarcode.startsWith('200'), true);
      expect(testBarcode.length, 12);

      const double initialUnitCost = 20.0;
      const String category = 'Snacks'; // 30% margin rule -> Selling Price ₱26.00
      final double calculatedSellingPrice = CategoryMarkupRules.calculateSellingPrice(
        unitCost: initialUnitCost,
        category: category,
      );
      expect(calculatedSellingPrice, 26.0);

      final initialBatch = ProductBatch(
        id: 'batch-001',
        productId: 'prod-1001',
        quantity: 10,
        unitCost: initialUnitCost,
        expiryDate: DateTime.now().add(const Duration(days: 15)), // Expiring in 15 days
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        invoiceNumber: 'INV-001',
      );

      final product = Product(
        id: 'prod-1001',
        name: 'Test Potato Chips 100g',
        brand: 'GDC Brand',
        category: category,
        price: calculatedSellingPrice,
        costPrice: initialUnitCost,
        stock: 10,
        unit: 'pcs',
        barcode: testBarcode,
        batches: [initialBatch],
      );

      // ----------------------------------------------------------------------
      // Step 2: Simulate Second Delivery Batch #2 (Higher Cost, Later Expiry)
      // ----------------------------------------------------------------------
      final secondBatch = ProductBatch(
        id: 'batch-002',
        productId: 'prod-1001',
        quantity: 20,
        unitCost: 22.0,
        expiryDate: DateTime.now().add(const Duration(days: 60)), // Expiring in 60 days
        createdAt: DateTime.now(),
        invoiceNumber: 'INV-002',
      );

      final updatedProductMultiBatch = product.copyWith(
        stock: product.stock + secondBatch.quantity, // 10 + 20 = 30 pcs
        batches: [...product.batches, secondBatch],
      );

      expect(updatedProductMultiBatch.stock, 30);
      expect(updatedProductMultiBatch.batches.length, 2);

      // ----------------------------------------------------------------------
      // Step 3: Simulate POS Cart Purchase across Batch Threshold (Buy 15 pcs)
      // ----------------------------------------------------------------------
      final initialCartItem = CartItem(
        productId: 'prod-1001',
        name: 'Test Potato Chips 100g',
        price: calculatedSellingPrice, // ₱26.00
        costPrice: initialUnitCost,     // ₱20.00 base
        qty: 15,                        // Exceeds Batch #1 (10 pcs) by 5 pcs
        isPerishable: true,
      );

      // ----------------------------------------------------------------------
      // Step 4: Perform In-Memory FEFO Batch Stock Deduction (FEFO Logic)
      // ----------------------------------------------------------------------
      int remainingToDeduct = initialCartItem.qty; // 15 pcs
      final List<ProductBatch> sortedBatches = List.from(updatedProductMultiBatch.batches);

      // Sort by FEFO (expiry date ascending)
      sortedBatches.sort((a, b) {
        if (a.expiryDate != null && b.expiryDate != null) {
          return a.expiryDate!.compareTo(b.expiryDate!);
        }
        return a.createdAt.compareTo(b.createdAt);
      });

      // Verify Batch #1 is sorted first (expires in 15 days vs 60 days)
      expect(sortedBatches.first.id, 'batch-001');

      final List<ProductBatch> postCheckoutBatches = [];
      final List<BatchDepletionRecord> depletedBatches = [];
      double totalCogsForOrder = 0.0;

      for (final b in sortedBatches) {
        if (remainingToDeduct <= 0) {
          postCheckoutBatches.add(b);
          continue;
        }

        if (b.quantity > remainingToDeduct) {
          // Partial deduction
          final int deductedQty = remainingToDeduct;
          totalCogsForOrder += (deductedQty * b.unitCost);
          depletedBatches.add(BatchDepletionRecord(
            batchId: b.id,
            quantity: deductedQty,
            unitCost: b.unitCost,
          ));

          postCheckoutBatches.add(ProductBatch(
            id: b.id,
            productId: b.productId,
            quantity: b.quantity - deductedQty,
            unitCost: b.unitCost,
            expiryDate: b.expiryDate,
            createdAt: b.createdAt,
            invoiceNumber: b.invoiceNumber,
          ));
          remainingToDeduct = 0;
        } else {
          // Full batch depletion
          final int deductedQty = b.quantity;
          totalCogsForOrder += (deductedQty * b.unitCost);
          depletedBatches.add(BatchDepletionRecord(
            batchId: b.id,
            quantity: deductedQty,
            unitCost: b.unitCost,
          ));
          remainingToDeduct -= deductedQty;
        }
      }

      final double weightedCostPrice = totalCogsForOrder / initialCartItem.qty;
      final finalCartItem = initialCartItem.copyWith(
        costPrice: weightedCostPrice,
        totalCogs: totalCogsForOrder,
        depletedBatches: depletedBatches,
      );

      // ----------------------------------------------------------------------
      // Step 5: Assert Split-Batch Payload & Financial Reconciliation
      // ----------------------------------------------------------------------
      // 10 pcs from Batch #1 @ ₱20 = ₱200
      // 5 pcs from Batch #2 @ ₱22 = ₱110
      // Total COGS = ₱310.00
      expect(finalCartItem.totalCogs, 310.0);
      expect(finalCartItem.costPrice, (310.0 / 15));
      expect(finalCartItem.depletedBatches.length, 2);

      expect(finalCartItem.depletedBatches[0].batchId, 'batch-001');
      expect(finalCartItem.depletedBatches[0].quantity, 10);
      expect(finalCartItem.depletedBatches[0].unitCost, 20.0);

      expect(finalCartItem.depletedBatches[1].batchId, 'batch-002');
      expect(finalCartItem.depletedBatches[1].quantity, 5);
      expect(finalCartItem.depletedBatches[1].unitCost, 22.0);

      // Batch #1 should be completely depleted (removed from active batches)
      expect(postCheckoutBatches.length, 1);
      expect(postCheckoutBatches.first.id, 'batch-002');
      expect(postCheckoutBatches.first.quantity, 15); // 20 - 5 = 15 pcs remaining

      final int finalProductStock = postCheckoutBatches.fold(0, (sum, b) => sum + b.quantity);
      expect(finalProductStock, 15); // 30 - 15 = 15 pcs remaining

      // Total Revenue = 15 pcs * ₱26 = ₱390.00
      final double totalRevenue = finalCartItem.qty * finalCartItem.price;
      expect(totalRevenue, 390.0);

      // Net Profit = Revenue (₱390) - True COGS (₱310) = ₱80.00
      final double netProfit = totalRevenue - finalCartItem.totalCogs;
      expect(netProfit, 80.0);

      final double profitMarginPercentage = (netProfit / totalRevenue) * 100;
      expect(profitMarginPercentage.toStringAsFixed(2), '20.51');
    });
  });
}
