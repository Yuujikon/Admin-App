import 'package:cloud_firestore/cloud_firestore.dart';

class ProductBundle {
  final String id;
  final String name;
  final String description;
  final List<String> productIds;
  final String? photoBase64;
  final bool isActive;

  const ProductBundle({
    required this.id,
    required this.name,
    required this.description,
    required this.productIds,
    this.photoBase64,
    this.isActive = true,
  });

  factory ProductBundle.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProductBundle(
      id: doc.id,
      name: d['name'] ?? '',
      description: d['description'] ?? '',
      productIds: List<String>.from(d['productIds'] ?? []),
      photoBase64: d['photoBase64'],
      isActive: d['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'description': description,
    'productIds': productIds,
    'photoBase64': photoBase64,
    'isActive': isActive,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
