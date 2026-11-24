import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../utils/format.dart';
import '../utils/pricing_engine.dart';
import 'batch.dart';
export 'batch.dart';

/// Product publication status state.
enum ProductStatus { published, draft, archived }

/// Variant data model for multi-option products (e.g., sizes, colors, flavors).
class ProductVariant {
  final String id;
  final String name; // e.g. "Small", "Large", "Red"
  final double price;
  final double costPrice;
  final int stock;
  final int reservedStock;
  final int? initialStock;
  final String? barcode;

  const ProductVariant({
    required this.id,
    required this.name,
    required this.price,
    this.costPrice = 0,
    required this.stock,
    this.reservedStock = 0,
    this.initialStock,
    this.barcode,
  });

  /// Non-negative reserved quantity for pending pre-orders (guards against legacy negative drift).
  int get effectiveReservedStock => reservedStock > 0 ? reservedStock : 0;

  int get availableStock {
    final safeStock = stock > 0 ? stock : 0;
    final avail = safeStock - effectiveReservedStock;
    return avail > 0 ? avail : 0;
  }

  int get effectiveInitialStock =>
      (initialStock != null && initialStock! > 0) ? initialStock! : stock;

  bool get isOutOfStockForCustomer =>
      availableStock <= 0 ||
      availableStock <= (effectiveInitialStock * 0.15).ceil();

  int get maxPurchasableStock {
    if (availableStock <= 0) return 0;
    final buffer = (effectiveInitialStock * 0.15).ceil();
    final available = availableStock - buffer;
    return available > 0 ? available : 0;
  }

  factory ProductVariant.fromMap(dynamic m) {
    if (m is! Map) {
      return const ProductVariant(
          id: '', name: 'Invalid Variant', price: 0, stock: 0);
    }
    final data = Map<String, dynamic>.from(m);
    return ProductVariant(
      id: data['id']?.toString() ?? '',
      name: data['name']?.toString() ?? 'Unnamed Variant',
      price: double.tryParse(data['price']?.toString() ?? '0') ?? 0.0,
      costPrice: double.tryParse(data['costPrice']?.toString() ?? '0') ?? 0.0,
      stock: int.tryParse(data['stock']?.toString() ?? '0') ?? 0,
      reservedStock:
          int.tryParse(data['reservedStock']?.toString() ?? '0') ?? 0,
      initialStock: int.tryParse(data['initialStock']?.toString() ?? ''),
      barcode: data['barcode']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'costPrice': costPrice,
        'stock': stock,
        'reservedStock': reservedStock,
        'initialStock': initialStock ?? stock,
        'barcode': barcode,
      };

  ProductVariant copyWith({
    String? name,
    double? price,
    double? costPrice,
    int? stock,
    int? reservedStock,
    int? initialStock,
    String? barcode,
  }) =>
      ProductVariant(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        stock: stock ?? this.stock,
        reservedStock: reservedStock ?? this.reservedStock,
        initialStock: initialStock ?? this.initialStock,
        barcode: barcode ?? this.barcode,
      );
}

/// Core product model representing an inventory item in the sari-sari store database.
class Product {
  /// Accepted pricing mode constants.
  static const String pricingModeAuto = 'auto';
  static const String pricingModeManual = 'manual';

  final String id;
  final String name;
  final String? brand;
  final String? parentId; // Parent ID for customer app variant grouping
  final String category;
  final double price;
  final double costPrice; // Base unit COGS (per piece)
  final int stock; // Always stored in base units (e.g. pieces)
  final int reservedStock; // Quantity reserved for active online pre-orders
  final int? initialStock;
  final String unit; // Base unit e.g. 'pcs', 'bottle', 'can'

  // ── NEW UOM / WHOLESALE FIELDS ──
  final String bulkUnit; // Bulk unit e.g. 'box', 'case', 'pack'
  final double? packCost; // Wholesale cost for 1 full bulk box/case
  final int? itemsPerCase; // Items per Box/Case (Pack Size)

  // ── DYNAMIC VELOCITY-BASED MARKUP FIELDS (NON-BREAKING OPTIONAL SCHEMA) ──
  /// `'auto'` (system-calculated velocity + category markup) or `'manual'` (admin-locked override).
  final String pricingMode;

  /// Admin-defined percentage (e.g., `18.5`) used ONLY when [pricingMode] == `'manual'`.
  final double? manualMarkupPercent;

  /// Normalized score from `0.0` (slowest-moving) to `1.0` (fastest-moving).
  final double salesVelocityScore;

