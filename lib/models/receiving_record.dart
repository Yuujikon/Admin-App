import 'package:cloud_firestore/cloud_firestore.dart';

/// Single split batch row (Accepted Qty + Expiration Date) logged for a product line item.
class SplitBatchEntry {
  final int acceptedQty;
  final DateTime? expiryDate;
  final String batchTag;

  const SplitBatchEntry({
    required this.acceptedQty,
    this.expiryDate,
    required this.batchTag,
  });

  factory SplitBatchEntry.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val != null) return DateTime.tryParse(val.toString());
      return null;
    }

    return SplitBatchEntry(
      acceptedQty:
          (map['acceptedQty'] as num? ?? map['qty'] as num? ?? 0).toInt(),
      expiryDate: parseDate(map['expiryDate'] ?? map['expirationDate']),
      batchTag: map['batchTag']?.toString() ?? map['batchId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'acceptedQty': acceptedQty,
        if (expiryDate != null) 'expiryDate': Timestamp.fromDate(expiryDate!),
        'batchTag': batchTag,
      };
}

/// Item input verification passed into the atomic PO receiving workflow.
class LineItemReceivingVerification {
  final String productId;
  final List<SplitBatchEntry> splitBatches;
  final int rejectedQty;
  final String? rejectionReason;
  final double actualUnitPrice;

  const LineItemReceivingVerification({
    required this.productId,
    required this.splitBatches,
    this.rejectedQty = 0,
    this.rejectionReason,
    required this.actualUnitPrice,
  });

  int get totalAcceptedQty =>
      splitBatches.fold(0, (acc, b) => acc + b.acceptedQty);
}

/// Item detail inside a receiving record.
class ReceivingItem {
  final String productId;
  final String productName;
  final String sku;
  final int acceptedQty;
  final int rejectedQty;
  final String? rejectionReason;
  final double estimatedUnitCost;
  final double actualUnitPrice;
  final double priceVariance;
  final List<SplitBatchEntry> splitBatches;
  final String batchId;

  const ReceivingItem({
    required this.productId,
    this.productName = '',
    this.sku = '',
    required this.acceptedQty,
    this.rejectedQty = 0,
    this.rejectionReason,
    this.estimatedUnitCost = 0.0,
    this.actualUnitPrice = 0.0,
    this.priceVariance = 0.0,
    this.splitBatches = const [],
    this.batchId = '',
  });

  double get itemDeliveryCost => acceptedQty * actualUnitPrice;

  factory ReceivingItem.fromMap(Map<String, dynamic> map) {
    final rawSplits = (map['splitBatches'] as List? ?? []);
    final splitBatches = rawSplits
        .map(
            (s) => SplitBatchEntry.fromMap(Map<String, dynamic>.from(s as Map)))
        .toList();

    return ReceivingItem(
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      sku: map['sku']?.toString() ?? '',
      acceptedQty:
          (map['acceptedQty'] as num? ?? map['qty'] as num? ?? 0).toInt(),
      rejectedQty: (map['rejectedQty'] as num? ?? 0).toInt(),
      rejectionReason: map['rejectionReason']?.toString(),
      estimatedUnitCost:
          (map['estimatedUnitCost'] as num? ?? map['unitCost'] as num? ?? 0.0)
              .toDouble(),
      actualUnitPrice:
          (map['actualUnitPrice'] as num? ?? map['unitCost'] as num? ?? 0.0)
              .toDouble(),
      priceVariance: (map['priceVariance'] as num? ?? 0.0).toDouble(),
      splitBatches: splitBatches,
      batchId: map['batchId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'sku': sku,
        'acceptedQty': acceptedQty,
        'rejectedQty': rejectedQty,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'estimatedUnitCost': estimatedUnitCost,
        'actualUnitPrice': actualUnitPrice,
        'priceVariance': priceVariance,
        'splitBatches': splitBatches.map((s) => s.toMap()).toList(),
        'batchId': batchId,
      };
}

/// Receiving Record document representing physical delivery receipt verification for a Purchase Order.
class ReceivingRecord {
  final String id;
  final String poId;
  final String poNumber;
  final String deliveryReceiptNo;
  final DateTime receivedAt;
  final String receivedBy;
  final String? discrepancyNote;
  final double actualDeliveryCost;
  final int deliveryCount;
  final List<ReceivingItem> itemsReceived;

  const ReceivingRecord({
    required this.id,
    required this.poId,
    this.poNumber = '',
    required this.deliveryReceiptNo,
    required this.receivedAt,
    this.receivedBy = 'Admin',
    this.discrepancyNote,
    this.actualDeliveryCost = 0.0,
    this.deliveryCount = 1,
    required this.itemsReceived,
  });

  factory ReceivingRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val != null) {
        final parsed = DateTime.tryParse(val.toString());
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    final rawItems = (data['itemsReceived'] as List? ?? []);
    final items = rawItems
        .map((i) => ReceivingItem.fromMap(Map<String, dynamic>.from(i as Map)))
        .toList();

    return ReceivingRecord(
      id: doc.id,
      poId: data['poId']?.toString() ?? '',
      poNumber: data['poNumber']?.toString() ?? '',
      deliveryReceiptNo: data['deliveryReceiptNo']?.toString() ?? '',
      receivedAt: parseDate(data['receivedAt'], DateTime.now()),
      receivedBy: data['receivedBy']?.toString() ?? 'Admin',
      discrepancyNote: data['discrepancyNote']?.toString(),
      actualDeliveryCost:
          (data['actualDeliveryCost'] as num? ?? 0.0).toDouble(),
      deliveryCount: (data['deliveryCount'] as num? ?? 1).toInt(),
      itemsReceived: items,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'poId': poId,
        'poNumber': poNumber,
        'deliveryReceiptNo': deliveryReceiptNo,
        'receivedAt': Timestamp.fromDate(receivedAt),
        'receivedBy': receivedBy,
        'discrepancyNote': discrepancyNote,
        'actualDeliveryCost': actualDeliveryCost,
        'deliveryCount': deliveryCount,
        'itemsReceived': itemsReceived.map((i) => i.toMap()).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      };
}
