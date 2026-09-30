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
  CollectionReference get _bundles => _db.collection('bundles');
  CollectionReference get _restockInquiries =>
      _db.collection('restock_inquiries');
  CollectionReference get _deliveryLogs => _db.collection('delivery_logs');
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

  Future<void> addProduct(Product p) => _products.add(p.toFirestore());

  Future<void> updateProduct(Product p) =>
      _products.doc(p.id).update(p.toFirestore());

  Future<void> deleteProduct(String productId) =>
      _products.doc(productId).delete();

  Future<void> updateStock(String productId, int newStock) =>
      _products.doc(productId).update({'stock': newStock});

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

    // 2. Perform in-memory FIFO/FEFO batch deduction and stock updates across products
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
        // In-memory FIFO/FEFO Batch Deduction
        int remainingToDeduct = item.qty;
        final List<ProductBatch> currentBatches = List.from(product.batches);

        // Sort by expiry date / created date ascending (FIFO / FEFO)
        currentBatches.sort((a, b) {
          if (a.expiryDate != null && b.expiryDate != null) {
            return a.expiryDate!.compareTo(b.expiryDate!);
          }
          return a.createdAt.compareTo(b.createdAt);
        });

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

        final int newStock = (product.stock - item.qty).clamp(0, 999999);

        batch.update(productDocRef, {
          'stock': newStock,
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

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to process refund: $e');
    }
  }

  // ── Suppliers ──────────────────────────────────────────────────────────────

  Stream<List<Supplier>> suppliersStream() => _suppliers
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map(Supplier.fromFirestore).toList());

  Future<void> addSupplier(Supplier s) => _suppliers.add(s.toFirestore());

  Future<void> updateSupplier(Supplier s) =>
      _suppliers.doc(s.id).update(s.toFirestore());

  Future<void> deleteSupplier(String id) => _suppliers.doc(id).delete();

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

  Future<void> updateOrder(PreOrder order) =>
      _orders.doc(order.id).update(order.toFirestore());

  Future<void> updateOrderStatus(String orderId, OrderStatus status,
          {String? reason}) =>
      _orders.doc(orderId).update({
        'status': status.name,
        if (reason != null) 'rejectionReason': reason,
      });

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

  // ── Customers ──────────────────────────────────────────────────────────────

  Stream<List<Customer>> customersStream() =>
      _customers.orderBy('name').snapshots().map((s) => s.docs
          .map((d) => Customer.fromMap(d.id, d.data() as Map<String, dynamic>))
          .toList());

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
}
