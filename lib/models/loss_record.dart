import 'package:cloud_firestore/cloud_firestore.dart';

/// Categorization enum for inventory loss/spoilage reasons.
enum LossType { expired, damaged, lost, personalUse, refundReturn }

/// Data model representing an inventory loss or spoilage record.
class LossRecord {
  /// Unique loss record document ID.
  final String id;

  /// Associated product ID.
  final String productId;

  /// Product display name.
  final String productName;

  /// Quantity of items lost.
  final int qty;

  /// Unit cost/price of item at time of loss.
  final double unitPrice;

  /// Type of inventory loss.
  final LossType type;

  /// Notes explaining reason or incident details.
  final String notes;

  /// Timestamp when loss was logged.
  final DateTime createdAt;

  /// Staff member who logged or verified the loss.
  final String? processedBy;

  /// Associated order or transaction reference ID.
  final String? referenceId;

  /// Creates a [LossRecord] instance.
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

  /// Total monetary valuation of the inventory loss.
  double get totalLoss => qty * unitPrice;

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
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

  /// Converts model to Map for Firestore persistence.
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
