import 'package:cloud_firestore/cloud_firestore.dart';
import 'order.dart';

/// Payment tender methods.
enum PaymentMethod { cash }

/// Transaction origin type.
enum TransactionType { inStore, pickup }

/// Completed sales transaction record model.
class StoreTransaction {
  /// Unique transaction document ID.
  final String id;

  /// Purchased cart line items.
  final List<CartItem> items;

  /// Total transaction amount in Pesos.
  final double total;

  /// Cash amount tendered by customer.
  final double cashTendered;

  /// Change given back to customer.
  final double changeGiven;

  /// Timestamp when sale transaction was created.
  final DateTime createdAt;

  /// Customer profile ID if linked.
  final String? customerId;

  /// Customer email address if recorded.
  final String? customerEmail;

  /// Payment method used.
  final PaymentMethod paymentMethod;

  /// Transaction channel type.
  final TransactionType type;

  /// Indicates if transaction was refunded.
  final bool isRefunded;

  /// Legacy aliases for backward compatibility across existing views
  double get cash => cashTendered;
  double get change => changeGiven;

  /// Creates a [StoreTransaction] instance.
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

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory StoreTransaction.fromFirestore(DocumentSnapshot doc) {
    try {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      return StoreTransaction(
        id: doc.id,
        items: (d['items'] as List? ?? [])
            .map((e) => CartItem.fromMap(e))
            .toList(),
        total: (d['total'] as num? ?? 0).toDouble(),
        cashTendered: (d['cashTendered'] ?? d['cash'] as num? ?? 0).toDouble(),
        changeGiven: (d['changeGiven'] ?? d['change'] as num? ?? 0).toDouble(),
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        customerId: d['customerId']?.toString(),
        customerEmail: d['customerEmail']?.toString(),
        paymentMethod: PaymentMethod.values.firstWhere(
          (e) => e.name == (d['paymentMethod'] ?? 'cash'),
          orElse: () => PaymentMethod.cash,
        ),
        type: TransactionType.values.firstWhere(
          (e) => e.name == (d['type'] ?? 'inStore'),
          orElse: () => TransactionType.inStore,
        ),
        isRefunded: d['isRefunded'] ?? false,
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

  /// Converts transaction instance to Map for Firestore persistence.
  Map<String, dynamic> toFirestore() => {
        'items': items.map((i) => i.toMap()).toList(),
        'total': total,
        'cashTendered': cashTendered,
        'changeGiven': changeGiven,
        'cash': cashTendered,
        'change': changeGiven,
        'createdAt': FieldValue.serverTimestamp(),
        'customerId': customerId,
        'customerEmail': customerEmail,
        'paymentMethod': paymentMethod.name,
        'type': type.name,
        'isRefunded': isRefunded,
      };
}
