import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/email_validator.dart';

/// Describes a missing or malformed supplier field discovered during pre-flight validation.
class SupplierFieldIssue {
  final String fieldKey;
  final String label;
  final String message;
  final bool isBlocking;

  const SupplierFieldIssue({
    required this.fieldKey,
    required this.label,
    required this.message,
    this.isBlocking = true,
  });
}

/// Aggregated validation result for pre-flight PO / Backorder PDF and email dispatch.
class SupplierValidationResult {
  final List<SupplierFieldIssue> blockingIssues;
  final List<SupplierFieldIssue> advisoryIssues;

  const SupplierValidationResult({
    required this.blockingIssues,
    this.advisoryIssues = const [],
  });

  /// Whether all mandatory supplier fields are present and well-formed.
  bool get isValid => blockingIssues.isEmpty;

  /// Human-readable summary of all blocking issues.
  String get summaryMessage {
    if (isValid) return 'All mandatory supplier details are valid.';
    return blockingIssues.map((i) => i.message).join(' • ');
  }
}

/// Exception thrown when PDF generation or dispatch is attempted with incomplete supplier data.
class SupplierValidationException implements Exception {
  final SupplierValidationResult validationResult;

  const SupplierValidationException(this.validationResult);

  @override
  String toString() =>
      'SupplierValidationException: ${validationResult.summaryMessage}';
}

/// Immutable point-in-time snapshot of a supplier embedded on Purchase Orders and Backorders.
///
/// Serves as the Single Source of Truth across on-screen review UI,
/// Purchase Order PDFs, Backorder PDFs, and dual-recipient transactional emails.
class SupplierSnapshot {
  final String supplierId;
  final String supplierName;
  final String contactPerson;
  final String email;
  final String phone;
  final String address;
  final String tin;
  final String paymentTerms;
  final String category;
  final DateTime? snapshottedAt;

  const SupplierSnapshot({
    required this.supplierId,
    required this.supplierName,
    this.contactPerson = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.tin = '',
    this.paymentTerms = '',
    this.category = 'General',
    this.snapshottedAt,
  });

  /// Creates a snapshot from a live Firestore [Supplier] profile.
  factory SupplierSnapshot.fromSupplier(
    Supplier supplier, {
    DateTime? snapshottedAt,
  }) {
    return SupplierSnapshot(
      supplierId: supplier.id.trim(),
      supplierName: supplier.name.trim(),
      contactPerson: supplier.contactName.trim(),
      email: supplier.email.trim(),
      phone: supplier.phone.trim(),
      address: supplier.address.trim(),
      tin: supplier.tin.trim(),
      paymentTerms: supplier.paymentTerms.trim(),
      category: supplier.category.trim().isEmpty
          ? 'General'
          : supplier.category.trim(),
      snapshottedAt: snapshottedAt ?? DateTime.now(),
    );
  }

  /// Hydrates a [SupplierSnapshot] from a Firestore map, tolerating legacy key aliases.
  factory SupplierSnapshot.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    String readStr(List<String> keys, [String fallback = '']) {
      for (final key in keys) {
        final raw = map[key];
        if (raw != null && raw.toString().trim().isNotEmpty) {
          return raw.toString().trim();
        }
      }
      return fallback;
    }

