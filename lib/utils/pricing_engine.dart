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

/// Category-specific profit markup rules for Smart Pricing Engine
class CategoryMarkupRules {
  static const Map<String, double> categoryMargins = {
    'Beverages': 0.20,      // 20% margin
    'Snacks': 0.30,         // 30% margin
    'Canned Goods': 0.25,   // 25% margin
    'Personal Care': 0.25, // 25% margin
    'Condiments': 0.25,    // 25% margin
    'Fresh': 0.20,         // 20% margin
    'Grains': 0.15,        // 15% margin
  };

  static const double defaultMargin = 0.15; // 15% fallback

  static double getMarginForCategory(String category) {
    return categoryMargins[category] ?? defaultMargin;
  }

  /// Calculates auto-suggested selling price based on Unit Cost and Category Margin %
  static double calculateSellingPrice({
    required double unitCost,
    required String category,
  }) {
    if (unitCost <= 0) return 0.0;
    final margin = getMarginForCategory(category);
    return unitCost * (1 + margin);
  }
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

    final finalVat = taxableSubtotal - (taxableSubtotal / (1 + vatRate));
    final total = subtotal.clamp(0.0, double.infinity);

    return PricingBreakdown(
      subtotal: subtotal,
      vAtAmount: finalVat,
      total: total,
    );
  }
}
