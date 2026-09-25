import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/format.dart';

class CatalogProduct {
  final String id;
  final String name;
  final String? brand;
  final String category;
  final String? barcode;
  final String? photoBase64;
  final String? description;

  const CatalogProduct({
    required this.id,
    required this.name,
    this.brand,
    required this.category,
    this.barcode,
    this.photoBase64,
    this.description,
  });

  factory CatalogProduct.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final name = d['name']?.toString() ?? 'Unnamed Product';
    return CatalogProduct(
      id: doc.id,
      name: name.capitalize(),
      brand: d['brand']?.toString().capitalize(),
      category: d['category']?.toString() ?? 'Others',
      barcode: d['barcode']?.toString(),
      photoBase64: d['photoBase64']?.toString(),
      description: d['description']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'brand': brand,
    'category': category,
    'barcode': barcode,
    'photoBase64': photoBase64,
    'description': description,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  CatalogProduct copyWith({
    String? name,
    String? brand,
    String? category,
    String? barcode,
    String? photoBase64,
    String? description,
  }) => CatalogProduct(
    id: id,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    category: category ?? this.category,
    barcode: barcode ?? this.barcode,
    photoBase64: photoBase64 ?? this.photoBase64,
    description: description ?? this.description,
  );
}
