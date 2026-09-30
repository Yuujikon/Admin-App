import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum OrderStatus { pending, staging, ready, collected, cancelled, refunded, refundRequested, refundRejected }

/// Represents the audit record of a specific batch segment depleted during checkout
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
      return const BatchDepletionRecord(batchId: '', quantity: 0, unitCost: 0.0);
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

class CartItem {
  final String productId;
  final String? variantId;
  final String name;
  final String? variantName;
  final double price;
  final double costPrice;
  final int    qty;
  final bool   isPerishable;
  final String? notes;
  final double totalCogs;
  final List<BatchDepletionRecord> depletedBatches;

  const CartItem({
    required this.productId,
    this.variantId,
    required this.name,
    this.variantName,
    required this.price,
    this.costPrice = 0,
    required this.qty,
    this.isPerishable = false,
    this.notes,
    this.totalCogs = 0.0,
    this.depletedBatches = const [],
  });

  factory CartItem.fromMap(dynamic m) {
    if (m is! Map) {
      return const CartItem(productId: '', name: 'Unknown Item', price: 0, qty: 1);
    }
    final int rawQty = (m['qty'] as num? ?? 1).toInt();
    final int safeQty = rawQty < 1 ? 1 : rawQty;
    final double rawTotalCogs = (m['totalCogs'] as num? ?? 0.0).toDouble();
    final double rawCostPrice = (m['costPrice'] as num? ?? 0.0).toDouble();
    
    final double effectiveCostPrice = rawTotalCogs > 0
        ? (rawTotalCogs / safeQty)
        : rawCostPrice;

    final List<BatchDepletionRecord> batchesList = (m['depletedBatches'] is List)
        ? (m['depletedBatches'] as List).map((e) => BatchDepletionRecord.fromMap(e)).toList()
        : const [];

    return CartItem(
      productId:       m['productId'] ?? '',
      variantId:       m['variantId'],
      name:            m['name'] ?? '',
      variantName:     m['variantName'],
      price:           (m['price'] as num? ?? 0).toDouble(),
      costPrice:       effectiveCostPrice,
      qty:             safeQty,
      isPerishable:    m['isPerishable'] ?? false,
      notes:           m['notes']?.toString(),
      totalCogs:       rawTotalCogs > 0 ? rawTotalCogs : (effectiveCostPrice * safeQty),
      depletedBatches: batchesList,
    );
  }

  Map<String, dynamic> toMap() => {
    'productId':       productId,
    if (variantId != null) 'variantId': variantId,
    'name':            name,
    if (variantName != null) 'variantName': variantName,
    'price':           price,
    'costPrice':       costPrice,
    'qty':             qty < 1 ? 1 : qty,
    'isPerishable':    isPerishable,
    if (notes != null) 'notes': notes,
    'totalCogs':       totalCogs > 0 ? totalCogs : (costPrice * qty),
    'depletedBatches': depletedBatches.map((b) => b.toMap()).toList(),
  };

  CartItem copyWith({
    int? qty,
    double? price,
    double? costPrice,
    String? notes,
    double? totalCogs,
    List<BatchDepletionRecord>? depletedBatches,
  }) =>
      CartItem(
        productId: productId, 
        variantId: variantId,
        name: name, 
        variantName: variantName,
        price: price ?? this.price, 
        costPrice: costPrice ?? this.costPrice,
        qty: qty != null ? (qty < 1 ? 1 : qty) : this.qty, 
        isPerishable: isPerishable,
        notes: notes ?? this.notes,
        totalCogs: totalCogs ?? this.totalCogs,
        depletedBatches: depletedBatches ?? this.depletedBatches,
      );
}

class PreOrder {
  final String         id;
  final String         orderId;
  final String         customerName;
  final String         customerEmail;
  final List<CartItem> items;
  final double         subtotal;
  final double         tax;
  final double         total;
  final OrderStatus    status;
  final String         notes;
  final String         location;
  final String         pickupTime;
  final DateTime       createdAt;
  final DateTime?      expiresAt;
  final String?        rejectionReason;
  final String?        customerPhone;
  final Map<String, DateTime> statusTimeline;
  final String?        processedBy;

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
    this.notes      = '',
    this.location   = '',
    this.pickupTime = '',
    required this.createdAt,
    this.expiresAt,
    this.rejectionReason,
    this.customerPhone,
    this.statusTimeline = const {},
    this.processedBy,
  });

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
        id:            doc.id,
        orderId:       d['orderId']?.toString() ?? 'GDC-????',
        customerName:  d['customerName']?.toString() ?? 'Unknown Customer',
        customerEmail: d['customerEmail']?.toString() ?? '',
        items:         (d['items'] as List? ?? []).map((e) => CartItem.fromMap(e)).toList(),
        subtotal:      (d['subtotal'] as num? ?? 0).toDouble(),
        tax:           (d['tax'] as num? ?? 0).toDouble(),
        total:         (d['total'] as num? ?? 0).toDouble(),
        status: OrderStatus.values.firstWhere(
          (e) => e.name == (d['status'] ?? 'pending'),
          orElse: () => OrderStatus.pending,
        ),
        notes:         d['notes']?.toString() ?? '',
        location:      d['location']?.toString() ?? '',
        pickupTime:    d['pickupTime']?.toString() ?? '',
        createdAt:     (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        expiresAt:     (d['expiresAt'] as Timestamp?)?.toDate(),
        rejectionReason: d['rejectionReason']?.toString(),
        customerPhone: d['customerPhone']?.toString(),
        statusTimeline: timeline,
        processedBy:   d['processedBy']?.toString(),
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
        createdAt: DateTime.now()
      );
    }
  }

  Map<String, dynamic> toFirestore() => {
    'orderId':       orderId,
    'customerName':  customerName,
    'customerEmail': customerEmail,
    'items':         items.map((i) => i.toMap()).toList(),
    'subtotal':      subtotal,
    'tax':           tax,
    'total':         total,
    'status':        status.name,
    'notes':         notes,
    'location':      location,
    'pickupTime':    pickupTime,
    'createdAt':     Timestamp.fromDate(createdAt),
    'expiresAt':     expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    'customerPhone': customerPhone,
    'statusTimeline': statusTimeline.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
    'processedBy':   processedBy,
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
  };

  PreOrder copyWith({OrderStatus? status, Map<String, DateTime>? timeline, String? processedBy, String? rejectionReason}) {
    final newTimeline = timeline ?? Map.from(statusTimeline);
    if (status != null && status != this.status) {
      newTimeline[status.name] = DateTime.now();
    }

    return PreOrder(
      id: id, orderId: orderId,
      customerName: customerName, customerEmail: customerEmail,
      items: items, 
      subtotal: subtotal, tax: tax, total: total,
      status: status ?? this.status,
      notes: notes, location: location,
      pickupTime: pickupTime, createdAt: createdAt,
      expiresAt: expiresAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      customerPhone: customerPhone,
      statusTimeline: newTimeline,
      processedBy: processedBy ?? this.processedBy,
    );
  }
}
