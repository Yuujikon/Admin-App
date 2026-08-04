import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import '../models/expense.dart';
import '../models/refund_request.dart';
import '../models/bundle.dart';
import '../models/promotion.dart';
import '../models/store_settings.dart';
import '../models/supplier.dart';
import '../models/loss_record.dart';
import '../models/customer.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // ── Collections ────────────────────────────────────────────────────────────
  CollectionReference get _products       => _db.collection('products');
  CollectionReference get _orders         => _db.collection('orders');
  CollectionReference get _transactions   => _db.collection('transactions');
  CollectionReference get _expenses       => _db.collection('expenses');
  CollectionReference get _refundRequests => _db.collection('refund_requests');
  CollectionReference get _suppliers      => _db.collection('suppliers');
  CollectionReference get _lossRecords    => _db.collection('loss_records');
  CollectionReference get _customers      => _db.collection('customers');
  CollectionReference get _promotions     => _db.collection('promotions');
  CollectionReference get _bundles        => _db.collection('bundles');
  DocumentReference   get _settings       => _db.collection('settings').doc('store_settings');

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

  Future<void> addProduct(Product p) =>
      _products.add(p.toFirestore());

  Future<void> updateProduct(Product p) =>
      _products.doc(p.id).update(p.toFirestore());

  Future<void> deleteProduct(String productId) =>
      _products.doc(productId).delete();

  Future<void> updateStock(String productId, int newStock) =>
      _products.doc(productId).update({'stock': newStock});

  Future<void> recordSale(StoreTransaction tx) {
    final batch = _db.batch();
    
    batch.set(_transactions.doc(tx.id), tx.toFirestore());

    for (final item in tx.items) {
      batch.update(_products.doc(item.productId), {
        'stock': FieldValue.increment(-item.qty),
      });
    }

    if (tx.customerId != null) {
      final pointsAwarded = (tx.total / 100).floor();
      final netPoints = pointsAwarded - tx.pointsRedeemed;
      
      batch.update(_customers.doc(tx.customerId), {
        'loyaltyPoints': FieldValue.increment(netPoints),
        'totalSpent':    FieldValue.increment(tx.total),
        'lastVisit':     FieldValue.serverTimestamp(),
      });
    }

    return batch.commit();
  }

  Future<void> decrementStockBatch(List<CartItem> items) {
    final batch = _db.batch();
    for (final item in items) {
      batch.update(_products.doc(item.productId), {
        'stock': FieldValue.increment(-item.qty),
      });
    }
    return batch.commit();
  }

  Future<void> refundTransaction(StoreTransaction tx) {
    final batch = _db.batch();
    batch.delete(_transactions.doc(tx.id));

    for (final item in tx.items) {
      batch.update(_products.doc(item.productId), {
        'stock': FieldValue.increment(item.qty),
      });
    }

    if (tx.customerId != null) {
      final points = (tx.total / 100).floor();
      if (points > 0) {
        batch.update(_customers.doc(tx.customerId), {
          'loyaltyPoints': FieldValue.increment(-points),
        });
      }
    }

    return batch.commit();
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
      _orders.orderBy('createdAt', descending: true).snapshots().map(
              (s) => s.docs.map(PreOrder.fromFirestore).toList());

  Stream<List<PreOrder>> ordersStreamForEmail(String email) =>
      _orders
          .where('customerEmail', isEqualTo: email)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(PreOrder.fromFirestore).toList());

  Future<DocumentReference> addOrder(PreOrder order) =>
      _orders.add(order.toFirestore());

  Future<void> updateOrderStatus(String orderId, OrderStatus status) =>
      _orders.doc(orderId).update({'status': status.name});

  // ── Transactions ───────────────────────────────────────────────────────────

  Stream<List<StoreTransaction>> transactionsStream() =>
      _transactions.orderBy('createdAt', descending: true).snapshots().map(
              (s) => s.docs.map(StoreTransaction.fromFirestore).toList());

  Future<void> addTransaction(StoreTransaction tx) =>
      _transactions.add(tx.toFirestore());

  // ── Expenses ───────────────────────────────────────────────────────────────

  Stream<List<Expense>> expensesStream() =>
      _expenses.orderBy('createdAt', descending: true).snapshots().map(
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

  Future<void> updateCustomerPoints(String id, int delta) =>
      _customers.doc(id).update({'loyaltyPoints': FieldValue.increment(delta)});

  // ── Refund Requests ────────────────────────────────────────────────────────

  Stream<List<RefundRequest>> refundRequestsStream() =>
      _refundRequests.orderBy('createdAt', descending: true).snapshots().map(
              (s) => s.docs.map(RefundRequest.fromFirestore).toList());

  Future<void> updateRefundStatus(String requestId, RefundStatus status, String adminEmail, {String? reason}) =>
      _refundRequests.doc(requestId).update({
        'status': status.name,
        'processedByEmail': adminEmail,
        if (reason != null) 'rejectionReason': reason,
      });

  Future<void> processApprovedRefund(RefundRequest request, String adminEmail) {
    final batch = _db.batch();
    
    batch.update(_refundRequests.doc(request.id), {
      'status': RefundStatus.approved.name,
      'processedByEmail': adminEmail,
    });

    for (final item in request.items) {
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

    return batch.commit();
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

  // ── Promotions ─────────────────────────────────────────────────────────────

  Stream<List<Promotion>> promotionsStream() =>
      _promotions.snapshots().map((s) => s.docs.map(Promotion.fromFirestore).toList());

  Future<void> savePromotion(Promotion p) {
    if (p.id.isEmpty) return _promotions.add(p.toFirestore());
    return _promotions.doc(p.id).update(p.toFirestore());
  }

  Future<void> deletePromotion(String id) => _promotions.doc(id).delete();
}
