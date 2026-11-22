import '../models/order.dart';
import '../models/product.dart';

/// Pricing calculation breakdown structure containing subtotal, VAT amount, and grand total.
class PricingBreakdown {
  final double subtotal;
  final double vAtAmount; // 12% of VATable sales
  final double total; // Final amount to pay
  final double savings; // Wholesale discount savings

  const PricingBreakdown({
    required this.subtotal,
    required this.vAtAmount,
    required this.total,
    this.savings = 0.0,
  });
}

/// Category-specific profit markup rules for Smart Pricing Engine.
class CategoryMarkupRules {
  static const Map<String, double> categoryMargins = {
    'Beverages': 0.20, // 20% margin
    'Snacks': 0.30, // 30% margin
    'Canned Goods': 0.25, // 25% margin
    'Personal Care': 0.25, // 25% margin
    'Condiments': 0.25, // 25% margin
    'Fresh': 0.20, // 20% margin
    'Grains': 0.15, // 15% margin
  };

  static const double defaultMargin = 0.15; // 15% fallback

  /// Returns recommended profit margin percentage for a product [category].
  static double getMarginForCategory(String category) {
    return categoryMargins[category] ?? defaultMargin;
  }

  /// Calculates auto-suggested selling price based on Unit Cost and Category Margin %.
  static double calculateSellingPrice({
    required double unitCost,
    required String category,
  }) {
    if (unitCost <= 0) return 0.0;
    final margin = getMarginForCategory(category);
    return unitCost * (1 + margin);
  }
}

/// Pricing calculation engine for computing subtotal, 12% VAT tax, and total cart amounts.
class PricingEngine {
  static const double vatRate = 0.12;

  /// Calculates total price, taxable amounts, and VAT breakdowns for a list of [items].
  static PricingBreakdown calculate({
    required List<CartItem> items,
    required List<Product> allProducts,
  }) {
    double subtotal = 0;
    double taxableSubtotal = 0;
    double savings = 0;

    for (final item in items) {
      final product = allProducts.firstWhere((p) => p.id == item.productId,
          orElse: () => Product(
              id: item.productId,
              name: item.name,
              category: 'Others',
              price: item.price,
              stock: 0));

      final regularSubtotal = product.price * item.qty;
      final itemSubtotal = item.price * item.qty;
      
      subtotal += itemSubtotal;
      savings += (regularSubtotal - itemSubtotal);

      if (product.isTaxable) {
        taxableSubtotal += itemSubtotal;
      }
    }

    final finalVat = taxableSubtotal - (taxableSubtotal / (1 + vatRate));
    final total = subtotal.clamp(0.0, double.infinity);

    return PricingBreakdown(
      subtotal: subtotal + savings, // Subtotal usually represents price before discount
      vAtAmount: finalVat,
      total: total,
      savings: savings,
    );
  }

  /// Checks if a [sellingPrice] is strictly below the [unitCost].
  static bool isBelowCost({
    required double sellingPrice,
    required double unitCost,
  }) {
    return sellingPrice > 0 && unitCost > 0 && sellingPrice < unitCost;
  }

  /// Calculates potential per-unit financial loss if [sellingPrice] is below [unitCost].
  static double calculateUnitLoss({
    required double sellingPrice,
    required double unitCost,
  }) {
    if (!isBelowCost(sellingPrice: sellingPrice, unitCost: unitCost)) {
      return 0.0;
    }
    return unitCost - sellingPrice;
  }
}
