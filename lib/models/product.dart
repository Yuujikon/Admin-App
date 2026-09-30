import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../utils/format.dart';

enum ProductStatus { draft, published }

class ProductVariant {
  final String id;
  final String name; // e.g. "Small", "Large", "Red"
  final double price;
  final double costPrice;
  final int    stock;
  final int?   initialStock;
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

  int get effectiveInitialStock => (initialStock != null && initialStock! > 0) ? initialStock! : stock;

  bool get isOutOfStockForCustomer => stock <= 0 || stock <= (effectiveInitialStock * 0.15).ceil();

  int get maxPurchasableStock {
    if (stock <= 0) return 0;
    final buffer = (effectiveInitialStock * 0.15).ceil();
    final available = stock - buffer;
    return available > 0 ? available : 0;
  }

  factory ProductVariant.fromMap(dynamic m) {
    if (m is! Map) return const ProductVariant(id: '', name: 'Invalid Variant', price: 0, stock: 0);
    final data = Map<String, dynamic>.from(m);
    return ProductVariant(
      id:           data['id']?.toString() ?? '',
      name:         data['name']?.toString() ?? 'Unnamed Variant',
      price:        double.tryParse(data['price']?.toString() ?? '0') ?? 0.0,
      costPrice:    double.tryParse(data['costPrice']?.toString() ?? '0') ?? 0.0,
      stock:        int.tryParse(data['stock']?.toString() ?? '0') ?? 0,
      initialStock: int.tryParse(data['initialStock']?.toString() ?? ''),
      barcode:      data['barcode']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id':           id,
    'name':         name,
    'price':        price,
    'costPrice':    costPrice,
    'stock':        stock,
    'initialStock': initialStock ?? stock,
    'barcode':      barcode,
  };

  ProductVariant copyWith({
    String? name,
    double? price,
    double? costPrice,
    int? stock,
    int? initialStock,
    String? barcode,
  }) => ProductVariant(
    id: id,
    name: name ?? this.name,
    price: price ?? this.price,
    costPrice: costPrice ?? this.costPrice,
    stock: stock ?? this.stock,
    initialStock: initialStock ?? this.initialStock,
    barcode: barcode ?? this.barcode,
  );
}

class ProductBatch {
  final String id;
  final String productId;
  final int quantity;
  final double unitCost;
  final DateTime? expiryDate;
  final DateTime createdAt;
  final String? invoiceNumber;

  const ProductBatch({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    this.expiryDate,
    required this.createdAt,
    this.invoiceNumber,
  });

  factory ProductBatch.fromMap(dynamic m) {
    if (m is! Map) {
      return ProductBatch(
        id: '',
        productId: '',
        quantity: 0,
        unitCost: 0,
        createdAt: DateTime.now(),
      );
    }
    final data = Map<String, dynamic>.from(m);
    return ProductBatch(
      id:            data['id']?.toString() ?? '',
      productId:     data['productId']?.toString() ?? '',
      quantity:      (data['quantity'] as num? ?? 0).toInt(),
      unitCost:      (data['unitCost'] as num? ?? 0).toDouble(),
      expiryDate:    data['expiryDate'] is Timestamp 
          ? (data['expiryDate'] as Timestamp).toDate() 
          : (data['expiryDate'] != null ? DateTime.tryParse(data['expiryDate'].toString()) : null),
      createdAt:     data['createdAt'] is Timestamp 
          ? (data['createdAt'] as Timestamp).toDate() 
          : DateTime.now(),
      invoiceNumber: data['invoiceNumber']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id':            id,
    'productId':     productId,
    'quantity':      quantity,
    'unitCost':      unitCost,
    'expiryDate':    expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
    'createdAt':     Timestamp.fromDate(createdAt),
    'invoiceNumber': invoiceNumber,
  };
}

class Product {
  final String id;
  final String name;
  final String? brand; 
  final String category;
  final double price;
  final double costPrice; 
  final int    stock;
  final int?   initialStock;
  final String unit; 
  final String? barcode;     
  final int?   shelfDays;   
  final int?   pickupWindowHours; 
  final String? photoBase64; 
  final double? wholesalePrice;
  final int?    wholesaleThreshold;
  final int?    itemsPerCase; // Items per Box/Case (Ordering Unit)
  final String? supplierId;
  final DateTime? expiryDate;

  final ProductStatus status;
  final int lowStockThreshold;
  final bool isTaxable;

  final List<ProductVariant> variants;
  final List<ProductBatch> batches;

  const Product({
    required this.id,
    required this.name,
    this.brand,
    required this.category,
    required this.price,
    this.costPrice = 0,
    required this.stock,
    this.initialStock,
    this.unit = 'pcs',
    this.barcode,
    this.shelfDays,
    this.pickupWindowHours,
    this.photoBase64,
    this.wholesalePrice,
    this.wholesaleThreshold,
    this.itemsPerCase,
    this.supplierId,
    this.expiryDate,
    this.status = ProductStatus.published, 
    this.lowStockThreshold = 5,
    this.isTaxable = true,
    this.variants = const [],
    this.batches = const [],
  });

  bool get isPerishable => shelfDays != null;
  bool get hasVariants => variants.isNotEmpty;

  int get effectiveInitialStock => (initialStock != null && initialStock! > 0) ? initialStock! : stock;

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

