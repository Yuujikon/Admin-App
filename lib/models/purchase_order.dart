import 'package:cloud_firestore/cloud_firestore.dart';

/// Status state for Purchase Orders (PO).
enum PurchaseOrderStatus {
  pendingDelivery,
  partiallyReceived,
  completed,
  shortClosed,
  cancelled,
}

extension PurchaseOrderStatusExtension on PurchaseOrderStatus {
  String get displayName {
    switch (this) {
      case PurchaseOrderStatus.pendingDelivery:
        return 'Pending Delivery';
      case PurchaseOrderStatus.partiallyReceived:
        return 'Partially Received';
      case PurchaseOrderStatus.completed:
        return 'Completed';
      case PurchaseOrderStatus.shortClosed:
        return 'Short-Closed';
      case PurchaseOrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// Line item inside a Purchase Order.
class PurchaseOrderItem {
  final String productId;
  final String productName;
  final String sku;
  final int orderedQty;
  final int receivedQty;
  final double unitCost;

  const PurchaseOrderItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.orderedQty,
    this.receivedQty = 0,
    required this.unitCost,
  });

  int get remainingQty {
    final rem = orderedQty - receivedQty;
    return rem > 0 ? rem : 0;
  }

  bool get isComplete => receivedQty >= orderedQty;

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      sku: map['sku']?.toString() ?? '',
      orderedQty: (map['orderedQty'] as num? ?? 0).toInt(),
      receivedQty: (map['receivedQty'] as num? ?? 0).toInt(),
      unitCost: (map['unitCost'] as num? ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'sku': sku,
        'orderedQty': orderedQty,
        'receivedQty': receivedQty,
        'unitCost': unitCost,
      };

  PurchaseOrderItem copyWith({
    String? productId,
    String? productName,
    String? sku,
    int? orderedQty,
    int? receivedQty,
    double? unitCost,
  }) {
    return PurchaseOrderItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      orderedQty: orderedQty ?? this.orderedQty,
      receivedQty: receivedQty ?? this.receivedQty,
      unitCost: unitCost ?? this.unitCost,
    );
  }
}

/// Purchase Order (PO) document representing a binding buying commitment with a supplier.
class PurchaseOrder {
  final String id;
  final String poNumber;
  final String rfqId;
  final String supplierId;
  final String supplierName;
  final PurchaseOrderStatus status;
  final DateTime orderDate;
  final List<PurchaseOrderItem> items;

  const PurchaseOrder({
    required this.id,
    required this.poNumber,
    required this.rfqId,
    required this.supplierId,
    required this.supplierName,
    this.status = PurchaseOrderStatus.pendingDelivery,
    required this.orderDate,
    required this.items,
  });

  int get totalOrderedQty =>
      items.fold(0, (acc, item) => acc + item.orderedQty);

  int get totalReceivedQty =>
      items.fold(0, (acc, item) => acc + item.receivedQty);

  int get totalRemainingQty =>
      items.fold(0, (acc, item) => acc + item.remainingQty);

  double get totalOrderedValue =>
      items.fold(0.0, (acc, item) => acc + (item.orderedQty * item.unitCost));

  double get totalReceivedValue =>
      items.fold(0.0, (acc, item) => acc + (item.receivedQty * item.unitCost));

  bool get isFullyReceived =>
      items.isNotEmpty && items.every((item) => item.isComplete);

  factory PurchaseOrder.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val != null) {
        final parsed = DateTime.tryParse(val.toString());
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    final rawStatus = data['status']?.toString() ?? 'pendingDelivery';
    final status = PurchaseOrderStatus.values.firstWhere(
      (e) =>
          e.name.toLowerCase() == rawStatus.toLowerCase() ||
          e.displayName.toLowerCase() == rawStatus.toLowerCase(),
      orElse: () => PurchaseOrderStatus.pendingDelivery,
    );

    final rawItems = (data['items'] as List? ?? []);
    final items = rawItems
        .map((i) =>
            PurchaseOrderItem.fromMap(Map<String, dynamic>.from(i as Map)))
        .toList();

    return PurchaseOrder(
      id: doc.id,
      poNumber: data['poNumber']?.toString() ?? doc.id,
      rfqId: data['rfqId']?.toString() ?? '',
      supplierId: data['supplierId']?.toString() ?? '',
      supplierName: data['supplierName']?.toString() ?? '',
      status: status,
      orderDate: parseDate(data['orderDate'], DateTime.now()),
      items: items,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'poNumber': poNumber,
        'rfqId': rfqId,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'status': status.name,
        'orderDate': Timestamp.fromDate(orderDate),
        'items': items.map((i) => i.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  PurchaseOrder copyWith({
    String? id,
    String? poNumber,
    String? rfqId,
    String? supplierId,
    String? supplierName,
    PurchaseOrderStatus? status,
    DateTime? orderDate,
    List<PurchaseOrderItem>? items,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      poNumber: poNumber ?? this.poNumber,
      rfqId: rfqId ?? this.rfqId,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      status: status ?? this.status,
      orderDate: orderDate ?? this.orderDate,
      items: items ?? this.items,
    );
  }
}
