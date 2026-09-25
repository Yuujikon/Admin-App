import '../models/order.dart';
import '../models/product.dart';

class PricingBreakdown {
  final double subtotal;
  final double vAtAmount;     // 12% of VATable sales
  final double total;         // Final amount to pay

  const PricingBreakdown({
    required this.subtotal,
    required this.vAtAmount,
    required this.total,
  });
}

class PricingEngine {
  static const double vatRate = 0.12;

  static PricingBreakdown calculate({
    required List<CartItem> items,
    required List<Product> allProducts,
  }) {
    double subtotal = 0;
    double taxableSubtotal = 0;

    for (final item in items) {
      final product = allProducts.firstWhere((p) => p.id == item.productId, 
          orElse: () => Product(id: item.productId, name: item.name, category: 'Others', price: item.price, stock: 0));
      
      final itemSubtotal = product.price * item.qty;
      subtotal += itemSubtotal;

      if (product.isTaxable) {
        taxableSubtotal += itemSubtotal;
      }
    }

    // Regular VAT calculation: Taxable amount is inclusive of VAT
    // Tax = Amount - (Amount / 1.12)
    final finalVat = taxableSubtotal - (taxableSubtotal / (1 + vatRate));
    final total = subtotal.clamp(0.0, double.infinity);

    return PricingBreakdown(
      subtotal: subtotal,
      vAtAmount: finalVat,
      total: total,
    );
  }
}
