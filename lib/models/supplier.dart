import 'package:cloud_firestore/cloud_firestore.dart';

class Supplier {
  final String id;
  final String name;
  final String contactName;
  final String phone;
  final String email;
  final String category; // e.g. Beverages, Snacks
  final bool autoNotifyLowStock;

  const Supplier({
    required this.id,
    required this.name,
    this.contactName = '',
    this.phone = '',
    this.email = '',
    this.category = 'General',
    this.autoNotifyLowStock = true,
  });

  factory Supplier.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Supplier(
      id: doc.id,
      name: d['name'] ?? 'Unnamed Supplier',
      contactName: d['contactName'] ?? '',
      phone: d['phone'] ?? '',
      email: d['email'] ?? '',
      category: d['category'] ?? 'General',
      autoNotifyLowStock: d['autoNotifyLowStock'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'contactName': contactName,
    'phone': phone,
    'email': email,
    'category': category,
    'autoNotifyLowStock': autoNotifyLowStock,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Supplier copyWith({
    String? id,
    String? name,
    String? contactName,
    String? phone,
    String? email,
    String? category,
    bool? autoNotifyLowStock,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      contactName: contactName ?? this.contactName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      category: category ?? this.category,
      autoNotifyLowStock: autoNotifyLowStock ?? this.autoNotifyLowStock,
    );
  }
}
