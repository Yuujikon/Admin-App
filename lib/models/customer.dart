import 'package:cloud_firestore/cloud_firestore.dart';

class Customer {
  final String id;
  final String name;
  final String phone;
  final int loyaltyPoints;
  final double totalSpent;
  final DateTime? lastVisit;
  final String notes;
  final DateTime createdAt;

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.loyaltyPoints = 0,
    this.totalSpent = 0,
    this.lastVisit,
    this.notes = '',
    required this.createdAt,
  });

  factory Customer.fromMap(String id, Map<String, dynamic> map) {
    return Customer(
      id: id,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      loyaltyPoints: (map['loyaltyPoints'] ?? 0).toInt(),
      totalSpent: (map['totalSpent'] ?? 0).toDouble(),
      lastVisit: (map['lastVisit'] as Timestamp?)?.toDate(),
      notes: map['notes'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'loyaltyPoints': loyaltyPoints,
      'totalSpent': totalSpent,
      'lastVisit': lastVisit != null ? Timestamp.fromDate(lastVisit!) : null,
      'notes': notes,
      'createdAt': createdAt,
    };
  }

  Customer copyWith({String? name, String? phone, int? loyaltyPoints, double? totalSpent, DateTime? lastVisit, String? notes}) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      totalSpent: totalSpent ?? this.totalSpent,
      lastVisit: lastVisit ?? this.lastVisit,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}

