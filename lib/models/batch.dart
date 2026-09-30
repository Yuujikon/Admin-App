import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a distinct delivery lot/batch of a single product for FEFO (First Expiring, First Out) inventory management.
class ProductBatch {
  /// Unique batch identifier.
  final String batchId;

  /// Associated product document ID.
  final String productId;

  /// Remaining quantity of stock available in this batch.
  final int quantityRemaining;

  /// Unit purchase cost for this batch lot.
  final double unitCost;

  /// Date when batch was delivered/received.
  final DateTime dateReceived;

  /// Optional expiration date for perishable items.
  final DateTime? expirationDate;

  /// Supplier invoice or delivery receipt reference number.
  final String? invoiceNumber;

  /// Creates a new [ProductBatch] instance.
  ProductBatch({
    String? batchId,
    String? id,
    required this.productId,
    int? quantityRemaining,
    int? quantity,
    this.unitCost = 0.0,
    DateTime? dateReceived,
    DateTime? createdAt,
    DateTime? expirationDate,
    DateTime? expiryDate,
    this.invoiceNumber,
  })  : batchId = batchId ?? id ?? '',
        quantityRemaining = quantityRemaining ?? quantity ?? 0,
        dateReceived = dateReceived ?? createdAt ?? DateTime.now(),
        expirationDate = expirationDate ?? expiryDate;

  // Aliases for backwards compatibility with existing codebase references
  String get id => batchId;
  int get quantity => quantityRemaining;
  DateTime get createdAt => dateReceived;
  DateTime? get expiryDate => expirationDate;

  /// Days remaining until batch expiration (null if no expiration date set).
  int? get daysUntilExpiration {
    if (expirationDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(
        expirationDate!.year, expirationDate!.month, expirationDate!.day);
    return expiry.difference(today).inDays;
  }

  /// Whether batch is already expired.
  bool get isExpired {
    final days = daysUntilExpiration;
    return days != null && days <= 0;
  }

  /// Whether batch expires within the 30-day warning threshold.
  bool get isNearExpiration {
    final days = daysUntilExpiration;
    return days != null && days > 0 && days <= 30;
  }

  /// Whether batch is healthy (> 30 days or no expiration).
  bool get isSafe {
    final days = daysUntilExpiration;
    return days == null || days > 30;
  }

  /// Factory constructor to parse map / Firestore data safely.
  factory ProductBatch.fromMap(dynamic m) {
    if (m is! Map) {
      return ProductBatch(
        batchId: '',
        productId: '',
        quantityRemaining: 0,
        unitCost: 0.0,
        dateReceived: DateTime.now(),
      );
    }
    final data = Map<String, dynamic>.from(m);

    // Parse date fields from Timestamp or String
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

    final id = data['batchId']?.toString() ?? data['id']?.toString() ?? '';
    final prodId = data['productId']?.toString() ?? '';
    final qty =
        (data['quantityRemaining'] as num? ?? data['quantity'] as num? ?? 0)
            .toInt();
    final cost = (data['unitCost'] as num? ?? 0).toDouble();
    final received =
        parseDate(data['dateReceived'] ?? data['createdAt'], DateTime.now());
    final expiry =
        parseNullableDate(data['expirationDate'] ?? data['expiryDate']);
    final invoice = data['invoiceNumber']?.toString();

    return ProductBatch(
      batchId: id,
      productId: prodId,
      quantityRemaining: qty,
      unitCost: cost,
      dateReceived: received,
      expirationDate: expiry,
      invoiceNumber: invoice,
    );
  }

  /// Factory constructor for parsing Firestore DocumentSnapshot.
  factory ProductBatch.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    data['batchId'] ??= doc.id;
    return ProductBatch.fromMap(data);
  }

  /// Convert model to Map for Firestore persistence.
  Map<String, dynamic> toMap() => {
        'batchId': batchId,
        'id': batchId, // Backwards compatible duplicate
        'productId': productId,
        'quantityRemaining': quantityRemaining,
        'quantity': quantityRemaining, // Backwards compatible duplicate
        'unitCost': unitCost,
        'dateReceived': Timestamp.fromDate(dateReceived),
        'createdAt':
            Timestamp.fromDate(dateReceived), // Backwards compatible duplicate
        'expirationDate':
            expirationDate != null ? Timestamp.fromDate(expirationDate!) : null,
        'expiryDate': expirationDate != null
            ? Timestamp.fromDate(expirationDate!)
            : null, // Backwards compatible duplicate
        'invoiceNumber': invoiceNumber,
      };

  /// Alias for toMap().
  Map<String, dynamic> toFirestore() => toMap();

  /// Create a copy with updated properties.
  ProductBatch copyWith({
    String? batchId,
    String? id,
    String? productId,
    int? quantityRemaining,
    int? quantity,
    double? unitCost,
    DateTime? dateReceived,
    DateTime? createdAt,
    DateTime? expirationDate,
    DateTime? expiryDate,
    String? invoiceNumber,
  }) {
    return ProductBatch(
      batchId: batchId ?? id ?? this.batchId,
      productId: productId ?? this.productId,
      quantityRemaining:
          quantityRemaining ?? quantity ?? this.quantityRemaining,
      unitCost: unitCost ?? this.unitCost,
      dateReceived: dateReceived ?? createdAt ?? this.dateReceived,
      expirationDate: expirationDate ?? expiryDate ?? this.expirationDate,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
    );
  }
}
