import '../models/order.dart';
import '../models/product.dart';
import '../models/store_settings.dart';
import '../models/transaction.dart';

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

/// Represents a category's `[minMarkup, maxMarkup]` percentage range.
class CategoryMarkupRange {
  final String canonicalCategory;
  final double minMarkup; // e.g. 5.0 (%)
  final double maxMarkup; // e.g. 15.0 (%)
  final bool isFallback;

  const CategoryMarkupRange({
    required this.canonicalCategory,
    required this.minMarkup,
    required this.maxMarkup,
    this.isFallback = false,
  });

  String get formattedRange =>
      '${minMarkup.toStringAsFixed(1)}% – ${maxMarkup.toStringAsFixed(1)}%';
}

/// Detailed pricing evaluation output for Admin UI previews and safety checks.
class ItemPricingResult {
  final double unitCost;
  final bool hasInvalidCost;
  final String? warningMessage;
  final String pricingMode;
  final CategoryMarkupRange categoryRange;
  final double velocityScore;
  final String speedTag;
  final double computedMarkupPercent;
  final double rawSellingPrice;
  final double finalSellingPrice;
  final double roundingStep;
  final bool usedGlobalBenchmarkOnly;

  const ItemPricingResult({
    required this.unitCost,
    required this.hasInvalidCost,
    this.warningMessage,
    required this.pricingMode,
    required this.categoryRange,
    required this.velocityScore,
    required this.speedTag,
    required this.computedMarkupPercent,
    required this.rawSellingPrice,
    required this.finalSellingPrice,
    required this.roundingStep,
    required this.usedGlobalBenchmarkOnly,
  });
}

/// Output when an active FIFO batch transition triggers a selling price recalculation.
class FifoPricingUpdate {
  final double newActiveUnitCost;
  final double computedMarkupPercent;
  final double newSellingPrice;
  final bool hasInvalidCost;

  const FifoPricingUpdate({
    required this.newActiveUnitCost,
    required this.computedMarkupPercent,
    required this.newSellingPrice,
    this.hasInvalidCost = false,
  });
}

/// Summary returned after running a background/manual velocity pricing sync.
class VelocitySyncSummary {
  final int updatedAutoCount;
  final int preservedManualCount;
  final int skippedZeroCostCount;

  const VelocitySyncSummary({
    required this.updatedAutoCount,
    required this.preservedManualCount,
    required this.skippedZeroCostCount,
  });
}

/// Pure helper function that calculates the active markup percentage for [item]
/// in strict priority order:
/// 1. Admin Override (`pricingMode == 'manual'` and `manualMarkupPercent != null`)
/// 2. Category Base Range Lookup (`pricingMode == 'auto'`)
/// 3. Velocity Scaling Formula (15%–25% global benchmark blended with category bounds)
double calculateItemMarkup(
  Product item, {
  bool useGlobalBenchmarkOnly = false,
}) {
  // 1. Admin Override Check (Highest Priority)
  if (item.pricingMode == Product.pricingModeManual &&
      item.manualMarkupPercent != null &&
      item.manualMarkupPercent!.isFinite) {
    return double.parse(item.manualMarkupPercent!.toStringAsFixed(2));
  }

  // 2. Category Base Range Lookup (pricingMode == 'auto')
  final CategoryMarkupRange range =
      CategoryMarkupRules.getRangeForCategory(item.category);

  // 3. Velocity Scaling Formula
  final double rawV =
      item.salesVelocityScore.isFinite ? item.salesVelocityScore : 0.5;
  final double v = rawV.clamp(0.0, 1.0).toDouble();

  final double velocityTarget = CategoryMarkupRules.globalMinMarkup +
      (v *
          (CategoryMarkupRules.globalMaxMarkup -
              CategoryMarkupRules.globalMinMarkup));

  final double categoryTarget =
      range.minMarkup + (v * (range.maxMarkup - range.minMarkup));

  // Default rule: Use categoryTarget for defined categories, and velocityTarget (15%–25%)
  // for Others/uncategorized or when Store Settings enables pure global benchmark mode.
  final double finalMarkup = (useGlobalBenchmarkOnly || range.isFallback)
      ? velocityTarget
      : categoryTarget;

  return double.parse(finalMarkup.toStringAsFixed(2));
}

/// Category-specific profit markup ranges for Dynamic Velocity-Based Pricing Engine.
class CategoryMarkupRules {
  static const double globalMinMarkup = 15.0;
  static const double globalMaxMarkup = 25.0;

