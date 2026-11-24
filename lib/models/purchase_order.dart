import 'package:cloud_firestore/cloud_firestore.dart';
import 'supplier.dart';

/// Status lifecycle state for Purchase Orders (PO).
enum PurchaseOrderStatus {
  draft,
  sent,
  pendingDelivery,
  partiallyReceived,
  backordered,
  completed,
  shortClosed,
  cancelled,
}

extension PurchaseOrderStatusExtension on PurchaseOrderStatus {
  String get displayName {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'Draft';
      case PurchaseOrderStatus.sent:
        return 'Sent / Pending';
      case PurchaseOrderStatus.pendingDelivery:
        return 'Pending Delivery';
      case PurchaseOrderStatus.partiallyReceived:
        return 'Partially Received (Backorder)';
      case PurchaseOrderStatus.backordered:
        return 'Partially Received (Backorder)';
      case PurchaseOrderStatus.completed:
        return 'Completed';
      case PurchaseOrderStatus.shortClosed:
        return 'Closed Short';
      case PurchaseOrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool get isActive {
    return this == PurchaseOrderStatus.sent ||
        this == PurchaseOrderStatus.pendingDelivery ||
        this == PurchaseOrderStatus.partiallyReceived ||
        this == PurchaseOrderStatus.backordered;
  }

  bool get isBackorder {
    return this == PurchaseOrderStatus.partiallyReceived ||
        this == PurchaseOrderStatus.backordered;
  }
}

/// Line item inside a Purchase Order.
class PurchaseOrderItem {
  final String productId;
  final String productName;
  final String sku;
  final int orderedQty;
  final int receivedQty; // Accepted (Good) Qty
  final int rejectedQty; // Damaged / Expired / Rejected Qty
  final String? rejectionReason;
  final double unitCost; // Estimated Unit Price
  final double? actualUnitCost; // Actual Unit Price on delivery arrival

