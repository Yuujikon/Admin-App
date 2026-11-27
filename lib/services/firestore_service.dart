import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import '../models/expense.dart';
import '../models/refund_request.dart';
import '../models/bundle.dart';
import '../models/store_settings.dart';
import '../models/supplier.dart';
import '../models/loss_record.dart';
import '../models/customer.dart';
import '../models/catalog_product.dart';
import '../models/restock_inquiry.dart';
import '../models/delivery_log.dart';
import '../models/rfq.dart';
import '../models/purchase_order.dart';
import '../models/receiving_record.dart';
import '../models/inventory_batch_record.dart';
import '../models/daily_resupply_log.dart';
import '../shared/services/time_service.dart';
import '../shared/services/admin_messaging_service.dart';
import 'audit_log_service.dart';
import 'inventory_batch_service.dart';

/// Payload model representing a single line item delivery payload received during stock reconciliation.
class DeliveryItemPayload {
  /// The target inventory product being updated.
  final Product product;

  /// Quantity of units received in this delivery batch.
  final int qtyReceived;

  /// Unit purchase cost for this stock batch.
  final double unitCost;

  /// New batch details including expiration date and batch code.
  final ProductBatch newBatch;

  /// Originally ordered quantity from the purchase order/inquiry, if available.
  final int? orderedQty;

  /// Originally quoted unit cost, if available.
  final double? orderedUnitCost;

  /// Notes explaining quantity or cost variances.
  final String? discrepancyNote;

  /// Associated supplier identifier.
  final String? supplierId;

  /// Associated supplier name.
  final String? supplierName;

  /// Creates a new instance of [DeliveryItemPayload].
  DeliveryItemPayload({
    required this.product,
    required this.qtyReceived,
    required this.unitCost,
    required this.newBatch,
    this.orderedQty,
    this.orderedUnitCost,
    this.discrepancyNote,
    this.supplierId,
    this.supplierName,
  });
}

/// Core service handling Cloud Firestore database operations for inventory, orders, sales, and analytics.
class FirestoreService {
  final _db = FirebaseFirestore.instance;
  final _batchService = InventoryBatchService();

