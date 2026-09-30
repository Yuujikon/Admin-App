import 'package:cloud_firestore/cloud_firestore.dart';
import 'order.dart';

enum PaymentMethod { cash }
enum TransactionType { inStore, pickup }

class StoreTransaction {
  final String         id;
  final List<CartItem> items;
  final double         total;
  final double         cashTendered;
  final double         changeGiven;
  final DateTime       createdAt;
  final String?        customerId;
  final String?        customerEmail; // Track email for stats
  final PaymentMethod  paymentMethod;
  final TransactionType type;
  final bool           isRefunded;

  /// Legacy aliases for backward compatibility across existing views
  double get cash => cashTendered;
  double get change => changeGiven;

  const StoreTransaction({
    required this.id,
    required this.items,
    required this.total,
    required this.cashTendered,
    required this.changeGiven,
    required this.createdAt,
    this.customerId,
    this.customerEmail,
    this.paymentMethod = PaymentMethod.cash,
    this.type = TransactionType.inStore,
    this.isRefunded = false,
  });

  factory StoreTransaction.fromFirestore(DocumentSnapshot doc) {
    try {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      return StoreTransaction(
        id:            doc.id,
        items:         (d['items'] as List? ?? []).map((e) => CartItem.fromMap(e)).toList(),
        total:         (d['total'] as num? ?? 0).toDouble(),
        cashTendered:  (d['cashTendered'] ?? d['cash'] as num? ?? 0).toDouble(),
        changeGiven:   (d['changeGiven'] ?? d['change'] as num? ?? 0).toDouble(),
        createdAt:     (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        customerId:    d['customerId']?.toString(),
        customerEmail: d['customerEmail']?.toString(),
        paymentMethod: PaymentMethod.values.firstWhere(
          (e) => e.name == (d['paymentMethod'] ?? 'cash'),
          orElse: () => PaymentMethod.cash,
        ),
        type: TransactionType.values.firstWhere(
          (e) => e.name == (d['type'] ?? 'inStore'),
          orElse: () => TransactionType.inStore,
        ),
        isRefunded:    d['isRefunded'] ?? false,
      );
    } catch (e) {
      return StoreTransaction(
        id: doc.id,
        items: [],
        total: 0,
        cashTendered: 0,
        changeGiven: 0,
        createdAt: DateTime.now(),
      );
    }
  }

  Map<String, dynamic> toFirestore() => {
    'items':         items.map((i) => i.toMap()).toList(),
    'total':         total,
    'cashTendered':  cashTendered,
    'changeGiven':   changeGiven,
    'cash':          cashTendered,
    'change':        changeGiven,
    'createdAt':     FieldValue.serverTimestamp(),
    'customerId':    customerId,
    'customerEmail': customerEmail,
    'paymentMethod': paymentMethod.name,
    'type':          type.name,
    'isRefunded':    isRefunded,
  };
}
