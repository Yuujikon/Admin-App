import 'package:cloud_firestore/cloud_firestore.dart';

/// Representation of an inventory lot document stored in the top-level `inventory_batches` collection.
class InventoryBatchRecord {
  final String batchId;
  final String productId;
  final String? poId;
  final String? receiptId;
  final int quantityRemaining;
  final double unitCost;
  final DateTime receivedAt;
  final DateTime? expiryDate;

  const InventoryBatchRecord({
    required this.batchId,
    required this.productId,
    this.poId,
    this.receiptId,
    required this.quantityRemaining,
    required this.unitCost,
    required this.receivedAt,
    this.expiryDate,
  });

  int? get daysUntilExpiration {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry =
        DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    return expiry.difference(today).inDays;
  }

  bool get isExpired {
    final days = daysUntilExpiration;
    return days != null && days <= 0;
  }

  bool get isNearExpiration {
    final days = daysUntilExpiration;
    return days != null && days > 0 && days <= 30;
  }

  factory InventoryBatchRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val != null) {
        final parsed = DateTime.tryParse(val.toString());
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val != null) return DateTime.tryParse(val.toString());
      return null;
    }

    return InventoryBatchRecord(
      batchId: doc.id,
      productId: data['productId']?.toString() ?? '',
      poId: data['poId']?.toString(),
      receiptId: data['receiptId']?.toString(),
      quantityRemaining:
          (data['quantityRemaining'] as num? ?? data['quantity'] as num? ?? 0)
              .toInt(),
      unitCost: (data['unitCost'] as num? ?? 0.0).toDouble(),
      receivedAt: parseDate(
          data['receivedAt'] ?? data['dateReceived'] ?? data['createdAt'],
          DateTime.now()),
      expiryDate:
          parseNullableDate(data['expiryDate'] ?? data['expirationDate']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'batchId': batchId,
        'productId': productId,
        'poId': poId,
        'receiptId': receiptId,
        'quantityRemaining': quantityRemaining,
        'unitCost': unitCost,
        'receivedAt': Timestamp.fromDate(receivedAt),
        'expiryDate':
            expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  InventoryBatchRecord copyWith({
    String? batchId,
    String? productId,
    String? poId,
    String? receiptId,
    int? quantityRemaining,
    double? unitCost,
    DateTime? receivedAt,
    DateTime? expiryDate,
  }) {
    return InventoryBatchRecord(
      batchId: batchId ?? this.batchId,
      productId: productId ?? this.productId,
      poId: poId ?? this.poId,
      receiptId: receiptId ?? this.receiptId,
      quantityRemaining: quantityRemaining ?? this.quantityRemaining,
      unitCost: unitCost ?? this.unitCost,
      receivedAt: receivedAt ?? this.receivedAt,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }
}