    return SupplierSnapshot(
      supplierId: readStr(['supplierId', 'id']),
      supplierName: readStr(['supplierName', 'name']),
      contactPerson: readStr(['contactPerson', 'contactName']),
      email: readStr(['email', 'supplierEmail']),
      phone: readStr(['phone', 'contactNumber', 'supplierPhone']),
      address: readStr(['address', 'physicalAddress', 'supplierAddress']),
      tin: readStr(['tin', 'businessId', 'tinNumber']),
      paymentTerms: readStr(['paymentTerms', 'terms']),
      category: readStr(['category'], 'General'),
      snapshottedAt: parseDate(map['snapshottedAt']),
    );
  }

  /// Serializes this snapshot for Firestore persistence inside a PO/Backorder document.
  Map<String, dynamic> toMap() => {
        'supplierId': supplierId.trim(),
        'supplierName': supplierName.trim(),
        'contactPerson': contactPerson.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'tin': tin.trim(),
        'paymentTerms': paymentTerms.trim(),
        'category': category.trim().isEmpty ? 'General' : category.trim(),
        'snapshottedAt': snapshottedAt != null
            ? Timestamp.fromDate(snapshottedAt!)
            : FieldValue.serverTimestamp(),
      };

  /// Fills any missing fields on an older snapshot using a live [Supplier] profile.
  SupplierSnapshot mergeWithFallback(Supplier? liveSupplier) {
    if (liveSupplier == null) return this;
    String pick(String current, String fallback) =>
        current.trim().isNotEmpty ? current.trim() : fallback.trim();

    return SupplierSnapshot(
      supplierId: pick(supplierId, liveSupplier.id),
      supplierName: pick(supplierName, liveSupplier.name),
      contactPerson: pick(contactPerson, liveSupplier.contactName),
      email: pick(email, liveSupplier.email),
      phone: pick(phone, liveSupplier.phone),
      address: pick(address, liveSupplier.address),
      tin: pick(tin, liveSupplier.tin),
      paymentTerms: pick(paymentTerms, liveSupplier.paymentTerms),
      category: pick(category, liveSupplier.category),
      snapshottedAt: snapshottedAt,
    );
  }

  /// Converts this snapshot back to a master [Supplier] model for Firestore profile syncing.
  Supplier toSupplier({bool autoNotifyLowStock = true}) {
    return Supplier(
      id: supplierId,
      name: supplierName.trim(),
      contactName: contactPerson.trim(),
      phone: phone.trim(),
      email: email.trim(),
      address: address.trim(),
      tin: tin.trim(),
      paymentTerms: paymentTerms.trim(),
      category: category.trim().isEmpty ? 'General' : category.trim(),
      autoNotifyLowStock: autoNotifyLowStock,
    );
  }

  SupplierSnapshot copyWith({
    String? supplierId,
    String? supplierName,
    String? contactPerson,
    String? email,
    String? phone,
    String? address,
    String? tin,
    String? paymentTerms,
    String? category,
    DateTime? snapshottedAt,
  }) {
    return SupplierSnapshot(
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      contactPerson: contactPerson ?? this.contactPerson,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      tin: tin ?? this.tin,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      category: category ?? this.category,
      snapshottedAt: snapshottedAt ?? this.snapshottedAt,
    );
  }

  /// Validates mandatory and advisory fields prior to PDF generation and dual-email dispatch.
  ///
  /// Mandatory (blocking): [supplierName], valid [email], [phone] (>= 7 digits), [address] (>= 5 chars).
  /// Advisory (non-blocking): [contactPerson], [tin], [paymentTerms].
  SupplierValidationResult validateForDispatch() {
    final List<SupplierFieldIssue> blocking = [];
    final List<SupplierFieldIssue> advisory = [];

    final cleanName = supplierName.trim();
    if (cleanName.isEmpty ||
        cleanName.toLowerCase() == 'unnamed supplier' ||
        cleanName.toLowerCase() == 'unknown supplier') {
      blocking.add(const SupplierFieldIssue(
        fieldKey: 'supplierName',
        label: 'Supplier Name',
        message: 'Missing Supplier Name – Required for PO/Backorder PDF',
      ));
    }

    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      blocking.add(const SupplierFieldIssue(
        fieldKey: 'email',
        label: 'Supplier Email',
        message: 'Missing Supplier Email – Required to dispatch document',
      ));
    } else {
      final emailError = EmailValidator.validate(cleanEmail);
      if (emailError != null) {
        blocking.add(SupplierFieldIssue(
          fieldKey: 'email',
          label: 'Supplier Email',
          message: 'Invalid Supplier Email – $emailError',
        ));
      }
    }

    final cleanPhone = phone.trim();
    final digitCount = cleanPhone.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (cleanPhone.isEmpty) {
      blocking.add(const SupplierFieldIssue(
        fieldKey: 'phone',
        label: 'Contact Number',
        message: 'Missing Contact Number – Required for PO/Backorder PDF',
      ));
    } else if (digitCount < 7) {
      blocking.add(const SupplierFieldIssue(
        fieldKey: 'phone',
        label: 'Contact Number',
        message: 'Malformed Contact Number – Enter at least 7 digits',
      ));
    }

    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) {
      blocking.add(const SupplierFieldIssue(
        fieldKey: 'address',
        label: 'Physical Address',
        message: 'Missing Address – Required for PO/Backorder PDF',
      ));
    } else if (cleanAddress.length < 5) {
      blocking.add(const SupplierFieldIssue(
        fieldKey: 'address',
        label: 'Physical Address',
        message: 'Incomplete Address – Provide full street/city address',
      ));
    }

    if (contactPerson.trim().isEmpty) {
      advisory.add(const SupplierFieldIssue(
        fieldKey: 'contactPerson',
        label: 'Contact Person',
        message: 'Contact Person not specified (recommended)',
        isBlocking: false,
      ));
    }

    if (tin.trim().isEmpty) {
      advisory.add(const SupplierFieldIssue(
        fieldKey: 'tin',
        label: 'TIN / Business ID',
        message: 'TIN / Business ID not specified',
        isBlocking: false,
      ));
    }

    if (paymentTerms.trim().isEmpty) {
      advisory.add(const SupplierFieldIssue(
        fieldKey: 'paymentTerms',
        label: 'Payment Terms',
        message: 'Payment Terms not specified',
        isBlocking: false,
      ));
    }

    return SupplierValidationResult(
      blockingIssues: blocking,
      advisoryIssues: advisory,
    );
  }
}

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

  /// Physical business / warehouse address.
  final String address;

  /// Tax Identification Number (TIN) or Business Registration ID.
  final String tin;

  /// Agreed payment terms (e.g., COD, Net 15, Net 30).
  final String paymentTerms;

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
    this.address = '',
    this.tin = '',
    this.paymentTerms = '',
    this.category = 'General',
    this.autoNotifyLowStock = true,
  });

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory Supplier.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Supplier(
      id: doc.id,
      name: (d['name'] ?? d['supplierName'] ?? 'Unnamed Supplier')
          .toString()
          .trim(),
      contactName:
          (d['contactName'] ?? d['contactPerson'] ?? '').toString().trim(),
      phone: (d['phone'] ?? d['contactNumber'] ?? '').toString().trim(),
      email: (d['email'] ?? '').toString().trim(),
      address: (d['address'] ?? d['physicalAddress'] ?? '').toString().trim(),
      tin: (d['tin'] ?? d['businessId'] ?? d['tinNumber'] ?? '')
          .toString()
          .trim(),
      paymentTerms: (d['paymentTerms'] ?? d['terms'] ?? '').toString().trim(),
      category: (d['category'] ?? 'General').toString().trim(),
      autoNotifyLowStock: (d['autoNotifyLowStock'] as bool?) ?? true,
    );
  }

  /// Converts supplier model to Map for Firestore persistence.
  Map<String, dynamic> toFirestore() => {
        'name': name.trim(),
        'contactName': contactName.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'address': address.trim(),
        'tin': tin.trim(),
        'paymentTerms': paymentTerms.trim(),
        'category': category.trim().isEmpty ? 'General' : category.trim(),
        'autoNotifyLowStock': autoNotifyLowStock,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Converts this master supplier profile into an immutable [SupplierSnapshot].
  SupplierSnapshot toSnapshot({DateTime? snapshottedAt}) =>
      SupplierSnapshot.fromSupplier(this, snapshottedAt: snapshottedAt);

  /// Returns a copy of [Supplier] with updated fields.
  Supplier copyWith({
    String? id,
    String? name,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? tin,
    String? paymentTerms,
    String? category,
    bool? autoNotifyLowStock,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      contactName: contactName ?? this.contactName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      tin: tin ?? this.tin,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      category: category ?? this.category,
      autoNotifyLowStock: autoNotifyLowStock ?? this.autoNotifyLowStock,
    );
  }
}
