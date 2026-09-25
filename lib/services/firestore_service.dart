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

class FirestoreService {
  final _db = FirebaseFirestore.instance;

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
  CollectionReference get _products          => _db.collection('products');
  CollectionReference get _catalog           => _db.collection('catalog');
  CollectionReference get _orders            => _db.collection('orders');
  CollectionReference get _transactions      => _db.collection('transactions');
  CollectionReference get _expenses          => _db.collection('expenses');
  CollectionReference get _refundRequests    => _db.collection('refund_requests');
  CollectionReference get _suppliers         => _db.collection('suppliers');
  CollectionReference get _lossRecords       => _db.collection('loss_records');
  CollectionReference get _customers         => _db.collection('customers');
  CollectionReference get _bundles           => _db.collection('bundles');
  CollectionReference get _restockInquiries  => _db.collection('restock_inquiries');
  DocumentReference   get _settings          => _db.collection('settings').doc('store_settings');

  // ── Store Settings ─────────────────────────────────────────────────────────

  Stream<StoreSettings> settingsStream() =>
      _settings.snapshots().map(StoreSettings.fromFirestore);

  Future<void> updateStoreStatus(bool isClosed, {String? message, DateTime? closeAt, DateTime? openAt}) =>
      _settings.set({
        'isClosed': isClosed,
        'closureMessage': message,
        'scheduledCloseAt': closeAt != null ? Timestamp.fromDate(closeAt) : null,
        'scheduledOpenAt': openAt != null ? Timestamp.fromDate(openAt) : null,
      }, SetOptions(merge: true));

  Future<void> saveStoreSettings(StoreSettings s) =>
      _settings.set(s.toFirestore(), SetOptions(merge: true));

  // ── Products ───────────────────────────────────────────────────────────────

  Stream<List<Product>> productsStream() =>
      _products.orderBy('name').snapshots().map(
              (s) => s.docs.map(Product.fromFirestore).toList());

  /// Use this for public/customer views to ensure internal draft products are hidden
  Stream<List<Product>> publishedProductsStream() =>
      _products.where('status', isEqualTo: 'published')
          .orderBy('name').snapshots().map(
              (s) => s.docs.map(Product.fromFirestore).toList());

  Future<void> addProduct(Product p) =>
      _products.add(p.toFirestore());

  Future<void> updateProduct(Product p) =>
      _products.doc(p.id).update(p.toFirestore());

  Future<void> deleteProduct(String productId) =>
      _products.doc(productId).delete();

  Future<void> updateStock(String productId, int newStock) =>
      _products.doc(productId).update({'stock': newStock});

  // ── Catalog ────────────────────────────────────────────────────────────────

  Stream<List<CatalogProduct>> catalogStream() =>
      _catalog.orderBy('name').snapshots().map(
              (s) => s.docs.map(CatalogProduct.fromFirestore).toList());

  Future<void> addCatalogProduct(CatalogProduct p) =>
      _catalog.add(p.toFirestore());

  Future<void> updateCatalogProduct(CatalogProduct p) =>
      _catalog.doc(p.id).update(p.toFirestore());

  Future<void> deleteCatalogProduct(String id) =>
      _catalog.doc(id).delete();

  Future<void> linkBarcodeToCatalog(String catalogId, String barcode) =>
      _catalog.doc(catalogId).update({'barcode': barcode});

