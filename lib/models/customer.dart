import 'package:cloud_firestore/cloud_firestore.dart';
import '../shared/services/time_service.dart';

/// Customer profile data model supporting ghosting offense escalation and account restriction management.
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

  /// Total recorded ghosting/uncollected order offenses (0 to 4+).
  final int offenseCount;

  /// Expiration timestamp for temporary ordering restriction.
  final DateTime? restrictedUntil;

  /// True if customer account is permanently locked (4th offense).
  final bool isPermanentlyLocked;

  /// Detailed history log of recorded offenses.
  final List<Map<String, dynamic>> offenseHistory;

  /// Status of account unlock appeal ('none', 'pending', 'approved', 'rejected').
  final String? appealStatus;

  /// Appeal statement submitted by customer.
  final String? appealMessage;

  /// Timestamp when appeal was submitted.
  final DateTime? appealSubmittedAt;

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
    this.offenseCount = 0,
    this.restrictedUntil,
    this.isPermanentlyLocked = false,
    this.offenseHistory = const [],
    this.appealStatus,
    this.appealMessage,
    this.appealSubmittedAt,
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
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? TimeService.now,
      offenseCount: (map['offenseCount'] as num? ?? 0).toInt(),
      restrictedUntil: (map['restrictedUntil'] as Timestamp?)?.toDate(),
      isPermanentlyLocked: map['isPermanentlyLocked'] ?? false,
      offenseHistory: (map['offenseHistory'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e is Map ? e : {}))
          .toList(),
      appealStatus: map['appealStatus']?.toString(),
      appealMessage: map['appealMessage']?.toString(),
      appealSubmittedAt: (map['appealSubmittedAt'] as Timestamp?)?.toDate(),
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
      'createdAt': Timestamp.fromDate(createdAt),
      'offenseCount': offenseCount,
      'restrictedUntil':
          restrictedUntil != null ? Timestamp.fromDate(restrictedUntil!) : null,
      'isPermanentlyLocked': isPermanentlyLocked,
      'offenseHistory': offenseHistory,
      if (appealStatus != null) 'appealStatus': appealStatus,
      if (appealMessage != null) 'appealMessage': appealMessage,
      if (appealSubmittedAt != null)
        'appealSubmittedAt': Timestamp.fromDate(appealSubmittedAt!),
    };
  }

  /// True if customer is currently restricted or permanently locked from ordering.
  bool get isRestricted {
    if (isPermanentlyLocked) return true;
    if (restrictedUntil == null) return false;
    return restrictedUntil!.isAfter(TimeService.now);
  }

  /// Calculates restriction penalty duration in hours for a given offense level.
  /// 1st Offense: 2 hours
  /// 2nd Offense: 24 hours
  /// 3rd Offense: 72 hours (3 days)
  /// 4th Offense: Permanent Lock (-1)
  static int getRestrictionHoursForOffense(int offenseLevel) {
    switch (offenseLevel) {
      case 1:
        return 2;
      case 2:
        return 24;
      case 3:
        return 72;
      default:
        return -1; // Permanent Account Lock
    }
  }

  /// Descriptive label for current offense status.
  String get offenseStatusLabel {
    if (isPermanentlyLocked) return '4th Offense: Permanent Lock';
    if (offenseCount == 0) return 'Clean Record';
    if (!isRestricted) return 'Offense $offenseCount (Lock Expired)';

    switch (offenseCount) {
      case 1:
        return '1st Offense: 2-Hour Lock';
      case 2:
        return '2nd Offense: 24-Hour Lock';
      case 3:
        return '3rd Offense: 72-Hour Lock';
      default:
        return 'Offense $offenseCount: Locked';
    }
  }

  /// Returns a copy of [Customer] with modified properties.
  Customer copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    double? totalSpent,
    DateTime? lastVisit,
    String? notes,
    int? offenseCount,
    DateTime? restrictedUntil,
    bool? isPermanentlyLocked,
    List<Map<String, dynamic>>? offenseHistory,
    String? appealStatus,
    String? appealMessage,
    DateTime? appealSubmittedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      totalSpent: totalSpent ?? this.totalSpent,
      lastVisit: lastVisit ?? this.lastVisit,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      offenseCount: offenseCount ?? this.offenseCount,
      restrictedUntil: restrictedUntil ?? this.restrictedUntil,
      isPermanentlyLocked: isPermanentlyLocked ?? this.isPermanentlyLocked,
      offenseHistory: offenseHistory ?? this.offenseHistory,
      appealStatus: appealStatus ?? this.appealStatus,
      appealMessage: appealMessage ?? this.appealMessage,
      appealSubmittedAt: appealSubmittedAt ?? this.appealSubmittedAt,
    );
  }
}
