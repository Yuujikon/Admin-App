import 'package:cloud_firestore/cloud_firestore.dart';

enum LossType { expired, damaged, lost, personalUse, refundReturn }

class LossRecord {
  final String id;
  final String productId;
  final String productName;
  final int    qty;
  final double unitPrice;
  final LossType type;
  final String notes;
  final DateTime createdAt;
  
  // NEW FIELDS
  final String? processedBy;
  final String? referenceId; // Order ID or Transaction ID

  const LossRecord({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    required this.type,
    this.notes = '',
    required this.createdAt,
    this.processedBy,
    this.referenceId,
  });

  double get totalLoss => qty * unitPrice;

  factory LossRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return LossRecord(
      id: doc.id,
      productId: d['productId'] ?? '',
      productName: d['productName'] ?? 'Unknown',
      qty: (d['qty'] as num? ?? 0).toInt(),
      unitPrice: (d['unitPrice'] as num? ?? 0).toDouble(),
      type: LossType.values.firstWhere(
        (e) => e.name == (d['type'] ?? 'lost'),
        orElse: () => LossType.lost,
      ),
      notes: d['notes'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      processedBy: d['processedBy'],
      referenceId: d['referenceId'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'productId': productId,
    'productName': productName,
    'qty': qty,
    'unitPrice': unitPrice,
    'type': type.name,
    'notes': notes,
    'createdAt': FieldValue.serverTimestamp(),
    'processedBy': processedBy,
    'referenceId': referenceId,
  };
}
