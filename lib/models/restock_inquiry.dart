import 'package:cloud_firestore/cloud_firestore.dart';

/// Status state for supplier restock order inquiries.
enum RestockInquiryStatus {
  draft,
  pending,
  sent,
  acknowledged,
  partiallyFulfilled,
  fulfilled,
  cancelled
}

/// Line item details inside a supplier restock purchase inquiry.
class RestockInquiryItem {
  final String productId;
  final String productName;
  final String sku;
  final int currentStock;
  final int lowStockThreshold;
  final String unit;
  final int suggestedQty;
  final int requestedQty;
  final double costPrice;
  final String? notes;
  final int? receivedQty;
  final double? receivedCostPrice;
  final String? discrepancyNote;

  RestockInquiryItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.currentStock,
    required this.lowStockThreshold,
    required this.unit,
    required this.suggestedQty,
    required this.requestedQty,
    this.costPrice = 0.0,
    this.notes,
    this.receivedQty,
    this.receivedCostPrice,
    this.discrepancyNote,
  });

  /// Factory constructor for parsing map data.
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
      costPrice: (map['costPrice'] as num? ?? 0.0).toDouble(),
      notes: map['notes'],
      receivedQty: map['receivedQty'] != null
          ? (map['receivedQty'] as num).toInt()
          : null,
      receivedCostPrice: map['receivedCostPrice'] != null
          ? (map['receivedCostPrice'] as num).toDouble()
          : null,
      discrepancyNote: map['discrepancyNote'],
    );
  }

  /// Converts item instance to Map payload.
  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'sku': sku,
        'currentStock': currentStock,
        'lowStockThreshold': lowStockThreshold,
        'unit': unit,
        'suggestedQty': suggestedQty,
        'requestedQty': requestedQty,
        'costPrice': costPrice,
        'notes': notes,
        'receivedQty': receivedQty,
        'receivedCostPrice': receivedCostPrice,
        'discrepancyNote': discrepancyNote,
      };

  /// Returns a copy of [RestockInquiryItem] with updated properties.
  RestockInquiryItem copyWith({
    int? requestedQty,
    double? costPrice,
    String? notes,
    int? receivedQty,
    double? receivedCostPrice,
    String? discrepancyNote,
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
      costPrice: costPrice ?? this.costPrice,
      notes: notes ?? this.notes,
      receivedQty: receivedQty ?? this.receivedQty,
      receivedCostPrice: receivedCostPrice ?? this.receivedCostPrice,
      discrepancyNote: discrepancyNote ?? this.discrepancyNote,
    );
  }
}

/// Restock order inquiry document sent to suppliers.
class RestockInquiry {
  final String id;
  final String inquiryNumber;
  final String supplierId;
  final String supplierName;
  final String? supplierContact;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? expectedDeliveryDate;
  final RestockInquiryStatus status;
  final List<RestockInquiryItem> items;
  final String? createdBy;
  final String? batchId;

  /// Creates a [RestockInquiry] instance.
  RestockInquiry({
    required this.id,
    required this.inquiryNumber,
    required this.supplierId,
    required this.supplierName,
    this.supplierContact,
    required this.createdAt,
    this.sentAt,
    this.expectedDeliveryDate,
    this.status = RestockInquiryStatus.draft,
    required this.items,
    this.createdBy,
    this.batchId,
  });

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
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
      expectedDeliveryDate: (d['expectedDeliveryDate'] as Timestamp?)?.toDate(),
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

  /// Converts inquiry object to Map for Firestore persistence.
  Map<String, dynamic> toFirestore() => {
        'inquiryNumber': inquiryNumber,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'supplierContact': supplierContact,
        'createdAt': Timestamp.fromDate(createdAt),
        'sentAt': sentAt != null ? Timestamp.fromDate(sentAt!) : null,
        'expectedDeliveryDate': expectedDeliveryDate != null
            ? Timestamp.fromDate(expectedDeliveryDate!)
            : null,
        'status': status.name,
        'items': items.map((i) => i.toMap()).toList(),
        'createdBy': createdBy,
        'batchId': batchId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  int get totalRequestedQty =>
      items.fold(0, (acc, item) => acc + item.requestedQty);

  int get totalReceivedQty => items.fold(
      0, (acc, item) => acc + (item.receivedQty ?? item.requestedQty));

  double get totalOrderedValue => items.fold(
      0.0, (acc, item) => acc + (item.requestedQty * item.costPrice));

  double get totalReceivedValue => items.fold(
      0.0,
      (acc, item) =>
          acc +
          ((item.receivedQty ?? item.requestedQty) *
              (item.receivedCostPrice ?? item.costPrice)));

  /// Returns a copy of [RestockInquiry] with modified fields.
  RestockInquiry copyWith({
    RestockInquiryStatus? status,
    DateTime? sentAt,
    DateTime? expectedDeliveryDate,
    List<RestockInquiryItem>? items,
  }) =>
      RestockInquiry(
        id: id,
        inquiryNumber: inquiryNumber,
        supplierId: supplierId,
        supplierName: supplierName,
        supplierContact: supplierContact,
        createdAt: createdAt,
        sentAt: sentAt ?? this.sentAt,
        expectedDeliveryDate: expectedDeliveryDate ?? this.expectedDeliveryDate,
        status: status ?? this.status,
        items: items ?? this.items,
        createdBy: createdBy,
        batchId: batchId,
      );
}
