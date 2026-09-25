import 'package:cloud_firestore/cloud_firestore.dart';

class Customer {
  final String id;
  final String name;
  final String? email; // NEW
  final String phone;
  final double totalSpent;
  final DateTime? lastVisit;
  final String notes;
  final DateTime createdAt;

  const Customer({
    required this.id,
    required this.name,
    this.email,
    required this.phone,
    this.totalSpent = 0,
    this.lastVisit,
    this.notes = '',
    required this.createdAt,
  });

  factory Customer.fromMap(String id, Map<String, dynamic> map) {
    return Customer(
      id: id,
      name: map['name'] ?? '',
      email: map['email'],
      phone: map['phone'] ?? '',
      totalSpent: (map['totalSpent'] ?? 0).toDouble(),
      lastVisit: (map['lastVisit'] as Timestamp?)?.toDate(),
      notes: map['notes'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'totalSpent': totalSpent,
      'lastVisit': lastVisit != null ? Timestamp.fromDate(lastVisit!) : null,
      'notes': notes,
      'createdAt': createdAt,
    };
  }

  Customer copyWith({String? name, String? email, String? phone, double? totalSpent, DateTime? lastVisit, String? notes}) {
    return Customer(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      totalSpent: totalSpent ?? this.totalSpent,
      lastVisit: lastVisit ?? this.lastVisit,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}
