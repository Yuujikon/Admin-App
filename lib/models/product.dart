import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../utils/format.dart';
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
  final int? initialStock;
  final String? barcode;

  const ProductVariant({
    required this.id,
    required this.name,
    required this.price,
    this.costPrice = 0,
    required this.stock,
    this.initialStock,
    this.barcode,
  });

  int get effectiveInitialStock =>
      (initialStock != null && initialStock! > 0) ? initialStock! : stock;

  bool get isOutOfStockForCustomer =>
      stock <= 0 || stock <= (effectiveInitialStock * 0.15).ceil();

  int get maxPurchasableStock {
    if (stock <= 0) return 0;
    final buffer = (effectiveInitialStock * 0.15).ceil();
    final available = stock - buffer;
    return available > 0 ? available : 0;
  }

  factory ProductVariant.fromMap(dynamic m) {
    if (m is! Map)
      return const ProductVariant(
          id: '', name: 'Invalid Variant', price: 0, stock: 0);
    final data = Map<String, dynamic>.from(m);
    return ProductVariant(
      id: data['id']?.toString() ?? '',
      name: data['name']?.toString() ?? 'Unnamed Variant',
      price: double.tryParse(data['price']?.toString() ?? '0') ?? 0.0,
      costPrice: double.tryParse(data['costPrice']?.toString() ?? '0') ?? 0.0,
      stock: int.tryParse(data['stock']?.toString() ?? '0') ?? 0,
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
        'initialStock': initialStock ?? stock,
        'barcode': barcode,
      };

  ProductVariant copyWith({
    String? name,
    double? price,
    double? costPrice,
    int? stock,
    int? initialStock,
    String? barcode,
  }) =>
      ProductVariant(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        stock: stock ?? this.stock,
        initialStock: initialStock ?? this.initialStock,
        barcode: barcode ?? this.barcode,
      );
}

/// Core product model representing an inventory item in the sari-sari store database.
class Product {
  final String id;
  final String name;
  final String? brand;
  final String? parentId; // Parent ID for customer app variant grouping
  final String category;
  final double price;
  final double costPrice; // Base unit COGS (per piece)
  final int stock; // Always stored in base units (e.g. pieces)
  final int? initialStock;
  final String unit; // Base unit e.g. 'pcs', 'bottle', 'can'

  // ── NEW UOM / WHOLESALE FIELDS ──
  final String bulkUnit; // Bulk unit e.g. 'box', 'case', 'pack'
  final double? packCost; // Wholesale cost for 1 full bulk box/case
  final int? itemsPerCase; // Items per Box/Case (Pack Size)

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
    this.initialStock,
    this.unit = 'pcs',
    this.bulkUnit = 'box',
    this.packCost,
    this.itemsPerCase,
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

  /// Expresses current base stock in terms of full bulk boxes + remaining loose pieces.
  String get formattedBulkStock {
    if (stock <= 0) return '0 $unit';
    if (!hasBulkPacking) return '$stock $unit';
    final int boxes = stock ~/ piecesPerPack;
    final int remainder = stock % piecesPerPack;
    if (boxes == 0) return '$remainder $unit';
    if (remainder == 0) return '$boxes $bulkUnit${boxes > 1 ? 'es' : ''}';
    return '$boxes $bulkUnit${boxes > 1 ? 'es' : ''}, $remainder $unit';
  }

  bool get isPerishable => shelfDays != null;
  bool get hasVariants => variants.isNotEmpty;
  bool get hasParentGroup => parentId != null && parentId!.trim().isNotEmpty;

  int get effectiveInitialStock =>
      (initialStock != null && initialStock! > 0) ? initialStock! : stock;

  bool get isOutOfStockForCustomer {
    if (hasVariants) {
      if (variants.isEmpty) return totalStock <= 0;
      return variants.every((v) => v.isOutOfStockForCustomer);
    } else {
      if (stock <= 0) return true;
      final buffer = (effectiveInitialStock * 0.15).ceil();
      return stock <= buffer;
    }
  }

  int get maxPurchasableStock {
    if (hasVariants) {
      return variants.fold(0, (acc, v) => acc + v.maxPurchasableStock);
    } else {
      if (stock <= 0) return 0;
      final buffer = (effectiveInitialStock * 0.15).ceil();
      final available = stock - buffer;
      return available > 0 ? available : 0;
    }
  }

  /// Calculates how many items should be ordered to restock (`(lowStockThreshold * 3) - totalStock`).
  int calculateSuggestedRestock() {
    int suggested = (lowStockThreshold * 3) - totalStock;
    return suggested > 0 ? suggested : lowStockThreshold;
  }

  /// Returns the total stock (sum of variants if they exist, otherwise base stock).
  int get totalStock =>
      hasVariants ? variants.fold(0, (acc, v) => acc + v.stock) : stock;

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory Product.fromFirestore(DocumentSnapshot doc) {
    try {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final String rawName = d['name']?.toString() ?? 'Unnamed Product';
      final String rawBrand = d['brand']?.toString() ?? '';
      final String rawParentId = d['parentId']?.toString() ?? '';

      return Product(
        id: doc.id,
        name: rawName.capitalize(),
        brand: rawBrand.isEmpty ? null : rawBrand.capitalize(),
        parentId: rawParentId.isEmpty ? null : rawParentId.trim(),
        category: d['category']?.toString() ?? 'Others',
        price: double.tryParse(d['price']?.toString() ?? '0') ?? 0.0,
        costPrice: double.tryParse(d['costPrice']?.toString() ?? '0') ?? 0.0,
        stock: int.tryParse(d['stock']?.toString() ?? '0') ?? 0,
        initialStock: int.tryParse(d['initialStock']?.toString() ?? ''),
        unit: d['unit']?.toString() ?? 'pcs',
        bulkUnit: d['bulkUnit']?.toString() ?? 'box',
        packCost: double.tryParse(d['packCost']?.toString() ?? ''),
        itemsPerCase: int.tryParse(
            d['itemsPerCase']?.toString() ?? d['boxQty']?.toString() ?? ''),
        barcode: d['barcode']?.toString(),
        shelfDays: int.tryParse(d['shelfDays']?.toString() ?? ''),
        pickupWindowHours:
            int.tryParse(d['pickupWindowHours']?.toString() ?? ''),
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
            ? (d['variants'] as Map)
                .values
                .map((e) => ProductVariant.fromMap(e))
                .toList()
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
        'costPrice': costPrice,
        'stock': stock,
        'initialStock': initialStock ?? stock,
        'unit': unit,
        'bulkUnit': bulkUnit,
        'packCost': packCost,
        'itemsPerCase': itemsPerCase,
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
    int? initialStock,
    double? costPrice,
    String? unit,
    String? bulkUnit,
    double? packCost,
    int? itemsPerCase,
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
        initialStock: initialStock ?? this.initialStock,
        unit: unit ?? this.unit,
        bulkUnit: bulkUnit ?? this.bulkUnit,
        packCost: packCost ?? this.packCost,
        itemsPerCase: itemsPerCase ?? this.itemsPerCase,
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
