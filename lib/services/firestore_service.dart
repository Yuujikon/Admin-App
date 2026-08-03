import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import '../models/expense.dart';
import '../models/refund_request.dart';
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

  // ── Products ───────────────────────────────────────────────────────────────

  // Real-time stream — widgets rebuild automatically on changes
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
    
    // 1. Record transaction
    batch.set(_transactions.doc(tx.id), tx.toFirestore());

    // 2. Decrement stock
    for (final item in tx.items) {
      batch.update(_products.doc(item.productId), {
        'stock': FieldValue.increment(-item.qty),
      });
    }

    // 3. Award Loyalty Points (1 pt per 100 PHP) and Lifetime Stats
    if (tx.customerId != null) {
      final points = (tx.total / 100).floor();
      batch.update(_customers.doc(tx.customerId), {
        'loyaltyPoints': FieldValue.increment(points),
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
    // 1. Delete the transaction record (or mark as refunded)
    batch.delete(_transactions.doc(tx.id));

    // 2. Return items to stock
    for (final item in tx.items) {
      batch.update(_products.doc(item.productId), {
        'stock': FieldValue.increment(item.qty),
      });
    }

    // 3. Deduct awarded Loyalty Points
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
    
    // 1. Log the loss
    batch.set(_lossRecords.doc(), record.toFirestore());

    // 2. Decrement stock
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

  Future<void> updateCustomerPoints(String id, int delta) =>
      _customers.doc(id).update({'loyaltyPoints': FieldValue.increment(delta)});

  // ── Refund Requests ────────────────────────────────────────────────────────

  Stream<List<RefundRequest>> refundRequestsStream() =>
      _refundRequests.orderBy('createdAt', descending: true).snapshots().map(
              (s) => s.docs.map(RefundRequest.fromFirestore).toList());

  // Added based on requirements
  Stream<List<RefundRequest>> getRefundQueue() {
    return _refundRequests
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(RefundRequest.fromFirestore).toList());
  }

  Future<void> updateRefundStatus(String requestId, RefundStatus status, String adminEmail, {String? reason}) =>
      _refundRequests.doc(requestId).update({
        'status': status.name,
        'processedByEmail': adminEmail,
        if (reason != null) 'rejectionReason': reason,
      });

  Future<void> processApprovedRefund(RefundRequest request, String adminEmail) {
    final batch = _db.batch();
    
    // 1. Mark request as approved and record who did it
    batch.update(_refundRequests.doc(request.id), {
      'status': RefundStatus.approved.name,
      'processedByEmail': adminEmail,
    });

    // 2. Return items to stock
    for (final item in request.items) {
      batch.update(_products.doc(item.productId), {
        'stock': FieldValue.increment(item.qty),
      });
    }

    // 3. Update the original order status to 'refunded'
    // We search for the order by its orderId (transactionId in the request)
    // Note: Since we don't have the order document ID here directly, 
    // we use a where query in the provider or just update the order if we had its ID.
    // Better yet, update the order inside the batch if we find it.

    return batch.commit();
  }
}