  /// Initializes [FirestoreService] and ensures offline persistence is configured.
  FirestoreService() {
    try {
      _db.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (_) {
      // Settings can only be set once before any Firestore calls
    }
  }

  // ── Collections ────────────────────────────────────────────────────────────
  CollectionReference get _products => _db.collection('products');
  CollectionReference get _catalog => _db.collection('catalog');
  CollectionReference get _orders => _db.collection('orders');
  CollectionReference get _transactions => _db.collection('transactions');
  CollectionReference get _expenses => _db.collection('expenses');
  CollectionReference get _refundRequests => _db.collection('refund_requests');
  CollectionReference get _suppliers => _db.collection('suppliers');
  CollectionReference get _lossRecords => _db.collection('loss_records');
  CollectionReference get _customers => _db.collection('customers');
  CollectionReference get _users => _db.collection('users');
  CollectionReference get _bundles => _db.collection('bundles');
  CollectionReference get _restockInquiries =>
      _db.collection('restock_inquiries');
  CollectionReference get _deliveryLogs => _db.collection('delivery_logs');
  CollectionReference get _rfqs => _db.collection('rfqs');
  CollectionReference get _purchaseOrders => _db.collection('purchase_orders');
  CollectionReference get _receivingRecords =>
      _db.collection('receiving_records');
  CollectionReference get _inventoryBatches =>
      _db.collection('inventory_batches');
  DocumentReference get _settings =>
      _db.collection('settings').doc('store_settings');

  // ── Store Settings ─────────────────────────────────────────────────────────

  Stream<StoreSettings> settingsStream() =>
      _settings.snapshots().map(StoreSettings.fromFirestore);

  Future<void> updateStoreStatus(bool isClosed,
          {String? message, DateTime? closeAt, DateTime? openAt}) =>
      _settings.set({
        'isClosed': isClosed,
        'closureMessage': message,
        'scheduledCloseAt':
            closeAt != null ? Timestamp.fromDate(closeAt) : null,
        'scheduledOpenAt': openAt != null ? Timestamp.fromDate(openAt) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> saveStoreSettings(StoreSettings s) =>
      _settings.set(s.toFirestore(), SetOptions(merge: true));

  // ── Products ───────────────────────────────────────────────────────────────

  Stream<List<Product>> productsStream() =>
      _products.orderBy('name').snapshots().map((s) {
        final List<Product> list = [];
        for (final doc in s.docs) {
          try {
            list.add(Product.fromFirestore(doc));
          } catch (e) {
            debugPrint('Error parsing Product ${doc.id}: $e');
          }
        }
        return list;
      });

  /// Real-time stream of all `products/{productId}/batches` documents grouped by productId.
  Stream<Map<String, List<ProductBatch>>> allBatchesGroupStream() =>
      _batchService.allBatchesGroupStream();

  /// Use this for public/customer views to ensure internal draft products are hidden
  Stream<List<Product>> publishedProductsStream() => _products
          .where('status', isEqualTo: 'published')
          .orderBy('name')
          .snapshots()
          .map((s) {
        final List<Product> list = [];
        for (final doc in s.docs) {
          try {
            list.add(Product.fromFirestore(doc));
          } catch (e) {
            debugPrint('Error parsing published Product ${doc.id}: $e');
          }
        }
        return list;
      });

  Future<List<Product>> getProductsOnce() async {
    final snap = await _products.get();
    final List<Product> list = [];
    for (final doc in snap.docs) {
      try {
        list.add(Product.fromFirestore(doc));
      } catch (e) {
        debugPrint('Error parsing Product ${doc.id}: $e');
      }
    }
    return list;
  }

  Future<void> addProduct(Product p) async {
    final docRef = await _products.add(p.toFirestore());
    try {
      await AuditLogService().logAction(
        module: 'Inventory',
        action: 'CREATE',
        targetId: docRef.id,
        targetName: p.name,
        summary: 'Inventory record created for [${p.name}] (ID: ${docRef.id}).',
        afterData: p.toFirestore(),
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<void> updateProduct(
    Product p, {
    bool allowDirectStockOverride = false,
  }) async {
    final Map<String, dynamic> payload = p.toFirestore();
    // Single Source of Truth protection: for non-variant products, `stock` and
    // `batches` are owned exclusively by atomic `InventoryBatchService`
    // transactions so profile edits never clobber live FIFO batch counts.
    if (!p.hasVariants && !allowDirectStockOverride) {
      payload.remove('stock');
      payload.remove('batches');
      payload.remove('physicalReserve');
    }
    // Never overwrite live reservedStock during product profile edits
    payload.remove('reservedStock');
    await _products.doc(p.id).update(payload);
    try {
      await AuditLogService().logAction(
        module: 'Inventory',
        action: 'UPDATE',
        targetId: p.id,
        targetName: p.name,
        summary: 'Inventory record updated for [${p.name}] (ID: ${p.id}).',
        afterData: payload,
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<void> deleteProduct(String productId) async {
    await _products.doc(productId).delete();
    try {
      await AuditLogService().logAction(
        module: 'Inventory',
        action: 'DELETE',
        targetId: productId,
        targetName: 'Product $productId',
        summary: 'Inventory record deleted for product (ID: $productId).',
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<void> updateStock(String productId, int newStock) async {
    await _batchService.adjustStockManualAtomic(
      productId: productId,
      targetStock: newStock,
    );
  }

  Future<void> decrementStockBatch(List<CartItem> items) async {
    await _batchService.deductStockFIFO(items: items);
  }

  /// Deduct main stock via atomic FIFO transaction and release reservedStock safely.
  Future<void> fulfillOrderStockBatch(List<CartItem> items) async {
    await _batchService.deductStockFIFO(
      items: items,
      preOrderItemsForReservationRelease: items,
    );
  }

  /// Atomically release reservedStock inside `runTransaction` (clamped >= 0, idempotent).
  Future<void> clearReservedStockBatch(
    List<CartItem> items, {
    String? orderDocId,
    PreOrder? updatedOrder,
  }) async {
    await _batchService.releaseReservedStockAtomic(
      items: items,
      orderDocId: orderDocId,
      updatedOrder: updatedOrder,
    );
  }

  // ── Catalog ────────────────────────────────────────────────────────────────

  Stream<List<CatalogProduct>> catalogStream() =>
      _catalog.orderBy('name').snapshots().map((s) {
        final List<CatalogProduct> list = [];
        for (final doc in s.docs) {
          try {
            list.add(CatalogProduct.fromFirestore(doc));
          } catch (e) {
            debugPrint('Error parsing CatalogProduct ${doc.id}: $e');
          }
        }
        return list;
      });

  Future<void> addCatalogProduct(CatalogProduct p) =>
      _catalog.add(p.toFirestore());

  Future<void> updateCatalogProduct(CatalogProduct p) =>
      _catalog.doc(p.id).update(p.toFirestore());

  Future<void> deleteCatalogProduct(String id) => _catalog.doc(id).delete();

  Future<void> linkBarcodeToCatalog(String catalogId, String barcode) =>
      _catalog.doc(catalogId).update({'barcode': barcode});

  /// Batch-updates velocity scores and dynamic pricing fields across multiple products safely.
  /// Chunks writes into batches of 400 to respect Firestore's 500-operation WriteBatch limit.
  Future<void> batchUpdateProductPricing(
      List<Map<String, dynamic>> updates) async {
    if (updates.isEmpty) return;
    const int chunkSize = 400;
    for (int i = 0; i < updates.length; i += chunkSize) {
      final chunk = updates.sublist(
        i,
        (i + chunkSize) > updates.length ? updates.length : (i + chunkSize),
      );
      final batch = _db.batch();
      for (final entry in chunk) {
        final String productId = entry['id'] as String;
        final Map<String, dynamic> fields =
            Map<String, dynamic>.from(entry['data'] as Map);
        fields['updatedAt'] = FieldValue.serverTimestamp();
        batch.update(_products.doc(productId), fields);
      }
      await batch.commit();
    }
  }

  // ── Admin In-App Notifications (`admin_notifications`) ─────────────────────

  CollectionReference<Map<String, dynamic>> get _adminNotifications =>
      _db.collection('admin_notifications');

  Stream<List<Map<String, dynamic>>> adminNotificationsStream(
      {int limit = 50}) {
    return _adminNotifications
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Future<void> addAdminNotification(Map<String, dynamic> payload) async {
    final data = Map<String, dynamic>.from(payload);
    data.putIfAbsent('isRead', () => false);
    data.putIfAbsent('createdAt', () => FieldValue.serverTimestamp());
    await _adminNotifications.add(data);
  }

  Future<void> markAdminNotificationRead(String notificationId) async {
    await _adminNotifications.doc(notificationId).update({'isRead': true});
  }

  Future<void> markAllAdminNotificationsRead() async {
    final unread =
        await _adminNotifications.where('isRead', isEqualTo: false).get();
    if (unread.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // ── Daily End-of-Day Resupply Logs (`daily_resupply_logs/{YYYY-MM-DD}`) ────

  CollectionReference<Map<String, dynamic>> get _dailyResupplyLogs =>
      _db.collection('daily_resupply_logs');

  Stream<DailyResupplyLog> dailyResupplyLogStream(
    String dateKey, {
    String defaultStoreEmail = 'gdcstore.ph@gmail.com',
  }) {
    return _dailyResupplyLogs.doc(dateKey).snapshots().map((doc) {
      if (!doc.exists) {
        return DailyResupplyLog.empty(dateKey, storeEmail: defaultStoreEmail);
      }
      return DailyResupplyLog.fromFirestore(doc);
    });
  }

  Future<DailyResupplyLog?> getDailyResupplyLog(String dateKey) async {
    final doc = await _dailyResupplyLogs.doc(dateKey).get();
    if (!doc.exists) return null;
    return DailyResupplyLog.fromFirestore(doc);
  }

  /// Atomically records/updates a product (or variant) that hit its physical
  /// low-stock threshold on [dateKey].
  ///
  /// Returns `true` if this item was newly added to [dateKey]'s resupply log
  /// (so callers know to emit a one-time Inventory Alert for today's breach).
  Future<bool> recordDailyResupplyItem({
    required String dateKey,
    required DailyResupplyItem item,
    required String storeEmail,
  }) async {
    final docRef = _dailyResupplyLogs.doc(dateKey);
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(docRef);
      final existingData = snap.exists
          ? Map<String, dynamic>.from(snap.data() ?? {})
          : <String, dynamic>{};

      final Map<String, dynamic> itemsMap = existingData['items'] is Map
          ? Map<String, dynamic>.from(existingData['items'] as Map)
          : <String, dynamic>{};

      final bool isNew = !itemsMap.containsKey(item.itemKey);
      final existingItemRaw = itemsMap[item.itemKey];
      final DateTime preservedFirstTriggered = existingItemRaw is Map &&
              existingItemRaw['firstTriggeredAt'] is Timestamp
          ? (existingItemRaw['firstTriggeredAt'] as Timestamp).toDate()
          : item.firstTriggeredAt;

      final mergedItem = DailyResupplyItem(
        itemKey: item.itemKey,
        productId: item.productId,
        variantId: item.variantId,
        productName: item.productName,
        variantName: item.variantName,
        category: item.category,
        unit: item.unit,
        originalStock: item.effectiveOriginalStock,
        lowStockThreshold: item.lowStockThreshold,
        physicalStock: item.physicalStock,
        onlineStock: item.onlineStock,
        totalStock: item.totalStock,
        availableStock: item.availableStock,
        suggestedResupplyQty: item.suggestedResupplyQty,
        onlineOutOfStock: item.onlineOutOfStock,
        firstTriggeredAt: preservedFirstTriggered,
        lastUpdatedAt: item.lastUpdatedAt,
      );

      itemsMap[item.itemKey] = mergedItem.toMap();

      tx.set(docRef, {
        'dateKey': dateKey,
        'storeEmail': storeEmail.trim().isNotEmpty
            ? storeEmail.trim()
            : 'gdcstore.ph@gmail.com',
        'items': itemsMap,
        'itemCount': itemsMap.length,
        'summaryEmailSent': existingData['summaryEmailSent'] == true,
        if (existingData['summaryEmailStatus'] != null)
          'summaryEmailStatus': existingData['summaryEmailStatus'],
        if (existingData['summaryEmailSentAt'] != null)
          'summaryEmailSentAt': existingData['summaryEmailSentAt'],
        if (existingData['summaryEmailSentBy'] != null)
          'summaryEmailSentBy': existingData['summaryEmailSentBy'],
        if (existingData['summaryEmailError'] != null)
          'summaryEmailError': existingData['summaryEmailError'],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return isNew;
    });
  }

  /// Atomically claims the End-of-Day Resupply Summary email dispatch lock for
  /// [dateKey] so Admin App & Cloud Scheduler never send duplicate emails.
  ///
  /// Returns the claimed [DailyResupplyLog] snapshot if dispatch should proceed,
  /// or `null` if already sent/in-progress or empty.
  Future<DailyResupplyLog?> claimDailyResupplyEmailDispatch({
    required String dateKey,
    required String triggeredBy,
    bool forceResend = false,
  }) async {
    final docRef = _dailyResupplyLogs.doc(dateKey);
    return _db.runTransaction<DailyResupplyLog?>((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return null;
      final log = DailyResupplyLog.fromFirestore(snap);
      if (log.itemCount == 0) return null;

      if (!forceResend &&
          (log.summaryEmailSent || log.summaryEmailStatus == 'sending')) {
        return null;
      }

      tx.update(docRef, {
        'summaryEmailStatus': 'sending',
        'summaryEmailSentBy': triggeredBy,
        'summaryEmailError': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return log;
    });
  }

  Future<void> markDailyResupplyEmailResult({
    required String dateKey,
    required bool success,
    required String sentBy,
    String? error,
  }) async {
    final docRef = _dailyResupplyLogs.doc(dateKey);
    await docRef.update({
      'summaryEmailSent': success,
      'summaryEmailStatus': success ? 'sent' : 'failed',
      if (success) 'summaryEmailSentAt': FieldValue.serverTimestamp(),
      'summaryEmailSentBy': sentBy,
      'summaryEmailError': success ? null : error,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Atomic FIFO checkout pipeline (routed through [InventoryBatchService.deductStockFIFO]
  /// so subcollection batches and parent `products/{id}.stock` never diverge).
  Future<void> recordSaleOfflineFirst({
    required StoreTransaction tx,
    required List<Product> cachedProducts,
    StoreSettings? settings,
  }) async {
    await _batchService.deductStockFIFO(
      items: tx.items,
      transactionToWrite: tx,
      settings: settings,
    );
  }

  Future<RefundRestorationResult> refundTransaction(StoreTransaction tx) async {
    try {
      final refundLines = tx.items
          .where((item) => (item.qty - item.returnedQty) > 0)
          .map((item) => RefundLineInput(
                productId: item.productId,
                variantId: item.variantId,
                productName: item.name,
                barcode: item.barcode,
                qty: item.qty - item.returnedQty,
                price: item.unitPriceAtSale,
                condition: 'SELLABLE',
              ))
          .toList();

      if (refundLines.isEmpty) {
        await _transactions.doc(tx.id).update({'isRefunded': true});
        return const RefundRestorationResult(
          restoredAllocations: [],
          writtenOffAllocations: [],
        );
      }

      return await _batchService.restoreBatchOnRefund(
        transactionId: tx.id,
        orderId: tx.orderId,
        itemsToRefund: refundLines,
        totalRefundAmount: tx.total,
        processedBy: 'Admin',
        customerEmail: tx.customerEmail,
      );
    } catch (e) {
      throw Exception('Failed to process refund: $e');
    }
  }

  /// Processes a single line item return or 1-to-1 swap atomically via FIFO batch backtracking.
  Future<RefundRestorationResult> processItemReturn({
    required String transactionId,
    String? orderId,
    required String productId,
    String? variantId,
    required String barcode,
    required int returnQty,
    required bool isCashRefund,
    bool isDamagedSwap = false,
    String? condition,
    String? preferredBatchId,
    String? productName,
    double unitPrice = 0.0,
    String processedBy = 'Admin',
    StoreSettings? settings,
  }) async {
    try {
      final String effectiveCondition = condition ??
          (isDamagedSwap
              ? 'DAMAGED'
              : (isCashRefund ? 'SELLABLE' : 'SELLABLE'));

      final result = await _batchService.restoreBatchOnRefund(
        transactionId: transactionId,
        orderId: orderId,
        itemsToRefund: [
          RefundLineInput(
            productId: productId,
            variantId: variantId,
            productName: productName ?? productId,
            barcode: barcode,
            qty: returnQty,
            price: unitPrice,
            condition: effectiveCondition,
            preferredBatchId: preferredBatchId,
          ),
        ],
        totalRefundAmount: isCashRefund ? (unitPrice * returnQty) : 0.0,
        processedBy: processedBy,
        isSwap: !isCashRefund,
        isDamagedSwap: isDamagedSwap,
        settings: settings,
      );

      // For a 1-to-1 Damaged Swap on a non-variant product, deduct the fresh replacement
      // unit using FIFO so the oldest active batch is decremented cleanly.
      if (!isCashRefund &&
          isDamagedSwap &&
          (variantId == null || variantId.isEmpty)) {
        await _batchService.deductStockFIFO(
          items: [
            CartItem(
              productId: productId,
              name: productName ?? productId,
              price: unitPrice,
              qty: returnQty,
              barcode: barcode,
            ),
          ],
          settings: settings,
          performedByName: processedBy,
        );
      }

      return result;
    } catch (e) {
      debugPrint('Error processing item return: $e');
      rethrow;
    }
  }

  /// Processes a multi-item refund for a transaction via FIFO batch backtracking.
  Future<RefundRestorationResult> processMultiItemRefund({
    required String transactionId,
    required List<Map<String, dynamic>> itemsToRefund,
    required double totalRefundAmount,
    required String processedBy,
    String? customerEmail,
    String? orderId,
    StoreSettings? settings,
  }) async {
    if (itemsToRefund.isEmpty) {
      return const RefundRestorationResult(
        restoredAllocations: [],
        writtenOffAllocations: [],
      );
    }

    final lines = itemsToRefund
        .map((r) => RefundLineInput(
              productId: r['productId']?.toString() ?? '',
              variantId: r['variantId']?.toString(),
              productName: r['name']?.toString() ?? '',
              barcode: r['barcode']?.toString() ?? '',
              qty: (r['qty'] as num? ?? 0).toInt(),
              price: (r['price'] as num? ?? 0.0).toDouble(),
              condition: r['condition']?.toString() ?? 'SELLABLE',
              preferredBatchId: r['preferredBatchId']?.toString(),
            ))
        .where((l) => l.productId.isNotEmpty && l.qty > 0)
        .toList();

    return await _batchService.restoreBatchOnRefund(
      transactionId: transactionId,
      orderId: orderId,
      itemsToRefund: lines,
      totalRefundAmount: totalRefundAmount,
      processedBy: processedBy,
      customerEmail: customerEmail,
      settings: settings,
    );
  }

  /// Streams list of recorded item refunds from Firestore for Inventory Records
  Stream<List<Map<String, dynamic>>> refundRecordsStream() {
    return _db
        .collection('refund_records')
        .orderBy('refundedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              return {
                'id': d.id,
                'transactionId': data['transactionId'] ?? '',
                'orderId': data['orderId'],
                'customerEmail': data['customerEmail'] ?? '',
                'refundedAt': (data['refundedAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
                'items': (data['items'] as List? ?? [])
                    .map((e) => Map<String, dynamic>.from(e is Map ? e : {}))
                    .toList(),
                'totalAmount': (data['totalAmount'] as num? ?? 0.0).toDouble(),
                'processedBy': data['processedBy'] ?? 'Admin',
              };
            }).toList());
  }

  // ── Suppliers ──────────────────────────────────────────────────────────────

  Stream<List<Supplier>> suppliersStream() => _suppliers
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map(Supplier.fromFirestore).toList());

  /// Fetches the latest authoritative [Supplier] document directly from Firestore.
  Future<Supplier?> fetchSupplierById(String supplierId) async {
    final trimmed = supplierId.trim();
    if (trimmed.isEmpty) return null;
    final doc = await _suppliers.doc(trimmed).get();
    if (!doc.exists) return null;
    return Supplier.fromFirestore(doc);
  }

  Future<void> addSupplier(Supplier s) async {
    final docRef = await _suppliers.add(s.toFirestore());
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'CREATE',
        targetId: docRef.id,
        targetName: s.name,
        summary: 'Supplier record created for [${s.name}] (ID: ${docRef.id}).',
        afterData: s.toFirestore(),
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<void> updateSupplier(Supplier s) async {
    await _suppliers.doc(s.id).update(s.toFirestore());
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'UPDATE',
        targetId: s.id,
        targetName: s.name,
        summary: 'Supplier record updated for [${s.name}] (ID: ${s.id}).',
        afterData: s.toFirestore(),
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<void> deleteSupplier(String id) async {
    await _suppliers.doc(id).delete();
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'DELETE',
        targetId: id,
        targetName: 'Supplier $id',
        summary: 'Supplier record deleted for ID: [$id].',
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  // ── Loss & Waste ───────────────────────────────────────────────────────────

  Stream<List<LossRecord>> lossRecordsStream() =>
      _lossRecords.orderBy('createdAt', descending: true).snapshots().map((s) {
        final List<LossRecord> list = [];
        for (final doc in s.docs) {
          try {
            list.add(LossRecord.fromFirestore(doc));
          } catch (e) {
            debugPrint('Error parsing LossRecord ${doc.id}: $e');
          }
        }
        return list;
      });

  Future<void> recordLoss(LossRecord record) async {
    await _batchService.recordLossFIFO(
      productId: record.productId,
      productName: record.productName,
      qtyLost: record.qty,
      unitPrice: record.unitPrice,
      lossType: record.type.name,
      notes: record.notes,
    );
  }

  // ── Orders ─────────────────────────────────────────────────────────────────

  Stream<List<PreOrder>> ordersStream() => _orders.snapshots().map((s) {
        final List<PreOrder> list = [];
        for (final doc in s.docs) {
          try {
            list.add(PreOrder.fromFirestore(doc));
          } catch (e) {
            debugPrint('Error parsing PreOrder ${doc.id}: $e');
          }
        }
        return list;
      });

  Stream<List<PreOrder>> ordersStreamForEmail(String email) => _orders
      .where('customerEmail', isEqualTo: email)
      .snapshots()
      .map((s) => s.docs.map(PreOrder.fromFirestore).toList());

  Future<DocumentReference> addOrder(PreOrder order) =>
      _orders.add(order.toFirestore());

  Future<void> updateOrder(PreOrder order) async {
    await _orders.doc(order.id).update(order.toFirestore());
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status,
      {String? reason}) async {
    await _orders.doc(orderId).update({
      'status': status.name,
      if (reason != null) 'rejectionReason': reason,
    });
    try {
      await AuditLogService().logAction(
        module: 'Pre-Orders',
        action: 'STATUS_CHANGE',
        targetId: orderId,
        targetName: 'Order #${orderId.substring(0, 5)}',
        summary:
            'Order status transitioned to [${status.name}]${reason != null ? ' Reason: [$reason].' : '.'}',
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<void> bulkUpdateOrders(List<PreOrder> orders) async {
    if (orders.isEmpty) return;
    final batch = _db.batch();
    for (final order in orders) {
      batch.update(_orders.doc(order.id), order.toFirestore());
    }
    await batch.commit();
  }

  // ── Transactions ───────────────────────────────────────────────────────────

  Stream<List<StoreTransaction>> transactionsStream() =>
      _transactions.snapshots().map((s) {
        final List<StoreTransaction> list = [];
        for (final doc in s.docs) {
          try {
            list.add(StoreTransaction.fromFirestore(doc));
          } catch (e) {
            debugPrint('Error parsing StoreTransaction ${doc.id}: $e');
          }
        }
        return list;
      });

  Future<void> addTransaction(StoreTransaction tx) =>
      _transactions.add(tx.toFirestore());

  // ── Expenses ───────────────────────────────────────────────────────────────

  Stream<List<Expense>> expensesStream() => _expenses.snapshots().map((s) {
        final List<Expense> list = [];
        for (final doc in s.docs) {
          try {
            list.add(Expense.fromFirestore(doc));
          } catch (e) {
            debugPrint('Error parsing Expense ${doc.id}: $e');
          }
        }
        return list;
      });

  Future<void> addExpense(Expense e) => _expenses.add(e.toFirestore());

  // ── Customers & Appeals ───────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> appealsStream() =>
      _db.collection('appeals').snapshots().map((s) => s.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList());

  Stream<List<Customer>> customersStream() {
    return _customers.orderBy('name').snapshots().asyncMap((snap) async {
      final List<Customer> list = snap.docs
          .map((d) => Customer.fromMap(d.id, d.data() as Map<String, dynamic>))
          .toList();

      // Merge customer user records from 'users' collection who have offenses or pending appeals
      try {
        final usersSnap =
            await _users.where('isCustomer', isEqualTo: true).get();
        for (final uDoc in usersSnap.docs) {
          final uData = uDoc.data() as Map<String, dynamic>? ?? {};
          final uId = uDoc.id;
          final email = uData['email'] as String?;

          final existingIdx = list.indexWhere((c) =>
              c.id == uId ||
              (email != null &&
                  email.isNotEmpty &&
                  c.email?.toLowerCase() == email.toLowerCase()));

          if (existingIdx == -1) {
            if ((uData['offenseCount'] as num? ?? 0) > 0 ||
                uData['isPermanentlyLocked'] == true ||
                (uData['appealStatus'] != null &&
                    uData['appealStatus'] != 'none')) {
              list.add(Customer.fromMap(uId, uData));
            }
          } else {
            final existing = list[existingIdx];
            if (uData['appealStatus'] != null &&
                uData['appealStatus'] != 'none') {
              list[existingIdx] = existing.copyWith(
                appealStatus: uData['appealStatus']?.toString(),
                appealMessage: uData['appealMessage']?.toString(),
                appealSubmittedAt:
                    (uData['appealSubmittedAt'] as Timestamp?)?.toDate(),
                isPermanentlyLocked: uData['isPermanentlyLocked'] ??
                    existing.isPermanentlyLocked,
                offenseCount:
                    (uData['offenseCount'] as num? ?? existing.offenseCount)
                        .toInt(),
              );
            }
          }
        }
      } catch (e) {
        debugPrint(
            'Error merging user customer records into customersStream: $e');
      }

      return list;
    });
  }

  Future<void> addCustomer(Customer c) => _customers.add(c.toMap());

  Future<void> updateCustomer(Customer c) =>
      _customers.doc(c.id).update(c.toMap());

  Future<void> deleteCustomer(String id) => _customers.doc(id).delete();

  Future<Customer?> getCustomerByEmail(String email) async {
    final snap =
        await _customers.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Customer.fromMap(
        snap.docs.first.id, snap.docs.first.data() as Map<String, dynamic>);
  }

  /// Records a ghosting/uncollected order offense for a customer and applies restriction penalty.
  /// 1st Offense: 2-hour order restriction
  /// 2nd Offense: 24-hour order restriction
  /// 3rd Offense: 72-hour (3-day) order restriction
  /// 4th Offense: Permanent Account Lock (Can submit appeal)
  Future<Customer?> recordCustomerOffense({
    required String email,
    required String customerName,
    required String orderId,
    required String reason,
    bool isManualAdminFlag = false,
  }) async {
    if (email.isEmpty) return null;

    Customer? customer = await getCustomerByEmail(email);

    final now = TimeService.now;
    final int newOffenseCount = ((customer?.offenseCount ?? 0) + 1);
    final int hours = Customer.getRestrictionHoursForOffense(newOffenseCount);

    final bool isPermanent = newOffenseCount >= 4;
    final DateTime? newRestrictedUntil =
        isPermanent ? null : now.add(Duration(hours: hours));

    final newOffenseRecord = {
      'offenseNumber': newOffenseCount,
      'timestamp': Timestamp.fromDate(now),
      'orderId': orderId,
      'reason': reason,
      'restrictionHours': hours,
      'isPermanentLock': isPermanent,
      'flaggedType':
          isManualAdminFlag ? 'Manual Admin Flag' : 'Auto Cancellation',
    };

    final updatedHistory =
        List<Map<String, dynamic>>.from(customer?.offenseHistory ?? [])
          ..add(newOffenseRecord);

    if (customer != null) {
      final updatedCustomer = customer.copyWith(
        offenseCount: newOffenseCount,
        restrictedUntil: newRestrictedUntil,
        isPermanentlyLocked: isPermanent,
        offenseHistory: updatedHistory,
      );
      await updateCustomer(updatedCustomer);

      final userQuery = await _users.where('email', isEqualTo: email).get();
      for (final uDoc in userQuery.docs) {
        await uDoc.reference.update({
          'offenseCount': newOffenseCount,
          'restrictedUntil': newRestrictedUntil != null
              ? Timestamp.fromDate(newRestrictedUntil)
              : null,
          'isPermanentlyLocked': isPermanent,
          'offenseHistory': updatedHistory,
        });
      }

      final String penaltyText = isPermanent
          ? 'Your account has been permanently locked due to multiple uncollected orders (4th offense). You may submit an appeal via the app.'
          : 'Ordering has been temporarily restricted for $hours hours due to an uncollected order (Offense #$newOffenseCount).';

      await AdminMessagingService().sendNotification(
        recipientEmail: email,
        title: isPermanent
            ? 'Account Permanently Locked (4th Offense)'
            : 'Order Restriction Notice (Offense #$newOffenseCount)',
        body: penaltyText,
      );

      return updatedCustomer;
    } else {
      final newCustomer = Customer(
        id: '',
        name: customerName,
        email: email,
        phone: '',
        createdAt: now,
        offenseCount: newOffenseCount,
        restrictedUntil: newRestrictedUntil,
        isPermanentlyLocked: isPermanent,
        offenseHistory: updatedHistory,
      );
      final ref = await _customers.add(newCustomer.toMap());

      final userQuery = await _users.where('email', isEqualTo: email).get();
      for (final uDoc in userQuery.docs) {
        await uDoc.reference.update({
          'offenseCount': newOffenseCount,
          'restrictedUntil': newRestrictedUntil != null
              ? Timestamp.fromDate(newRestrictedUntil)
              : null,
          'isPermanentlyLocked': isPermanent,
          'offenseHistory': updatedHistory,
        });
      }

      return newCustomer.copyWith(id: ref.id);
    }
  }

  /// Lifts/removes ordering restriction for a customer with optional resolution notes and optional offense reset.
  Future<void> liftCustomerRestriction({
    required String customerId,
    String? reason,
    bool resetOffenses = false,
  }) async {
    final now = TimeService.now;
    String? email;
    String name = 'Customer';
    int currentOffenses = 0;
    List<Map<String, dynamic>> history = [];

    final docRef = _customers.doc(customerId);
    final snap = await docRef.get();

    if (snap.exists) {
      final data = snap.data() as Map<String, dynamic>? ?? {};
      email = data['email'] as String?;
      name = data['name'] as String? ?? 'Customer';
      currentOffenses = (data['offenseCount'] as num? ?? 0).toInt();
      history = List<Map<String, dynamic>>.from(
          data['offenseHistory'] as List? ?? []);
    }

    final userDocRef = _users.doc(customerId);
    final userSnap = await userDocRef.get();

    if (userSnap.exists) {
      final uData = userSnap.data() as Map<String, dynamic>? ?? {};
      email ??= uData['email'] as String?;
      name = uData['name'] as String? ?? name;
      if (currentOffenses == 0) {
        currentOffenses = (uData['offenseCount'] as num? ?? 0).toInt();
      }
      if (history.isEmpty) {
        history = List<Map<String, dynamic>>.from(
            uData['offenseHistory'] as List? ?? []);
      }
    }

    final int updatedOffenseCount = resetOffenses ? 0 : currentOffenses;

    final removalLog = {
      'offenseNumber': currentOffenses,
      'timestamp': Timestamp.fromDate(now),
      'orderId': 'LIFT_RESTRICTION',
      'reason': reason != null && reason.isNotEmpty
          ? reason
          : 'Restriction lifted by store management / complaint resolution',
      'restrictionHours': 0,
      'isPermanentLock': false,
      'flaggedType': 'Restriction Lifted',
    };
    history.add(removalLog);

    final Map<String, dynamic> updateMap = {
      'restrictedUntil': null,
      'isPermanentlyLocked': false,
      'offenseCount': updatedOffenseCount,
      'appealStatus': 'approved',
      'appealReviewedAt': Timestamp.fromDate(now),
      'offenseHistory': history,
    };

    if (snap.exists) {
      await docRef.update(updateMap);
    }

    if (userSnap.exists) {
      await userDocRef.update(updateMap);
    } else if (email != null && email.isNotEmpty) {
      final userQuery = await _users.where('email', isEqualTo: email).get();
      for (final uDoc in userQuery.docs) {
        await uDoc.reference.update(updateMap);
      }
    }

    // Update appeals collection documents if matching userId or customerId
    try {
      final appealsQuery = await _db
          .collection('appeals')
          .where('userId', isEqualTo: customerId)
          .get();
      for (final aDoc in appealsQuery.docs) {
        await aDoc.reference.update({
          'status': 'approved',
          'appealStatus': 'approved',
          'reviewedAt': Timestamp.fromDate(now),
          'resolutionNotes': reason,
        });
      }
      if (email != null && email.isNotEmpty) {
        final appealsEmailQuery = await _db
            .collection('appeals')
            .where('customerEmail', isEqualTo: email)
            .get();
        for (final aDoc in appealsEmailQuery.docs) {
          await aDoc.reference.update({
            'status': 'approved',
            'appealStatus': 'approved',
            'reviewedAt': Timestamp.fromDate(now),
            'resolutionNotes': reason,
          });
        }
      }
    } catch (_) {}

    if (email != null && email.isNotEmpty) {
      final noteText =
          reason != null && reason.isNotEmpty ? '\n\nNote: $reason' : '';
      await AdminMessagingService().sendNotification(
        recipientEmail: email,
        title: 'GDC Store - Ordering Restriction Lifted',
        body:
            'Hello $name,\n\nYour account ordering restriction has been removed by GDC Sari-Sari Store Management following complaint review.$noteText\n\nYou may now resume placing pre-orders.',
      );
    }
  }

  /// Approves a customer's account unlock appeal, unlocking account and emailing confirmation.
  Future<void> approveCustomerAppeal(String customerId,
      {String? adminNotes, bool resetOffenses = false}) async {
    await liftCustomerRestriction(
      customerId: customerId,
      reason: adminNotes ?? 'Customer appeal approved by management',
      resetOffenses: resetOffenses,
    );
  }

  /// Rejects a customer's account unlock appeal and emails decision.
  Future<void> rejectCustomerAppeal(String customerId,
      {String? adminNotes}) async {
    final docRef = _customers.doc(customerId);
    final snap = await docRef.get();
    String? email;
    String name = 'Customer';

    if (snap.exists) {
      final data = snap.data() as Map<String, dynamic>? ?? {};
      email = data['email'] as String?;
      name = data['name'] as String? ?? 'Customer';

      await docRef.update({
        'appealStatus': 'rejected',
        'appealReviewedAt': Timestamp.fromDate(TimeService.now),
      });
    }

    final userDocRef = _users.doc(customerId);
    final userSnap = await userDocRef.get();
    if (userSnap.exists) {
      final uData = userSnap.data() as Map<String, dynamic>? ?? {};
      email ??= uData['email'] as String?;
      name = uData['name'] as String? ?? name;

      await userDocRef.update({
        'appealStatus': 'rejected',
        'appealReviewedAt': Timestamp.fromDate(TimeService.now),
      });
    } else if (email != null && email.isNotEmpty) {
      final userQuery = await _users.where('email', isEqualTo: email).get();
      for (final uDoc in userQuery.docs) {
        await uDoc.reference.update({
          'appealStatus': 'rejected',
          'appealReviewedAt': Timestamp.fromDate(TimeService.now),
        });
      }
    }

    try {
      final appealsQuery = await _db
          .collection('appeals')
          .where('userId', isEqualTo: customerId)
          .get();
      for (final aDoc in appealsQuery.docs) {
        await aDoc.reference.update({
          'status': 'rejected',
          'appealStatus': 'rejected',
          'reviewedAt': Timestamp.fromDate(TimeService.now),
        });
      }
    } catch (_) {}

    if (email != null && email.isNotEmpty) {
      await AdminMessagingService().sendNotification(
        recipientEmail: email,
        title: 'GDC Store - Account Unlock Appeal REJECTED',
        body:
            'Hello $name,\n\nYour account unlock appeal was reviewed and REJECTED by GDC Sari-Sari Store Management. Your account remains restricted due to uncollected order policy violations.',
      );
    }
  }

  /// Resets a customer's offense record and restrictions back to clean state.
  Future<void> resetCustomerOffenses(String customerId) async {
    final docRef = _customers.doc(customerId);
    final snap = await docRef.get();
    if (!snap.exists) return;

    final data = snap.data() as Map<String, dynamic>? ?? {};
    final email = data['email'] as String?;

    await docRef.update({
      'offenseCount': 0,
      'restrictedUntil': null,
      'isPermanentlyLocked': false,
      'appealStatus': 'none',
    });

    if (email != null && email.isNotEmpty) {
      final userQuery = await _users.where('email', isEqualTo: email).get();
      for (final uDoc in userQuery.docs) {
        await uDoc.reference.update({
          'offenseCount': 0,
          'restrictedUntil': null,
          'isPermanentlyLocked': false,
          'appealStatus': 'none',
        });
      }
    }
  }

  // ── Refund Requests ────────────────────────────────────────────────────────

  Stream<List<RefundRequest>> refundRequestsStream() =>
      _refundRequests.snapshots().map((s) {
        final List<RefundRequest> list = [];
        for (final doc in s.docs) {
          try {
            list.add(RefundRequest.fromFirestore(doc));
          } catch (e) {
            debugPrint('Error parsing RefundRequest ${doc.id}: $e');
          }
        }
        return list;
      });

  Future<void> updateRefundStatus(
          String requestId, RefundStatus status, String adminEmail,
          {String? reason, String? notes}) =>
      _refundRequests.doc(requestId).update({
        'status': status.name,
        'processedByEmail': adminEmail,
        if (reason != null) 'rejectionReason': reason,
        if (notes != null) 'adminNotes': notes,
      });

  Future<RefundRestorationResult> processApprovedRefund(
      RefundRequest request, String adminEmail,
      {StoreSettings? settings}) async {
    try {
      final String cond = request.condition == RefundCondition.restockable
          ? 'SELLABLE'
          : (request.condition == RefundCondition.expired
              ? 'expired'
              : 'DAMAGED');

      final lines = request.items
          .map((item) => RefundLineInput(
                productId: item.productId,
                variantId: item.variantId,
                productName: item.name,
                barcode: item.barcode,
                qty: item.qty,
                price: item.unitPriceAtSale,
                condition: cond,
              ))
          .toList();

      return await _batchService.restoreBatchOnRefund(
        transactionId: request.transactionId,
        orderId: request.transactionId,
        itemsToRefund: lines,
        totalRefundAmount: request.total,
        processedBy: adminEmail,
        customerEmail: request.customerEmail,
        refundRequestId: request.id,
        refundRequestCondition: request.condition,
        adminNotes: request.adminNotes,
        settings: settings,
      );
    } catch (e) {
      throw Exception('Failed to process approved refund: $e');
    }
  }

  // ── Delivery & Stock Arrivals ──────────────────────────────────────────────

  Future<void> logStockArrival({
    required String productId,
    required String productName,
    required int qtyReceived,
    required double unitCost,
    DateTime? expiryDate,
    String? invoiceNumber,
    required String receivedBy,
    String? notes,
  }) async {
    await _db.collection('delivery_logs').add({
      'productId': productId,
      'productName': productName,
      'qtyReceived': qtyReceived,
      'unitCost': unitCost,
      'totalValue': qtyReceived * unitCost,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate) : null,
      'invoiceNumber': invoiceNumber,
      'receivedBy': receivedBy,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> processInquiryDeliveryAtomic({
    required String inquiryId,
    required RestockInquiryStatus newStatus,
    required List<DeliveryItemPayload> items,
    required String receivedBy,
    String? supplierId,
    String? supplierName,
    List<Map<String, dynamic>>? updatedInquiryItems,
    String? invoiceNumber,
    String? notes,
    StoreSettings? settings,
  }) async {
    final String resolvedSupplierId =
        (supplierId != null && supplierId.trim().isNotEmpty)
            ? supplierId.trim()
            : items
                .map((i) => i.supplierId ?? i.product.supplierId ?? '')
                .firstWhere((id) => id.trim().isNotEmpty, orElse: () => '')
                .trim();
    final String? resolvedSupplierName =
        (supplierName != null && supplierName.trim().isNotEmpty)
            ? supplierName.trim()
            : items.map((i) => i.supplierName).firstWhere(
                (n) => n != null && n.trim().isNotEmpty,
                orElse: () => null);

    final batchInputs = items
        .where((item) => item.qtyReceived > 0)
        .map((item) => InquiryDeliveryBatchInput(
              productId: item.product.id,
              productName: item.product.name,
              qtyReceived: item.qtyReceived,
              unitCost: item.unitCost,
              datePurchased: item.newBatch.datePurchased,
              dateArrived: item.newBatch.dateArrived,
              expiryDate: item.newBatch.expiryDate ?? item.product.expiryDate,
              customBatchId: item.newBatch.batchId,
              invoiceNumber: invoiceNumber ?? item.newBatch.invoiceNumber,
              discrepancyNote: item.discrepancyNote,
              orderedQty: item.orderedQty,
              orderedUnitCost: item.orderedUnitCost,
            ))
        .toList();

    await _batchService.receiveRestockInquiryAtomic(
      inquiryId: inquiryId,
      supplierId: resolvedSupplierId,
      supplierName: resolvedSupplierName,
      newStatusName: newStatus.name,
      items: batchInputs,
      receivedBy: receivedBy,
      updatedInquiryItems: updatedInquiryItems,
      invoiceNumber: invoiceNumber,
      notes: notes,
      settings: settings,
    );
  }

  Future<void> processSingleDeliveryAtomic({
    required Product product,
    required ProductBatch newBatch,
    required String receivedBy,
    String? supplierName,
    String? invoiceNumber,
    String? notes,
    StoreSettings? settings,
  }) async {
    await _batchService.receiveBatch(
      productId: product.id,
      productName: product.name,
      receivedQty: newBatch.remainingQty,
      costPrice: newBatch.costPrice,
      datePurchased: newBatch.datePurchased,
      dateArrived: newBatch.dateArrived,
      expiryDate: newBatch.expiryDate ?? product.expiryDate,
      supplierId: newBatch.supplierId ?? product.supplierId,
      supplierName: newBatch.supplierName ?? supplierName,
      poId: newBatch.poId,
      poNumber: newBatch.poNumber,
      invoiceNumber: invoiceNumber ?? newBatch.invoiceNumber,
      customBatchId: newBatch.batchId,
      performedByName: receivedBy,
      notes: notes,
      settings: settings,
      packCost: product.packCost,
      itemsPerCase: product.itemsPerCase,
    );
  }

  Future<void> saveProductWithBatch({
    required Product product,
    required ProductBatch initialBatch,
    String? supplierName,
    String? receivedBy,
    String? notes,
  }) async {
    await _batchService.receiveProductWithInitialBatch(
      product: product,
      initialBatch: initialBatch,
      supplierName: supplierName,
      receivedBy: receivedBy,
      notes: notes,
    );
  }

  // ── Product Watches ────────────────────────────────────────────────────────

  Future<List<String>> getWatchersForProduct(String productId) async {
    final snap = await _db
        .collection('watched_products')
        .where('productId', isEqualTo: productId)
        .get();
    return snap.docs.map((d) => d.data()['email'] as String).toList();
  }

  Future<void> removeWatchesForProduct(String productId) async {
    final snap = await _db
        .collection('watched_products')
        .where('productId', isEqualTo: productId)
        .get();
    final batch = _db.batch();
    for (var doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ── Bundles ────────────────────────────────────────────────────────────────

  Stream<List<ProductBundle>> bundlesStream() => _bundles
      .snapshots()
      .map((s) => s.docs.map(ProductBundle.fromFirestore).toList());

  Future<void> saveBundle(ProductBundle b) {
    if (b.id.isEmpty) return _bundles.add(b.toFirestore());
    return _bundles.doc(b.id).update(b.toFirestore());
  }

  Future<void> deleteBundle(String id) => _bundles.doc(id).delete();

  // ── Restock Inquiries ──────────────────────────────────────────────────────

  Stream<List<RestockInquiry>> restockInquiriesStream() => _restockInquiries
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(RestockInquiry.fromFirestore).toList());

  Future<void> addRestockInquiry(RestockInquiry ri) =>
      _restockInquiries.add(ri.toFirestore());

  Future<void> updateRestockInquiry(RestockInquiry ri) =>
      _restockInquiries.doc(ri.id).update(ri.toFirestore());

  Future<void> deleteRestockInquiry(String id) =>
      _restockInquiries.doc(id).delete();

  Future<void> updateRestockInquiryStatus(
          String id, RestockInquiryStatus status,
          {DateTime? sentAt}) =>
      _restockInquiries.doc(id).update({
        'status': status.name,
        if (sentAt != null) 'sentAt': Timestamp.fromDate(sentAt),
      });

  // ── Delivery Logs Stream ───────────────────────────────────────────────────

  Stream<List<DeliveryLog>> deliveryLogsStream() => _deliveryLogs
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(DeliveryLog.fromFirestore).toList());

  // ── RFQ Operations ─────────────────────────────────────────────────────────

  Stream<List<Rfq>> rfqsStream() => _rfqs
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Rfq.fromFirestore).toList());

  Future<void> addRfq(Rfq rfq) async {
    final docRef = await _rfqs.add(rfq.toFirestore());
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'CREATE',
        targetId: docRef.id,
        targetName: 'RFQ ${rfq.rfqNumber}',
        summary:
            'Request for Quotation created for RFQ Number: [${rfq.rfqNumber}].',
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<void> updateRfq(Rfq rfq) async {
    await _rfqs.doc(rfq.id).update(rfq.toFirestore());
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'UPDATE',
        targetId: rfq.id,
        targetName: 'RFQ ${rfq.rfqNumber}',
        summary:
            'Request for Quotation updated for RFQ Number: [${rfq.rfqNumber}].',
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<void> updateRfqStatus(String id, RfqStatus status) async {
    await _rfqs.doc(id).update({
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'STATUS_CHANGE',
        targetId: id,
        targetName: 'RFQ $id',
        summary: 'RFQ status transitioned to [${status.name}].',
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<String> convertRfqToPurchaseOrder(Rfq rfq, String poNumber) async {
    final freshSupplier = await fetchSupplierById(rfq.supplierId);
    final SupplierSnapshot supplierSnapshot = freshSupplier != null
        ? freshSupplier.toSnapshot()
        : SupplierSnapshot(
            supplierId: rfq.supplierId,
            supplierName: rfq.supplierName,
            snapshottedAt: DateTime.now(),
          );

    final batch = _db.batch();

    // 1. Lock RFQ status to converted
    final rfqRef = _rfqs.doc(rfq.id);
    batch.update(rfqRef, {
      'status': RfqStatus.converted.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Create Purchase Order document with hydrated SupplierSnapshot
    final poRef = _purchaseOrders.doc();
    final poItems = rfq.items.map((i) {
      return PurchaseOrderItem(
        productId: i.productId,
        productName: i.productName,
        sku: i.sku,
        orderedQty: i.requestedQty,
        receivedQty: 0,
        unitCost: i.quotedUnitPrice ?? 0.0,
      );
    }).toList();

    final po = PurchaseOrder(
      id: poRef.id,
      poNumber: poNumber,
      rfqId: rfq.id,
      supplierId: supplierSnapshot.supplierId,
      supplierName: supplierSnapshot.supplierName,
      supplierSnapshot: supplierSnapshot,
      status: PurchaseOrderStatus.pendingDelivery,
      orderDate: DateTime.now(),
      items: poItems,
    );

    batch.set(poRef, po.toFirestore());
    await batch.commit();
    return poRef.id;
  }

  // ── Purchase Order Operations ──────────────────────────────────────────────

  Stream<List<PurchaseOrder>> purchaseOrdersStream() => _purchaseOrders
      .orderBy('orderDate', descending: true)
      .snapshots()
      .map((s) => s.docs.map(PurchaseOrder.fromFirestore).toList());

  /// FIFO sorted pending purchase orders (oldest pending order date first)
  Stream<List<PurchaseOrder>> fifoPurchaseOrdersStream() => _purchaseOrders
          .orderBy('orderDate', descending: false)
          .snapshots()
          .map((s) {
        final all = s.docs.map(PurchaseOrder.fromFirestore).toList();
        return all
            .where((po) =>
                po.status == PurchaseOrderStatus.pendingDelivery ||
                po.status == PurchaseOrderStatus.partiallyReceived)
            .toList();
      });

  /// Check if an active (Sent / Pending or Partially Received / Backordered) PO exists for a supplier or product list.
  Future<List<PurchaseOrder>> checkActiveDuplicatePo({
    required String supplierId,
    List<String>? productIds,
  }) async {
    final snapshot =
        await _purchaseOrders.where('supplierId', isEqualTo: supplierId).get();

    final active = snapshot.docs
        .map(PurchaseOrder.fromFirestore)
        .where((po) => po.status.isActive)
        .toList();

    if (productIds == null || productIds.isEmpty) {
      return active;
    }

    return active.where((po) {
      return po.items.any((item) => productIds.contains(item.productId));
    }).toList();
  }

  /// Creates a Purchase Order in Firestore with an authoritative hydrated [SupplierSnapshot],
  /// guaranteeing that the returned [PurchaseOrder.id] matches the persisted Firestore document ID.
  Future<PurchaseOrder> createPurchaseOrder(PurchaseOrder po) async {
    SupplierSnapshot? snapshot = po.supplierSnapshot;
    if (snapshot == null && po.supplierId.trim().isNotEmpty) {
      final freshSupplier = await fetchSupplierById(po.supplierId);
      if (freshSupplier != null) {
        snapshot = freshSupplier.toSnapshot();
      }
    }
    snapshot ??= SupplierSnapshot(
      supplierId: po.supplierId,
      supplierName: po.supplierName,
      snapshottedAt: po.orderDate,
    );

    final docRef = po.id.trim().isNotEmpty
        ? _purchaseOrders.doc(po.id.trim())
        : _purchaseOrders.doc();

    final hydratedPo = po.copyWith(
      id: docRef.id,
      supplierName: snapshot.supplierName.isNotEmpty
          ? snapshot.supplierName
          : po.supplierName,
      supplierSnapshot: snapshot,
    );

    await docRef.set(hydratedPo.toFirestore());

    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: hydratedPo.status == PurchaseOrderStatus.draft
            ? 'CREATE_DRAFT'
            : 'CREATE_PO',
        targetId: docRef.id,
        targetName: 'PO ${hydratedPo.poNumber}',
        summary:
            'Purchase Order ${hydratedPo.poNumber} created for supplier ${hydratedPo.effectiveSupplierName} with ${hydratedPo.items.length} items (Status: ${hydratedPo.status.displayName}).',
        afterData: {
          'poNumber': hydratedPo.poNumber,
          'supplierId': hydratedPo.supplierId,
          'supplierName': hydratedPo.effectiveSupplierName,
          'supplierSnapshot': snapshot.toMap(),
          'status': hydratedPo.status.name,
          'totalItems': hydratedPo.totalOrderedQty,
          'totalEstimatedValue': hydratedPo.totalOrderedValue,
          if (hydratedPo.requestedDeliveryDate != null)
            'requestedDeliveryDate':
                hydratedPo.requestedDeliveryDate!.toIso8601String(),
          'itemsOrderedSummary': hydratedPo.items
              .map((i) => {
                    'productName': i.productName,
                    'sku': i.sku,
                    'orderedQty': i.orderedQty,
                    'unitCost': i.unitCost,
                    'totalCost': i.orderedQty * i.unitCost,
                  })
              .toList(),
        },
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }

    return hydratedPo;
  }

  /// Updates the embedded [SupplierSnapshot] on an existing Purchase Order / Backorder document.
  Future<void> updatePurchaseOrderSupplierSnapshot(
    String poId,
    SupplierSnapshot snapshot,
  ) async {
    await _purchaseOrders.doc(poId).update({
      'supplierName': snapshot.supplierName,
      'supplierSnapshot': snapshot.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'UPDATE_PO_SUPPLIER_SNAPSHOT',
        targetId: poId,
        targetName: 'PO $poId',
        summary:
            'Updated supplier snapshot on PO/Backorder for ${snapshot.supplierName} (${snapshot.email}).',
      );
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<void> updatePurchaseOrderStatus(
      String id, PurchaseOrderStatus status) async {
    await _purchaseOrders.doc(id).update({
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'STATUS_CHANGE',
        targetId: id,
        targetName: 'PO $id',
        summary:
            'Purchase Order status transitioned to [${status.displayName}].',
      );
    } catch (_) {
      // Non-fatal: audit log failure should not interrupt database operation.
    }
  }

  Future<void> shortClosePurchaseOrder(
    String poId,
    List<PurchaseOrderItem> updatedItems, {
    String reason = 'Supplier short-fulfillment',
    String closedBy = 'Admin',
  }) async {
    final poDoc = await _purchaseOrders.doc(poId).get();
    final Map<String, dynamic>? beforeSnapshot =
        poDoc.exists ? poDoc.data() as Map<String, dynamic>? : null;

    final batch = _db.batch();
    final poRef = _purchaseOrders.doc(poId);

    batch.update(poRef, {
      'status': PurchaseOrderStatus.shortClosed.name,
      'items': updatedItems.map((i) => i.toMap()).toList(),
      'cancelledReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await AuditLogService().logAction(
      module: 'Suppliers',
      action: 'CLOSED_SHORT',
      targetId: poId,
      targetName: 'PO $poId',
      summary:
          'Purchase Order force-closed short. Reason: $reason. Unfulfilled remaining balance zeroed out.',
      beforeData: beforeSnapshot,
      afterData: {
        'status': PurchaseOrderStatus.shortClosed.name,
        'cancelledReason': reason,
        'closedBy': closedBy,
        'itemsReceivedSummary': updatedItems
            .where((i) => i.receivedQty > 0)
            .map((i) => {
                  'productName': i.productName,
                  'sku': i.sku,
                  'receivedQty': i.receivedQty,
                  'actualUnitCost': i.actualUnitCost ?? i.unitCost,
                  'totalCost': i.receivedQty * (i.actualUnitCost ?? i.unitCost),
                })
            .toList(),
        'itemsMissingSummary': updatedItems
            .where((i) => i.remainingQty > 0 || i.rejectedQty > 0)
            .map((i) => {
                  'productName': i.productName,
                  'sku': i.sku,
                  'orderedQty': i.orderedQty,
                  'receivedQty': i.receivedQty,
                  'rejectedQty': i.rejectedQty,
                  'missingQty': i.remainingQty + i.rejectedQty,
                  'rejectionReason': reason,
                })
            .toList(),
      },
      batch: batch,
    );

    await batch.commit();
  }

  // ── Receiving Records & Inventory Batches Streams ──────────────────────────

  Stream<List<ReceivingRecord>> receivingRecordsStream() => _receivingRecords
      .orderBy('receivedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(ReceivingRecord.fromFirestore).toList());

  Stream<List<InventoryBatchRecord>> inventoryBatchesStream() =>
      _inventoryBatches
          .orderBy('receivedAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(InventoryBatchRecord.fromFirestore).toList());

  // ── Atomic PO Stock Receiving Workflow ────────────────────────────────────

  Future<PurchaseOrder> processPoDeliveryAtomic({
    required String poId,
    required PurchaseOrder currentPo,
    required String deliveryReceiptNo,
    required Map<String, int> receivedQtyMap,
    required Map<String, DateTime?> expiryDateMap,
    required Map<String, double> unitCostMap,
    required List<Product> cachedProducts,
    required String receivedBy,
    DateTime? datePurchased,
    DateTime? dateArrived,
    Map<String, String>? batchNumberMap,
    Map<String, List<SplitBatchEntry>>? splitBatchesMap,
    Map<String, int>? rejectedQtyMap,
    Map<String, String>? rejectionReasonMap,
    String? discrepancyNote,
    bool syncProductCostPrice = false,
    bool shortCloseRemaining = false,
    String overDeliveryAction = 'cap', // 'accept' or 'cap'
    StoreSettings? settings,
  }) async {
    final freshSupplier = await fetchSupplierById(currentPo.supplierId);
    return await _batchService.receivePurchaseOrderAtomic(
      poId: poId,
      currentPo: currentPo,
      deliveryReceiptNo: deliveryReceiptNo,
      receivedQtyMap: receivedQtyMap,
      expiryDateMap: expiryDateMap,
      unitCostMap: unitCostMap,
      receivedBy: receivedBy,
      datePurchased: datePurchased ?? currentPo.orderDate,
      dateArrived: dateArrived ?? DateTime.now(),
      freshSupplier: freshSupplier,
      batchNumberMap: batchNumberMap,
      splitBatchesMap: splitBatchesMap,
      rejectedQtyMap: rejectedQtyMap,
      rejectionReasonMap: rejectionReasonMap,
      discrepancyNote: discrepancyNote,
      syncProductCostPrice: syncProductCostPrice,
      shortCloseRemaining: shortCloseRemaining,
      overDeliveryAction: overDeliveryAction,
      settings: settings,
    );
  }
}
