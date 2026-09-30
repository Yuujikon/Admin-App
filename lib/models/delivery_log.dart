import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a stock delivery log entry created when inventory is received or updated.
class DeliveryLog {
  /// Unique delivery log document ID.
  final String id;

  /// Associated product ID.
  final String productId;

  /// Display name of the delivered product.
  final String productName;

  /// Quantity of units received in this delivery batch.
  final int qtyReceived;

  /// Unit cost for received items.
  final double unitCost;

  /// Total valuation for received items (`qtyReceived * unitCost`).
  final double totalValue;

  /// Expiration date for delivered stock batch.
  final DateTime? expiryDate;

  /// Supplier invoice or delivery receipt reference.
  final String? invoiceNumber;

  /// Name or email of staff member who processed the delivery.
  final String receivedBy;

  /// Optional notes regarding delivery condition or variances.
  final String? notes;

  /// Timestamp when delivery entry was recorded.
  final DateTime createdAt;

  /// Quantity originally ordered from supplier.
  final int? orderedQty;

  /// Unit cost originally quoted by supplier.
  final double? orderedUnitCost;

  /// Associated supplier identifier.
  final String? supplierId;

  /// Associated supplier display name.
  final String? supplierName;

  /// Creates a [DeliveryLog] instance.
  DeliveryLog({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qtyReceived,
    required this.unitCost,
    required this.totalValue,
    this.expiryDate,
    this.invoiceNumber,
    required this.receivedBy,
    this.notes,
    required this.createdAt,
    this.orderedQty,
    this.orderedUnitCost,
    this.supplierId,
    this.supplierName,
  });

  /// Days remaining until batch expiration (null if no expiration date set).
  int? get daysUntilExpiration {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry =
        DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    return expiry.difference(today).inDays;
  }

  /// Whether batch is already expired.
  bool get isExpired {
    final days = daysUntilExpiration;
    return days != null && days <= 0;
  }

  /// Whether batch expires within 30 days.
  bool get isNearExpiration {
    final days = daysUntilExpiration;
    return days != null && days > 0 && days <= 30;
  }

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory DeliveryLog.fromFirestore(DocumentSnapshot doc) {
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

    final qty = (data['qtyReceived'] as num? ?? 0).toInt();
    final unit = (data['unitCost'] as num? ?? 0.0).toDouble();
    final calcTotal = qty * unit;
    final rawTotal = (data['totalValue'] as num? ?? calcTotal).toDouble();

    return DeliveryLog(
      id: doc.id,
      productId: data['productId']?.toString() ?? '',
      productName: data['productName']?.toString() ?? 'Unknown Product',
      qtyReceived: qty,
      unitCost: unit,
      totalValue: rawTotal > 0 ? rawTotal : calcTotal,
      expiryDate: parseNullableDate(data['expiryDate']),
      invoiceNumber: data['invoiceNumber']?.toString(),
      receivedBy: data['receivedBy']?.toString() ?? 'System',
      notes: data['notes']?.toString(),
      createdAt: parseDate(data['createdAt'], DateTime.now()),
      orderedQty: data['orderedQty'] != null
          ? (data['orderedQty'] as num).toInt()
          : null,
      orderedUnitCost: data['orderedUnitCost'] != null
          ? (data['orderedUnitCost'] as num).toDouble()
          : null,
      supplierId: data['supplierId']?.toString(),
      supplierName: data['supplierName']?.toString(),
    );
  }

  /// Converts model instance to Map for Firestore persistence.
  Map<String, dynamic> toFirestore() {
    return {
      'productId': productId,
      'productName': productName,
      'qtyReceived': qtyReceived,
      'unitCost': unitCost,
      'totalValue': totalValue,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'invoiceNumber': invoiceNumber,
      'receivedBy': receivedBy,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      if (orderedQty != null) 'orderedQty': orderedQty,
      if (orderedUnitCost != null) 'orderedUnitCost': orderedUnitCost,
      if (supplierId != null) 'supplierId': supplierId,
      if (supplierName != null) 'supplierName': supplierName,
    };
  }
}
