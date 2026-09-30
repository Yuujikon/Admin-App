import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model representing a product bundle / combo deal.
class ProductBundle {
  /// Unique bundle document ID.
  final String id;

  /// Display name of the product bundle.
  final String name;

  /// Description outlining bundle contents or promotion details.
  final String description;

  /// Category grouping for the bundle.
  final String category;

  /// List of product IDs included in this bundle.
  final List<String> productIds;

  /// Optional Base64 encoded thumbnail image string.
  final String? photoBase64;

  /// Indicates if bundle is currently available for sale.
  final bool isActive;

  /// Creates a [ProductBundle] instance.
  const ProductBundle({
    required this.id,
    required this.name,
    required this.description,
    this.category = 'General',
    required this.productIds,
    this.photoBase64,
    this.isActive = true,
  });

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory ProductBundle.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProductBundle(
      id: doc.id,
      name: d['name'] ?? '',
      description: d['description'] ?? '',
      category: d['category'] ?? 'General',
      productIds: List<String>.from(d['productIds'] ?? []),
      photoBase64: d['photoBase64'],
      isActive: d['isActive'] ?? true,
    );
  }

  /// Converts model instance to Firestore map payload.
  Map<String, dynamic> toFirestore() => {
        'name': name,
        'description': description,
        'category': category,
        'productIds': productIds,
        'photoBase64': photoBase64,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
