import '../models/order.dart';
import '../models/product.dart';
import '../models/promotion.dart';

class PricingBreakdown {
  final double subtotal;      // Before any discounts
  final double promoDiscount; // From active promotions
  final double vAtAmount;     // 12% of VATable sales
  final double seniorDiscount; // 20% if applicable
  final double pointsDiscount; // Redemeed points value
  final double total;         // Final amount to pay

  const PricingBreakdown({
    required this.subtotal,
    required this.promoDiscount,
    required this.vAtAmount,
    required this.seniorDiscount,
    required this.pointsDiscount,
    required this.total,
  });
}

class PricingEngine {
  static const double vatRate = 0.12;

  static PricingBreakdown calculate({
    required List<CartItem> items,
    required List<Product> allProducts,
    required List<Promotion> activePromos,
    bool isSeniorOrPWD = false,
    int pointsToRedeem = 0,
  }) {
    double subtotal = 0;
    double totalPromoDiscount = 0;
    double taxableSubtotal = 0;
    
    const double pointsValueRate = 1.0; // 1 point = ₱1.00
    double pointsDiscount = pointsToRedeem * pointsValueRate;

    for (final item in items) {
      final product = allProducts.firstWhere((p) => p.id == item.productId, 
          orElse: () => Product(id: item.productId, name: item.name, category: 'Others', price: item.price, stock: 0));
      
      final itemSubtotal = product.price * item.qty;
      subtotal += itemSubtotal;

      // 1. Apply Product/Category Discounts from Promotions
      double itemPromoDiscount = 0;
      for (final promo in activePromos) {
        if (!promo.isCurrentlyActive) continue;

        bool isTarget = false;
        if (promo.type == PromotionType.productDiscount && promo.targetIds.contains(product.id)) isTarget = true;
        if (promo.type == PromotionType.categoryDiscount && promo.targetIds.contains(product.category)) isTarget = true;

        if (isTarget) {
          if (promo.isPercentage) {
            itemPromoDiscount += (product.price * (promo.discountValue / 100)) * item.qty;
          } else {
            itemPromoDiscount += promo.discountValue * item.qty;
          }
        }
      }

      // 2. Apply BOGO / Bundle Discounts
      for (final promo in activePromos) {
        if (!promo.isCurrentlyActive) continue;
        if (promo.type == PromotionType.bogo && promo.targetIds.contains(product.id)) {
          final buy = promo.buyQty ?? 1;
          final get = promo.getQty ?? 1;
          final bundles = (item.qty / (buy + get)).floor();
          itemPromoDiscount += bundles * get * product.price;
        }
      }

      totalPromoDiscount += itemPromoDiscount;

      if (product.isTaxable) {
        taxableSubtotal += (itemSubtotal - itemPromoDiscount);
      }
    }

    double seniorDiscount = 0;
    double finalVat = 0;

    if (isSeniorOrPWD) {
      // VAT Exempt + 20% discount on the net-of-VAT amount
      // Standard PH logic: (Sales / 1.12) * 0.20
      seniorDiscount = (taxableSubtotal / (1 + vatRate)) * 0.20;
      finalVat = 0; // Exempt
    } else {
      // Regular VAT calculation: Taxable amount is inclusive of VAT
      // Tax = Amount - (Amount / 1.12)
      finalVat = taxableSubtotal - (taxableSubtotal / (1 + vatRate));
    }

    final total = (subtotal - totalPromoDiscount - seniorDiscount - pointsDiscount).clamp(0.0, double.infinity);

    return PricingBreakdown(
      subtotal: subtotal,
      promoDiscount: totalPromoDiscount,
      vAtAmount: finalVat,
      seniorDiscount: seniorDiscount,
      pointsDiscount: pointsDiscount,
      total: total,
    );
  }
}
