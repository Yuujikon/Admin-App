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
    } catch(e) {}
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
    } catch(e) {}
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
    } catch(e) {}
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
    } catch(e) {}
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

  /// Deduct main stock and clear the reservedStock for a fulfilled order
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
          'reservedStock': FieldValue.increment(-item.qty),
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
  Future<void> clearReservedStockBatch(List<CartItem> items) async {
    final batch = _db.batch();
    for (final item in items) {
      final docRef = _products.doc(item.productId);
      if (item.variantId != null && item.variantId!.isNotEmpty) {
        batch.update(docRef, {
          'variants.${item.variantId}.reservedStock':
              FieldValue.increment(-item.qty),
          'reservedStock': FieldValue.increment(-item.qty),
        });
      } else {
        batch.update(docRef, {
          'reservedStock': FieldValue.increment(-item.qty),
        });
      }
    }
    await batch.commit();
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

  /// Offline-First Checkout Pipeline using WriteBatch (Zero runTransaction dependency)
  Future<void> recordSaleOfflineFirst({
    required StoreTransaction tx,
    required List<Product> cachedProducts,
  }) async {
    final batch = _db.batch();

    // 1. Stage transaction document in 'transactions' collection
    final txDocRef = _transactions.doc(tx.id);
    batch.set(txDocRef, tx.toFirestore());

    // 2. Perform in-memory FIFO batch deduction and stock updates across products
    for (final item in tx.items) {
      final productIndex =
          cachedProducts.indexWhere((p) => p.id == item.productId);
      if (productIndex < 0) continue;

      final product = cachedProducts[productIndex];
      final productDocRef = _products.doc(product.id);

      if (item.variantId != null) {
        // Variant stock update
        batch.update(productDocRef, {
          'variants.${item.variantId}.stock': FieldValue.increment(-item.qty),
          'stock': FieldValue.increment(-item.qty),
        });
      } else {
        // In-memory FIFO Batch Deduction
        int remainingToDeduct = item.qty;
        final List<ProductBatch> currentBatches = List.from(product.batches);

        // Sort by created date ascending (FIFO)
        currentBatches.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        final List<ProductBatch> updatedBatches = [];

        for (final b in currentBatches) {
          if (remainingToDeduct <= 0) {
            updatedBatches.add(b);
            continue;
          }

          if (b.quantity > remainingToDeduct) {
            updatedBatches.add(ProductBatch(
              id: b.id,
              productId: b.productId,
              quantity: b.quantity - remainingToDeduct,
              unitCost: b.unitCost,
              expiryDate: b.expiryDate,
              createdAt: b.createdAt,
              invoiceNumber: b.invoiceNumber,
            ));
            remainingToDeduct = 0;
          } else {
            remainingToDeduct -= b.quantity;
          }
        }

        batch.update(productDocRef, {
          'stock': FieldValue.increment(-item.qty),
          'batches': {for (var b in updatedBatches) b.id: b.toMap()},
        });
      }
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
      targetName: 'Tx #${tx.id.substring(0, 5)}',
      summary: 'Sale transaction completed. Total: [₱${tx.total.toStringAsFixed(2)}] for [${tx.items.length}] items.',
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
        if (item.variantId != null) {
          batch.update(_products.doc(item.productId), {
            'variants.${item.variantId}.stock': FieldValue.increment(item.qty),
          });
        } else {
          batch.update(_products.doc(item.productId), {
            'stock': FieldValue.increment(item.qty),
          });
        }
      }

      await AuditLogService().logAction(
        module: 'POS',
        action: 'VOID_SALE',
        targetId: tx.id,
        targetName: 'Tx #${tx.id.substring(0, 5)}',
        summary: 'Sale transaction voided/refunded. Total amount refunded: [₱${tx.total.toStringAsFixed(2)}].',
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

        // 3. Inventory stock adjustment math
        if (productSnap.exists) {
          if (isCashRefund) {
            // Cash refund: Restock +returnQty to sellable shelf
            if (variantId != null && variantId.isNotEmpty) {
              transaction.update(productRef, {
                'variants.$variantId.stock': FieldValue.increment(returnQty),
              });
            } else {
              transaction.update(productRef, {
                'stock': FieldValue.increment(returnQty),
              });
            }
          } else if (isDamagedSwap) {
            // 1-to-1 Swap (Damaged write-off): Fresh unit issued, returned unit written off -> -returnQty
            if (variantId != null && variantId.isNotEmpty) {
              transaction.update(productRef, {
                'variants.$variantId.stock': FieldValue.increment(-returnQty),
              });
            } else {
              transaction.update(productRef, {
                'stock': FieldValue.increment(-returnQty),
              });
            }
          }
          // Note: 1-to-1 Swap with sellable restock (!isCashRefund && !isDamagedSwap) has net 0 stock change.
        }
        
        final logRef = _db.collection('audit_logs').doc();
        transaction.set(logRef, {
           'timestamp': FieldValue.serverTimestamp(),
           'actorId': 'system', // could pass processedBy if available, but hardcode for now
           'actorEmail': 'system', 
           'actorRole': 'system',
           'module': 'POS',
           'action': 'RETURN_ITEM',
           'targetId': transactionId,
           'targetName': 'Tx #${transactionId.substring(0, 5)}',
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
            if (vid != null && vid.isNotEmpty) {
              transaction.update(productRef, {
                'variants.$vid.stock': FieldValue.increment(rQty),
              });
            } else {
              transaction.update(productRef, {
                'stock': FieldValue.increment(rQty),
              });
            }
          } else {
            // Damaged/Expired/Write-off: Log inventory loss record
            final lossRef = _db.collection('loss_records').doc();
            final double price = (refItem['price'] as num? ?? 0.0).toDouble();
            transaction.set(lossRef, {
              'productId': pid,
              if (vid != null) 'variantId': vid,
              'productName': refItem['name'] ?? '',
              'qty': rQty,
              'unitPrice': price,
              'unitLossCost': price,
              'totalLoss': price * rQty,
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
         'targetName': 'Tx #${transactionId.substring(0, 5)}',
         'summary': 'Processed multi-item refund of ₱${totalRefundAmount.toStringAsFixed(2)}',
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
    } catch(e) {}
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
    } catch(e) {}
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
    } catch(e) {}
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
          targetName: 'Order #${orderId.substring(0, 5)}',
          summary: 'Order status transitioned to [${status.name}]' + (reason != null ? ' Reason: [$reason].' : '.'),
        );
      } catch(e) {}
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
      final batch = _db.batch();

      batch.update(_refundRequests.doc(request.id), {
        'status': RefundStatus.approved.name,
        'processedByEmail': adminEmail,
        if (request.condition != null) 'condition': request.condition!.name,
        if (request.adminNotes != null) 'adminNotes': request.adminNotes,
      });

      for (final item in request.items) {
        if (request.condition == RefundCondition.restockable) {
          if (item.variantId != null) {
            batch.update(_products.doc(item.productId), {
              'variants.${item.variantId}.stock':
                  FieldValue.increment(item.qty),
            });
          } else {
            batch.update(_products.doc(item.productId), {
              'stock': FieldValue.increment(item.qty),
            });
          }
        } else {
          final lossDoc = _lossRecords.doc();
          batch.set(lossDoc, {
            'productId': item.productId,
            'productName': item.name,
            'qty': item.qty,
            'unitPrice': item.price,
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
      final int updatedStock = item.product.stock + item.qtyReceived;
      final double updatedCostPrice =
          item.unitCost > 0 ? item.unitCost : item.product.costPrice;
      final updatedBatches = [...item.product.batches, item.newBatch];

      DateTime? earliestExp;
      for (var b in updatedBatches) {
        if (b.quantity > 0 && b.expiryDate != null) {
          if (earliestExp == null || b.expiryDate!.isBefore(earliestExp)) {
            earliestExp = b.expiryDate;
          }
        }
      }

      final Map<String, dynamic> prodUpdateData = {
        'stock': updatedStock,
        'costPrice': updatedCostPrice,
        'batches': {for (var b in updatedBatches) b.id: b.toMap()},
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (earliestExp != null) {
        prodUpdateData['expiryDate'] = Timestamp.fromDate(earliestExp);
      }

      // 1. Update Product document (stock, cost, batches, nearest expiry)
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
    final int updatedStock = product.stock + newBatch.quantity;
    final double updatedCostPrice =
        newBatch.unitCost > 0 ? newBatch.unitCost : product.costPrice;
    final updatedBatches = [...product.batches, newBatch];

    DateTime? earliestExp;
    for (var b in updatedBatches) {
      if (b.quantity > 0 && b.expiryDate != null) {
        if (earliestExp == null || b.expiryDate!.isBefore(earliestExp)) {
          earliestExp = b.expiryDate;
        }
      }
    }

    final Map<String, dynamic> updateData = {
      'stock': updatedStock,
      'costPrice': updatedCostPrice,
      'batches': {for (var b in updatedBatches) b.id: b.toMap()},
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (earliestExp != null) {
      updateData['expiryDate'] = Timestamp.fromDate(earliestExp);
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
    } catch(e) {}
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
    } catch(e) {}
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
      } catch(e) {}
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
    } catch(e) {}
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
      } catch(e) {}
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
    } catch(e) {}
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

          final updatedBatches = [...prod.batches, newProductBatch];
          final int updatedStock = prod.stock + qtyReceivingNow;

          DateTime? earliestExp;
          for (var b in updatedBatches) {
            if (b.quantity > 0 && b.expiryDate != null) {
              if (earliestExp == null || b.expiryDate!.isBefore(earliestExp)) {
                earliestExp = b.expiryDate;
              }
            }
          }

          final Map<String, dynamic> prodUpdateData = {
            'stock': updatedStock,
            'batches': {for (var b in updatedBatches) b.id: b.toMap()},
            'updatedAt': FieldValue.serverTimestamp(),
          };

          if (syncProductCostPrice && effectiveUnitCost > 0) {
            prodUpdateData['costPrice'] = effectiveUnitCost;
          }

          if (earliestExp != null) {
            prodUpdateData['expiryDate'] = Timestamp.fromDate(earliestExp);
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
