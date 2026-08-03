import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String   id;
  final String   description;
  final double   amount;
  final String   category;
  final DateTime createdAt;

  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.createdAt,
  });

  factory Expense.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Expense(
      id:          doc.id,
      description: d['description'] ?? '',
      amount:      (d['amount'] as num).toDouble(),
      category:    d['category'] ?? '',
      createdAt:   (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'description': description,
    'amount':      amount,
    'category':    category,
    'createdAt':   FieldValue.serverTimestamp(),
  };
}