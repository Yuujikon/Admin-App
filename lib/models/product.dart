import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum ProductStatus { draft, published }

class Product {
  final String id;
  final String name;
  final String category;
  final double price;
  final int    stock;
  final String unit; // UOM: pcs, pack, etc.
  final String? barcode;     
  final int?   shelfDays;   
  final int?   pickupWindowHours; 
  final String? photoBase64; 
  final double? wholesalePrice;
  final int?    wholesaleThreshold;
  final String? supplierId;
  final DateTime? expiryDate;

  // NEW FIELDS
  final ProductStatus status;
  final int lowStockThreshold;
  final double discountPercentage;
  final double discountFixed;
  final bool isTaxable;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    this.unit = 'pcs',
    this.barcode,
    this.shelfDays,
    this.pickupWindowHours,
    this.photoBase64,
    this.wholesalePrice,
    this.wholesaleThreshold,
    this.supplierId,
    this.expiryDate,
    this.status = ProductStatus.published, // Default to published for existing items
    this.lowStockThreshold = 5,
    this.discountPercentage = 0,
    this.discountFixed = 0,
    this.isTaxable = true,
  });

  bool get isPerishable => shelfDays != null;

  factory Product.fromFirestore(DocumentSnapshot doc) {
    try {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      return Product(
        id:        doc.id,
        name:      d['name']?.toString() ?? 'Unnamed Product',
        category:  d['category']?.toString() ?? 'Others',
        price:     (d['price'] as num? ?? 0).toDouble(),
        stock:     (d['stock'] as num? ?? 0).toInt(),
        unit:      d['unit']?.toString() ?? 'pcs',
        barcode:   d['barcode']?.toString(),
        shelfDays: (d['shelfDays'] as num?)?.toInt(),
        pickupWindowHours: (d['pickupWindowHours'] as num?)?.toInt(),
        photoBase64: d['photoBase64']?.toString(),
        wholesalePrice: (d['wholesalePrice'] as num?)?.toDouble(),
        wholesaleThreshold: (d['wholesaleThreshold'] as num?)?.toInt(),
        supplierId: d['supplierId']?.toString(),
        expiryDate: (d['expiryDate'] as Timestamp?)?.toDate(),
        status: ProductStatus.values.firstWhere(
          (e) => e.name == (d['status'] ?? 'published'),
          orElse: () => ProductStatus.published,
        ),
        lowStockThreshold: (d['lowStockThreshold'] as num? ?? 5).toInt(),
        discountPercentage: (d['discountPercentage'] as num? ?? 0).toDouble(),
        discountFixed: (d['discountFixed'] as num? ?? 0).toDouble(),
        isTaxable: d['isTaxable'] ?? true,
      );
    } catch (e) {
      debugPrint('Error parsing product ${doc.id}: $e');
      return Product(id: doc.id, name: 'Error Loading', category: 'Error', price: 0, stock: 0);
    }
  }

  Map<String, dynamic> toFirestore() => {
    'name':      name,
    'category':  category,
    'price':     price,
    'stock':     stock,
    'unit':      unit,
    'barcode':   barcode,
    'shelfDays': shelfDays,
    'pickupWindowHours': pickupWindowHours,
    'photoBase64': photoBase64,
    'wholesalePrice': wholesalePrice,
    'wholesaleThreshold': wholesaleThreshold,
    'supplierId': supplierId,
    'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
    'status':    status.name,
    'lowStockThreshold': lowStockThreshold,
    'discountPercentage': discountPercentage,
    'discountFixed': discountFixed,
    'isTaxable': isTaxable,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Product copyWith({
    int? stock, 
    String? barcode, 
    String? photoBase64, 
    int? pickupWindowHours,
    ProductStatus? status,
    int? lowStockThreshold,
    double? discountPercentage,
    double? discountFixed,
    bool? isTaxable,
  }) => Product(
    id: id, name: name, category: category,
    price: price, stock: stock ?? this.stock,
    unit: unit, shelfDays: shelfDays,
    barcode: barcode ?? this.barcode,
    pickupWindowHours: pickupWindowHours ?? this.pickupWindowHours,
    photoBase64: photoBase64 ?? this.photoBase64,
    wholesalePrice: wholesalePrice,
    wholesaleThreshold: wholesaleThreshold,
    supplierId: supplierId,
    expiryDate: expiryDate,
    status: status ?? this.status,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    discountPercentage: discountPercentage ?? this.discountPercentage,
    discountFixed: discountFixed ?? this.discountFixed,
    isTaxable: isTaxable ?? this.isTaxable,
  );
}
