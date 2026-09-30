import 'package:cloud_firestore/cloud_firestore.dart';

enum ShiftStatus { active, closed }

class CashDrop {
  final String id;
  final double amount;
  final String reason;
  final DateTime createdAt;

  const CashDrop({
    required this.id,
    required this.amount,
    required this.reason,
    required this.createdAt,
  });

  factory CashDrop.fromMap(dynamic m) {
    if (m is! Map) return CashDrop(id: '', amount: 0, reason: '', createdAt: DateTime.now());
    return CashDrop(
      id: m['id']?.toString() ?? '',
      amount: (m['amount'] as num? ?? 0.0).toDouble(),
      reason: m['reason']?.toString() ?? '',
      createdAt: m['createdAt'] is Timestamp 
          ? (m['createdAt'] as Timestamp).toDate() 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'amount': amount,
    'reason': reason,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

class ShiftSession {
  final String id;
  final String cashierId;
  final String cashierName;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingFloat;
  final double cashSales;
  final double gcashSales;
  final List<CashDrop> cashDrops;
  final double? actualCashCounted;
  final ShiftStatus status;

  const ShiftSession({
    required this.id,
    required this.cashierId,
    required this.cashierName,
    required this.openedAt,
    this.closedAt,
    required this.openingFloat,
    this.cashSales = 0.0,
    this.gcashSales = 0.0,
    this.cashDrops = const [],
    this.actualCashCounted,
    this.status = ShiftStatus.active,
  });

  double get totalCashDrops => cashDrops.fold(0.0, (acc, d) => acc + d.amount);
  double get expectedCash => openingFloat + cashSales - totalCashDrops;
  double get cashDifference => (actualCashCounted ?? expectedCash) - expectedCash;
  bool get isShortage => cashDifference < 0;
  bool get isOverage => cashDifference > 0;

  factory ShiftSession.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ShiftSession(
      id: doc.id,
      cashierId: d['cashierId']?.toString() ?? '',
      cashierName: d['cashierName']?.toString() ?? 'Cashier',
      openedAt: (d['openedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      closedAt: (d['closedAt'] as Timestamp?)?.toDate(),
      openingFloat: (d['openingFloat'] as num? ?? 0.0).toDouble(),
      cashSales: (d['cashSales'] as num? ?? 0.0).toDouble(),
      gcashSales: (d['gcashSales'] as num? ?? 0.0).toDouble(),
      cashDrops: (d['cashDrops'] as List? ?? []).map((e) => CashDrop.fromMap(e)).toList(),
      actualCashCounted: d['actualCashCounted'] != null ? (d['actualCashCounted'] as num).toDouble() : null,
      status: ShiftStatus.values.firstWhere(
        (e) => e.name == (d['status'] ?? 'active'),
        orElse: () => ShiftStatus.active,
      ),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'cashierId': cashierId,
    'cashierName': cashierName,
    'openedAt': Timestamp.fromDate(openedAt),
    'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
    'openingFloat': openingFloat,
    'cashSales': cashSales,
    'gcashSales': gcashSales,
    'cashDrops': cashDrops.map((d) => d.toMap()).toList(),
    'actualCashCounted': actualCashCounted,
    'status': status.name,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  ShiftSession copyWith({
    double? cashSales,
    double? gcashSales,
    List<CashDrop>? cashDrops,
    double? actualCashCounted,
    DateTime? closedAt,
    ShiftStatus? status,
  }) => ShiftSession(
    id: id,
    cashierId: cashierId,
    cashierName: cashierName,
    openedAt: openedAt,
    closedAt: closedAt ?? this.closedAt,
    openingFloat: openingFloat,
    cashSales: cashSales ?? this.cashSales,
    gcashSales: gcashSales ?? this.gcashSales,
    cashDrops: cashDrops ?? this.cashDrops,
    actualCashCounted: actualCashCounted ?? this.actualCashCounted,
    status: status ?? this.status,
  );
}
