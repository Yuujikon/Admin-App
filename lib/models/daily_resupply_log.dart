import 'package:cloud_firestore/cloud_firestore.dart';

/// Snapshot of a product (or variant) whose 100% physical store stock reached
/// 30% of its original stock on a given calendar day and is included in the
/// Store-Closing Resupply Summary email.
class DailyResupplyItem {
  final String itemKey;
  final String productId;
  final String? variantId;
  final String productName;
  final String? variantName;
  final String category;
  final String unit;
  final int originalStock;
  final int lowStockThreshold;
  final int physicalStock;
  final int onlineStock;
  final int totalStock;
  final int availableStock;
  final int suggestedResupplyQty;
  final bool onlineOutOfStock;
  final DateTime firstTriggeredAt;
  final DateTime lastUpdatedAt;

  const DailyResupplyItem({
    required this.itemKey,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantName,
    required this.category,
    required this.unit,
    this.originalStock = 0,
    required this.lowStockThreshold,
    required this.physicalStock,
    required this.onlineStock,
    required this.totalStock,
    required this.availableStock,
    required this.suggestedResupplyQty,
    required this.onlineOutOfStock,
    required this.firstTriggeredAt,
    required this.lastUpdatedAt,
  });

  int get effectiveOriginalStock =>
      originalStock > 0 ? originalStock : totalStock;

  String get displayName =>
      (variantName != null && variantName!.trim().isNotEmpty)
          ? '$productName (${variantName!.trim()})'
          : productName;

  bool get isOutOfStock => availableStock <= 0;

  static String buildItemKey(String productId, [String? variantId]) {
    final cleanVar = variantId?.trim() ?? '';
    return cleanVar.isEmpty ? productId : '${productId}__$cleanVar';
  }

  factory DailyResupplyItem.fromMap(
    Map<String, dynamic> data, {
    required String itemKey,
  }) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
      return DateTime.now();
    }

    final int parsedTotal = (data['totalStock'] as num? ?? 0).toInt();
    final int parsedOriginal =
        (data['originalStock'] as num? ?? parsedTotal).toInt();

    return DailyResupplyItem(
      itemKey: itemKey,
      productId: data['productId']?.toString() ?? itemKey,
      variantId: data['variantId']?.toString(),
      productName: data['productName']?.toString() ?? 'Unnamed Product',
      variantName: data['variantName']?.toString(),
      category: data['category']?.toString() ?? 'Others',
      unit: data['unit']?.toString() ?? 'pcs',
      originalStock: parsedOriginal,
      lowStockThreshold: (data['lowStockThreshold'] as num? ?? 0).toInt(),
      physicalStock: (data['physicalStock'] as num? ?? 0).toInt(),
      onlineStock: (data['onlineStock'] as num? ?? 0).toInt(),
      totalStock: parsedTotal,
      availableStock: (data['availableStock'] as num? ?? 0).toInt(),
      suggestedResupplyQty:
          (data['suggestedResupplyQty'] as num? ?? 10).toInt(),
      onlineOutOfStock: data['onlineOutOfStock'] == true,
      firstTriggeredAt: parseDate(data['firstTriggeredAt']),
      lastUpdatedAt: parseDate(data['lastUpdatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'productId': productId,
        if (variantId != null && variantId!.trim().isNotEmpty)
          'variantId': variantId!.trim(),
        'productName': productName,
        if (variantName != null && variantName!.trim().isNotEmpty)
          'variantName': variantName!.trim(),
        'category': category,
        'unit': unit,
        'originalStock': effectiveOriginalStock,
        'lowStockThreshold': lowStockThreshold,
        'physicalStock': physicalStock,
        'onlineStock': onlineStock,
        'totalStock': totalStock,
        'availableStock': availableStock,
        'suggestedResupplyQty': suggestedResupplyQty,
        'onlineOutOfStock': onlineOutOfStock,
        'firstTriggeredAt': Timestamp.fromDate(firstTriggeredAt),
        'lastUpdatedAt': Timestamp.fromDate(lastUpdatedAt),
      };
}

/// Daily resupply log persisted at `daily_resupply_logs/{YYYY-MM-DD}` tracking
/// every product/variant that hit its physical low-stock threshold that day and
/// coordinating idempotent End-of-Day summary email dispatch.
class DailyResupplyLog {
  final String dateKey;
  final String storeEmail;
  final Map<String, DailyResupplyItem> items;
  final bool summaryEmailSent;
  final String? summaryEmailStatus;
  final DateTime? summaryEmailSentAt;
  final String? summaryEmailSentBy;
  final String? summaryEmailError;
  final DateTime? updatedAt;

  const DailyResupplyLog({
    required this.dateKey,
    required this.storeEmail,
    this.items = const {},
    this.summaryEmailSent = false,
    this.summaryEmailStatus,
    this.summaryEmailSentAt,
    this.summaryEmailSentBy,
    this.summaryEmailError,
    this.updatedAt,
  });

  List<DailyResupplyItem> get sortedItems {
    final list = items.values.toList()
      ..sort((a, b) {
        final stockCmp = a.availableStock.compareTo(b.availableStock);
        if (stockCmp != 0) return stockCmp;
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      });
    return list;
  }

  int get itemCount => items.length;

  int get totalSuggestedUnits =>
      items.values.fold(0, (acc, i) => acc + i.suggestedResupplyQty);

  factory DailyResupplyLog.empty(
    String dateKey, {
    String storeEmail = 'gdcstore.ph@gmail.com',
  }) {
    return DailyResupplyLog(
      dateKey: dateKey,
      storeEmail: storeEmail,
    );
  }

  factory DailyResupplyLog.fromMap(
    Map<String, dynamic> data, {
    required String dateKey,
  }) {
    DateTime? parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    final Map<String, DailyResupplyItem> parsedItems = {};
    final rawItems = data['items'];
    if (rawItems is Map) {
      for (final entry in rawItems.entries) {
        if (entry.value is Map) {
          final key = entry.key.toString();
          parsedItems[key] = DailyResupplyItem.fromMap(
            Map<String, dynamic>.from(entry.value as Map),
            itemKey: key,
          );
        }
      }
    }

    return DailyResupplyLog(
      dateKey: (data['dateKey']?.toString().trim().isNotEmpty ?? false)
          ? data['dateKey'].toString().trim()
          : dateKey,
      storeEmail: (data['storeEmail']?.toString().trim().isNotEmpty ?? false)
          ? data['storeEmail'].toString().trim()
          : 'gdcstore.ph@gmail.com',
      items: parsedItems,
      summaryEmailSent: data['summaryEmailSent'] == true,
      summaryEmailStatus: data['summaryEmailStatus']?.toString(),
      summaryEmailSentAt: parseDate(data['summaryEmailSentAt']),
      summaryEmailSentBy: data['summaryEmailSentBy']?.toString(),
      summaryEmailError: data['summaryEmailError']?.toString(),
      updatedAt: parseDate(data['updatedAt']),
    );
  }

  factory DailyResupplyLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return DailyResupplyLog.fromMap(data, dateKey: doc.id);
  }
}