  static const CategoryMarkupRange basicStaplesRange = CategoryMarkupRange(
    canonicalCategory: 'Basic Staples & Essentials',
    minMarkup: 5.0,
    maxMarkup: 15.0,
  );

  static const CategoryMarkupRange beveragesRange = CategoryMarkupRange(
    canonicalCategory: 'Beverages & Cold Items',
    minMarkup: 15.0,
    maxMarkup: 25.0,
  );

  static const CategoryMarkupRange personalCareRange = CategoryMarkupRange(
    canonicalCategory: 'Personal Care & Toiletries',
    minMarkup: 20.0,
    maxMarkup: 30.0,
  );

  static const CategoryMarkupRange householdRange = CategoryMarkupRange(
    canonicalCategory: 'Household & Cleaning Supplies',
    minMarkup: 15.0,
    maxMarkup: 25.0,
  );

  static const CategoryMarkupRange snacksRange = CategoryMarkupRange(
    canonicalCategory: 'Snacks, Candies & Biscuits',
    minMarkup: 15.0,
    maxMarkup: 25.0,
  );

  static const CategoryMarkupRange condimentsRange = CategoryMarkupRange(
    canonicalCategory: 'Condiments & Cooking Basics',
    minMarkup: 10.0,
    maxMarkup: 20.0,
  );

  static const CategoryMarkupRange alcoholTobaccoRange = CategoryMarkupRange(
    canonicalCategory: 'Alcohol & Cigarettes/Tobacco',
    minMarkup: 5.0,
    maxMarkup: 15.0,
  );

  static const CategoryMarkupRange othersRange = CategoryMarkupRange(
    canonicalCategory: 'Others',
    minMarkup: 15.0,
    maxMarkup: 25.0,
    isFallback: true,
  );

  /// All defined canonical category ranges for reference and UI display.
  static const List<CategoryMarkupRange> allRanges = [
    basicStaplesRange,
    beveragesRange,
    personalCareRange,
    householdRange,
    snacksRange,
    condimentsRange,
    alcoholTobaccoRange,
    othersRange,
  ];

  /// Maps any [category] string (case-insensitive) to its `[minMarkup, maxMarkup]` bounds.
  /// Supports both full canonical category labels and existing short sari-sari categories.
  static CategoryMarkupRange getRangeForCategory(String category) {
    final normalized = category.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized == 'others' ||
        normalized == 'other' ||
        normalized == 'uncategorized' ||
        normalized == 'general') {
      return othersRange;
    }

    // 1. Basic Staples & Essentials (Rice, Eggs, Instant Noodles, Canned Goods): 5.0% – 15.0%
    if (normalized == 'basic staples & essentials' ||
        normalized.contains('staple') ||
        normalized.contains('essential') ||
        normalized.contains('rice') ||
        normalized.contains('grain') ||
        normalized.contains('egg') ||
        normalized.contains('noodle') ||
        normalized.contains('canned') ||
        normalized == 'fresh') {
      return basicStaplesRange;
    }

    // 2. Alcohol & Cigarettes/Tobacco: 5.0% – 15.0%
    // Checked before beverages so "alcohol/beer" isn't caught by generic drink keywords.
    if (normalized == 'alcohol & cigarettes/tobacco' ||
        normalized.contains('alcohol') ||
        normalized.contains('cigarette') ||
        normalized.contains('tobacco') ||
        normalized.contains('liquor') ||
        normalized.contains('beer') ||
        normalized.contains('wine')) {
      return alcoholTobaccoRange;
    }

    // 3. Beverages & Cold Items (Soft Drinks, Bottled Water, Ice): 15.0% – 25.0%
    if (normalized == 'beverages & cold items' ||
        normalized.contains('beverage') ||
        normalized.contains('cold item') ||
        normalized.contains('soft drink') ||
        normalized.contains('drink') ||
        normalized.contains('water') ||
        normalized == 'ice' ||
        normalized.contains('ice ')) {
      return beveragesRange;
    }

    // 4. Personal Care & Toiletries (Soap, Shampoo, Toothpaste, Tissue): 20.0% – 30.0%
    if (normalized == 'personal care & toiletries' ||
        normalized.contains('personal care') ||
        normalized.contains('toiletr') ||
        normalized.contains('soap') ||
        normalized.contains('shampoo') ||
        normalized.contains('toothpaste') ||
        normalized.contains('tissue') ||
        normalized.contains('hygiene')) {
      return personalCareRange;
    }

    // 5. Household & Cleaning Supplies (Detergent, Dishwashing Liquid): 15.0% – 25.0%
    if (normalized == 'household & cleaning supplies' ||
        normalized.contains('household') ||
        normalized.contains('cleaning') ||
        normalized.contains('detergent') ||
        normalized.contains('dishwashing') ||
        normalized.contains('laundry')) {
      return householdRange;
    }

