import 'package:cloud_firestore/cloud_firestore.dart';

enum PromotionType { productDiscount, categoryDiscount, bogo, bundleDiscount }

class Promotion {
  final String id;
  final String title;
  final String description;
  final PromotionType type;
  
  // Logic fields
  final List<String> targetIds; // Product IDs or Category names
  final double discountValue;   // Percentage (e.g. 10 for 10%) or Fixed amount
  final bool isPercentage;
  final int? buyQty;            // For BOGO/Bundle
  final int? getQty;            // For BOGO/Bundle

  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;

  const Promotion({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.targetIds,
    this.discountValue = 0,
    this.isPercentage = true,
    this.buyQty,
    this.getQty,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
  });

  bool get isCurrentlyActive {
    final now = DateTime.now();
    return isActive && now.isAfter(startDate) && now.isBefore(endDate);
  }

  factory Promotion.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Promotion(
      id: doc.id,
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      type: PromotionType.values.firstWhere((e) => e.name == d['type']),
      targetIds: List<String>.from(d['targetIds'] ?? []),
      discountValue: (d['discountValue'] as num? ?? 0).toDouble(),
      isPercentage: d['isPercentage'] ?? true,
      buyQty: d['buyQty'],
      getQty: d['getQty'],
      startDate: (d['startDate'] as Timestamp).toDate(),
      endDate: (d['endDate'] as Timestamp).toDate(),
      isActive: d['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'title': title,
    'description': description,
    'type': type.name,
    'targetIds': targetIds,
    'discountValue': discountValue,
    'isPercentage': isPercentage,
    'buyQty': buyQty,
    'getQty': getQty,
    'startDate': Timestamp.fromDate(startDate),
    'endDate': Timestamp.fromDate(endDate),
    'isActive': isActive,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
