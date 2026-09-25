import 'package:cloud_firestore/cloud_firestore.dart';

enum RestockInquiryStatus {
  draft,
  pending,
  sent,
  acknowledged,
  partiallyFulfilled,
  fulfilled,
  cancelled
}

class RestockInquiryItem {
  final String productId;
  final String productName;
  final String sku;
  final int currentStock;
  final int lowStockThreshold;
  final String unit;
  final int suggestedQty;
  final int requestedQty;
  final String? notes;

  RestockInquiryItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.currentStock,
    required this.lowStockThreshold,
    required this.unit,
    required this.suggestedQty,
    required this.requestedQty,
    this.notes,
  });

  factory RestockInquiryItem.fromMap(Map<String, dynamic> map) {
    return RestockInquiryItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      sku: map['sku'] ?? '',
      currentStock: (map['currentStock'] as num? ?? 0).toInt(),
      lowStockThreshold: (map['lowStockThreshold'] as num? ?? 0).toInt(),
      unit: map['unit'] ?? 'pcs',
      suggestedQty: (map['suggestedQty'] as num? ?? 0).toInt(),
      requestedQty: (map['requestedQty'] as num? ?? 0).toInt(),
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'sku': sku,
    'currentStock': currentStock,
    'lowStockThreshold': lowStockThreshold,
    'unit': unit,
    'suggestedQty': suggestedQty,
    'requestedQty': requestedQty,
    'notes': notes,
  };

  RestockInquiryItem copyWith({
    int? requestedQty,
    String? notes,
  }) {
    return RestockInquiryItem(
      productId: productId,
      productName: productName,
      sku: sku,
      currentStock: currentStock,
      lowStockThreshold: lowStockThreshold,
      unit: unit,
      suggestedQty: suggestedQty,
      requestedQty: requestedQty ?? this.requestedQty,
      notes: notes ?? this.notes,
    );
  }
}

class RestockInquiry {
  final String id;
  final String inquiryNumber;
  final String supplierId;
  final String supplierName;
  final String? supplierContact;
  final DateTime createdAt;
  final DateTime? sentAt;
  final RestockInquiryStatus status;
  final List<RestockInquiryItem> items;
  final String? createdBy;
  final String? batchId;

  RestockInquiry({
    required this.id,
    required this.inquiryNumber,
    required this.supplierId,
    required this.supplierName,
    this.supplierContact,
    required this.createdAt,
    this.sentAt,
    this.status = RestockInquiryStatus.draft,
    required this.items,
    this.createdBy,
    this.batchId,
  });

  factory RestockInquiry.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return RestockInquiry(
      id: doc.id,
      inquiryNumber: d['inquiryNumber'] ?? '',
      supplierId: d['supplierId'] ?? '',
      supplierName: d['supplierName'] ?? '',
      supplierContact: d['supplierContact'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      sentAt: (d['sentAt'] as Timestamp?)?.toDate(),
      status: RestockInquiryStatus.values.firstWhere(
        (e) => e.name == (d['status'] ?? 'draft'),
        orElse: () => RestockInquiryStatus.draft,
      ),
      items: (d['items'] as List? ?? [])
          .map((i) => RestockInquiryItem.fromMap(i as Map<String, dynamic>))
          .toList(),
      createdBy: d['createdBy'],
      batchId: d['batchId'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'inquiryNumber': inquiryNumber,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'supplierContact': supplierContact,
    'createdAt': Timestamp.fromDate(createdAt),
    'sentAt': sentAt != null ? Timestamp.fromDate(sentAt!) : null,
    'status': status.name,
    'items': items.map((i) => i.toMap()).toList(),
    'createdBy': createdBy,
    'batchId': batchId,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  int get totalRequestedQty => items.fold(0, (sum, item) => sum + item.requestedQty);

  RestockInquiry copyWith({
    RestockInquiryStatus? status,
    DateTime? sentAt,
    List<RestockInquiryItem>? items,
  }) => RestockInquiry(
    id: id,
    inquiryNumber: inquiryNumber,
    supplierId: supplierId,
    supplierName: supplierName,
    supplierContact: supplierContact,
    createdAt: createdAt,
    sentAt: sentAt ?? this.sentAt,
    status: status ?? this.status,
    items: items ?? this.items,
    createdBy: createdBy,
    batchId: batchId,
  );
}
