import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model representing an operational expense record.
class Expense {
  /// Unique expense document ID.
  final String id;

  /// Expense memo / description.
  final String description;

  /// Expense monetary amount in Pesos.
  final double amount;

  /// Expense category (e.g., Utilities, Logistics, Maintenance).
  final String category;

  /// Timestamp when expense was recorded.
  final DateTime createdAt;

  /// Creates an [Expense] instance.
  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.createdAt,
  });

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory Expense.fromFirestore(DocumentSnapshot doc) {
    try {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      return Expense(
        id: doc.id,
        description: d['description']?.toString() ?? '',
        amount: (d['amount'] as num? ?? 0).toDouble(),
        category: d['category']?.toString() ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    } catch (e) {
      return Expense(
        id: doc.id,
        description: '',
        amount: 0,
        category: '',
        createdAt: DateTime.now(),
      );
    }
  }

  /// Converts model to Map for Firestore write operations.
  Map<String, dynamic> toFirestore() => {
        'description': description,
        'amount': amount,
        'category': category,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
