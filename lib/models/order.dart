import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum OrderStatus { pending, staging, ready, collected, cancelled, refunded, refundRequested, refundRejected }

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
  });

  factory CartItem.fromMap(dynamic m) {
    if (m is! Map) {
      return const CartItem(productId: '', name: 'Unknown Item', price: 0, qty: 0);
    }
    return CartItem(
      productId:    m['productId'] ?? '',
      variantId:    m['variantId'],
      name:         m['name'] ?? '',
      variantName:  m['variantName'],
      price:        (m['price'] as num? ?? 0).toDouble(),
      costPrice:    (m['costPrice'] as num? ?? 0).toDouble(),
      qty:          m['qty'] ?? 1,
      isPerishable: m['isPerishable'] ?? false,
      notes:        m['notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'productId':    productId,
    if (variantId != null) 'variantId': variantId,
    'name':         name,
    if (variantName != null) 'variantName': variantName,
    'price':        price,
    'costPrice':    costPrice,
    'qty':          qty,
    'isPerishable': isPerishable,
    if (notes != null) 'notes': notes,
  };

  CartItem copyWith({int? qty, double? price, double? costPrice, String? notes}) =>
      CartItem(
        productId: productId, 
        variantId: variantId,
        name: name, 
        variantName: variantName,
        price: price ?? this.price, 
        costPrice: costPrice ?? this.costPrice,
        qty: qty ?? this.qty, 
        isPerishable: isPerishable,
        notes: notes ?? this.notes,
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
    'createdAt':     FieldValue.serverTimestamp(),
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