  /// Active markup percentage applied to the current active FIFO batch `unitCost`.
  final double computedMarkupPercent;

  final String? barcode;
  final int? shelfDays;
  final int? pickupWindowHours;
  final String? photoBase64;
  final double? wholesalePrice;
  final int? wholesaleThreshold;
  final String? supplierId;
  final DateTime? expiryDate;

  final ProductStatus status;
  final int lowStockThreshold;
  final bool isTaxable;

  final List<ProductVariant> variants;
  final List<ProductBatch> batches;

  /// Creates a [Product] instance.
  const Product({
    required this.id,
    required this.name,
    this.brand,
    this.parentId,
    required this.category,
    required this.price,
    this.costPrice = 0,
    required this.stock,
    this.reservedStock = 0,
    this.initialStock,
    this.unit = 'pcs',
    this.bulkUnit = 'box',
    this.packCost,
    this.itemsPerCase,
    this.pricingMode = pricingModeAuto,
    this.manualMarkupPercent,
    this.salesVelocityScore = 0.5,
    this.computedMarkupPercent = 20.0,
    this.barcode,
    this.shelfDays,
    this.pickupWindowHours,
    this.photoBase64,
    this.wholesalePrice,
    this.wholesaleThreshold,
    this.supplierId,
    this.expiryDate,
    this.status = ProductStatus.published,
    this.lowStockThreshold = 5,
    this.isTaxable = true,
    this.variants = const [],
    this.batches = const [],
  });

  /// Alias for [price] matching selling price terminology.
  double get sellingPrice => price;

  /// Whether pricing is controlled by an admin custom override.
  bool get isManualPricing => pricingMode == pricingModeManual;

  /// Whether pricing is automatically scaled by category & sales velocity.
  bool get isAutoPricing => pricingMode != pricingModeManual;

  /// Returns the currently active (oldest sellable) FIFO batch, if any.
  ProductBatch? get activeFifoBatch {
    final active = batches.where((b) => b.isSellable).toList();
    if (active.isEmpty) return null;
    active.sort(ProductBatch.compareFifo);
    return active.first;
  }

  /// Active FIFO batch unit cost, falling back to derived/base [effectiveUnitCost].
  double get activeFifoUnitCost {
    final batch = activeFifoBatch;
    if (batch != null && batch.unitCost > 0 && batch.unitCost.isFinite) {
      return batch.unitCost;
    }
    return effectiveUnitCost;
  }

  /// True when cost is missing, zero, negative, or non-finite (markup math must be skipped).
  bool get hasInvalidUnitCost =>
      !activeFifoUnitCost.isFinite || activeFifoUnitCost <= 0;

  /// Non-negative reserved stock count (guards against legacy negative drift from
  /// unguarded decrements inflating walk-in POS availability above physical stock).
  int get effectiveReservedStock => reservedStock > 0 ? reservedStock : 0;

  /// Total non-negative reserved stock across variants or base product.
  int get totalReservedStock => hasVariants
      ? variants.fold(0, (acc, v) => acc + v.effectiveReservedStock)
      : effectiveReservedStock;

  /// Authoritative sellable stock derived from active, non-expired FIFO batches
  /// using the unified [ProductBatch.isSellable] rule.
  ///
  /// Falls back to clamped parent `stock` only for variant products or legacy
  /// products that have not yet been initialized with batch documents.
  int get sellableStock {
    if (hasVariants) {
      return variants.fold(0, (acc, v) => acc + (v.stock > 0 ? v.stock : 0));
    }
    if (batches.isNotEmpty) {
      return ProductBatch.sumSellableStock(batches);
    }
    return stock > 0 ? stock : 0;
  }

  /// Stock physically available for sale to walk-in customers (excluding active pre-order reservations).
  int get availableStock {
    if (hasVariants) {
      return variants.fold(0, (acc, v) => acc + v.availableStock);
    }
    final avail = sellableStock - effectiveReservedStock;
    return avail > 0 ? avail : 0;
  }

  static final Map<String, Uint8List> _imageCache = {};

  /// Returns cached decoded bytes of [photoBase64] to prevent image flickering during rebuilds.
  Uint8List? get imageBytes {
    if (photoBase64 == null || photoBase64!.trim().isEmpty) return null;
    final key = photoBase64!.trim();
    if (!_imageCache.containsKey(key)) {
      try {
        _imageCache[key] = base64Decode(key);
      } catch (_) {
        return null;
      }
    }
    return _imageCache[key];
  }