  /// Business Logic: Calculates how many items should be ordered to restock
  /// Rule: (LowStockThreshold * 3) - CurrentStock
  int calculateSuggestedRestock() {
    int suggested = (lowStockThreshold * 3) - totalStock;
    return suggested > 0 ? suggested : lowStockThreshold;
  }

  /// Returns the total stock (sum of variants if they exist, otherwise base stock)
  int get totalStock => hasVariants 
      ? variants.fold(0, (acc, v) => acc + v.stock) 
      : stock;

  factory Product.fromFirestore(DocumentSnapshot doc) {
    try {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final String rawName = d['name']?.toString() ?? 'Unnamed Product';
      final String rawBrand = d['brand']?.toString() ?? '';
      
      return Product(
        id:        doc.id,
        name:      rawName.capitalize(),
        brand:     rawBrand.isEmpty ? null : rawBrand.capitalize(), 
        category:  d['category']?.toString() ?? 'Others',
        price:     double.tryParse(d['price']?.toString() ?? '0') ?? 0.0,
        costPrice: double.tryParse(d['costPrice']?.toString() ?? '0') ?? 0.0,
        stock:     int.tryParse(d['stock']?.toString() ?? '0') ?? 0,
        initialStock: int.tryParse(d['initialStock']?.toString() ?? ''),
        unit:      d['unit']?.toString() ?? 'pcs',
        barcode:   d['barcode']?.toString(),
        shelfDays: int.tryParse(d['shelfDays']?.toString() ?? ''),
        pickupWindowHours: int.tryParse(d['pickupWindowHours']?.toString() ?? ''),
        photoBase64: d['photoBase64']?.toString(),
        wholesalePrice: double.tryParse(d['wholesalePrice']?.toString() ?? ''),
        wholesaleThreshold: int.tryParse(d['wholesaleThreshold']?.toString() ?? ''),
        itemsPerCase: int.tryParse(d['itemsPerCase']?.toString() ?? d['boxQty']?.toString() ?? ''),
        supplierId: d['supplierId']?.toString(),
        expiryDate: d['expiryDate'] is Timestamp ? (d['expiryDate'] as Timestamp).toDate() : null,
        status: ProductStatus.values.firstWhere(
          (e) => e.name == (d['status'] ?? 'published'),
          orElse: () => ProductStatus.published,
        ),
        lowStockThreshold: (int.tryParse(d['lowStockThreshold']?.toString() ?? '5') ?? 5),
        isTaxable: d['isTaxable'] ?? true,
        variants: (d['variants'] is Map)
            ? (d['variants'] as Map).values.map((e) => ProductVariant.fromMap(e)).toList()
            : (d['variants'] is List)
                ? (d['variants'] as List).map((e) => ProductVariant.fromMap(e)).toList()
                : [],
        batches: (d['batches'] is Map)
            ? (d['batches'] as Map).values.map((e) => ProductBatch.fromMap(e)).toList()
            : (d['batches'] is List)
                ? (d['batches'] as List).map((e) => ProductBatch.fromMap(e)).toList()
                : [],
      );
    } catch (e, stack) {
      debugPrint('Error parsing product ${doc.id}: $e');
      debugPrint('Stacktrace: $stack');
      return Product(id: doc.id, name: 'Error Loading', category: 'Error', price: 0, stock: 0);
    }
  }

  Map<String, dynamic> toFirestore() => {
    'name':      name,
    'brand':     brand, 
    'category':  category,
    'price':     price,
    'costPrice': costPrice,
    'stock':     stock,
    'initialStock': initialStock ?? stock,
    'unit':      unit,
    'barcode':   barcode,
    'shelfDays': shelfDays,
    'pickupWindowHours': pickupWindowHours,
    'photoBase64': photoBase64,
    'wholesalePrice': wholesalePrice,
    'wholesaleThreshold': wholesaleThreshold,
    'itemsPerCase': itemsPerCase,
    'supplierId': supplierId,
    'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
    'status':    status.name,
    'lowStockThreshold': lowStockThreshold,
    'isTaxable': isTaxable,
    'variants':  { for (var v in variants) v.id: v.toMap() },
    'batches':   { for (var b in batches) b.id: b.toMap() },
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Product copyWith({
    String? name,
    String? brand,
    String? category,
    double? price,
    int? stock, 
    int? initialStock,
    double? costPrice,
    String? barcode, 
    String? photoBase64, 
    int? pickupWindowHours,
    ProductStatus? status,
    int? lowStockThreshold,
    bool? isTaxable,
    List<ProductVariant>? variants,
    List<ProductBatch>? batches,
  }) => Product(
    id: id, 
    name: name ?? this.name,
    brand: brand ?? this.brand,
    category: category ?? this.category,
    price: price ?? this.price, 
    costPrice: costPrice ?? this.costPrice,
    stock: stock ?? this.stock,
    initialStock: initialStock ?? this.initialStock,
    unit: unit,
    barcode: barcode ?? this.barcode,
    shelfDays: shelfDays,
    pickupWindowHours: pickupWindowHours ?? this.pickupWindowHours,
    photoBase64: photoBase64 ?? this.photoBase64,
    wholesalePrice: wholesalePrice,
    wholesaleThreshold: wholesaleThreshold,
    itemsPerCase: itemsPerCase,
    supplierId: supplierId,
    expiryDate: expiryDate,
    status: status ?? this.status,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    isTaxable: isTaxable ?? this.isTaxable,
    variants: variants ?? this.variants,
    batches: batches ?? this.batches,
  );
}
