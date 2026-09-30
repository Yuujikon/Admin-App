import 'package:cloud_firestore/cloud_firestore.dart';

/// Supplier contact and vendor profile data model.
class Supplier {
  /// Unique supplier document ID.
  final String id;

  /// Business/company name of supplier.
  final String name;

  /// Primary contact person.
  final String contactName;

  /// Telephone / Mobile contact number.
  final String phone;

  /// Email address.
  final String email;

  /// Product category supplied (e.g. Beverages, Snacks).
  final String category;

  /// Auto-send low stock notification flag.
  final bool autoNotifyLowStock;

  /// Creates a [Supplier] instance.
  const Supplier({
    required this.id,
    required this.name,
    this.contactName = '',
    this.phone = '',
    this.email = '',
    this.category = 'General',
    this.autoNotifyLowStock = true,
  });

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
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

  /// Converts supplier model to Map for Firestore persistence.
  Map<String, dynamic> toFirestore() => {
        'name': name,
        'contactName': contactName,
        'phone': phone,
        'email': email,
        'category': category,
        'autoNotifyLowStock': autoNotifyLowStock,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Returns a copy of [Supplier] with updated fields.
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
