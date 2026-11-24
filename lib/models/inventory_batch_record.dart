import 'package:cloud_firestore/cloud_firestore.dart';
import 'batch.dart';

/// Representation of an inventory lot document stored in the top-level `inventory_batches` collection.
class InventoryBatchRecord {
  final String batchId;
  final String productId;
  final String productName;
  final String? supplierId;
  final String? supplierName;
  final String? poId;
  final String? poNumber;
  final String? receiptId;
  final int initialQty;
  final int quantityRemaining;
  final double unitCost;
  final DateTime datePurchased;
  final DateTime receivedAt;
  final DateTime? expiryDate;
  final String status;

  InventoryBatchRecord({
    required this.batchId,
    required this.productId,
    this.productName = '',
    this.supplierId,
    this.supplierName,
    this.poId,
    this.poNumber,
    this.receiptId,
    int? initialQty,
    required this.quantityRemaining,
    required this.unitCost,
    DateTime? datePurchased,
    required this.receivedAt,
    this.expiryDate,
    String? status,
  })  : initialQty = initialQty ?? quantityRemaining,
        datePurchased = datePurchased ?? receivedAt,
        status = (status != null && status.trim().isNotEmpty)
            ? status.trim().toUpperCase()
            : (quantityRemaining > 0
                ? BatchStatus.active
                : BatchStatus.depleted);

  /// Evaluates whether this batch record is expired as of [now].
  bool isExpiredAt(DateTime now) {
    if (status.trim().toUpperCase() == BatchStatus.expired) return true;
    if (expiryDate == null) return false;
    return !expiryDate!.isAfter(now);
  }

  /// Unified sellable stock rule matching [ProductBatch.isSellableAt].
  bool isSellableAt(DateTime now) {
    if (status.trim().toUpperCase() != BatchStatus.active) return false;
    if (quantityRemaining <= 0) return false;
    if (expiryDate != null && !expiryDate!.isAfter(now)) return false;
    return true;
  }

  bool get isSellable => isSellableAt(DateTime.now());

  bool get isActive => isSellable;

  bool get hasValidSupplier =>
      supplierId != null && supplierId!.trim().isNotEmpty;

  int? get daysUntilExpiration {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry =
        DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    return expiry.difference(today).inDays;
  }

  bool get isExpired => isExpiredAt(DateTime.now());

  bool get isNearExpiration {
    if (isExpired) return false;
    final days = daysUntilExpiration;
    return days != null && days >= 0 && days <= 30;
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

    final int qtyRem = (data['remainingQty'] as num? ??
            data['quantityRemaining'] as num? ??
            data['quantity'] as num? ??
            0)
        .toInt();
    final int initQty =
        (data['initialQty'] as num? ?? data['initial_qty'] as num? ?? qtyRem)
            .toInt();
    final received = parseDate(
      data['dateArrived'] ??
          data['receivedAt'] ??
          data['dateReceived'] ??
          data['createdAt'],
      DateTime.now(),
    );
    final purchased = parseDate(data['datePurchased'], received);

    return InventoryBatchRecord(
      batchId: data['batchId']?.toString().trim().isNotEmpty == true
          ? data['batchId'].toString().trim()
          : doc.id,
      productId: data['productId']?.toString() ?? '',
      productName: data['productName']?.toString() ?? '',
      supplierId: data['supplierId']?.toString(),
      supplierName: data['supplierName']?.toString(),
      poId: data['poId']?.toString(),
      poNumber: data['poNumber']?.toString(),
      receiptId: data['receiptId']?.toString(),
      initialQty: initQty < qtyRem ? qtyRem : initQty,
      quantityRemaining: qtyRem < 0 ? 0 : qtyRem,
      unitCost: (data['costPrice'] as num? ?? data['unitCost'] as num? ?? 0.0)
          .toDouble(),
      datePurchased: purchased,
      receivedAt: received,
      expiryDate:
          parseNullableDate(data['expiryDate'] ?? data['expirationDate']),
      status: data['status']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'batchId': batchId,
        'productId': productId,
        'productName': productName,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'poId': poId,
        'poNumber': poNumber,
        'receiptId': receiptId,
        'initialQty': initialQty,
        'quantityRemaining': quantityRemaining,
        'remainingQty': quantityRemaining,
        'unitCost': unitCost,
        'costPrice': unitCost,
        'datePurchased': Timestamp.fromDate(datePurchased),
        'dateArrived': Timestamp.fromDate(receivedAt),
        'receivedAt': Timestamp.fromDate(receivedAt),
        'expiryDate':
            expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  InventoryBatchRecord copyWith({
    String? batchId,
    String? productId,
    String? productName,
    String? supplierId,
    String? supplierName,
    String? poId,
    String? poNumber,
    String? receiptId,
    int? initialQty,
    int? quantityRemaining,
    double? unitCost,
    DateTime? datePurchased,
    DateTime? receivedAt,
    DateTime? expiryDate,
    String? status,
  }) {
    return InventoryBatchRecord(
      batchId: batchId ?? this.batchId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      poId: poId ?? this.poId,
      poNumber: poNumber ?? this.poNumber,
      receiptId: receiptId ?? this.receiptId,
      initialQty: initialQty ?? this.initialQty,
      quantityRemaining: quantityRemaining ?? this.quantityRemaining,
      unitCost: unitCost ?? this.unitCost,
      datePurchased: datePurchased ?? this.datePurchased,
      receivedAt: receivedAt ?? this.receivedAt,
      expiryDate: expiryDate ?? this.expiryDate,
      status: status ?? this.status,
    );
  }
}