  Future<void> recordSale(StoreTransaction tx) async {
    return _db.runTransaction((transaction) async {
      // 1. Verify stock for all items within the transaction (Server-side check)
      for (final item in tx.items) {
        final productDoc = await transaction.get(_products.doc(item.productId));
        if (!productDoc.exists) throw Exception('Product ${item.name} does not exist.');
        
        final data = (productDoc.data() as Map<String, dynamic>?) ?? {};
        
        if (item.variantId != null) {
          final variants = data['variants'] as Map? ?? {};
          final vData = variants[item.variantId] as Map? ?? {};
          final int stock = (vData['stock'] as num? ?? 0).toInt();
          if (stock < item.qty) throw Exception('Insufficient stock for ${item.name} (${vData['name']}). Only $stock left.');
        } else {
          final int stock = (data['stock'] as num? ?? 0).toInt();
          if (stock < item.qty) throw Exception('Insufficient stock for ${item.name}. Only $stock left.');
        }

        if (data['status'] == 'draft') throw Exception('Product ${item.name} is no longer available.');
      }

      // 2. Perform updates
      transaction.set(_transactions.doc(tx.id), tx.toFirestore());

      for (final item in tx.items) {
        if (item.variantId != null) {
          transaction.update(_products.doc(item.productId), {
            'variants.${item.variantId}.stock': FieldValue.increment(-item.qty),
          });
        } else {
          transaction.update(_products.doc(item.productId), {
            'stock': FieldValue.increment(-item.qty),
          });
        }
      }

      if (tx.customerId != null) {
        transaction.set(_customers.doc(tx.customerId), {
          'totalSpent':    FieldValue.increment(tx.total),
          'lastVisit':     FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }).catchError((e) {
      throw Exception('Failed to record sale: $e');
    });
  }

  Future<void> decrementStockBatch(List<CartItem> items) async {
    return _db.runTransaction((transaction) async {
      for (final item in items) {
        final productDoc = await transaction.get(_products.doc(item.productId));
        if (!productDoc.exists) continue;

        final data = productDoc.data() as Map<String, dynamic>;

        if (item.variantId != null) {
          final variants = data['variants'] as Map? ?? {};
          final vData = variants[item.variantId] as Map? ?? {};
          final int stock = (vData['stock'] as num? ?? 0).toInt();
          // We allow decrement if it's already negative from a previous error, 
          // but we prioritize preventing it during the transaction.
          if (stock < item.qty && item.qty > 0) throw Exception('Insufficient stock for ${item.name}.');

          transaction.update(_products.doc(item.productId), {
            'variants.${item.variantId}.stock': FieldValue.increment(-item.qty),
          });
        } else {
          final int stock = (data['stock'] as num? ?? 0).toInt();
          if (stock < item.qty && item.qty > 0) throw Exception('Insufficient stock for ${item.name}.');

          transaction.update(_products.doc(item.productId), {
            'stock': FieldValue.increment(-item.qty),
          });
        }
      }
    }).catchError((e) {
      throw Exception('Failed to update stock: $e');
    });
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

  Stream<List<Supplier>> suppliersStream() =>
      _suppliers.orderBy('name').snapshots().map(
              (s) => s.docs.map(Supplier.fromFirestore).toList());

  Future<void> addSupplier(Supplier s) =>
      _suppliers.add(s.toFirestore());

  Future<void> updateSupplier(Supplier s) =>
      _suppliers.doc(s.id).update(s.toFirestore());

  Future<void> deleteSupplier(String id) =>
      _suppliers.doc(id).delete();

  // ── Loss & Waste ───────────────────────────────────────────────────────────

  Stream<List<LossRecord>> lossRecordsStream() =>
      _lossRecords.orderBy('createdAt', descending: true).snapshots().map(
              (s) => s.docs.map(LossRecord.fromFirestore).toList());

  Future<void> recordLoss(LossRecord record) async {
    final batch = _db.batch();
    batch.set(_lossRecords.doc(), record.toFirestore());
    batch.update(_products.doc(record.productId), {
      'stock': FieldValue.increment(-record.qty),
    });
    return batch.commit();
  }

  // ── Orders ─────────────────────────────────────────────────────────────────

  Stream<List<PreOrder>> ordersStream() =>
      _orders.snapshots().map(
              (s) => s.docs.map(PreOrder.fromFirestore).toList());

  Stream<List<PreOrder>> ordersStreamForEmail(String email) =>
      _orders
          .where('customerEmail', isEqualTo: email)
          .snapshots()
          .map((s) => s.docs.map(PreOrder.fromFirestore).toList());

  Future<DocumentReference> addOrder(PreOrder order) =>
      _orders.add(order.toFirestore());

  Future<void> updateOrder(PreOrder order) =>
      _orders.doc(order.id).update(order.toFirestore());

  Future<void> updateOrderStatus(String orderId, OrderStatus status, {String? reason}) =>
      _orders.doc(orderId).update({
        'status': status.name,
        if (reason != null) 'rejectionReason': reason,
      });

  // ── Transactions ───────────────────────────────────────────────────────────

  Stream<List<StoreTransaction>> transactionsStream() =>
      _transactions.snapshots().map(
              (s) => s.docs.map(StoreTransaction.fromFirestore).toList());

  Future<void> addTransaction(StoreTransaction tx) =>
      _transactions.add(tx.toFirestore());

  // ── Expenses ───────────────────────────────────────────────────────────────

  Stream<List<Expense>> expensesStream() =>
      _expenses.snapshots().map(
              (s) => s.docs.map(Expense.fromFirestore).toList());

  Future<void> addExpense(Expense e) =>
      _expenses.add(e.toFirestore());

  // ── Customers ──────────────────────────────────────────────────────────────

  Stream<List<Customer>> customersStream() =>
      _customers.orderBy('name').snapshots().map(
              (s) => s.docs.map((d) => Customer.fromMap(d.id, d.data() as Map<String, dynamic>)).toList());

  Future<void> addCustomer(Customer c) =>
      _customers.add(c.toMap());

  Future<void> updateCustomer(Customer c) =>
      _customers.doc(c.id).update(c.toMap());

  Future<void> deleteCustomer(String id) =>
      _customers.doc(id).delete();

  Future<Customer?> getCustomerByEmail(String email) async {
    final snap = await _customers.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Customer.fromMap(snap.docs.first.id, snap.docs.first.data() as Map<String, dynamic>);
  }

  // ── Refund Requests ────────────────────────────────────────────────────────

  Stream<List<RefundRequest>> refundRequestsStream() =>
      _refundRequests.snapshots().map(
              (s) => s.docs.map(RefundRequest.fromFirestore).toList());

  Future<void> updateRefundStatus(String requestId, RefundStatus status, String adminEmail, {String? reason, String? notes}) =>
      _refundRequests.doc(requestId).update({
        'status': status.name,
        'processedByEmail': adminEmail,
        if (reason != null) 'rejectionReason': reason,
        if (notes != null) 'adminNotes': notes,
      });

  Future<void> processApprovedRefund(RefundRequest request, String adminEmail) async {
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
              'variants.${item.variantId}.stock': FieldValue.increment(item.qty),
            });
          } else {
            batch.update(_products.doc(item.productId), {
              'stock': FieldValue.increment(item.qty),
            });
          }
        } else {
          final lossDoc = _lossRecords.doc();
          batch.set(lossDoc, {
            'productId':   item.productId,
            'productName': item.name,
            'qty':         item.qty,
            'unitPrice':   item.price,
            'type':        request.condition == RefundCondition.expired ? 'expired' : 'damaged',
            'notes':       'Refund Return: ${request.reason}',
            'createdAt':   FieldValue.serverTimestamp(),
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

  // ── Product Watches ────────────────────────────────────────────────────────

  Future<List<String>> getWatchersForProduct(String productId) async {
    final snap = await _db.collection('watched_products')
        .where('productId', isEqualTo: productId)
        .get();
    return snap.docs.map((d) => d.data()['email'] as String).toList();
  }

  Future<void> removeWatchesForProduct(String productId) async {
    final snap = await _db.collection('watched_products')
        .where('productId', isEqualTo: productId)
        .get();
    final batch = _db.batch();
    for (var doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ── Bundles ────────────────────────────────────────────────────────────────

  Stream<List<ProductBundle>> bundlesStream() =>
      _bundles.snapshots().map((s) => s.docs.map(ProductBundle.fromFirestore).toList());

  Future<void> saveBundle(ProductBundle b) {
    if (b.id.isEmpty) return _bundles.add(b.toFirestore());
    return _bundles.doc(b.id).update(b.toFirestore());
  }

  Future<void> deleteBundle(String id) => _bundles.doc(id).delete();

  // ── Restock Inquiries ──────────────────────────────────────────────────────

  Stream<List<RestockInquiry>> restockInquiriesStream() =>
      _restockInquiries.orderBy('createdAt', descending: true).snapshots().map(
              (s) => s.docs.map(RestockInquiry.fromFirestore).toList());

  Future<void> addRestockInquiry(RestockInquiry ri) =>
      _restockInquiries.add(ri.toFirestore());

  Future<void> updateRestockInquiry(RestockInquiry ri) =>
      _restockInquiries.doc(ri.id).update(ri.toFirestore());

  Future<void> deleteRestockInquiry(String id) =>
      _restockInquiries.doc(id).delete();

  Future<void> updateRestockInquiryStatus(String id, RestockInquiryStatus status, {DateTime? sentAt}) =>
      _restockInquiries.doc(id).update({
        'status': status.name,
        if (sentAt != null) 'sentAt': Timestamp.fromDate(sentAt),
      });
}
