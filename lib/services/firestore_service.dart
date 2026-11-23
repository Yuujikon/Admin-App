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
import 'package:uuid/uuid.dart';
import '../models/catalog_product.dart';
import '../models/restock_inquiry.dart';
import '../models/delivery_log.dart';
import '../models/rfq.dart';
import '../models/purchase_order.dart';
import '../models/receiving_record.dart';
import '../models/inventory_batch_record.dart';
import '../shared/services/time_service.dart';
import '../shared/services/admin_messaging_service.dart';
import '../utils/inventory_math.dart';
import 'audit_log_service.dart';

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
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
    }
  }

  Future<void> updateProduct(Product p) async {
    await _products.doc(p.id).update(p.toFirestore());
    try {
      await AuditLogService().logAction(
        module: 'Inventory',
        action: 'UPDATE',
        targetId: p.id,
        targetName: p.name,
        summary: 'Inventory record updated for [${p.name}] (ID: ${p.id}).',
        afterData: p.toFirestore(),
      );
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
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
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
    }
  }

  Future<void> updateStock(String productId, int newStock) async {
    await _products.doc(productId).update({'stock': newStock});
    try {
      await AuditLogService().logAction(
        module: 'Inventory',
        action: 'STOCK_ADJUST',
        targetId: productId,
        targetName: 'Product $productId',
        summary: 'Inventory stock manually adjusted to [$newStock] for product (ID: $productId).',
        afterData: {'stock': newStock},
      );
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
    }
  }

  Future<void> decrementStockBatch(List<CartItem> items) async {
    final batch = _db.batch();
    for (final item in items) {
      final docRef = _products.doc(item.productId);
      if (item.variantId != null && item.variantId!.isNotEmpty) {
        batch.update(docRef, {
          'variants.${item.variantId}.stock': FieldValue.increment(-item.qty),
          'stock': FieldValue.increment(-item.qty),
        });
      } else {
        batch.update(docRef, {
          'stock': FieldValue.increment(-item.qty),
        });
      }
    }
    await batch.commit();
  }

  /// Deduct main stock and clear the reservedStock for a fulfilled order.
  /// For variants, only decrements `variants.<id>.reservedStock` (matching Customer-App).
  Future<void> fulfillOrderStockBatch(List<CartItem> items) async {
    final batch = _db.batch();
    for (final item in items) {
      final docRef = _products.doc(item.productId);
      if (item.variantId != null && item.variantId!.isNotEmpty) {
        batch.update(docRef, {
          'variants.${item.variantId}.stock': FieldValue.increment(-item.qty),
          'variants.${item.variantId}.reservedStock':
              FieldValue.increment(-item.qty),
          'stock': FieldValue.increment(-item.qty),
        });
      } else {
        batch.update(docRef, {
          'stock': FieldValue.increment(-item.qty),
          'reservedStock': FieldValue.increment(-item.qty),
        });
      }
    }
    await batch.commit();
  }

  /// Decrement reservedStock for all items when an order is cancelled.
  /// For variants, only decrements `variants.<id>.reservedStock` (matching Customer-App).
  Future<void> clearReservedStockBatch(List<CartItem> items) async {
    final batch = _db.batch();
    for (final item in items) {
      final docRef = _products.doc(item.productId);
      if (item.variantId != null && item.variantId!.isNotEmpty) {
        batch.update(docRef, {
          'variants.${item.variantId}.reservedStock':
              FieldValue.increment(-item.qty),
        });
      } else {
        batch.update(docRef, {
          'reservedStock': FieldValue.increment(-item.qty),
        });
      }
    }
    await batch.commit();
  }

  /// Atomically fulfills a pre-order pickup (plus optional walk-in items) inside a single transaction:
  /// - Guards against duplicate fulfillment (`status == collected/cancelled` or `reservationReleased == true`)
  /// - Performs FEFO batch depletion & COGS calculation on fresh product snapshots
  /// - Clamps `reservedStock` release so it never goes negative
  /// - Updates order to `collected` with `reservationReleased: true`
  /// - Writes `transactions/{tx.id}` with matching document ID
  Future<StoreTransaction> fulfillOrderTransactional({
    required PreOrder order,
    required PreOrder updatedOrder,
    required StoreTransaction tx,
    List<CartItem> walkInItems = const [],
  }) {
    return _db.runTransaction<StoreTransaction>((transaction) async {
      final orderRef = _orders.doc(order.id);
      final orderSnap = await transaction.get(orderRef);
      if (!orderSnap.exists) {
        throw Exception('Order #${order.orderId} not found.');
      }

      final orderData = orderSnap.data() as Map<String, dynamic>? ?? {};
      final currentStatus = orderData['status']?.toString() ?? '';
      if (currentStatus == OrderStatus.collected.name ||
          currentStatus == OrderStatus.cancelled.name ||
          currentStatus == OrderStatus.refunded.name) {
        throw Exception(
            'Order #${order.orderId} is already $currentStatus and cannot be fulfilled again.');
      }
      final bool alreadyReleased = orderData['reservationReleased'] == true;

      // 1. ALL READS FIRST: Read every unique product doc involved in order + walk-in items
      final Set<String> productIds = {
        for (final item in order.items)
          if (item.productId.isNotEmpty) item.productId,
        for (final item in walkInItems)
          if (item.productId.isNotEmpty) item.productId,
      };

      final Map<String, DocumentSnapshot> productSnaps = {};
      for (final pid in productIds) {
        productSnaps[pid] = await transaction.get(_products.doc(pid));
      }

      // Parse live products and compute FEFO depletion plans once per product
      final Map<String, Product> liveProducts = {};
      for (final entry in productSnaps.entries) {
        if (entry.value.exists) {
          liveProducts[entry.key] = Product.fromFirestore(entry.value);
        }
      }

      // Compute depleted items (with accurate COGS) and track mutated batch state per product
      final Map<String, List<ProductBatch>> workingBatchesByProduct = {
        for (final entry in liveProducts.entries)
          entry.key: List<ProductBatch>.from(entry.value.batches),
      };
      final Map<String, int> inventoryBatchDeductions = {};
      final Map<String, Map<String, dynamic>> productFieldUpdates = {};

      void addStockDelta(String pid, String field, int delta) {
        if (delta == 0) return;
        productFieldUpdates.putIfAbsent(pid, () => {});
        final prev = productFieldUpdates[pid]![field];
        if (prev is int) {
          productFieldUpdates[pid]![field] = prev + delta;
        } else {
          productFieldUpdates[pid]![field] = delta;
        }
      }

      CartItem processLineItem(CartItem item, {required bool releaseReserved}) {
        final liveProduct = liveProducts[item.productId];
        if (liveProduct == null) return item;

        if (item.variantId != null && item.variantId!.isNotEmpty) {
          addStockDelta(item.productId, 'variants.${item.variantId}.stock', -item.qty);
          addStockDelta(item.productId, 'stock', -item.qty);
          if (releaseReserved && !alreadyReleased) {
            final matchedVariant = liveProduct.variants.where((v) => v.id == item.variantId);
            final currentReserved =
                matchedVariant.isNotEmpty ? matchedVariant.first.reservedStock : 0;
            final safeRelease =
                currentReserved >= item.qty ? item.qty : currentReserved;
            if (safeRelease > 0) {
              addStockDelta(
                  item.productId, 'variants.${item.variantId}.reservedStock', -safeRelease);
            }
          }
          final unitCost = item.costPrice > 0
              ? item.costPrice
              : (liveProduct.variants
                      .where((v) => v.id == item.variantId)
                      .map((v) => v.costPrice)
                      .firstOrNull ??
                  liveProduct.effectiveUnitCost);
          return item.copyWith(
            costPrice: unitCost,
            totalCogs: unitCost * item.qty,
            depletedBatches: [
              BatchDepletionRecord(
                batchId: 'variant-${item.variantId}',
                quantity: item.qty,
                unitCost: unitCost,
              ),
            ],
          );
        } else {
          final currentProductView = liveProduct.copyWith(
            batches: workingBatchesByProduct[item.productId] ?? const [],
          );
          final plan = planBatchDepletion(currentProductView, item.qty);
          workingBatchesByProduct[item.productId] = plan.remainingBatches;

          for (final bEntry in plan.batchQuantitiesDeducted.entries) {
            inventoryBatchDeductions[bEntry.key] =
                (inventoryBatchDeductions[bEntry.key] ?? 0) + bEntry.value;
          }

          addStockDelta(item.productId, 'stock', -item.qty);
          if (releaseReserved && !alreadyReleased) {
            final safeRelease = liveProduct.reservedStock >= item.qty
                ? item.qty
                : liveProduct.reservedStock;
            if (safeRelease > 0) {
              addStockDelta(item.productId, 'reservedStock', -safeRelease);
            }
          }

          return item.copyWith(
            barcode: item.barcode.isNotEmpty
                ? item.barcode
                : (liveProduct.barcode ?? ''),
            costPrice: plan.weightedUnitCost,
            totalCogs: plan.totalCogs,
            depletedBatches: plan.depletedBatches,
          );
        }
      }

      final List<CartItem> processedOrderItems = [
        for (final item in order.items)
          processLineItem(item, releaseReserved: true),
      ];
      final List<CartItem> processedWalkInItems = [
        for (final item in walkInItems)
          processLineItem(item, releaseReserved: false),
      ];

      // Read any matching top-level inventory_batches docs BEFORE writing
      final Map<String, DocumentSnapshot> invBatchSnaps = {};
      for (final batchId in inventoryBatchDeductions.keys) {
        invBatchSnaps[batchId] =
            await transaction.get(_inventoryBatches.doc(batchId));
      }

      // 2. ALL WRITES AT THE END
      for (final entry in productFieldUpdates.entries) {
        final pid = entry.key;
        final snap = productSnaps[pid];
        if (snap == null || !snap.exists) continue;
        final Map<String, dynamic> firestoreUpdate = {};
        for (final fieldEntry in entry.value.entries) {
          if (fieldEntry.value is int && fieldEntry.value != 0) {
            firestoreUpdate[fieldEntry.key] =
                FieldValue.increment(fieldEntry.value as int);
          }
        }
        // Persist updated FEFO batches for non-variant products
        final liveProduct = liveProducts[pid];
        if (liveProduct != null && !liveProduct.hasVariants) {
          final updatedBatches = workingBatchesByProduct[pid] ?? const [];
          firestoreUpdate['batches'] = {
            for (final b in updatedBatches) b.id: b.toMap(),
          };
        }
        if (firestoreUpdate.isNotEmpty) {
          transaction.update(snap.reference, firestoreUpdate);
        }
      }

      // Update matching top-level inventory_batches records
      for (final entry in inventoryBatchDeductions.entries) {
        final snap = invBatchSnaps[entry.key];
        if (snap != null && snap.exists) {
          transaction.update(snap.reference, {
            'quantityRemaining': FieldValue.increment(-entry.value),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      final finalOrderData = updatedOrder
          .copyWith(reservationReleased: true)
          .toFirestore();
      transaction.update(orderRef, finalOrderData);

      final enrichedTx = StoreTransaction(
        id: tx.id,
        orderId: tx.orderId,
        items: [...processedOrderItems, ...processedWalkInItems],
        total: tx.total,
        cashTendered: tx.cashTendered,
        changeGiven: tx.changeGiven,
        createdAt: tx.createdAt,
        customerId: tx.customerId,
        customerEmail: tx.customerEmail,
        paymentMethod: tx.paymentMethod,
        type: tx.type,
        isRefunded: tx.isRefunded,
      );

      final txDocRef =
          tx.id.isNotEmpty ? _transactions.doc(tx.id) : _transactions.doc();
      transaction.set(txDocRef, enrichedTx.toFirestore());

      return enrichedTx;
    });
  }

  /// Idempotently cancels an active order and releases `reservedStock` ONCE inside a transaction.
  /// Returns `true` if this call performed the cancellation/release, or `false` if already
  /// collected/refunded or already released by another device/customer.
  Future<bool> cancelOrderAndReleaseReservation({
    required String orderId,
    required String processedBy,
    String? reason,
  }) {
    return _db.runTransaction<bool>((transaction) async {
      final orderRef = _orders.doc(orderId);
      final orderSnap = await transaction.get(orderRef);
      if (!orderSnap.exists) return false;

      final orderData = orderSnap.data() as Map<String, dynamic>? ?? {};
      final currentStatus = orderData['status']?.toString() ?? '';
      if (currentStatus == OrderStatus.collected.name ||
          currentStatus == OrderStatus.refunded.name) {
        return false; // Never cancel or release reservation of a collected/refunded order
      }

      final bool alreadyReleased = orderData['reservationReleased'] == true;
      if (currentStatus == OrderStatus.cancelled.name && alreadyReleased) {
        return false;
      }

      final items = (orderData['items'] as List? ?? [])
          .map((e) => CartItem.fromMap(e))
          .toList();

      // Aggregate quantities to release per product/variant
      final Map<String, Map<String, int>> releaseByProductField = {};
      if (!alreadyReleased) {
        for (final item in items) {
          if (item.productId.isEmpty || item.qty <= 0) continue;
          final fieldKey = (item.variantId != null && item.variantId!.isNotEmpty)
              ? 'variants.${item.variantId}.reservedStock'
              : 'reservedStock';
          releaseByProductField.putIfAbsent(item.productId, () => {});
          releaseByProductField[item.productId]![fieldKey] =
              (releaseByProductField[item.productId]![fieldKey] ?? 0) + item.qty;
        }
      }

      // ALL READS BEFORE WRITES
      final Map<String, DocumentSnapshot> productSnaps = {};
      for (final pid in releaseByProductField.keys) {
        productSnaps[pid] = await transaction.get(_products.doc(pid));
      }

      // ALL WRITES
      for (final entry in releaseByProductField.entries) {
        final productSnap = productSnaps[entry.key];
        if (productSnap == null || !productSnap.exists) continue;
        final pData = productSnap.data() as Map<String, dynamic>? ?? {};
        final updates = <String, dynamic>{};

        for (final fieldEntry in entry.value.entries) {
          final fieldKey = fieldEntry.key;
          final qtyToRelease = fieldEntry.value;
          int currentReserved = 0;

          if (fieldKey == 'reservedStock') {
            currentReserved = (pData['reservedStock'] as num? ?? 0).toInt();
          } else {
            final variantId = fieldKey.split('.')[1];
            final variants = pData['variants'];
            if (variants is Map) {
              final variant = variants[variantId];
              if (variant is Map) {
                currentReserved = (variant['reservedStock'] as num? ?? 0).toInt();
              } else {
                continue;
              }
            } else {
              continue;
            }
          }

          final safeRelease =
              currentReserved >= qtyToRelease ? qtyToRelease : currentReserved;
          if (safeRelease > 0) {
            updates[fieldKey] = FieldValue.increment(-safeRelease);
          }
        }

        if (updates.isNotEmpty) {
          transaction.update(productSnap.reference, updates);
        }
      }

      transaction.update(orderRef, {
        'status': OrderStatus.cancelled.name,
        'reservationReleased': true,
        'processedBy': processedBy,
        if (reason != null) 'rejectionReason': reason,
        'statusTimeline.${OrderStatus.cancelled.name}':
            FieldValue.serverTimestamp(),
      });

      return !alreadyReleased;
    });
  }

  /// Idempotently records a ghosting offense for a customer when a pickup order expires uncollected.
  /// Penalty ladder: 1st = 2h, 2nd = 24h, 3rd = 72h, 4th+ = permanent lock.
  Future<void> recordGhostingOffense({
    String? userId,
    required String userEmail,
    required String orderId,
    required String sixCharOrderId,
  }) async {
    DocumentReference? userRef;
    if (userId != null && userId.isNotEmpty) {
      final snap = await _users.doc(userId).get();
      if (snap.exists) userRef = snap.reference;
    }
    if (userRef == null && userEmail.isNotEmpty) {
      final query =
          await _users.where('email', isEqualTo: userEmail).limit(1).get();
      if (query.docs.isNotEmpty) {
        userRef = query.docs.first.reference;
      }
    }
    if (userRef == null) {
      debugPrint(
          'No user record found for ghosting offense (order #$sixCharOrderId, email: $userEmail)');
      return;
    }

    final targetRef = userRef;
    Map<String, dynamic>? notificationPayload;

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(targetRef);
      if (!snap.exists) return;
      final userData = snap.data() as Map<String, dynamic>? ?? {};

      final List ghostedOrders = userData['ghostedOrders'] as List? ?? [];
      if (ghostedOrders.contains(orderId) ||
          ghostedOrders.contains(sixCharOrderId)) {
        return; // Already penalized for this order
      }

      final currentOffenses = (userData['offenseCount'] as num? ?? 0).toInt();
      final newOffenseCount = currentOffenses + 1;
      final now = TimeService.now;

      DateTime? restrictionUntil;
      bool isPermanentlyLocked = false;
      String restrictionMsg;

      if (newOffenseCount == 1) {
        restrictionUntil = now.add(const Duration(hours: 2));
        restrictionMsg = '2-hour order restriction';
      } else if (newOffenseCount == 2) {
        restrictionUntil = now.add(const Duration(hours: 24));
        restrictionMsg = '24-hour order restriction';
      } else if (newOffenseCount == 3) {
        restrictionUntil = now.add(const Duration(hours: 72));
        restrictionMsg = '72-hour (3-day) order restriction';
      } else {
        isPermanentlyLocked = true;
        restrictionMsg = 'Permanent account lock';
      }

      transaction.update(targetRef, {
        'offenseCount': newOffenseCount,
        'restrictedUntil': restrictionUntil != null
            ? Timestamp.fromDate(restrictionUntil)
            : null,
        'restrictionUntil': restrictionUntil != null
            ? Timestamp.fromDate(restrictionUntil)
            : null,
        'isPermanentlyLocked': isPermanentlyLocked,
        'lastOffenseAt': FieldValue.serverTimestamp(),
        'ghostedOrders': FieldValue.arrayUnion([orderId, sixCharOrderId]),
      });

      final String title = isPermanentlyLocked
          ? '⛔ Account Permanently Locked'
          : '⚠️ Ghosted Order Penalty ($newOffenseCount/4 Offenses)';
      final String body = isPermanentlyLocked
          ? 'Your order #$sixCharOrderId expired without collection. Your account is permanently locked from placing orders ($newOffenseCount offenses). You may submit an appeal.'
          : 'Your order #$sixCharOrderId expired without collection. Penalty: $restrictionMsg. You cannot place pre-orders during this period.';

      notificationPayload = {
        'title': title,
        'body': body,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'offense',
        'isRead': false,
        'relatedId': orderId,
      };
    });

    if (notificationPayload != null) {
      await targetRef.collection('notifications').add(notificationPayload!);
    }
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

  /// Offline-First Checkout Pipeline using WriteBatch (Zero runTransaction dependency).
  /// Applies precomputed [depletionPlans] (single source of truth) so batches are never double-deducted.
  Future<void> recordSaleOfflineFirst({
    required StoreTransaction tx,
    Map<String, BatchDepletionPlan>? depletionPlans,
    List<Product>? cachedProducts,
  }) async {
    final batch = _db.batch();

    // 1. Stage transaction document in 'transactions' collection
    final txDocRef = _transactions.doc(tx.id);
    batch.set(txDocRef, tx.toFirestore());

    // 2. Aggregate stock decrements per product/variant so duplicate line items apply cleanly
    final Map<String, Map<String, int>> stockDecrements = {};
    for (final item in tx.items) {
      if (item.productId.isEmpty || item.qty <= 0) continue;
      stockDecrements.putIfAbsent(item.productId, () => {});
      if (item.variantId != null && item.variantId!.isNotEmpty) {
        final vKey = 'variants.${item.variantId}.stock';
        stockDecrements[item.productId]![vKey] =
            (stockDecrements[item.productId]![vKey] ?? 0) + item.qty;
        stockDecrements[item.productId]!['stock'] =
            (stockDecrements[item.productId]!['stock'] ?? 0) + item.qty;
      } else {
        stockDecrements[item.productId]!['stock'] =
            (stockDecrements[item.productId]!['stock'] ?? 0) + item.qty;
      }
    }

    for (final entry in stockDecrements.entries) {
      final productId = entry.key;
      final productDocRef = _products.doc(productId);
      final Map<String, dynamic> updateData = {
        for (final fieldEntry in entry.value.entries)
          fieldEntry.key: FieldValue.increment(-fieldEntry.value),
      };

      // Use precomputed FEFO depletion plan if provided; otherwise compute once from cachedProducts
      BatchDepletionPlan? plan = depletionPlans?[productId];
      if (plan == null &&
          cachedProducts != null &&
          !entry.value.keys.any((k) => k.startsWith('variants.'))) {
        final idx = cachedProducts.indexWhere((p) => p.id == productId);
        if (idx >= 0) {
          plan = planBatchDepletion(
              cachedProducts[idx], entry.value['stock'] ?? 0);
        }
      }

      if (plan != null) {
        updateData['batches'] = {
          for (final b in plan.remainingBatches) b.id: b.toMap(),
        };
      }

      batch.update(productDocRef, updateData);
    }

    if (tx.customerId != null) {
      final customerDocRef = _customers.doc(tx.customerId);
      batch.set(
          customerDocRef,
          {
            'totalSpent': FieldValue.increment(tx.total),
            'lastVisit': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }

    await AuditLogService().logAction(
      module: 'POS',
      action: 'SALE_COMPLETE',
      targetId: tx.id,
      targetName: 'Tx #${safeShortId(tx.id)}',
      summary:
          'Sale transaction completed. Total: [₱${tx.total.toStringAsFixed(2)}] for [${tx.items.length}] items.',
      batch: batch,
    );

    // Commit batch atomically to local cache (completes instantly offline!)
    try {
      await batch.commit();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('unavailable') ||
          errStr.contains('deadline-exceeded')) {
        debugPrint(
            'Checkout WriteBatch committed to local cache while offline. Pending cloud sync.');
      } else {
        rethrow;
      }
    }
  }

  Future<void> refundTransaction(StoreTransaction tx) async {
    try {
      final batch = _db.batch();
      // Mark as refunded instead of deleting
      batch.update(_transactions.doc(tx.id), {'isRefunded': true});

      for (final item in tx.items) {
        final deltas = computeStockRestockDeltas(
          variantId: item.variantId,
          qty: item.qty,
        );
        batch.update(_products.doc(item.productId), {
          for (final e in deltas.entries) e.key: FieldValue.increment(e.value),
        });
      }

      await AuditLogService().logAction(
        module: 'POS',
        action: 'VOID_SALE',
        targetId: tx.id,
        targetName: 'Tx #${safeShortId(tx.id)}',
        summary:
            'Sale transaction voided/refunded. Total amount refunded: [₱${tx.total.toStringAsFixed(2)}].',
        batch: batch,
      );

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to process refund: $e');
    }
  }

  /// Processes a single line item return or 1-to-1 swap atomically.
  /// Enforces Firestore's strict Read-Before-Write rule: all reads performed before writes.
  Future<void> processItemReturn({
    required String transactionId,
    String? orderId,
    required String productId,
    String? variantId,
    required String barcode,
    required int returnQty,
    required bool isCashRefund,
    bool isDamagedSwap = false,
  }) async {
    try {
      await _db.runTransaction((transaction) async {
        final txRef = _transactions.doc(transactionId);
        final txSnap = await transaction.get(txRef);

        if (!txSnap.exists) {
          throw Exception('Transaction record not found.');
        }

        DocumentSnapshot? orderSnap;
        DocumentReference? orderRef;
        if (orderId != null && orderId.trim().isNotEmpty) {
          orderRef = _orders.doc(orderId.trim());
          final snap = await transaction.get(orderRef);
          if (snap.exists) {
            orderSnap = snap;
          }
        }

        final productRef = _products.doc(productId);
        final productSnap = await transaction.get(productRef);

        // --- READ PHASE COMPLETE: ALL TRANSACTION READS ARE ABOVE THIS LINE ---

        // 1. Process items array for Transaction
        final txData = txSnap.data() as Map<String, dynamic>? ?? {};
        final rawItems = (txData['items'] as List? ?? []);
        bool matched = false;
        final updatedTxItems = rawItems.map((raw) {
          if (raw is! Map) return raw;
          final itemMap = Map<String, dynamic>.from(raw);
          final String itemBarcode = itemMap['barcode']?.toString() ?? '';
          final String itemPid = itemMap['productId']?.toString() ?? '';
          final String? itemVid = itemMap['variantId']?.toString();

          final bool matchesBarcode =
              barcode.isNotEmpty && itemBarcode == barcode;
          final bool matchesId = (barcode.isEmpty || !matchesBarcode) &&
              itemPid == productId &&
              (variantId == null || itemVid == variantId);

          if (!matched && (matchesBarcode || matchesId)) {
            matched = true;
            final currentReturned =
                (itemMap['returnedQty'] as num? ?? 0).toInt();
            itemMap['returnedQty'] = currentReturned + returnQty;
          }
          return itemMap;
        }).toList();

        if (!matched) {
          throw Exception(
              'Selected item was not found on this transaction receipt.');
        }

        // Check if all items on this transaction have now been fully returned
        final bool allItemsFullyReturned = updatedTxItems.every((raw) {
          if (raw is! Map) return true;
          final int qty = (raw['qty'] as num? ?? 1).toInt();
          final int retQty = (raw['returnedQty'] as num? ?? 0).toInt();
          return retQty >= qty;
        });

        transaction.update(txRef, {
          'items': updatedTxItems,
          if (allItemsFullyReturned) 'isRefunded': true,
        });

        // 2. Process items array for Orders (if linked pre-order)
        if (orderRef != null && orderSnap != null) {
          final orderData = orderSnap.data() as Map<String, dynamic>? ?? {};
          final rawOrderItems = (orderData['items'] as List? ?? []);
          bool orderMatched = false;
          final updatedOrderItems = rawOrderItems.map((raw) {
            if (raw is! Map) return raw;
            final itemMap = Map<String, dynamic>.from(raw);
            final String itemBarcode = itemMap['barcode']?.toString() ?? '';
            final String itemPid = itemMap['productId']?.toString() ?? '';
            final String? itemVid = itemMap['variantId']?.toString();

            final bool matchesBarcode =
                barcode.isNotEmpty && itemBarcode == barcode;
            final bool matchesId = (barcode.isEmpty || !matchesBarcode) &&
                itemPid == productId &&
                (variantId == null || itemVid == variantId);

            if (!orderMatched && (matchesBarcode || matchesId)) {
              orderMatched = true;
              final currentReturned =
                  (itemMap['returnedQty'] as num? ?? 0).toInt();
              itemMap['returnedQty'] = currentReturned + returnQty;
            }
            return itemMap;
          }).toList();

          transaction.update(orderRef, {'items': updatedOrderItems});
        }

        // 3. Inventory stock adjustment math (variants update BOTH variant stock and top-level stock)
        if (productSnap.exists) {
          if (isCashRefund) {
            final deltas = computeStockRestockDeltas(
              variantId: variantId,
              qty: returnQty,
            );
            transaction.update(productRef, {
              for (final e in deltas.entries)
                e.key: FieldValue.increment(e.value),
            });
          } else if (isDamagedSwap) {
            final deltas = computeStockRestockDeltas(
              variantId: variantId,
              qty: -returnQty,
            );
            transaction.update(productRef, {
              for (final e in deltas.entries)
                e.key: FieldValue.increment(e.value),
            });
          }
          // Note: 1-to-1 Swap with sellable restock (!isCashRefund && !isDamagedSwap) has net 0 stock change.
        }

        final logRef = _db.collection('audit_logs').doc();
        transaction.set(logRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'actorId': 'system',
          'actorEmail': 'system',
          'actorRole': 'system',
          'module': 'POS',
          'action': 'RETURN_ITEM',
          'targetId': transactionId,
          'targetName': 'Tx #${safeShortId(transactionId)}',
          'summary': 'Processed return for ${returnQty}x of $productId',
        });
      });
    } catch (e) {
      debugPrint('Error processing item return: $e');
      rethrow;
    }
  }

  /// Processes a multi-item refund for a transaction, restocking item inventory,
  /// updating returned quantities on transaction & linked order, and logging a Refund Record in Firestore.
  Future<void> processMultiItemRefund({
    required String transactionId,
    required List<Map<String, dynamic>> itemsToRefund,
    required double totalRefundAmount,
    required String processedBy,
    String? customerEmail,
    String? orderId,
  }) async {
    if (itemsToRefund.isEmpty) return;

    final txRef = _transactions.doc(transactionId);
    final orderRef = (orderId != null && orderId.isNotEmpty) ? _orders.doc(orderId) : null;
    final refundLogRef = _db.collection('refund_records').doc();

    await _db.runTransaction((transaction) async {
      final txSnap = await transaction.get(txRef);
      if (!txSnap.exists) throw Exception('Transaction record not found.');

      DocumentSnapshot? orderSnap;
      if (orderRef != null) {
        orderSnap = await transaction.get(orderRef);
      }

      final txData = txSnap.data() as Map<String, dynamic>? ?? {};
      final rawItems = (txData['items'] as List? ?? []);

      final updatedTxItems = rawItems.map((raw) {
        if (raw is! Map) return raw;
        final itemMap = Map<String, dynamic>.from(raw);
        final String itemPid = itemMap['productId']?.toString() ?? '';
        final String? itemVid = itemMap['variantId']?.toString();

        final refundEntry = itemsToRefund.firstWhere(
          (r) =>
              r['productId'] == itemPid &&
              (r['variantId'] == itemVid || (r['variantId'] == null && itemVid == null)),
          orElse: () => {},
        );

        if (refundEntry.isNotEmpty) {
          final int returnQty = (refundEntry['qty'] as num? ?? 0).toInt();
          final int currentReturned = (itemMap['returnedQty'] as num? ?? 0).toInt();
          itemMap['returnedQty'] = currentReturned + returnQty;
        }
        return itemMap;
      }).toList();

      final bool allItemsFullyReturned = updatedTxItems.every((raw) {
        if (raw is! Map) return true;
        final int qty = (raw['qty'] as num? ?? 1).toInt();
        final int retQty = (raw['returnedQty'] as num? ?? 0).toInt();
        return retQty >= qty;
      });

      transaction.update(txRef, {
        'items': updatedTxItems,
        if (allItemsFullyReturned) 'isRefunded': true,
      });

      if (orderRef != null && orderSnap != null && orderSnap.exists) {
        final orderData = orderSnap.data() as Map<String, dynamic>? ?? {};
        final rawOrderItems = (orderData['items'] as List? ?? []);
        final updatedOrderItems = rawOrderItems.map((raw) {
          if (raw is! Map) return raw;
          final itemMap = Map<String, dynamic>.from(raw);
          final String itemPid = itemMap['productId']?.toString() ?? '';
          final String? itemVid = itemMap['variantId']?.toString();

          final refundEntry = itemsToRefund.firstWhere(
            (r) =>
                r['productId'] == itemPid &&
                (r['variantId'] == itemVid || (r['variantId'] == null && itemVid == null)),
            orElse: () => {},
          );

          if (refundEntry.isNotEmpty) {
            final int returnQty = (refundEntry['qty'] as num? ?? 0).toInt();
            final int currentReturned = (itemMap['returnedQty'] as num? ?? 0).toInt();
            itemMap['returnedQty'] = currentReturned + returnQty;
          }
          return itemMap;
        }).toList();

        transaction.update(orderRef, {'items': updatedOrderItems});
      }

      // Restock or Log Spoilage/Loss for refunded items
      for (final refItem in itemsToRefund) {
        final String pid = refItem['productId']?.toString() ?? '';
        final String? vid = refItem['variantId']?.toString();
        final int rQty = (refItem['qty'] as num? ?? 0).toInt();
        final String condition = refItem['condition']?.toString() ?? 'restock';

        if (pid.isNotEmpty && rQty > 0) {
          final productRef = _products.doc(pid);
          if (condition == 'restock') {
            final deltas = computeStockRestockDeltas(
              variantId: vid,
              qty: rQty,
            );
            transaction.update(productRef, {
              for (final e in deltas.entries)
                e.key: FieldValue.increment(e.value),
            });
          } else {
            // Damaged/Expired/Write-off: Log inventory loss record at costPrice
            final lossRef = _db.collection('loss_records').doc();
            final double price = (refItem['price'] as num? ?? 0.0).toDouble();
            final double itemCost =
                (refItem['costPrice'] as num? ?? 0.0).toDouble();
            final double lossUnitCost = computeRefundLossUnitCost(
              itemCostPrice: itemCost,
              retailPrice: price,
            );
            transaction.set(lossRef, {
              'productId': pid,
              if (vid != null) 'variantId': vid,
              'productName': refItem['name'] ?? '',
              'qty': rQty,
              'unitPrice': lossUnitCost,
              'unitLossCost': lossUnitCost,
              'totalLoss': lossUnitCost * rQty,
              'type': condition == 'expired' ? 'expired' : 'damaged',
              'notes':
                  'Refund Write-off ($condition) for Receipt #$transactionId',
              'processedBy': processedBy,
              'reportedBy': processedBy,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      // Log Refund Record in refund_records collection
      transaction.set(refundLogRef, {
        'transactionId': transactionId,
        'orderId': orderId,
        'customerEmail': customerEmail ?? txData['customerEmail'] ?? '',
        'refundedAt': FieldValue.serverTimestamp(),
        'items': itemsToRefund,
        'totalAmount': totalRefundAmount,
        'processedBy': processedBy,
      });

      final logRef = _db.collection('audit_logs').doc();
      transaction.set(logRef, {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': processedBy,
        'actorEmail': processedBy,
        'actorRole': 'admin',
        'module': 'POS',
        'action': 'VOID_SALE',
        'targetId': transactionId,
        'targetName': 'Tx #${safeShortId(transactionId)}',
        'summary':
            'Processed multi-item refund of ₱${totalRefundAmount.toStringAsFixed(2)}',
      });
      
    });
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
                'refundedAt': (data['refundedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
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
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
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
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
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
    final batch = _db.batch();
    batch.set(_lossRecords.doc(), record.toFirestore());
    batch.update(_products.doc(record.productId), {
      'stock': FieldValue.increment(-record.qty),
    });
    
    await AuditLogService().logAction(
      module: 'Inventory',
      action: 'STOCK_ADJUST',
      targetId: record.productId,
      targetName: 'Product ${record.productId}',
      summary: 'Inventory loss recorded: deducted [${record.qty}] units. Reason: [${record.notes}].',
      batch: batch,
    );
    
    return batch.commit();
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
        targetName: 'Order #${safeShortId(orderId)}',
        summary: 'Order status transitioned to [${status.name}]${reason != null ? ' Reason: [$reason].' : '.'}',
      );
    } catch (_) {}
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

  Future<void> addTransaction(StoreTransaction tx) {
    if (tx.id.isNotEmpty) {
      return _transactions.doc(tx.id).set(tx.toFirestore());
    }
    return _transactions.add(tx.toFirestore());
  }

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
                isPermanentlyLocked:
                    uData['isPermanentlyLocked'] ?? existing.isPermanentlyLocked,
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
      history =
          List<Map<String, dynamic>>.from(data['offenseHistory'] as List? ?? []);
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
        history =
            List<Map<String, dynamic>>.from(uData['offenseHistory'] as List? ?? []);
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

  Future<void> processApprovedRefund(
      RefundRequest request, String adminEmail) async {
    try {
      // Look up matching transaction(s) by doc ID or orderId so we mark isRefunded: true
      final List<DocumentReference> matchingTxRefs = [];
      if (request.transactionId.isNotEmpty) {
        final directTx =
            await _transactions.doc(request.transactionId).get();
        if (directTx.exists) {
          matchingTxRefs.add(directTx.reference);
        } else {
          final byOrder = await _transactions
              .where('orderId', isEqualTo: request.transactionId)
              .get();
          for (final doc in byOrder.docs) {
            matchingTxRefs.add(doc.reference);
          }
        }
      }

      // Fetch product costs for accurate cost-based loss write-offs when non-restockable
      final Map<String, double> productUnitCosts = {};
      if (request.condition != RefundCondition.restockable) {
        for (final item in request.items) {
          if (item.productId.isEmpty ||
              productUnitCosts.containsKey(item.productId)) {
            continue;
          }
          final pSnap = await _products.doc(item.productId).get();
          if (pSnap.exists) {
            final p = Product.fromFirestore(pSnap);
            productUnitCosts[item.productId] = p.effectiveUnitCost;
          }
        }
      }

      final batch = _db.batch();

      batch.update(_refundRequests.doc(request.id), {
        'status': RefundStatus.approved.name,
        'processedByEmail': adminEmail,
        if (request.condition != null) 'condition': request.condition!.name,
        if (request.adminNotes != null) 'adminNotes': request.adminNotes,
      });

      // Mark linked transaction(s) as refunded
      for (final txRef in matchingTxRefs) {
        batch.update(txRef, {'isRefunded': true});
      }

      for (final item in request.items) {
        if (request.condition == RefundCondition.restockable) {
          final deltas = computeStockRestockDeltas(
            variantId: item.variantId,
            qty: item.qty,
          );
          batch.update(_products.doc(item.productId), {
            for (final e in deltas.entries)
              e.key: FieldValue.increment(e.value),
          });
        } else {
          final lossUnitCost = computeRefundLossUnitCost(
            itemCostPrice: item.costPrice,
            productCostPrice: productUnitCosts[item.productId],
            retailPrice: item.price,
          );
          final lossDoc = _lossRecords.doc();
          batch.set(lossDoc, {
            'productId': item.productId,
            if (item.variantId != null) 'variantId': item.variantId,
            'productName': item.name,
            'qty': item.qty,
            'unitPrice': lossUnitCost,
            'unitLossCost': lossUnitCost,
            'totalLoss': lossUnitCost * item.qty,
            'type': request.condition == RefundCondition.expired
                ? 'expired'
                : 'damaged',
            'notes': 'Refund Return: ${request.reason}',
            'createdAt': FieldValue.serverTimestamp(),
            'processedBy': adminEmail,
            'referenceId': request.transactionId,
          });
        }
      }

      // Log audit record in refund_records collection
      final refundRecordRef = _db.collection('refund_records').doc();
      batch.set(refundRecordRef, {
        'refundRequestId': request.id,
        'transactionId': request.transactionId,
        'orderId': request.transactionId,
        'customerEmail': request.customerEmail,
        'refundedAt': FieldValue.serverTimestamp(),
        'items': request.items.map((i) => i.toMap()).toList(),
        'totalAmount': request.total,
        'condition': request.condition?.name ?? 'restockable',
        'processedBy': adminEmail,
      });

      await batch.commit();
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
    List<Map<String, dynamic>>? updatedInquiryItems,
    String? invoiceNumber,
    String? notes,
  }) async {
    final batch = _db.batch();

    for (final item in items) {
      if (item.qtyReceived <= 0) continue;

      final prodRef = _products.doc(item.product.id);
      final double updatedCostPrice =
          item.unitCost > 0 ? item.unitCost : item.product.costPrice;

      // Atomic stock increment + dot-notation batch insert (never overwrites concurrent sales/batches)
      final Map<String, dynamic> prodUpdateData = {
        'stock': FieldValue.increment(item.qtyReceived),
        'costPrice': updatedCostPrice,
        'batches.${item.newBatch.id}': item.newBatch.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (item.newBatch.expiryDate != null &&
          (item.product.expiryDate == null ||
              item.newBatch.expiryDate!.isBefore(item.product.expiryDate!))) {
        prodUpdateData['expiryDate'] =
            Timestamp.fromDate(item.newBatch.expiryDate!);
      }

      // 1. Update Product document atomically
      batch.update(prodRef, prodUpdateData);

      // 2. Create Delivery Log document
      final deliveryLogRef = _db.collection('delivery_logs').doc();
      batch.set(deliveryLogRef, {
        'productId': item.product.id,
        'productName': item.product.name,
        'qtyReceived': item.qtyReceived,
        'unitCost': item.unitCost,
        'totalValue': item.qtyReceived * item.unitCost,
        'expiryDate': item.newBatch.expiryDate != null
            ? Timestamp.fromDate(item.newBatch.expiryDate!)
            : (item.product.expiryDate != null
                ? Timestamp.fromDate(item.product.expiryDate!)
                : null),
        'invoiceNumber': invoiceNumber,
        'receivedBy': receivedBy,
        'notes': notes ?? item.discrepancyNote,
        'createdAt': FieldValue.serverTimestamp(),
        if (item.orderedQty != null) 'orderedQty': item.orderedQty,
        if (item.orderedUnitCost != null)
          'orderedUnitCost': item.orderedUnitCost,
        if (item.supplierId != null) 'supplierId': item.supplierId,
        if (item.supplierName != null) 'supplierName': item.supplierName,
      });
    }

    // 3. Update RestockInquiry status and updated items
    final inquiryRef = _restockInquiries.doc(inquiryId);
    final Map<String, dynamic> inquiryUpdateData = {
      'status': newStatus.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (updatedInquiryItems != null && updatedInquiryItems.isNotEmpty) {
      inquiryUpdateData['items'] = updatedInquiryItems;
    }
    batch.update(inquiryRef, inquiryUpdateData);

    try {
      await batch.commit();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('unavailable') ||
          errStr.contains('deadline-exceeded')) {
        debugPrint(
            'Inquiry Delivery WriteBatch committed to local cache while offline.');
      } else {
        rethrow;
      }
    }
  }

  Future<void> processSingleDeliveryAtomic({
    required Product product,
    required ProductBatch newBatch,
    required String receivedBy,
    String? invoiceNumber,
    String? notes,
  }) async {
    final batch = _db.batch();

    final prodRef = _products.doc(product.id);
    final double updatedCostPrice =
        newBatch.unitCost > 0 ? newBatch.unitCost : product.costPrice;

    // Atomic stock increment + dot-notation batch insert (never overwrites concurrent sales/batches)
    final Map<String, dynamic> updateData = {
      'stock': FieldValue.increment(newBatch.quantity),
      'costPrice': updatedCostPrice,
      'batches.${newBatch.id}': newBatch.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (newBatch.expiryDate != null &&
        (product.expiryDate == null ||
            newBatch.expiryDate!.isBefore(product.expiryDate!))) {
      updateData['expiryDate'] = Timestamp.fromDate(newBatch.expiryDate!);
    }
    if (product.packCost != null) {
      updateData['packCost'] = product.packCost;
    }
    if (product.itemsPerCase != null) {
      updateData['itemsPerCase'] = product.itemsPerCase;
    }

    batch.update(prodRef, updateData);

    final deliveryLogRef = _db.collection('delivery_logs').doc();
    batch.set(deliveryLogRef, {
      'productId': product.id,
      'productName': product.name,
      'qtyReceived': newBatch.quantity,
      'unitCost': newBatch.unitCost,
      'totalValue': newBatch.quantity * newBatch.unitCost,
      'expiryDate': newBatch.expiryDate != null
          ? Timestamp.fromDate(newBatch.expiryDate!)
          : (product.expiryDate != null
              ? Timestamp.fromDate(product.expiryDate!)
              : null),
      'invoiceNumber': invoiceNumber,
      'receivedBy': receivedBy,
      'notes': notes,
      if (product.supplierId != null && product.supplierId!.isNotEmpty)
        'supplierId': product.supplierId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('unavailable') ||
          errStr.contains('deadline-exceeded')) {
        debugPrint(
            'Single Delivery WriteBatch committed to local cache while offline.');
      } else {
        rethrow;
      }
    }
  }

  Future<void> saveProductWithBatch({
    required Product product,
    required ProductBatch initialBatch,
    String? receivedBy,
    String? notes,
  }) async {
    final batch = _db.batch();

    final docRef =
        product.id.isEmpty ? _products.doc() : _products.doc(product.id);
    final String finalId = docRef.id;

    final batchId =
        initialBatch.id.isEmpty ? const Uuid().v4() : initialBatch.id;
    final createdBatch = ProductBatch(
      id: batchId,
      productId: finalId,
      quantity: initialBatch.quantity,
      unitCost: initialBatch.unitCost,
      expiryDate: initialBatch.expiryDate,
      createdAt: initialBatch.createdAt,
      invoiceNumber: initialBatch.invoiceNumber,
    );

    final updatedProduct = product.copyWith(
      batches: [...product.batches, createdBatch],
    );

    batch.set(
        docRef,
        {
          ...updatedProduct.toFirestore(),
          'id': finalId,
        },
        SetOptions(merge: true));

    final deliveryLogRef = _db.collection('delivery_logs').doc();
    batch.set(deliveryLogRef, {
      'productId': finalId,
      'productName': product.name,
      'qtyReceived': initialBatch.quantity,
      'unitCost': initialBatch.unitCost,
      'totalValue': initialBatch.quantity * initialBatch.unitCost,
      'expiryDate': initialBatch.expiryDate != null
          ? Timestamp.fromDate(initialBatch.expiryDate!)
          : null,
      'invoiceNumber': initialBatch.invoiceNumber,
      'receivedBy': receivedBy ?? 'Admin',
      'notes': notes ?? 'Initial Inventory / Product Creation',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
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
        summary: 'Request for Quotation created for RFQ Number: [${rfq.rfqNumber}].',
      );
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
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
        summary: 'Request for Quotation updated for RFQ Number: [${rfq.rfqNumber}].',
      );
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
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
      } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
    }
  }

  Future<String> convertRfqToPurchaseOrder(Rfq rfq, String poNumber) async {
    final batch = _db.batch();

    // 1. Lock RFQ status to converted
    final rfqRef = _rfqs.doc(rfq.id);
    batch.update(rfqRef, {
      'status': RfqStatus.converted.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Create Purchase Order document
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
      supplierId: rfq.supplierId,
      supplierName: rfq.supplierName,
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

  Future<void> createPurchaseOrder(PurchaseOrder po) async {
    final docRef = await _purchaseOrders.add(po.toFirestore());
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'CREATE',
        targetId: docRef.id,
        targetName: 'PO ${po.poNumber}',
        summary: 'Purchase Order created for PO Number: [${po.poNumber}].',
      );
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
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
          summary: 'Purchase Order status transitioned to [${status.name}].',
        );
      } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
    }
  }

  Future<void> shortClosePurchaseOrder(
      String poId, List<PurchaseOrderItem> updatedItems) async {
    await _purchaseOrders.doc(poId).update({
      'status': PurchaseOrderStatus.shortClosed.name,
      'items': updatedItems.map((i) => i.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await AuditLogService().logAction(
        module: 'Suppliers',
        action: 'SHORT_CLOSE',
        targetId: poId,
        targetName: 'PO $poId',
        summary: 'Purchase Order short-closed with [${updatedItems.length}] valid items remaining.',
      );
    } catch (e) {
      debugPrint('AuditLogService.log failed: $e');
    }
  }

  // ── Receiving Records & Inventory Batches Streams ──────────────────────────

  Stream<List<ReceivingRecord>> receivingRecordsStream() => _receivingRecords
      .orderBy('receivedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(ReceivingRecord.fromFirestore).toList());

  Stream<List<InventoryBatchRecord>> inventoryBatchesStream() => _inventoryBatches
      .orderBy('receivedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(InventoryBatchRecord.fromFirestore).toList());

  // ── Atomic PO Stock Receiving Workflow ────────────────────────────────────

  Future<void> processPoDeliveryAtomic({
    required String poId,
    required PurchaseOrder currentPo,
    required String deliveryReceiptNo,
    required Map<String, int> receivedQtyMap,
    required Map<String, DateTime?> expiryDateMap,
    required Map<String, double> unitCostMap,
    required List<Product> cachedProducts,
    required String receivedBy,
    String? discrepancyNote,
    bool syncProductCostPrice = false,
    bool shortCloseRemaining = false,
  }) async {
    final batch = _db.batch();

    // 1. Prepare receiving record document
    final receivingRecordRef = _receivingRecords.doc();
    final List<ReceivingItem> itemsReceivedForRecord = [];

    // 2. Prepare updated PO items list
    final List<PurchaseOrderItem> updatedPoItems = [];

    for (final poItem in currentPo.items) {
      final int qtyReceivingNow = receivedQtyMap[poItem.productId] ?? 0;
      final int remaining = poItem.remainingQty;

      // Guardrail validation
      if (qtyReceivingNow > remaining) {
        throw Exception(
            'Cannot receive $qtyReceivingNow units for ${poItem.productName}. Maximum remaining is $remaining.');
      }

      final int newTotalReceivedQty = poItem.receivedQty + qtyReceivingNow;
      final double effectiveUnitCost =
          unitCostMap[poItem.productId] ?? poItem.unitCost;

      updatedPoItems.add(poItem.copyWith(
        receivedQty: newTotalReceivedQty,
        unitCost: effectiveUnitCost,
      ));

      if (qtyReceivingNow > 0) {
        final String newBatchId = const Uuid().v4();
        final DateTime? expiry = expiryDateMap[poItem.productId];

        itemsReceivedForRecord.add(ReceivingItem(
          productId: poItem.productId,
          productName: poItem.productName,
          qty: qtyReceivingNow,
          batchId: newBatchId,
        ));

        // 3. Create top-level `inventory_batches/{batchId}` document
        final inventoryBatchRef = _inventoryBatches.doc(newBatchId);
        batch.set(inventoryBatchRef, {
          'batchId': newBatchId,
          'productId': poItem.productId,
          'poId': poId,
          'receiptId': receivingRecordRef.id,
          'quantityRemaining': qtyReceivingNow,
          'unitCost': effectiveUnitCost,
          'receivedAt': FieldValue.serverTimestamp(),
          'expiryDate': expiry != null ? Timestamp.fromDate(expiry) : null,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // 4. Update parent Product document stock, cost, and embedded batches
        final prodIndex =
            cachedProducts.indexWhere((p) => p.id == poItem.productId);
        if (prodIndex >= 0) {
          final prod = cachedProducts[prodIndex];
          final prodRef = _products.doc(prod.id);

          final newProductBatch = ProductBatch(
            batchId: newBatchId,
            productId: prod.id,
            quantityRemaining: qtyReceivingNow,
            unitCost: effectiveUnitCost,
            dateReceived: DateTime.now(),
            expirationDate: expiry,
            invoiceNumber: deliveryReceiptNo,
          );

          final Map<String, dynamic> prodUpdateData = {
            'stock': FieldValue.increment(qtyReceivingNow),
            'batches.$newBatchId': newProductBatch.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          if (syncProductCostPrice && effectiveUnitCost > 0) {
            prodUpdateData['costPrice'] = effectiveUnitCost;
          }

          if (expiry != null &&
              (prod.expiryDate == null || expiry.isBefore(prod.expiryDate!))) {
            prodUpdateData['expiryDate'] = Timestamp.fromDate(expiry);
          }

          batch.update(prodRef, prodUpdateData);
        }

        // 5. Create DeliveryLog for backward compatibility with audit logs
        final deliveryLogRef = _deliveryLogs.doc();
        batch.set(deliveryLogRef, {
          'productId': poItem.productId,
          'productName': poItem.productName,
          'qtyReceived': qtyReceivingNow,
          'unitCost': effectiveUnitCost,
          'totalValue': qtyReceivingNow * effectiveUnitCost,
          'expiryDate': expiry != null ? Timestamp.fromDate(expiry) : null,
          'invoiceNumber': deliveryReceiptNo,
          'receivedBy': receivedBy,
          'notes': discrepancyNote,
          'orderedQty': poItem.orderedQty,
          'orderedUnitCost': poItem.unitCost,
          'supplierId': currentPo.supplierId,
          'supplierName': currentPo.supplierName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // Write receiving_records document
    batch.set(receivingRecordRef, {
      'poId': poId,
      'deliveryReceiptNo': deliveryReceiptNo,
      'receivedAt': FieldValue.serverTimestamp(),
      'discrepancyNote': discrepancyNote,
      'itemsReceived': itemsReceivedForRecord.map((i) => i.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 6. Calculate PO Status
    PurchaseOrderStatus newStatus;
    if (shortCloseRemaining) {
      newStatus = PurchaseOrderStatus.shortClosed;
    } else {
      final bool allDone =
          updatedPoItems.every((item) => item.receivedQty >= item.orderedQty);
      final bool anyReceived =
          updatedPoItems.any((item) => item.receivedQty > 0);

      if (allDone) {
        newStatus = PurchaseOrderStatus.completed;
      } else if (anyReceived) {
        newStatus = PurchaseOrderStatus.partiallyReceived;
      } else {
        newStatus = PurchaseOrderStatus.pendingDelivery;
      }
    }

    final poRef = _purchaseOrders.doc(poId);
    batch.update(poRef, {
      'status': newStatus.name,
      'items': updatedPoItems.map((i) => i.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    await AuditLogService().logAction(
      module: 'Inventory',
      action: 'RECEIVE_STOCK',
      targetId: poId,
      targetName: 'PO $poId / DR $deliveryReceiptNo',
      summary: 'Delivery receipt processed. Received [${itemsReceivedForRecord.length}] items. Purchase Order status transitioned to [${newStatus.name}].',
      batch: batch,
    );

    try {
      await batch.commit();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('unavailable') ||
          errStr.contains('deadline-exceeded')) {
        debugPrint(
            'PO Delivery WriteBatch committed to local cache while offline.');
      } else {
        rethrow;
      }
    }
  }
}