  const PurchaseOrderItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.orderedQty,
    this.receivedQty = 0,
    this.rejectedQty = 0,
    this.rejectionReason,
    required this.unitCost,
    this.actualUnitCost,
  });

  /// Accepted (Good) quantity received into stock.
  int get acceptedQty => receivedQty;

  /// Remaining expected quantity unfulfilled.
  int get remainingQty {
    final rem = orderedQty - receivedQty;
    return rem > 0 ? rem : 0;
  }

  bool get isComplete => receivedQty >= orderedQty;

  /// Effective unit price (actual if recorded during delivery, else estimated PO cost).
  double get effectiveUnitCost => actualUnitCost ?? unitCost;

  /// Price variance per unit: actual price minus estimated unit price.
  double get priceVariance =>
      actualUnitCost != null ? (actualUnitCost! - unitCost) : 0.0;

  /// Percentage price variance: e.g. +10.0 for 10% increase.
  double get priceVariancePercent =>
      unitCost > 0 ? (priceVariance / unitCost) * 100 : 0.0;

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      sku: map['sku']?.toString() ?? '',
      orderedQty: (map['orderedQty'] as num? ?? 0).toInt(),
      receivedQty:
          (map['receivedQty'] as num? ?? map['acceptedQty'] as num? ?? 0)
              .toInt(),
      rejectedQty: (map['rejectedQty'] as num? ?? 0).toInt(),
      rejectionReason: map['rejectionReason']?.toString(),
      unitCost: (map['unitCost'] as num? ?? 0.0).toDouble(),
      actualUnitCost: map['actualUnitCost'] != null
          ? (map['actualUnitCost'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'sku': sku,
        'orderedQty': orderedQty,
        'receivedQty': receivedQty,
        'rejectedQty': rejectedQty,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'unitCost': unitCost,
        if (actualUnitCost != null) 'actualUnitCost': actualUnitCost,
      };

  PurchaseOrderItem copyWith({
    String? productId,
    String? productName,
    String? sku,
    int? orderedQty,
    int? receivedQty,
    int? rejectedQty,
    String? rejectionReason,
    double? unitCost,
    double? actualUnitCost,
  }) {
    return PurchaseOrderItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      orderedQty: orderedQty ?? this.orderedQty,
      receivedQty: receivedQty ?? this.receivedQty,
      rejectedQty: rejectedQty ?? this.rejectedQty,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      unitCost: unitCost ?? this.unitCost,
      actualUnitCost: actualUnitCost ?? this.actualUnitCost,
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

  /// Validated point-in-time supplier snapshot persisted directly on this PO/Backorder.
  /// Serves as the Single Source of Truth for UI review, PO/Backorder PDFs, and dual-recipient emails.
  final SupplierSnapshot? supplierSnapshot;

  final PurchaseOrderStatus status;
  final DateTime orderDate;
  final DateTime? requestedDeliveryDate;
  final List<PurchaseOrderItem> items;
  final String? parentPoId;
  final String? childPoId;
  final bool isBackOrder;
  final String? cancelledReason;
  final double? actualDeliveryCost;
  final bool duplicateOverride;
  final String? overrideByUserId;
  final List<Map<String, dynamic>> notificationLogs;

  const PurchaseOrder({
    required this.id,
    required this.poNumber,
    required this.rfqId,
    required this.supplierId,
    required this.supplierName,
    this.supplierSnapshot,
    this.status = PurchaseOrderStatus.sent,
    required this.orderDate,
    this.requestedDeliveryDate,
    required this.items,
    this.parentPoId,
    this.childPoId,
    this.isBackOrder = false,
    this.cancelledReason,
    this.actualDeliveryCost,
    this.duplicateOverride = false,
    this.overrideByUserId,
    this.notificationLogs = const [],
  });

  /// Resolves the authoritative [SupplierSnapshot] for this PO/Backorder.
  ///
  /// Uses the persisted [supplierSnapshot] when present, filling any blank legacy fields
  /// from [liveSupplier] if provided, or falling back to a snapshot hydrated from [liveSupplier]
  /// (and ultimately [supplierId]/[supplierName] if no master record exists).
  SupplierSnapshot resolveSupplierSnapshot([Supplier? liveSupplier]) {
    if (supplierSnapshot != null) {
      return supplierSnapshot!.mergeWithFallback(liveSupplier);
    }
    if (liveSupplier != null) {
      return SupplierSnapshot.fromSupplier(
        liveSupplier,
        snapshottedAt: orderDate,
      ).copyWith(
        supplierId: liveSupplier.id.isNotEmpty ? liveSupplier.id : supplierId,
        supplierName:
            liveSupplier.name.isNotEmpty ? liveSupplier.name : supplierName,
      );
    }
    return SupplierSnapshot(
      supplierId: supplierId,
      supplierName: supplierName,
      snapshottedAt: orderDate,
    );
  }

  /// Effective supplier name resolved from snapshot first, then top-level field.
  String get effectiveSupplierName =>
      (supplierSnapshot?.supplierName.trim().isNotEmpty ?? false)
          ? supplierSnapshot!.supplierName.trim()
          : supplierName;

  int get totalOrderedQty =>
      items.fold(0, (acc, item) => acc + item.orderedQty);

  int get totalReceivedQty =>
      items.fold(0, (acc, item) => acc + item.receivedQty);

  int get totalRejectedQty =>
      items.fold(0, (acc, item) => acc + item.rejectedQty);

  int get totalRemainingQty =>
      items.fold(0, (acc, item) => acc + item.remainingQty);

  double get totalOrderedValue =>
      items.fold(0.0, (acc, item) => acc + (item.orderedQty * item.unitCost));

  double get totalReceivedValue => items.fold(
      0.0,
      (acc, item) =>
          acc + (item.receivedQty * (item.actualUnitCost ?? item.unitCost)));

  double get deliveryProgress => totalOrderedQty > 0
      ? (totalReceivedQty / totalOrderedQty).clamp(0.0, 1.0)
      : 0.0;

  bool get isFullyReceived =>
      items.isNotEmpty && items.every((item) => item.isComplete);

  bool get hasBackorders => totalRemainingQty > 0;

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

    DateTime? parseNullableDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val != null) return DateTime.tryParse(val.toString());
      return null;
    }

    final rawStatus = data['status']?.toString() ?? 'sent';
    final status = PurchaseOrderStatus.values.firstWhere(
      (e) =>
          e.name.toLowerCase() == rawStatus.toLowerCase() ||
          e.displayName.toLowerCase() == rawStatus.toLowerCase(),
      orElse: () => PurchaseOrderStatus.sent,
    );

    final rawItems = (data['items'] as List? ?? []);
    final items = rawItems
        .map((i) =>
            PurchaseOrderItem.fromMap(Map<String, dynamic>.from(i as Map)))
        .toList();

    SupplierSnapshot? parsedSnapshot;
    if (data['supplierSnapshot'] is Map) {
      parsedSnapshot = SupplierSnapshot.fromMap(
        Map<String, dynamic>.from(data['supplierSnapshot'] as Map),
      );
    }

    final parsedSupplierName = data['supplierName']?.toString().trim() ?? '';
    final effectiveName = parsedSupplierName.isNotEmpty
        ? parsedSupplierName
        : (parsedSnapshot?.supplierName ?? '');

    return PurchaseOrder(
      id: doc.id,
      poNumber: data['poNumber']?.toString() ?? doc.id,
      rfqId: data['rfqId']?.toString() ?? '',
      supplierId:
          data['supplierId']?.toString() ?? parsedSnapshot?.supplierId ?? '',
      supplierName: effectiveName,
      supplierSnapshot: parsedSnapshot,
      status: status,
      orderDate: parseDate(data['orderDate'], DateTime.now()),
      requestedDeliveryDate: parseNullableDate(data['requestedDeliveryDate']),
      items: items,
      parentPoId: data['parentPoId']?.toString(),
      childPoId: data['childPoId']?.toString(),
      isBackOrder: (data['isBackOrder'] as bool?) ?? false,
      cancelledReason: data['cancelledReason']?.toString(),
      actualDeliveryCost: data['actualDeliveryCost'] != null
          ? (data['actualDeliveryCost'] as num).toDouble()
          : null,
      duplicateOverride: (data['duplicateOverride'] as bool?) ?? false,
      overrideByUserId: data['overrideByUserId']?.toString(),
      notificationLogs: (data['notificationLogs'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'poNumber': poNumber,
        'rfqId': rfqId,
        'supplierId': supplierId,
        'supplierName': effectiveSupplierName,
        if (supplierSnapshot != null)
          'supplierSnapshot': supplierSnapshot!.toMap(),
        'status': status.name,
        'orderDate': Timestamp.fromDate(orderDate),
        'requestedDeliveryDate': requestedDeliveryDate != null
            ? Timestamp.fromDate(requestedDeliveryDate!)
            : null,
        'items': items.map((i) => i.toMap()).toList(),
        'parentPoId': parentPoId,
        'childPoId': childPoId,
        'isBackOrder': isBackOrder,
        if (cancelledReason != null) 'cancelledReason': cancelledReason,
        if (actualDeliveryCost != null)
          'actualDeliveryCost': actualDeliveryCost,
        'duplicateOverride': duplicateOverride,
        if (overrideByUserId != null) 'overrideByUserId': overrideByUserId,
        if (notificationLogs.isNotEmpty) 'notificationLogs': notificationLogs,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  PurchaseOrder copyWith({
    String? id,
    String? poNumber,
    String? rfqId,
    String? supplierId,
    String? supplierName,
    SupplierSnapshot? supplierSnapshot,
    PurchaseOrderStatus? status,
    DateTime? orderDate,
    DateTime? requestedDeliveryDate,
    List<PurchaseOrderItem>? items,
    String? parentPoId,
    String? childPoId,
    bool? isBackOrder,
    String? cancelledReason,
    double? actualDeliveryCost,
    bool? duplicateOverride,
    String? overrideByUserId,
    List<Map<String, dynamic>>? notificationLogs,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      poNumber: poNumber ?? this.poNumber,
      rfqId: rfqId ?? this.rfqId,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierSnapshot: supplierSnapshot ?? this.supplierSnapshot,
      status: status ?? this.status,
      orderDate: orderDate ?? this.orderDate,
      requestedDeliveryDate:
          requestedDeliveryDate ?? this.requestedDeliveryDate,
      items: items ?? this.items,
      parentPoId: parentPoId ?? this.parentPoId,
      childPoId: childPoId ?? this.childPoId,
      isBackOrder: isBackOrder ?? this.isBackOrder,
      cancelledReason: cancelledReason ?? this.cancelledReason,
      actualDeliveryCost: actualDeliveryCost ?? this.actualDeliveryCost,
      duplicateOverride: duplicateOverride ?? this.duplicateOverride,
      overrideByUserId: overrideByUserId ?? this.overrideByUserId,
      notificationLogs: notificationLogs ?? this.notificationLogs,
    );
  }
}
