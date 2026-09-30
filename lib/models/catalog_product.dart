import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/format.dart';

/// Master catalog product reference model used for quick lookup and barcode matching.
class CatalogProduct {
  /// Unique catalog product document ID.
  final String id;

  /// Commercial name of the product.
  final String name;

  /// Brand or manufacturer name.
  final String? brand;

  /// Primary product category.
  final String category;

  /// EAN / UPC barcode value.
  final String? barcode;

  /// Base64 encoded thumbnail image.
  final String? photoBase64;

  /// Extended product description.
  final String? description;

  /// Creates a [CatalogProduct] instance.
  const CatalogProduct({
    required this.id,
    required this.name,
    this.brand,
    required this.category,
    this.barcode,
    this.photoBase64,
    this.description,
  });

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
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

  /// Converts model instance to Firestore map payload.
  Map<String, dynamic> toFirestore() => {
        'name': name,
        'brand': brand,
        'category': category,
        'barcode': barcode,
        'photoBase64': photoBase64,
        'description': description,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Returns a copy of [CatalogProduct] with updated fields.
  CatalogProduct copyWith({
    String? name,
    String? brand,
    String? category,
    String? barcode,
    String? photoBase64,
    String? description,
  }) =>
      CatalogProduct(
        id: id,
        name: name ?? this.name,
        brand: brand ?? this.brand,
        category: category ?? this.category,
        barcode: barcode ?? this.barcode,
        photoBase64: photoBase64 ?? this.photoBase64,
        description: description ?? this.description,
      );
}