    // 6. Snacks, Candies & Biscuits: 15.0% – 25.0%
    if (normalized == 'snacks, candies & biscuits' ||
        normalized.contains('snack') ||
        normalized.contains('cand') ||
        normalized.contains('biscuit') ||
        normalized.contains('chip') ||
        normalized.contains('crack')) {
      return snacksRange;
    }

    // 7. Condiments & Cooking Basics (Oil, Soy Sauce, Vinegar, Sugar, Salt): 10.0% – 20.0%
    if (normalized == 'condiments & cooking basics' ||
        normalized.contains('condiment') ||
        normalized.contains('cooking') ||
        normalized.contains('soy sauce') ||
        normalized.contains('vinegar') ||
        normalized.contains('sugar') ||
        normalized.contains('salt') ||
        normalized.contains('oil') ||
        normalized.contains('seasoning')) {
      return condimentsRange;
    }

    // 8. Others / Uncategorized Fallback: 15.0% – 25.0%
    return othersRange;
  }

  /// Backward-compatible decimal margin lookup (evaluates category range at neutral velocity 0.5).
  static double getMarginForCategory(
    String category, {
    double velocityScore = 0.5,
    bool useGlobalBenchmarkOnly = false,
  }) {
    final pct = calculateItemMarkup(
      Product(
        id: '',
        name: '',
        category: category,
        price: 0,
        stock: 0,
        pricingMode: Product.pricingModeAuto,
        salesVelocityScore: velocityScore,
      ),
      useGlobalBenchmarkOnly: useGlobalBenchmarkOnly,
    );
    return pct / 100.0;
  }

  /// Calculates auto-suggested selling price based on Unit Cost, Category, and Sales Velocity.
  /// Returns `0.0` safely when [unitCost] is `<= 0` or non-finite.
  static double calculateSellingPrice({
    required double unitCost,
    required String category,
    double velocityScore = 0.5,
    bool useGlobalBenchmarkOnly = false,
    double roundingStep = 0.25,
  }) {
    if (!unitCost.isFinite || unitCost <= 0) return 0.0;
    final markupPct = calculateItemMarkup(
      Product(
        id: '',
        name: '',
        category: category,
        price: 0,
        costPrice: unitCost,
        stock: 0,
        pricingMode: Product.pricingModeAuto,
        salesVelocityScore: velocityScore,
      ),
      useGlobalBenchmarkOnly: useGlobalBenchmarkOnly,
    );
    return PricingEngine.calculateFinalSellingPrice(
      unitCost: unitCost,
      markupPercent: markupPct,
      roundingStep: roundingStep,
    );
  }
}

/// Pricing calculation engine for dynamic velocity markups, Philippine rounding,
/// FIFO batch price updates, and POS VAT/cart breakdowns.
class PricingEngine {
  static const double vatRate = 0.12;

  /// Supported Philippine sari-sari store price rounding steps.
  static const List<double> supportedRoundingSteps = [0.25, 0.50, 1.00];

  /// Returns a human-readable speed tag for a normalized velocity score `[0.0, 1.0]`.
  static String getSpeedTag(double velocityScore) {
    final v =
        velocityScore.isFinite ? velocityScore.clamp(0.0, 1.0).toDouble() : 0.5;
    if (v < 0.34) return 'Slow Moving';
    if (v >= 0.67) return 'Fast Moving';
    return 'Moderate';
  }

  /// Applies standard Philippine sari-sari store rounding (e.g. nearest ₱0.25, ₱0.50, or ₱1.00).
  static double roundPhilippinePrice(double rawPrice, {double step = 0.25}) {
    if (!rawPrice.isFinite || rawPrice <= 0) return 0.0;
    if (!step.isFinite || step <= 0) {
      return double.parse(rawPrice.toStringAsFixed(2));
    }
    final double rounded = (rawPrice / step).round() * step;
    return double.parse(rounded.toStringAsFixed(2));
  }

  /// Computes raw selling price `unitCost * (1 + markupPercent / 100)` and applies Philippine rounding.
  /// Returns `0.0` safely when [unitCost] <= 0 or non-finite.
  static double calculateFinalSellingPrice({
    required double unitCost,
    required double markupPercent,
    double roundingStep = 0.25,
  }) {
    if (!unitCost.isFinite || unitCost <= 0 || !markupPercent.isFinite) {
      return 0.0;
    }
    final double rawSellingPrice = unitCost * (1.0 + (markupPercent / 100.0));
    if (!rawSellingPrice.isFinite || rawSellingPrice <= 0) return 0.0;
    return roundPhilippinePrice(rawSellingPrice, step: roundingStep);
  }

