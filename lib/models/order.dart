import 'package:cloud_firestore/cloud_firestore.dart';

enum OrderStatus { pending, staging, ready, collected, cancelled, refunded, refundRequested, refundRejected }

class CartItem {
  final String productId;
  final String name;
  final double price;
  final int    qty;
  final bool   isPerishable;

  const CartItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.qty,
    this.isPerishable = false,
  });

  factory CartItem.fromMap(dynamic m) {
    if (m is! Map) {
      return const CartItem(productId: '', name: 'Unknown Item', price: 0, qty: 0);
    }
    return CartItem(
      productId:    m['productId'] ?? '',
      name:         m['name'] ?? '',
      price:        (m['price'] as num? ?? 0).toDouble(),
      qty:          m['qty'] ?? 1,
      isPerishable: m['isPerishable'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'productId':    productId,
    'name':         name,
    'price':        price,
    'qty':          qty,
    'isPerishable': isPerishable,
  };

  CartItem copyWith({int? qty, double? price}) =>
      CartItem(
        productId: productId, 
        name: name, 
        price: price ?? this.price, 
        qty: qty ?? this.qty, 
        isPerishable: isPerishable
      );
}

class PreOrder {
  final String         id;
  final String         orderId;
  final String         customerName;
  final String         customerEmail;
  final List<CartItem> items;
  final double         subtotal;
  final double         discount;
  final double         tax;
  final double         total;
  final OrderStatus    status;
  final String         notes;
  final String         location;
  final String         pickupTime;
  final DateTime       createdAt;
  final DateTime?      expiresAt;
  final String?        rejectionReason;
  final bool           isSeniorPWD;

  const PreOrder({
    required this.id,
    required this.orderId,
    required this.customerName,
    required this.customerEmail,
    required this.items,
    this.subtotal = 0,
    this.discount = 0,
    this.tax = 0,
    required this.total,
    required this.status,
    this.notes      = '',
    this.location   = '',
    this.pickupTime = '',
    required this.createdAt,
    this.expiresAt,
    this.rejectionReason,
    this.isSeniorPWD = false,
  });

  factory PreOrder.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PreOrder(
      id:            doc.id,
      orderId:       d['orderId'] ?? '',
      customerName:  d['customerName'] ?? '',
      customerEmail: d['customerEmail'] ?? '',
      items:         (d['items'] as List? ?? []).map((e) => CartItem.fromMap(e)).toList(),
      subtotal:      (d['subtotal'] as num? ?? 0).toDouble(),
      discount:      (d['discount'] as num? ?? 0).toDouble(),
      tax:           (d['tax'] as num? ?? 0).toDouble(),
      total:         (d['total'] as num? ?? 0).toDouble(),
      status: OrderStatus.values.firstWhere(
        (e) => e.name == (d['status'] ?? 'pending'),
        orElse: () => OrderStatus.pending,
      ),
      notes:         d['notes'] ?? '',
      location:      d['location'] ?? '',
      pickupTime:    d['pickupTime'] ?? '',
      createdAt:     (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt:     (d['expiresAt'] as Timestamp?)?.toDate(),
      rejectionReason: d['rejectionReason'],
      isSeniorPWD:   d['isSeniorPWD'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'orderId':       orderId,
    'customerName':  customerName,
    'customerEmail': customerEmail,
    'items':         items.map((i) => i.toMap()).toList(),
    'subtotal':      subtotal,
    'discount':      discount,
    'tax':           tax,
    'total':         total,
    'status':        status.name,
    'notes':         notes,
    'location':      location,
    'pickupTime':    pickupTime,
    'createdAt':     FieldValue.serverTimestamp(),
    'expiresAt':     expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    'isSeniorPWD':   isSeniorPWD,
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
  };

  PreOrder copyWith({OrderStatus? status}) => PreOrder(
    id: id, orderId: orderId,
    customerName: customerName, customerEmail: customerEmail,
    items: items, 
    subtotal: subtotal, discount: discount, tax: tax, total: total,
    status: status ?? this.status,
    notes: notes, location: location,
    pickupTime: pickupTime, createdAt: createdAt,
    expiresAt: expiresAt,
    rejectionReason: rejectionReason,
    isSeniorPWD: isSeniorPWD,
  );
}
