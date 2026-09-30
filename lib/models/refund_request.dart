import 'package:cloud_firestore/cloud_firestore.dart';
import 'order.dart';

/// Status enum for customer refund request processing.
enum RefundStatus { pending, approved, rejected }

/// Physical condition assessment for returned goods.
enum RefundCondition { restockable, expired, damaged }

/// Data model representing a customer refund or return request.
class RefundRequest {
  /// Unique refund request document ID.
  final String id;

  /// Associated original transaction ID.
  final String transactionId;

  /// Customer email address.
  final String customerEmail;

  /// Customer full name.
  final String customerName;

  /// Items requested for refund/return.
  final List<CartItem> items;

  /// Total refund value in Pesos.
  final double total;

  /// Customer statement or reason for refund request.
  final String reason;

  /// Rejection reason provided by store admin if request is declined.
  final String? rejectionReason;

  /// Internal administrative notes regarding resolution.
  final String? adminNotes;

  /// Current processing status.
  final RefundStatus status;

  /// Return item condition determined during inspection.
  final RefundCondition? condition;

  /// Timestamp when request was submitted.
  final DateTime createdAt;

  /// Email of store admin who processed or resolved the request.
  final String? processedByEmail;

  /// Base64 encoded proof photo submitted by customer.
  final String? photoBase64;

  /// Creates a [RefundRequest] instance.
  const RefundRequest({
    required this.id,
    required this.transactionId,
    required this.customerEmail,
    required this.customerName,
    required this.items,
    required this.total,
    required this.reason,
    this.rejectionReason,
    this.adminNotes,
    required this.status,
    this.condition,
    required this.createdAt,
    this.processedByEmail,
    this.photoBase64,
  });

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory RefundRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;

    RefundStatus status = RefundStatus.pending;
    try {
      status = RefundStatus.values.byName(d['status'] ?? 'pending');
    } catch (_) {}

    RefundCondition? condition;
    if (d['condition'] != null) {
      try {
        condition = RefundCondition.values.byName(d['condition']);
      } catch (_) {}
    }

    return RefundRequest(
      id: doc.id,
      transactionId: d['transactionId'] ?? '',
      customerEmail: d['customerEmail'] ?? '',
      customerName: d['customerName'] ?? '',
      items:
          (d['items'] as List? ?? []).map((e) => CartItem.fromMap(e)).toList(),
      total: (d['total'] as num? ?? 0).toDouble(),
      reason: d['reason'] ?? '',
      rejectionReason: d['rejectionReason'],
      adminNotes: d['adminNotes'],
      status: status,
      condition: condition,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      processedByEmail: d['processedByEmail'],
      photoBase64: d['photoBase64'] ?? d['proofPhotoBase64'],
    );
  }

  /// Converts model to Map for Firestore write operations.
  Map<String, dynamic> toFirestore() => {
        'transactionId': transactionId,
        'customerEmail': customerEmail,
        'customerName': customerName,
        'items': items.map((i) => i.toMap()).toList(),
        'total': total,
        'reason': reason,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        if (adminNotes != null) 'adminNotes': adminNotes,
        'status': status.name,
        if (condition != null) 'condition': condition!.name,
        'createdAt': FieldValue.serverTimestamp(),
        if (processedByEmail != null) 'processedByEmail': processedByEmail,
        if (photoBase64 != null) 'photoBase64': photoBase64,
      };
}