  // ── UOM CONVERSION HELPERS ──

  /// Effective items per pack/box (defaults to 1 if not set).
  int get piecesPerPack =>
      (itemsPerCase != null && itemsPerCase! > 0) ? itemsPerCase! : 1;

  /// Whether this product is configured for bulk purchasing.
  bool get hasBulkPacking => itemsPerCase != null && itemsPerCase! > 1;

  /// Converts bulk quantity (e.g., 2 boxes) into base unit quantity (e.g., 48 pcs). Negatives are clamped to 0.
  int convertBulkToUnits(int bulkQuantity) {
    if (bulkQuantity <= 0) return 0;
    return bulkQuantity * piecesPerPack;
  }

  /// Calculates derived per-piece cost (COGS) from a bulk pack cost (e.g., ₱480 / 24 = ₱20). Negatives are clamped to 0.
  double calculateUnitCostFromPack(double bulkCost) {
    if (bulkCost <= 0 || piecesPerPack <= 0) return 0.0;
    return double.parse((bulkCost / piecesPerPack).toStringAsFixed(2));
  }

  /// Derived per-piece cost price (prefers bulk pack cost conversion if set, otherwise base [costPrice]).
  double get effectiveUnitCost {
    if (packCost != null && packCost! > 0 && piecesPerPack > 0) {
      return calculateUnitCostFromPack(packCost!);
    }
    return costPrice;
  }

  /// Whether current selling price is strictly below calculated unit cost.
  bool get isPriceBelowCost =>
      price > 0 && effectiveUnitCost > 0 && price < effectiveUnitCost;

  /// Estimated financial loss per unit when selling price is below cost.
  double get unitLoss => isPriceBelowCost ? effectiveUnitCost - price : 0.0;

  /// Expresses current sellable base stock in terms of full bulk boxes + remaining loose pieces.
  String get formattedBulkStock {
    final int current = totalStock;
    if (current <= 0) return '0 $unit';
    if (!hasBulkPacking) return '$current $unit';
    final int boxes = current ~/ piecesPerPack;
    final int remainder = current % piecesPerPack;
    if (boxes == 0) return '$remainder $unit';
    if (remainder == 0) return '$boxes $bulkUnit${boxes > 1 ? 'es' : ''}';
    return '$boxes $bulkUnit${boxes > 1 ? 'es' : ''}, $remainder $unit';
  }

  bool get isPerishable => shelfDays != null;
  bool get hasVariants => variants.isNotEmpty;
  bool get hasParentGroup => parentId != null && parentId!.trim().isNotEmpty;

  int get effectiveInitialStock =>
      (initialStock != null && initialStock! > 0) ? initialStock! : totalStock;

  bool get isOutOfStockForCustomer {
    if (hasVariants) {
      if (variants.isEmpty) return totalAvailableStock <= 0;
      return variants.every((v) => v.isOutOfStockForCustomer);
    } else {
      if (availableStock <= 0) return true;
      final buffer = (effectiveInitialStock * 0.15).ceil();
      return availableStock <= buffer;
    }
  }

  int get maxPurchasableStock {
    if (hasVariants) {
      return variants.fold(0, (acc, v) => acc + v.maxPurchasableStock);
    } else {
      if (availableStock <= 0) return 0;
      final buffer = (effectiveInitialStock * 0.15).ceil();
      final available = availableStock - buffer;
      return available > 0 ? available : 0;
    }
  }

  /// Calculates how many items should be ordered to restock (`(lowStockThreshold * 3) - totalStock`).
  int calculateSuggestedRestock() {
    int suggested = (lowStockThreshold * 3) - totalStock;
    return suggested > 0 ? suggested : lowStockThreshold;
  }

  /// Returns authoritative sellable stock (derived from active non-expired FIFO batches
  /// for standard products, or sum of variant stocks for variant products).
  int get totalStock => sellableStock;

  /// Returns total available stock across variants or base sellable stock minus reservations.
  int get totalAvailableStock => hasVariants
      ? variants.fold(0, (acc, v) => acc + v.availableStock)
      : availableStock;

