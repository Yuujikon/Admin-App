import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle status for Request For Quotation (RFQ).
enum RfqStatus {
  draft,
  sent,
  quoted,
  converted,
  rejected,
  cancelled,
}

extension RfqStatusExtension on RfqStatus {
  String get displayName {
    switch (this) {
      case RfqStatus.draft:
        return 'Draft';
      case RfqStatus.sent:
        return 'Sent';
      case RfqStatus.quoted:
        return 'Quoted';
      case RfqStatus.converted:
        return 'Converted';
      case RfqStatus.rejected:
        return 'Rejected';
      case RfqStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// Line item details inside an RFQ.
class RfqItem {
  final String productId;
  final String productName;
  final String sku;
  final int requestedQty;
  final double? quotedUnitPrice;

  const RfqItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.requestedQty,
    this.quotedUnitPrice,
  });

  factory RfqItem.fromMap(Map<String, dynamic> map) {
    return RfqItem(
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      sku: map['sku']?.toString() ?? '',
      requestedQty: (map['requestedQty'] as num? ?? 0).toInt(),
      quotedUnitPrice: map['quotedUnitPrice'] != null
          ? (map['quotedUnitPrice'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'sku': sku,
        'requestedQty': requestedQty,
        'quotedUnitPrice': quotedUnitPrice,
      };

  RfqItem copyWith({
    String? productId,
    String? productName,
    String? sku,
    int? requestedQty,
    double? quotedUnitPrice,
  }) {
    return RfqItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      requestedQty: requestedQty ?? this.requestedQty,
      quotedUnitPrice: quotedUnitPrice ?? this.quotedUnitPrice,
    );
  }
}

/// Request for Quotation (RFQ) document sent to suppliers to ask for unit prices.
class Rfq {
  final String id;
  final String rfqNumber;
  final String supplierId;
  final String supplierName;
  final RfqStatus status;
  final DateTime createdAt;
  final DateTime? expectedDeliveryDate;
  final List<RfqItem> items;

  const Rfq({
    required this.id,
    required this.rfqNumber,
    required this.supplierId,
    required this.supplierName,
    this.status = RfqStatus.draft,
    required this.createdAt,
    this.expectedDeliveryDate,
    required this.items,
  });

  int get totalRequestedQty =>
      items.fold(0, (acc, item) => acc + item.requestedQty);

  double get totalQuotedValue => items.fold(0.0, (acc, item) {
        final price = item.quotedUnitPrice ?? 0.0;
        return acc + (item.requestedQty * price);
      });

  bool get isFullyQuoted =>
      items.isNotEmpty &&
      items.every(
          (item) => item.quotedUnitPrice != null && item.quotedUnitPrice! > 0);

  factory Rfq.fromFirestore(DocumentSnapshot doc) {
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

    final rawStatus = data['status']?.toString() ?? 'draft';
    final status = RfqStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == rawStatus.toLowerCase(),
      orElse: () => RfqStatus.draft,
    );

    final rawItems = (data['items'] as List? ?? []);
    final items = rawItems
        .map((i) => RfqItem.fromMap(Map<String, dynamic>.from(i as Map)))
        .toList();

    return Rfq(
      id: doc.id,
      rfqNumber: data['rfqNumber']?.toString() ?? doc.id,
      supplierId: data['supplierId']?.toString() ?? '',
      supplierName: data['supplierName']?.toString() ?? '',
      status: status,
      createdAt: parseDate(data['createdAt'], DateTime.now()),
      expectedDeliveryDate: parseNullableDate(data['expectedDeliveryDate']),
      items: items,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'rfqNumber': rfqNumber,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'expectedDeliveryDate': expectedDeliveryDate != null
            ? Timestamp.fromDate(expectedDeliveryDate!)
            : null,
        'items': items.map((i) => i.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Rfq copyWith({
    String? id,
    String? rfqNumber,
    String? supplierId,
    String? supplierName,
    RfqStatus? status,
    DateTime? createdAt,
    DateTime? expectedDeliveryDate,
    List<RfqItem>? items,
  }) {
    return Rfq(
      id: id ?? this.id,
      rfqNumber: rfqNumber ?? this.rfqNumber,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expectedDeliveryDate: expectedDeliveryDate ?? this.expectedDeliveryDate,
      items: items ?? this.items,
    );
  }
}
