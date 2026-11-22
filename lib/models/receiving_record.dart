import 'package:cloud_firestore/cloud_firestore.dart';

/// Item detail inside a receiving record.
class ReceivingItem {
  final String productId;
  final String productName;
  final int qty;
  final String batchId;

  const ReceivingItem({
    required this.productId,
    this.productName = '',
    required this.qty,
    required this.batchId,
  });

  factory ReceivingItem.fromMap(Map<String, dynamic> map) {
    return ReceivingItem(
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      qty: (map['qty'] as num? ?? 0).toInt(),
      batchId: map['batchId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'qty': qty,
        'batchId': batchId,
      };
}

/// Receiving Record document representing physical delivery receipt verification for a Purchase Order.
class ReceivingRecord {
  final String id;
  final String poId;
  final String deliveryReceiptNo;
  final DateTime receivedAt;
  final String? discrepancyNote;
  final List<ReceivingItem> itemsReceived;

  const ReceivingRecord({
    required this.id,
    required this.poId,
    required this.deliveryReceiptNo,
    required this.receivedAt,
    this.discrepancyNote,
    required this.itemsReceived,
  });

  factory ReceivingRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val != null) {
        final parsed = DateTime.tryParse(val.toString());
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    final rawItems = (data['itemsReceived'] as List? ?? []);
    final items = rawItems
        .map(
            (i) => ReceivingItem.fromMap(Map<String, dynamic>.from(i as Map)))
        .toList();

    return ReceivingRecord(
      id: doc.id,
      poId: data['poId']?.toString() ?? '',
      deliveryReceiptNo: data['deliveryReceiptNo']?.toString() ?? '',
      receivedAt: parseDate(data['receivedAt'], DateTime.now()),
      discrepancyNote: data['discrepancyNote']?.toString(),
      itemsReceived: items,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'poId': poId,
        'deliveryReceiptNo': deliveryReceiptNo,
        'receivedAt': Timestamp.fromDate(receivedAt),
        'discrepancyNote': discrepancyNote,
        'itemsReceived': itemsReceived.map((i) => i.toMap()).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      };
}
