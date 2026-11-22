import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Fulfillment status states for pre-orders.
enum OrderStatus {
  pending,
  staging,
  ready,
  collected,
  cancelled,
  refunded,
  refundRequested,
  refundRejected
}

/// Audit record of a specific batch segment depleted during checkout.
class BatchDepletionRecord {
  final String batchId;
  final int quantity;
  final double unitCost;

  const BatchDepletionRecord({
    required this.batchId,
    required this.quantity,
    required this.unitCost,
  });

  factory BatchDepletionRecord.fromMap(dynamic m) {
    if (m is! Map) {
      return const BatchDepletionRecord(
          batchId: '', quantity: 0, unitCost: 0.0);
    }
    return BatchDepletionRecord(
      batchId: m['batchId']?.toString() ?? '',
      quantity: (m['quantity'] as num? ?? 0).toInt(),
      unitCost: (m['unitCost'] as num? ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'batchId': batchId,
        'quantity': quantity,
        'unitCost': unitCost,
      };
}

/// Cart line item model representing a product in a POS transaction or Pre-Order.
class CartItem {
  final String productId;
  final String? variantId;
  final String name;
  final String? variantName;
  final String barcode;
  final double price;
  final double costPrice;
  final int qty;
  final int returnedQty;
  final bool isPerishable;
  final String? notes;
  final double totalCogs;
  final List<BatchDepletionRecord> depletedBatches;

  const CartItem({
    required this.productId,
    this.variantId,
    required this.name,
    this.variantName,
    this.barcode = '',
    required this.price,
    this.costPrice = 0,
    required this.qty,
    this.returnedQty = 0,
    this.isPerishable = false,
    this.notes,
    this.totalCogs = 0.0,
    this.depletedBatches = const [],
  });

  factory CartItem.fromMap(dynamic m) {
    if (m is! Map) {
      return const CartItem(
          productId: '', name: 'Unknown Item', price: 0, qty: 1);
    }
    final int rawQty = (m['qty'] as num? ?? 1).toInt();
    final int safeQty = rawQty < 1 ? 1 : rawQty;
    final double rawTotalCogs = (m['totalCogs'] as num? ?? 0.0).toDouble();
    final double rawCostPrice = (m['costPrice'] as num? ?? 0.0).toDouble();

    final double effectiveCostPrice =
        rawTotalCogs > 0 ? (rawTotalCogs / safeQty) : rawCostPrice;

    final List<BatchDepletionRecord> batchesList =
        (m['depletedBatches'] is List)
            ? (m['depletedBatches'] as List)
                .map((e) => BatchDepletionRecord.fromMap(e))
                .toList()
            : const [];

    return CartItem(
      productId: m['productId']?.toString() ??
          m['id']?.toString() ??
          m['product_id']?.toString() ??
          '',
      variantId: m['variantId']?.toString(),
      name: m['name']?.toString() ??
          m['productName']?.toString() ??
          m['title']?.toString() ??
          'Unknown Item',
      variantName: m['variantName']?.toString(),
      barcode: m['barcode']?.toString() ?? '',
      price: (m['price'] as num? ?? 0).toDouble(),
      costPrice: effectiveCostPrice,
      qty: safeQty,
      returnedQty: (m['returnedQty'] as num? ?? 0).toInt(),
      isPerishable: m['isPerishable'] ?? false,
      notes: m['notes']?.toString(),
      totalCogs:
          rawTotalCogs > 0 ? rawTotalCogs : (effectiveCostPrice * safeQty),
      depletedBatches: batchesList,
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'name': name,
        if (variantName != null) 'variantName': variantName,
        'barcode': barcode,
        'price': price,
        'costPrice': costPrice,
        'qty': qty < 1 ? 1 : qty,
        'returnedQty': returnedQty,
        'isPerishable': isPerishable,
        if (notes != null) 'notes': notes,
        'totalCogs': totalCogs > 0 ? totalCogs : (costPrice * qty),
        'depletedBatches': depletedBatches.map((b) => b.toMap()).toList(),
      };

  /// Whether current selling price of this line item is below its cost price.
  bool get isBelowCost => price > 0 && costPrice > 0 && price < costPrice;

  /// Estimated unit financial loss for this line item.
  double get unitLoss => isBelowCost ? costPrice - price : 0.0;

  /// Total estimated financial loss for all units of this cart line item.
  double get totalLoss => unitLoss * (qty < 1 ? 1 : qty);

  CartItem copyWith({
    int? qty,
    int? returnedQty,
    double? price,
    double? costPrice,
    String? barcode,
    String? notes,
    double? totalCogs,
    List<BatchDepletionRecord>? depletedBatches,
  }) =>
      CartItem(
        productId: productId,
        variantId: variantId,
        name: name,
        variantName: variantName,
        barcode: barcode ?? this.barcode,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        qty: qty != null ? (qty < 1 ? 1 : qty) : this.qty,
        returnedQty: returnedQty ?? this.returnedQty,
        isPerishable: isPerishable,
        notes: notes ?? this.notes,
        totalCogs: totalCogs ?? this.totalCogs,
        depletedBatches: depletedBatches ?? this.depletedBatches,
      );
}

/// Pre-order model representing customer online orders for store pickup.
class PreOrder {
  final String id;
  final String orderId;
  final String customerName;
  final String customerEmail;
  final List<CartItem> items;
  final double subtotal;
  final double tax;
  final double total;
  final OrderStatus status;
  final String notes;
  final String location;
  final String pickupTime;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? rejectionReason;
  final String? customerPhone;
  final Map<String, DateTime> statusTimeline;
  final String? processedBy;
  final String paymentMethod;
  final String paymentStatus;
  final bool isPaid;

  const PreOrder({
    required this.id,
    required this.orderId,
    required this.customerName,
    required this.customerEmail,
    required this.items,
    this.subtotal = 0,
    this.tax = 0,
    required this.total,
    required this.status,
    this.notes = '',
    this.location = '',
    this.pickupTime = '',
    required this.createdAt,
    this.expiresAt,
    this.rejectionReason,
    this.customerPhone,
    this.statusTimeline = const {},
    this.processedBy,
    this.paymentMethod = 'cash',
    this.paymentStatus = 'unpaid',
    this.isPaid = false,
  });

  /// True if the order was already paid online/cashless prior to store pickup.
  bool get isPrePaid {
    if (isPaid) return true;
    final status = paymentStatus.toLowerCase();
    if (status == 'paid' || status == 'completed') return true;
    final method = paymentMethod.toLowerCase();
    if (method.isNotEmpty &&
        method != 'cash' &&
        method != 'pay_at_store' &&
        method != 'cash_on_pickup' &&
        method != 'cod') {
      return true;
    }
    return false;
  }

  static OrderStatus _parseStatus(dynamic rawStatus) {
    final str = rawStatus?.toString() ?? 'pending';
    switch (str) {
      case 'staging':
      case 'processing':
        return OrderStatus.staging;
      case 'ready':
        return OrderStatus.ready;
      case 'collected':
      case 'completed':
        return OrderStatus.collected;
      case 'cancelled':
      case 'rejected':
        return OrderStatus.cancelled;
      case 'refunded':
        return OrderStatus.refunded;
      case 'refundRequested':
        return OrderStatus.refundRequested;
      case 'refundRejected':
        return OrderStatus.refundRejected;
      case 'pending':
      default:
        return OrderStatus.pending;
    }
  }

  factory PreOrder.fromFirestore(DocumentSnapshot doc) {
    try {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final timelineData = d['statusTimeline'] as Map<String, dynamic>? ?? {};
      final Map<String, DateTime> timeline = {};
      timelineData.forEach((key, value) {
        if (value is Timestamp) {
          timeline[key] = value.toDate();
        }
      });

      return PreOrder(
        id: doc.id,
        orderId: d['orderId']?.toString() ?? 'GDC-????',
        customerName: d['customerName']?.toString() ?? 'Unknown Customer',
        customerEmail: d['customerEmail']?.toString() ?? '',
        items: (d['items'] as List? ?? [])
            .map((e) => CartItem.fromMap(e))
            .toList(),
        subtotal: (d['subtotal'] as num? ?? 0).toDouble(),
        tax: (d['tax'] as num? ?? 0).toDouble(),
        total: (d['total'] as num? ?? 0).toDouble(),
        status: _parseStatus(d['status']),
        notes: (d['notes'] ??
                d['note'] ??
                d['customerNote'] ??
                d['customerNotes'] ??
                d['orderNote'] ??
                d['remarks'])
            ?.toString() ??
            '',
        location: d['location']?.toString() ?? '',
        pickupTime: d['pickupTime']?.toString() ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
        rejectionReason: d['rejectionReason']?.toString(),
        customerPhone: d['customerPhone']?.toString(),
        statusTimeline: timeline,
        processedBy: d['processedBy']?.toString(),
        paymentMethod: d['paymentMethod']?.toString() ??
            d['payment_method']?.toString() ??
            'cash',
        paymentStatus: d['paymentStatus']?.toString() ??
            d['payment_status']?.toString() ??
            'unpaid',
        isPaid: d['isPaid'] == true ||
            d['is_paid'] == true ||
            (d['paymentStatus']?.toString().toLowerCase() == 'paid') ||
            (d['payment_status']?.toString().toLowerCase() == 'paid'),
      );
    } catch (e) {
      debugPrint('Error parsing PreOrder ${doc.id}: $e');
      return PreOrder(
          id: doc.id,
          orderId: 'ERROR',
          customerName: 'Error Loading',
          customerEmail: '',
          items: [],
          total: 0,
          status: OrderStatus.cancelled,
          createdAt: DateTime.now());
    }
  }

  Map<String, dynamic> toFirestore() => {
        'orderId': orderId,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'items': items.map((i) => i.toMap()).toList(),
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'status': status.name,
        'notes': notes,
        'location': location,
        'pickupTime': pickupTime,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
        'customerPhone': customerPhone,
        'statusTimeline':
            statusTimeline.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
        'processedBy': processedBy,
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'isPaid': isPaid,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      };

  PreOrder copyWith(
      {OrderStatus? status,
      Map<String, DateTime>? timeline,
      String? processedBy,
      String? rejectionReason,
      String? paymentMethod,
      String? paymentStatus,
      bool? isPaid}) {
    final newTimeline = timeline ?? Map.from(statusTimeline);
    if (status != null && status != this.status) {
      newTimeline[status.name] = DateTime.now();
    }

    return PreOrder(
      id: id,
      orderId: orderId,
      customerName: customerName,
      customerEmail: customerEmail,
      items: items,
      subtotal: subtotal,
      tax: tax,
      total: total,
      status: status ?? this.status,
      notes: notes,
      location: location,
      pickupTime: pickupTime,
      createdAt: createdAt,
      expiresAt: expiresAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      customerPhone: customerPhone,
      statusTimeline: newTimeline,
      processedBy: processedBy ?? this.processedBy,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      isPaid: isPaid ?? this.isPaid,
    );
  }
}
