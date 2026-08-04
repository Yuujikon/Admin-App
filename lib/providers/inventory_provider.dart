import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/bundle.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import '../models/refund_request.dart';
import '../models/store_settings.dart';
import '../models/supplier.dart';
import '../models/loss_record.dart';
import '../models/customer.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class InventoryProvider extends ChangeNotifier {
  final _fs = FirestoreService();
  final List<StreamSubscription> _subs = [];

  List<Product>          _products       = [];
  List<StoreTransaction> _transactions    = [];
  List<RefundRequest>    _refundRequests = [];
  List<Supplier>         _suppliers      = [];
  List<LossRecord>       _lossRecords    = [];
  List<Customer>         _customers      = [];
  List<ProductBundle>    _bundles        = [];
  StoreSettings          _settings       = const StoreSettings(isClosed: false);
  String                 _adminName      = 'Admin';

  List<Product>          get products       => _products;
  List<StoreTransaction> get transactions    => _transactions;
  List<RefundRequest>    get refundRequests => _refundRequests;
  List<Supplier>         get suppliers      => _suppliers;
  List<LossRecord>       get lossRecords    => _lossRecords;
  List<Customer>         get customers      => _customers;
  List<ProductBundle>    get bundles        => _bundles;
  StoreSettings          get settings       => _settings;
  String                 get adminName      => _adminName;

  List<Product>? _cachedSortedProducts;
  DateTime?      _lastSortTime;

  // ── Sorting Logic ──────────────────────────────────────────────────────────

  /// Returns products sorted by sales volume (Last 30 Days)
  /// Fast-moving first, slow-moving later.
  List<Product> get sortedProducts {
    if (_products.isEmpty) return [];
    
    // Cache for 1 minute or until data changes
    if (_cachedSortedProducts != null && 
        _lastSortTime != null && 
        DateTime.now().difference(_lastSortTime!).inMinutes < 1) {
      return _cachedSortedProducts!;
    }

    if (_transactions.isEmpty) return _products;

    // 1. Calculate sales volume per product name in the last 30 days
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final recentCounts = <String, int>{};
    
    for (final tx in _transactions) {
      if (tx.createdAt.isAfter(thirtyDaysAgo)) {
        for (final item in tx.items) {
          recentCounts[item.productId] = (recentCounts[item.productId] ?? 0) + item.qty;
        }
      }
    }

    // 2. Sort the products list based on these counts
    final sorted = List<Product>.from(_products);
    sorted.sort((a, b) {
      // REQUIREMENT 14: SORTING
      // Available (stock > threshold) first, then Low Stock, then Out of Stock (0).
      
      int getSortOrder(Product p) {
        if (p.stock <= 0) return 3; // Out of stock last
        if (p.stock <= p.lowStockThreshold) return 2; // Low stock second
        return 1; // Available first
      }

      final orderA = getSortOrder(a);
      final orderB = getSortOrder(b);

      if (orderA != orderB) return orderA.compareTo(orderB);

      // Within same status, sort by sales volume (existing logic)
      final countA = recentCounts[a.id] ?? 0;
      final countB = recentCounts[b.id] ?? 0;
      return countB.compareTo(countA);
    });

    _cachedSortedProducts = sorted;
    _lastSortTime = DateTime.now();
    return sorted;
  }

  // Movement Insights (Last 30 Days)
  Map<String, int>? _cachedRecentCounts;
  List<MapEntry<String, int>> get fastMovingItems {
    if (_transactions.isEmpty) return [];
    
    if (_cachedRecentCounts != null) {
      final entries = _cachedRecentCounts!.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return entries;
    }

    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final counts = <String, int>{};
    for (final tx in _transactions) {
      if (tx.createdAt.isAfter(thirtyDaysAgo)) {
        for (final item in tx.items) {
          counts[item.name] = (counts[item.name] ?? 0) + item.qty;
        }
      }
    }
    _cachedRecentCounts = counts;
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  List<Product> get slowMovingItems {
    final counts = _cachedRecentCounts ?? {};
    if (counts.isEmpty && _transactions.isNotEmpty) {
      // Force a calculation of recent counts if it's missing but we have transactions
      final _ = fastMovingItems; 
    }
    
    final slow = _products
        .where((p) => (counts[p.name] ?? 0) <= 2)
        .toList();
    slow.sort((a, b) => (counts[a.name] ?? 0).compareTo(counts[b.name] ?? 0));
    return slow;
  }

  Map<String, int> get recentMovementCounts => _cachedRecentCounts ?? {};

  void initialize() {
    cancelSubscriptions();
    _cachedSortedProducts = null; 
    _cachedRecentCounts = null;

    _subs.add(_fs.productsStream().listen((list) {
      _products = list;
      _cachedSortedProducts = null;
      notifyListeners();
    }, onError: (e) => debugPrint('Inventory Stream Error: $e')));

    _subs.add(_fs.transactionsStream().listen((list) {
      _transactions = list;
      _cachedSortedProducts = null;
      _cachedRecentCounts = null; // Invalidate movement counts
      notifyListeners();
    }, onError: (e) => debugPrint('Transactions Stream Error: $e')));

    _subs.add(_fs.refundRequestsStream().listen((list) {
      // Check for new pending requests to show a notification
      if (_refundRequests.isNotEmpty && list.length > _refundRequests.length) {
        final newOnes = list.where((req) => 
          req.status == RefundStatus.pending && 
          !_refundRequests.any((old) => old.id == req.id)
        );
        for (var req in newOnes) {
          NotificationService.showRefundRequestAlert(req.transactionId, req.customerName);
        }
      }
      _refundRequests = list;
      notifyListeners();
    }, onError: (e) => debugPrint('RefundRequests Stream Error: $e')));

    _subs.add(_fs.suppliersStream().listen((list) {
      _suppliers = list;
      notifyListeners();
    }, onError: (e) => debugPrint('Suppliers Stream Error: $e')));

    _subs.add(_fs.lossRecordsStream().listen((list) {
      _lossRecords = list;
      notifyListeners();
    }, onError: (e) => debugPrint('LossRecords Stream Error: $e')));

    _subs.add(_fs.customersStream().listen((list) {
      _customers = list;
      notifyListeners();
    }, onError: (e) => debugPrint('Customers Stream Error: $e')));

    _subs.add(_fs.bundlesStream().listen((list) {
      _bundles = list;
      notifyListeners();
    }, onError: (e) => debugPrint('Bundles Stream Error: $e')));

    _subs.add(_fs.settingsStream().listen((settings) {
      _settings = settings;
      notifyListeners();
    }, onError: (e) => debugPrint('Settings Stream Error: $e')));
  }

  void cancelSubscriptions() {
    for (var s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    cancelSubscriptions();
    super.dispose();
  }

  Future<void> toggleStoreStatus(bool isClosed, {String? message, DateTime? closeAt, DateTime? openAt}) async {
    await _fs.updateStoreStatus(isClosed, message: message, closeAt: closeAt, openAt: openAt);
  }

  Future<void> saveStoreSettings(StoreSettings s) async {
    await _fs.saveStoreSettings(s);
  }

  void setAdminEmail(String name) {
    _adminName = name;
    notifyListeners();
  }

  Future<void> saveProduct(Product product) async {
    // Check for stock increase for notifications
    if (product.id.isNotEmpty) {
      try {
        final old = _products.firstWhere((p) => p.id == product.id);
        if (old.stock <= 0 && product.stock > 0) {
          _notifyBackInStock(product);
        }
      } catch (_) {}
    }

    if (product.id.isEmpty) {
      await _fs.addProduct(product);
    } else {
      await _fs.updateProduct(product);
    }
  }

  void _notifyBackInStock(Product p) async {
    final watchers = await _fs.getWatchersForProduct(p.id);
    if (watchers.isEmpty) return;

    for (var email in watchers) {
      await NotificationService.sendBackInStock(p.name, email);
    }
    
    // Clear watches after notifying
    await _fs.removeWatchesForProduct(p.id);
  }

  Future<void> deleteProduct(String id) async {
    await _fs.deleteProduct(id);
  }

  Future<void> saveSupplier(Supplier s) {
    if (s.id.isEmpty) return _fs.addSupplier(s);
    return _fs.updateSupplier(s);
  }

  Future<void> deleteSupplier(String id) async {
    await _fs.deleteSupplier(id);
  }

  Future<void> logLoss(LossRecord record) async {
    await _fs.recordLoss(record);
  }

  Future<void> saveCustomer(Customer c) {
    if (c.id.isEmpty) return _fs.addCustomer(c);
    return _fs.updateCustomer(c);
  }

  Future<void> deleteCustomer(String id) async {
    await _fs.deleteCustomer(id);
  }

  Future<void> adjustPoints(String customerId, int delta) async {
    await _fs.updateCustomerPoints(customerId, delta);
  }

  Future<void> saveBundle(ProductBundle b) => _fs.saveBundle(b);
  Future<void> deleteBundle(String id) => _fs.deleteBundle(id);

  Future<void> completeSale(List<CartItem> cart, double cash, {String? customerId, PaymentMethod paymentMethod = PaymentMethod.cash}) async {
    final total  = cart.fold(0.0, (s, i) => s + i.price * i.qty);
    final change = paymentMethod == PaymentMethod.cash ? (cash - total) : 0.0;

    final tx = StoreTransaction(
      id:        const Uuid().v4(),
      items:     cart,
      total:     total,
      cash:      paymentMethod == PaymentMethod.cash ? cash : 0.0,
      change:    change,
      createdAt: DateTime.now(),
      customerId: customerId,
      paymentMethod: paymentMethod,
    );

    await _fs.recordSale(tx);

    // Check for low stock after decrement
    for (var item in cart) {
      try {
        final p = _products.firstWhere((p) => p.id == item.productId);
        // If stock is now 5 or less
        if (p.stock - item.qty <= 5) {
          _notifySupplierLowStock(p);
        }
      } catch (_) {}
    }
  }

  void _notifySupplierLowStock(Product p) {
    if (p.supplierId == null) return;
    try {
      final supplier = _suppliers.firstWhere((s) => s.id == p.supplierId);
      if (supplier.autoNotifyLowStock) {
        NotificationService.showLowStockSupplierAlert(p.name, supplier.name, supplier.phone);
      }
    } catch (_) {}
  }

  Future<void> refundTransaction(StoreTransaction tx) async {
    await _fs.refundTransaction(tx);
  }

  Future<void> approveRefundRequest(RefundRequest request, {required RefundCondition condition}) async {
    // 1. Process the refund in Firestore (updates status and logs Loss)
    final updatedReq = RefundRequest(
      id: request.id,
      transactionId: request.transactionId,
      customerEmail: request.customerEmail,
      customerName: request.customerName,
      items: request.items,
      total: request.total,
      reason: request.reason,
      status: RefundStatus.approved,
      condition: condition,
      createdAt: request.createdAt,
      processedByEmail: _adminName,
    );

    await _fs.processApprovedRefund(updatedReq, _adminName);

    // 2. Find and update the original Order status if it exists
    final orderSnap = await FirebaseFirestore.instance.collection('orders')
        .where('orderId', isEqualTo: request.transactionId)
        .limit(1)
        .get();

    if (orderSnap.docs.isNotEmpty) {
      await _fs.updateOrderStatus(orderSnap.docs.first.id, OrderStatus.refunded);
    }

    // 3. Send notification to customer
    await NotificationService.sendRefundUpdate(request.transactionId, true);
  }

  Future<void> rejectRefundRequest(RefundRequest request, String reason) async {
    await _fs.updateRefundStatus(request.id, RefundStatus.rejected, _adminName, reason: reason);

    final orderSnap = await FirebaseFirestore.instance.collection('orders')
        .where('orderId', isEqualTo: request.transactionId)
        .limit(1)
        .get();

    if (orderSnap.docs.isNotEmpty) {
      await FirebaseFirestore.instance.collection('orders')
          .doc(orderSnap.docs.first.id)
          .update({
            'status': OrderStatus.refundRejected.name,
            'rejectionReason': reason,
          });
    }

    await NotificationService.sendRefundUpdate(request.transactionId, false);
  }
}