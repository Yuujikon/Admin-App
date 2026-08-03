import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class Product {
  final String id;
  final String name;
  final String category;
  final double price;
  final int    stock;
  final String unit;
  final String? barcode;
  final int?   shelfDays;   // null = non-perishable
  final String? photoBase64; // Image stored as Base64 string
  final String? supplierId;  // Associated supplier
  final DateTime? expiryDate;
  final double? wholesalePrice;
  final int? wholesaleThreshold;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    this.unit = 'pc',
    this.barcode,
    this.shelfDays,
    this.photoBase64,
    this.supplierId,
    this.expiryDate,
    this.wholesalePrice,
    this.wholesaleThreshold,
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
        unit:      d['unit']?.toString() ?? 'pc',
        barcode:   d['barcode']?.toString(),
        shelfDays: (d['shelfDays'] as num?)?.toInt(),
        photoBase64: d['photoBase64']?.toString(),
        supplierId: d['supplierId']?.toString(),
        expiryDate: (d['expiryDate'] as Timestamp?)?.toDate(),
        wholesalePrice: (d['wholesalePrice'] as num?)?.toDouble(),
        wholesaleThreshold: (d['wholesaleThreshold'] as num?)?.toInt(),
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
    'photoBase64': photoBase64,
    'supplierId': supplierId,
    'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
    'wholesalePrice': wholesalePrice,
    'wholesaleThreshold': wholesaleThreshold,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Product copyWith({
    int? stock, 
    String? barcode, 
    String? photoBase64, 
    String? supplierId,
    DateTime? expiryDate,
    double? wholesalePrice,
    int? wholesaleThreshold,
  }) => Product(
    id: id, name: name, category: category,
    price: price, stock: stock ?? this.stock,
    unit: unit, shelfDays: shelfDays,
    barcode: barcode ?? this.barcode,
    photoBase64: photoBase64 ?? this.photoBase64,
    supplierId: supplierId ?? this.supplierId,
    expiryDate: expiryDate ?? this.expiryDate,
    wholesalePrice: wholesalePrice ?? this.wholesalePrice,
    wholesaleThreshold: wholesaleThreshold ?? this.wholesaleThreshold,
  );
}