  /// Factory constructor for parsing a Firestore map with non-breaking legacy fallbacks.
  factory Product.fromMap(Map<String, dynamic> d, {required String id}) {
    final String rawName = d['name']?.toString() ?? 'Unnamed Product';
    final String rawBrand = d['brand']?.toString() ?? '';
    final String rawParentId = d['parentId']?.toString() ?? '';
    final String category = d['category']?.toString() ?? 'Others';

    final String rawPricingMode =
        d['pricingMode']?.toString().trim().toLowerCase() ?? pricingModeAuto;
    final String normalizedPricingMode = rawPricingMode == pricingModeManual
        ? pricingModeManual
        : pricingModeAuto;

    final double? parsedManualMarkup =
        double.tryParse(d['manualMarkupPercent']?.toString() ?? '');
    final double? safeManualMarkup =
        (parsedManualMarkup != null && parsedManualMarkup.isFinite)
            ? parsedManualMarkup
            : null;

    final double rawVelocity =
        double.tryParse(d['salesVelocityScore']?.toString() ?? '') ?? 0.5;
    final double safeVelocity =
        rawVelocity.isFinite ? rawVelocity.clamp(0.0, 1.0).toDouble() : 0.5;

    final double parsedPrice =
        double.tryParse((d['price'] ?? d['sellingPrice'])?.toString() ?? '0') ??
            0.0;

    final double? parsedComputedMarkup =
        double.tryParse(d['computedMarkupPercent']?.toString() ?? '');

    final baseProduct = Product(
      id: id,
      name: rawName.capitalize(),
      brand: rawBrand.isEmpty ? null : rawBrand.capitalize(),
      parentId: rawParentId.isEmpty ? null : rawParentId.trim(),
      category: category,
      price: parsedPrice,
      costPrice: double.tryParse(d['costPrice']?.toString() ?? '0') ?? 0.0,
      stock: int.tryParse(d['stock']?.toString() ?? '0') ?? 0,
      reservedStock: int.tryParse(d['reservedStock']?.toString() ?? '0') ?? 0,
      initialStock: int.tryParse(d['initialStock']?.toString() ?? ''),
      unit: d['unit']?.toString() ?? 'pcs',
      bulkUnit: d['bulkUnit']?.toString() ?? 'box',
      packCost: double.tryParse(d['packCost']?.toString() ?? ''),
      itemsPerCase: int.tryParse(
          d['itemsPerCase']?.toString() ?? d['boxQty']?.toString() ?? ''),
      pricingMode: normalizedPricingMode,
      manualMarkupPercent: safeManualMarkup,
      salesVelocityScore: safeVelocity,
      computedMarkupPercent:
          (parsedComputedMarkup != null && parsedComputedMarkup.isFinite)
              ? parsedComputedMarkup
              : 0.0,
      barcode: d['barcode']?.toString(),
      shelfDays: int.tryParse(d['shelfDays']?.toString() ?? ''),
      pickupWindowHours: int.tryParse(d['pickupWindowHours']?.toString() ?? ''),
      photoBase64: d['photoBase64']?.toString(),
      wholesalePrice: double.tryParse(d['wholesalePrice']?.toString() ?? ''),
      wholesaleThreshold:
          int.tryParse(d['wholesaleThreshold']?.toString() ?? ''),
      supplierId: d['supplierId']?.toString(),
      expiryDate: d['expiryDate'] is Timestamp
          ? (d['expiryDate'] as Timestamp).toDate()
          : null,
      status: ProductStatus.values.firstWhere(
        (e) => e.name == (d['status'] ?? 'published'),
        orElse: () => ProductStatus.published,
      ),
      lowStockThreshold:
          (int.tryParse(d['lowStockThreshold']?.toString() ?? '5') ?? 5),
      isTaxable: d['isTaxable'] ?? true,
      variants: (d['variants'] is Map)
          ? (d['variants'] as Map).entries.map((entry) {
              final mapData = entry.value is Map
                  ? Map<String, dynamic>.from(entry.value as Map)
                  : <String, dynamic>{};
              if (mapData['id'] == null || mapData['id'].toString().isEmpty) {
                mapData['id'] = entry.key.toString();
              }
              return ProductVariant.fromMap(mapData);
            }).toList()
          : (d['variants'] is List)
              ? (d['variants'] as List)
                  .map((e) => ProductVariant.fromMap(e))
                  .toList()
              : [],
      batches: (d['batches'] is Map)
          ? (d['batches'] as Map)
              .values
              .map((e) => ProductBatch.fromMap(e))
              .toList()
          : (d['batches'] is List)
              ? (d['batches'] as List)
                  .map((e) => ProductBatch.fromMap(e))
                  .toList()
              : [],
    );

    if (parsedComputedMarkup != null && parsedComputedMarkup.isFinite) {
      return baseProduct;
    }

    // Legacy document fallback: compute active markup percentage without mutating price
    final fallbackComputedMarkup = calculateItemMarkup(baseProduct);
    return baseProduct.copyWith(computedMarkupPercent: fallbackComputedMarkup);
  }

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory Product.fromFirestore(DocumentSnapshot doc) {
    try {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      return Product.fromMap(d, id: doc.id);
    } catch (e, stack) {
      debugPrint('Error parsing product ${doc.id}: $e');
      debugPrint('Stacktrace: $stack');
      return Product(
          id: doc.id,
          name: 'Error Loading',
          category: 'Error',
          price: 0,
          stock: 0);
    }
  }

