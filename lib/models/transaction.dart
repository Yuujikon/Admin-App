import 'package:cloud_firestore/cloud_firestore.dart';
import 'order.dart';

enum PaymentMethod { cash }

class StoreTransaction {
  final String         id;
  final List<CartItem> items;
  final double         total;
  final double         cash;
  final double         change;
  final DateTime       createdAt;
  final String?        customerId;
  final PaymentMethod  paymentMethod;

  const StoreTransaction({
    required this.id,
    required this.items,
    required this.total,
    required this.cash,
    required this.change,
    required this.createdAt,
    this.customerId,
    this.paymentMethod = PaymentMethod.cash,
  });

  factory StoreTransaction.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return StoreTransaction(
      id:        doc.id,
      items:     (d['items'] as List? ?? []).map((e) => CartItem.fromMap(e)).toList(),
      total:     (d['total'] as num).toDouble(),
      cash:      (d['cash'] as num).toDouble(),
      change:    (d['change'] as num).toDouble(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      customerId: d['customerId'],
      paymentMethod: PaymentMethod.values.firstWhere(
        (e) => e.name == (d['paymentMethod'] ?? 'cash'),
        orElse: () => PaymentMethod.cash,
      ),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'items':         items.map((i) => i.toMap()).toList(),
    'total':         total,
    'cash':          cash,
    'change':        change,
    'createdAt':     FieldValue.serverTimestamp(),
    'customerId':    customerId,
    'paymentMethod': paymentMethod.name,
  };
}
