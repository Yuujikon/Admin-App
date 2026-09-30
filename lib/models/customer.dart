import 'package:cloud_firestore/cloud_firestore.dart';

/// Customer profile data model.
class Customer {
  /// Unique customer document ID.
  final String id;

  /// Full customer name.
  final String name;

  /// Customer email address.
  final String? email;

  /// Primary phone number.
  final String phone;

  /// Cumulative lifetime purchase spend in Pesos.
  final double totalSpent;

  /// Timestamp of customer's last recorded order/visit.
  final DateTime? lastVisit;

  /// Administrative notes regarding customer preference or store credit.
  final String notes;

  /// Timestamp when customer account was registered.
  final DateTime createdAt;

  /// Creates a [Customer] instance.
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

  /// Factory constructor for parsing Firestore document map.
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

  /// Converts customer object to Map for Firestore persistence.
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

  /// Returns a copy of [Customer] with modified properties.
  Customer copyWith(
      {String? name,
      String? email,
      String? phone,
      double? totalSpent,
      DateTime? lastVisit,
      String? notes}) {
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
