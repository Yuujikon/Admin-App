import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'order.dart';

enum RefundStatus { pending, approved, rejected }

class RefundRequest {
  final String id;
  final String transactionId;
  final String customerEmail;
  final String customerName;
  final List<CartItem> items;
  final double total;
  final String reason;
  final String? rejectionReason;
  final RefundStatus status;
  final DateTime createdAt;
  final String? processedByEmail;

  const RefundRequest({
    required this.id,
    required this.transactionId,
    required this.customerEmail,
    required this.customerName,
    required this.items,
    required this.total,
    required this.reason,
    this.rejectionReason,
    required this.status,
    required this.createdAt,
    this.processedByEmail,
  });

  factory RefundRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    
    // Robust status parsing
    RefundStatus status = RefundStatus.pending;
    try {
      status = RefundStatus.values.byName(d['status'] ?? 'pending');
    } catch (e) {
      debugPrint('Error parsing RefundStatus for ${doc.id}: $e');
    }

    return RefundRequest(
      id: doc.id,
      transactionId: d['transactionId'] ?? '',
      customerEmail: d['customerEmail'] ?? '',
      customerName: d['customerName'] ?? '',
      items: (d['items'] as List? ?? []).map((e) => CartItem.fromMap(e)).toList(),
      total: (d['total'] as num? ?? 0).toDouble(),
      reason: d['reason'] ?? '',
      rejectionReason: d['rejectionReason'],
      status: status,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      processedByEmail: d['processedByEmail'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'transactionId': transactionId,
    'customerEmail': customerEmail,
    'customerName': customerName,
    'items': items.map((i) => i.toMap()).toList(),
    'total': total,
    'reason': reason,
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
    'status': status.name,
    'createdAt': FieldValue.serverTimestamp(),
    if (processedByEmail != null) 'processedByEmail': processedByEmail,
  };
}