  /// Converts product instance to Map for Firestore persistence.
  Map<String, dynamic> toFirestore() => {
        'name': name,
        'brand': brand,
        'parentId': parentId,
        'category': category,
        'price': price,
        'sellingPrice': price,
        'costPrice': costPrice,
        'stock': stock,
        'reservedStock': reservedStock,
        'initialStock': initialStock ?? stock,
        'unit': unit,
        'bulkUnit': bulkUnit,
        'packCost': packCost,
        'itemsPerCase': itemsPerCase,
        'pricingMode': pricingMode,
        'manualMarkupPercent': manualMarkupPercent,
        'salesVelocityScore': salesVelocityScore,
        'computedMarkupPercent': computedMarkupPercent,
        'barcode': barcode,
        'shelfDays': shelfDays,
        'pickupWindowHours': pickupWindowHours,
        'photoBase64': photoBase64,
        'wholesalePrice': wholesalePrice,
        'wholesaleThreshold': wholesaleThreshold,
        'supplierId': supplierId,
        'expiryDate':
            expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
        'status': status.name,
        'lowStockThreshold': lowStockThreshold,
        'isTaxable': isTaxable,
        'variants': {for (var v in variants) v.id: v.toMap()},
        'batches': {for (var b in batches) b.id: b.toMap()},
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Returns a copy of [Product] with modified attributes.
  Product copyWith({
    String? name,
    String? brand,
    String? parentId,
    String? category,
    double? price,
    int? stock,
    int? reservedStock,
    int? initialStock,
    double? costPrice,
    String? unit,
    String? bulkUnit,
    double? packCost,
    int? itemsPerCase,
    String? pricingMode,
    double? manualMarkupPercent,
    bool clearManualMarkupPercent = false,
    double? salesVelocityScore,
    double? computedMarkupPercent,
    String? barcode,
    String? photoBase64,
    int? pickupWindowHours,
    double? wholesalePrice,
    int? wholesaleThreshold,
    String? supplierId,
    DateTime? expiryDate,
    ProductStatus? status,
    int? lowStockThreshold,
    bool? isTaxable,
    List<ProductVariant>? variants,
    List<ProductBatch>? batches,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        brand: brand ?? this.brand,
        parentId: parentId ?? this.parentId,
        category: category ?? this.category,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        stock: stock ?? this.stock,
        reservedStock: reservedStock ?? this.reservedStock,
        initialStock: initialStock ?? this.initialStock,
        unit: unit ?? this.unit,
        bulkUnit: bulkUnit ?? this.bulkUnit,
        packCost: packCost ?? this.packCost,
        itemsPerCase: itemsPerCase ?? this.itemsPerCase,
        pricingMode: pricingMode ?? this.pricingMode,
        manualMarkupPercent: clearManualMarkupPercent
            ? null
            : (manualMarkupPercent ?? this.manualMarkupPercent),
        salesVelocityScore: salesVelocityScore ?? this.salesVelocityScore,
        computedMarkupPercent:
            computedMarkupPercent ?? this.computedMarkupPercent,
        barcode: barcode ?? this.barcode,
        shelfDays: shelfDays,
        pickupWindowHours: pickupWindowHours ?? this.pickupWindowHours,
        photoBase64: photoBase64 ?? this.photoBase64,
        wholesalePrice: wholesalePrice ?? this.wholesalePrice,
        wholesaleThreshold: wholesaleThreshold ?? this.wholesaleThreshold,
        supplierId: supplierId ?? this.supplierId,
        expiryDate: expiryDate ?? this.expiryDate,
        status: status ?? this.status,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        isTaxable: isTaxable ?? this.isTaxable,
        variants: variants ?? this.variants,
        batches: batches ?? this.batches,
      );
}