  /// Reverse-calculates `manualMarkupPercent = ((sellingPrice - unitCost) / unitCost) * 100`.
  /// Safely returns `null` when [unitCost] <= 0 to prevent `NaN` or division-by-zero.
  static double? reverseCalculateMarkupPercent({
    required double sellingPrice,
    required double unitCost,
  }) {
    if (!unitCost.isFinite || unitCost <= 0 || !sellingPrice.isFinite) {
      return null;
    }
    final double pct = ((sellingPrice - unitCost) / unitCost) * 100.0;
    if (!pct.isFinite) return null;
    return double.parse(pct.toStringAsFixed(2));
  }

  /// Evaluates complete pricing metadata for a [Product] (for Admin UI previews and saving).
  static ItemPricingResult evaluateProductPricing(
    Product item, {
    double? unitCostOverride,
    StoreSettings? settings,
    bool? useGlobalBenchmarkOnly,
    double? roundingStep,
  }) {
    final bool globalOnly = useGlobalBenchmarkOnly ??
        settings?.useGlobalVelocityBenchmarkOnly ??
        false;
    final double step = roundingStep ?? settings?.priceRoundingStep ?? 0.25;
    final double effectiveCost = unitCostOverride ?? item.activeFifoUnitCost;
    final bool invalidCost = !effectiveCost.isFinite || effectiveCost <= 0;
    final double clampedV = item.salesVelocityScore.isFinite
        ? item.salesVelocityScore.clamp(0.0, 1.0).toDouble()
        : 0.5;
    final CategoryMarkupRange range =
        CategoryMarkupRules.getRangeForCategory(item.category);
    final double markupPct = calculateItemMarkup(
      item,
      useGlobalBenchmarkOnly: globalOnly,
    );

    if (invalidCost) {
      return ItemPricingResult(
        unitCost: 0.0,
        hasInvalidCost: true,
        warningMessage:
            'Missing or zero unit cost (₱0.00). Markup math skipped — enter a valid cost price.',
        pricingMode: item.pricingMode,
        categoryRange: range,
        velocityScore: clampedV,
        speedTag: getSpeedTag(clampedV),
        computedMarkupPercent: markupPct,
        rawSellingPrice: 0.0,
        finalSellingPrice: 0.0,
        roundingStep: step,
        usedGlobalBenchmarkOnly: globalOnly,
      );
    }

    final double rawPrice = effectiveCost * (1.0 + (markupPct / 100.0));
    final double finalPrice = roundPhilippinePrice(rawPrice, step: step);

    return ItemPricingResult(
      unitCost: effectiveCost,
      hasInvalidCost: false,
      pricingMode: item.pricingMode,
      categoryRange: range,
      velocityScore: clampedV,
      speedTag: getSpeedTag(clampedV),
      computedMarkupPercent: markupPct,
      rawSellingPrice: double.parse(rawPrice.toStringAsFixed(2)),
      finalSellingPrice: finalPrice,
      roundingStep: step,
      usedGlobalBenchmarkOnly: globalOnly,
    );
  }

  /// Computes normalized sales velocity scores (`0.0` slowest to `1.0` fastest)
  /// across [products] using rolling [windowDays] (7 or 30) unit sales from [transactions].
  /// When no sales exist in the window, retains each product's current score (default `0.5`).
  static Map<String, double> computeVelocityScores({
    required List<Product> products,
    required List<StoreTransaction> transactions,
    int windowDays = 30,
    DateTime? referenceNow,
  }) {
    final DateTime now = referenceNow ?? DateTime.now();
    final DateTime cutoff = now.subtract(Duration(days: windowDays));

    final Map<String, int> unitSalesByProductId = {};
    for (final tx in transactions) {
      if (tx.createdAt.isBefore(cutoff)) continue;
      for (final item in tx.items) {
        if (item.productId.isEmpty) continue;
        final int netQty = (item.qty - item.returnedQty).clamp(0, 999999);
        if (netQty <= 0) continue;
        unitSalesByProductId[item.productId] =
            (unitSalesByProductId[item.productId] ?? 0) + netQty;
      }
    }

    if (unitSalesByProductId.isEmpty) {
      return {
        for (final p in products)
          p.id: p.salesVelocityScore.isFinite
              ? p.salesVelocityScore.clamp(0.0, 1.0).toDouble()
              : 0.5,
      };
    }

    int maxUnits = 0;
    for (final count in unitSalesByProductId.values) {
      if (count > maxUnits) maxUnits = count;
    }

    if (maxUnits <= 0) {
      return {for (final p in products) p.id: 0.5};
    }

    final Map<String, double> scores = {};
    for (final p in products) {
      final int sold = unitSalesByProductId[p.id] ?? 0;
      final double normalized = (sold / maxUnits).clamp(0.0, 1.0).toDouble();
      scores[p.id] = double.parse(normalized.toStringAsFixed(3));
    }
    return scores;
  }

  /// Recalculates a product's selling price when a new active FIFO batch becomes active
  /// with a different `unitCost`, applying `computedMarkupPercent` (both `'auto'` and `'manual'`).
  ///
  /// Returns `null` if no active batch exists or if the active FIFO batch cost did not change.
  /// If the newly active batch has `unitCost <= 0`, safely skips price recalculation
  /// and returns a [FifoPricingUpdate] flagged with `hasInvalidCost: true`.
  static FifoPricingUpdate? recalculateForFifoTransition({
    required Product product,
    required List<ProductBatch> updatedBatches,
    StoreSettings? settings,
  }) {
    final activeBatches = updatedBatches.where((b) => b.isSellable).toList();
    if (activeBatches.isEmpty) return null;

    activeBatches.sort(ProductBatch.compareFifo);
    final ProductBatch nextActiveBatch = activeBatches.first;

    final double prevCost = product.activeFifoUnitCost;
    final double nextCost = nextActiveBatch.unitCost;

    // Zero-cost / missing-cost safety guard: never produce NaN or overwrite valid price with 0
    if (!nextCost.isFinite || nextCost <= 0) {
      if ((nextCost - prevCost).abs() > 0.0001) {
        return FifoPricingUpdate(
          newActiveUnitCost: 0.0,
          computedMarkupPercent: product.computedMarkupPercent,
          newSellingPrice: product.price,
          hasInvalidCost: true,
        );
      }
      return null;
    }

    final bool costChanged = (nextCost - prevCost).abs() > 0.0001;
    final bool wasOutOfStock = product.activeFifoBatch == null;

    if (!costChanged && !wasOutOfStock) {
      return null;
    }

    final bool globalOnly = settings?.useGlobalVelocityBenchmarkOnly ?? false;
    final double roundingStep = settings?.priceRoundingStep ?? 0.25;

    // Respect manual override or compute active markup for auto mode
    final double activeMarkup =
        (product.pricingMode == Product.pricingModeManual &&
                product.manualMarkupPercent != null &&
                product.manualMarkupPercent!.isFinite)
            ? product.manualMarkupPercent!
            : (product.pricingMode == Product.pricingModeManual &&
                    product.computedMarkupPercent.isFinite)
                ? product.computedMarkupPercent
                : calculateItemMarkup(
                    product,
                    useGlobalBenchmarkOnly: globalOnly,
                  );

    final double newSellingPrice = calculateFinalSellingPrice(
      unitCost: nextCost,
      markupPercent: activeMarkup,
      roundingStep: roundingStep,
    );

    if (!newSellingPrice.isFinite || newSellingPrice <= 0) {
      return null;
    }

    return FifoPricingUpdate(
      newActiveUnitCost: nextCost,
      computedMarkupPercent: double.parse(activeMarkup.toStringAsFixed(2)),
      newSellingPrice: newSellingPrice,
      hasInvalidCost: false,
    );
  }

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
              price: item.unitPriceAtSale,
              stock: 0));

      double regularUnitPrice = product.price;
      if (item.variantId != null) {
        try {
          final variant =
              product.variants.firstWhere((v) => v.id == item.variantId);
          regularUnitPrice = variant.price;
        } catch (_) {}
      }

      final double lockedUnitPrice = item.unitPriceAtSale;
      final regularSubtotal = regularUnitPrice * item.qty;
      final itemSubtotal = lockedUnitPrice * item.qty;

      subtotal += itemSubtotal;
      savings += (regularSubtotal - itemSubtotal);

      if (product.isTaxable) {
        taxableSubtotal += itemSubtotal;
      }
    }

    final clampedSavings = savings.clamp(0.0, double.infinity);
    final finalVat = taxableSubtotal - (taxableSubtotal / (1 + vatRate));
    final total = subtotal.clamp(0.0, double.infinity);

    return PricingBreakdown(
      subtotal: subtotal +
          clampedSavings, // Subtotal usually represents price before discount
      vAtAmount: finalVat,
      total: total,
      savings: clampedSavings,
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
