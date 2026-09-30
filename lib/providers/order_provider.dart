import 'package:flutter/material.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../utils/pricing_engine.dart';

import 'base_provider.dart';

class OrderProvider extends BaseProvider {
  final _fs = FirestoreService();

  List<PreOrder> _orders  = [];
  final List<CartItem> _preCart = [];
  Timer? _expirationTimer;
  String _adminName = 'Admin';
  final Set<String> _processingOrders = {};
  final Set<String> _knownOrderIds = {};

  final StreamController<PreOrder> _newOrderStreamController = StreamController<PreOrder>.broadcast();
  Stream<PreOrder> get onNewOrderReceived => _newOrderStreamController.stream;

  final Set<String> _newlyArrivedOrderIds = {};

  List<PreOrder> get orders  => _orders;
  List<CartItem> get preCart => _preCart;
  String get adminName => _adminName;

  bool isOrderProcessing(String orderId) => _processingOrders.contains(orderId);
  bool isNewlyArrived(String orderId) => _newlyArrivedOrderIds.contains(orderId);

  void clearNewlyArrived(String orderId) {
    if (_newlyArrivedOrderIds.remove(orderId)) {
      notifyListeners();
    }
  }

  void clearAllNewlyArrived() {
    if (_newlyArrivedOrderIds.isNotEmpty) {
      _newlyArrivedOrderIds.clear();
      notifyListeners();
    }
  }

  void setAdminName(String name) {
    _adminName = name;
    notifyListeners();
  }

  // Stream that auto-updates for admin view
  Stream<List<PreOrder>> get ordersStream => _fs.ordersStream();

  void initialize() {
    cancelSubscriptions();
    setLoading(true);

    registerSubscription(_fs.ordersStream().listen((list) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (_knownOrderIds.isNotEmpty) {
        final newOrders = list.where((o) => !_knownOrderIds.contains(o.id) && o.status == OrderStatus.pending);
        for (final o in newOrders) {
          _newlyArrivedOrderIds.add(o.id);
          _newOrderStreamController.add(o);
          NotificationService.showSmsNotificationPopUp(
            title: '🛍️ New Pre-Order Received!',
            body: 'Customer ${o.customerName} placed order #${o.orderId} (₱${o.total.toStringAsFixed(2)}).',
          );
        }
      }
      _knownOrderIds.clear();
      _knownOrderIds.addAll(list.map((o) => o.id));

      _orders = list;
      setLoading(false);
      notifyListeners();
      _checkExpirations(list);
    }, onError: (e) {
      setLoading(false);
      debugPrint('Orders Stream Error: $e. Reconnecting in 3 seconds...');
      Timer(const Duration(seconds: 3), () {
        if (!isDisposed) {
          initialize();
        }
      });
    }));
    
    // Start a timer to check expirations every minute
    _expirationTimer?.cancel();
    _expirationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkExpirations(_orders);
    });
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    _newOrderStreamController.close();
    super.dispose();
  }

  void _checkExpirations(List<PreOrder> list) {
    final now = DateTime.now();
    for (final order in list) {
      if (_processingOrders.contains(order.id)) continue;
      
      if (order.status == OrderStatus.pending || 
          order.status == OrderStatus.staging || 
          order.status == OrderStatus.ready) {
        
        if (order.expiresAt != null && order.expiresAt!.isBefore(now)) {
          // Auto cancel expired order
          cancelOrder(order.id, isAuto: true);
        }
      }
    }
  }

  // ── Pre-order cart ─────────────────────────────────────────────────────────

  void addToPreCart(Product p) {
    final idx = _preCart.indexWhere((i) => i.productId == p.id);
    if (idx >= 0) {
      _preCart[idx] = _preCart[idx].copyWith(qty: (_preCart[idx].qty + 1).clamp(1, p.stock));
    } else {
      _preCart.add(CartItem(productId: p.id, name: p.name, price: p.price, qty: 1));
    }
    notifyListeners();
  }

  void removeFromPreCart(String productId) {
    _preCart.removeWhere((i) => i.productId == productId);
    notifyListeners();
  }

  void adjustPreCartQty(String productId, int delta) {
    final idx = _preCart.indexWhere((i) => i.productId == productId);
    if (idx < 0) return;
    _preCart[idx] = _preCart[idx].copyWith(qty: (_preCart[idx].qty + delta).clamp(1, 9999));
    notifyListeners();
  }

  void setPreCartQty(String productId, int qty) {
    final idx = _preCart.indexWhere((i) => i.productId == productId);
    if (idx < 0) return;
    _preCart[idx] = _preCart[idx].copyWith(qty: qty.clamp(1, 9999));
    notifyListeners();
  }

  // ── Submit order ───────────────────────────────────────────────────────────

  Future<PreOrder> submitOrder({
    required String customerName,
    required String customerEmail,
    required String notes,
    required String location,
    required String pickupSlot,
    required List<Product> allProducts,
  }) async {
    final orderCount = _orders.length + 45;
    // Determine expiration based on items
    final hasPerishables = _preCart.any((ci) => 
        allProducts.any((p) => p.id == ci.productId && p.isPerishable));
    final onlyPerishables = _preCart.every((ci) => 
        allProducts.any((p) => p.id == ci.productId && p.isPerishable));
    
    DateTime expiresAt;
    if (onlyPerishables) {
      expiresAt = DateTime.now().add(const Duration(hours: 2));
    } else if (hasPerishables) {
      expiresAt = DateTime.now().add(const Duration(days: 1));
    } else {
      expiresAt = DateTime.now().add(const Duration(days: 3));
    }

    // Calculate breakdown using PricingEngine
    final breakdown = PricingEngine.calculate(
      items: _preCart, 
      allProducts: allProducts, 
    );

    final order = PreOrder(
      id:            const Uuid().v4(),
      orderId:       'GDC-${orderCount.toString().padLeft(4, '0')}',
      customerName:  customerName,
      customerEmail: customerEmail,
      items:         List.from(_preCart),
      subtotal:      breakdown.subtotal,
      tax:           breakdown.vAtAmount,
      total:         breakdown.total,
      status:        OrderStatus.pending,
      notes:         notes,
      location:      location,
      pickupTime:    pickupSlot,
      createdAt:     DateTime.now(),
      expiresAt:     expiresAt,
      statusTimeline: {OrderStatus.pending.name: DateTime.now()},
    );

    await _fs.addOrder(order);

    // Schedule perishable auto-cancel via Firebase Cloud Functions
    // (see Cloud Functions section below)
    final hasPerishable = _preCart.any((ci) =>
        allProducts.any((p) => p.id == ci.productId && p.isPerishable));
    if (hasPerishable) {
      await NotificationService.schedulePerishableReminder(order.id, order.orderId);
    }

    _preCart.clear();
    notifyListeners();
    return order;
  }

  // ── Admin actions ──────────────────────────────────────────────────────────

  Future<void> completePickup(String orderId) async {
    if (_processingOrders.contains(orderId)) return;
    _processingOrders.add(orderId);
    notifyListeners();

    try {
      await _completePickupInternal(orderId);
    } finally {
      _processingOrders.remove(orderId);
      notifyListeners();
    }
  }

  Future<void> _completePickupInternal(String orderId) async {
    final order = _orders.firstWhere((o) => o.id == orderId);
    if (order.status == OrderStatus.collected || order.status == OrderStatus.cancelled) return;

    // 1. Ensure stock is deducted if not already done (done at 'staging' phase)
    if (order.status == OrderStatus.pending) {
      await _fs.decrementStockBatch(order.items);
    }

    // 2. Set final status
    final updatedOrder = order.copyWith(
      status: OrderStatus.collected,
      processedBy: _adminName,
    );
    await _fs.updateOrder(updatedOrder);

    // 3. Record as transaction
    final tx = StoreTransaction(
      id: const Uuid().v4(), 
      items: order.items,
      total: order.total,
      cashTendered: order.total,
      changeGiven: 0,
      createdAt: DateTime.now(),
      customerEmail: order.customerEmail,
      type: TransactionType.pickup,
    );
    await _fs.addTransaction(tx);

    // 4. Notify customer
    await NotificationService.sendOrderCollected(order.orderId, order.customerEmail);
  }

  /// Fast-checkout protocol for Click & Collect with strict cash tracking
  Future<StoreTransaction> completePickupWithCash({
    required String orderId,
    required double cashTendered,
    required double changeGiven,
    List<CartItem> walkInItems = const [],
  }) async {
    final order = _orders.firstWhere((o) => o.id == orderId);

    // 1. Ensure stock is deducted for pre-order items if pending
    if (order.status == OrderStatus.pending) {
      await _fs.decrementStockBatch(order.items);
    }

    // 2. Deduct stock for additional walk-in items
    if (walkInItems.isNotEmpty) {
      await _fs.decrementStockBatch(walkInItems);
    }

    final allItems = [...order.items, ...walkInItems];
    final grandTotal = allItems.fold<double>(0.0, (s, i) => s + (i.price * i.qty));

    // 3. Update Order status to collected
    final updatedOrder = order.copyWith(
      status: OrderStatus.collected,
      processedBy: _adminName,
    );
    await _fs.updateOrder(updatedOrder);

    // 4. Record StoreTransaction with exact cashTendered and changeGiven
    final tx = StoreTransaction(
      id: const Uuid().v4(),
      items: allItems,
      total: grandTotal,
      cashTendered: cashTendered,
      changeGiven: changeGiven,
      createdAt: DateTime.now(),
      customerEmail: order.customerEmail,
      paymentMethod: PaymentMethod.cash,
      type: TransactionType.pickup,
    );
    await _fs.addTransaction(tx);

    // 5. Notify customer
    await NotificationService.sendOrderCollected(order.orderId, order.customerEmail);
    return tx;
  }

  Future<void> advanceStatus(String orderId) async {
    if (_processingOrders.contains(orderId)) return;
    _processingOrders.add(orderId);
    notifyListeners();

    try {
      await _advanceStatusInternal(orderId);
    } finally {
      _processingOrders.remove(orderId);
      notifyListeners();
    }
  }

  Future<bool> _advanceStatusInternal(String orderId) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return false;
    final order = _orders[index];
    final next  = switch (order.status) {
      OrderStatus.pending  => OrderStatus.staging,
      OrderStatus.staging  => OrderStatus.ready,
      _ => null,
    };
    if (next == null) return false;

    // Deduct stock when admin starts packing (moves to staging)
    if (next == OrderStatus.staging) {
      await _fs.decrementStockBatch(order.items);
    }

    final updatedOrder = order.copyWith(
      status: next,
      processedBy: _adminName,
    );

    await _fs.updateOrder(updatedOrder);

    // Notify customer when order is ready
    if (next == OrderStatus.ready) {
      await NotificationService.sendOrderReady(order.orderId, order.customerEmail);
    }

    return true;
  }

  Future<void> cancelOrder(String orderId, {bool isAuto = false, String? reason}) async {
    if (_processingOrders.contains(orderId)) return;
    _processingOrders.add(orderId);
    
    try {
      await _cancelOrderInternal(orderId, isAuto: isAuto, reason: reason);
    } finally {
      _processingOrders.remove(orderId);
      notifyListeners();
    }
  }

  Future<void> _cancelOrderInternal(String orderId, {bool isAuto = false, String? reason}) async {
    final order = _orders.firstWhere((o) => o.id == orderId);
    if (order.status == OrderStatus.cancelled) return;

    // Replenish stock on cancellation for active orders (pending, staging, ready, collected)
    if (order.status == OrderStatus.pending ||
        order.status == OrderStatus.staging ||
        order.status == OrderStatus.ready ||
        order.status == OrderStatus.collected) {
      // Create inverted cart items to "increment" stock
      final returnItems = order.items.map((i) => i.copyWith(qty: -i.qty)).toList();
      await _fs.decrementStockBatch(returnItems);
    }

    final updatedOrder = order.copyWith(
      status: OrderStatus.cancelled,
      processedBy: isAuto ? 'System' : _adminName,
      rejectionReason: reason,
    );
    
    await _fs.updateOrder(updatedOrder);

    if (isAuto) {
      await NotificationService.sendOrderAutoCancelled(order.orderId, order.customerEmail);
    }
  }

  // ── Bulk Admin Actions ─────────────────────────────────────────────────────

  Future<int> bulkAdvanceStatus(List<String> orderIds) async {
    int count = 0;
    _processingOrders.addAll(orderIds);
    notifyListeners();

    try {
      for (final orderId in orderIds) {
        try {
          final success = await _advanceStatusInternal(orderId);
          if (success) count++;
        } catch (e) {
          debugPrint('Bulk advance error for $orderId: $e');
        }
      }
    } finally {
      _processingOrders.removeAll(orderIds);
      notifyListeners();
    }
    return count;
  }

  Future<int> bulkCompletePickup(List<String> orderIds) async {
    int count = 0;
    _processingOrders.addAll(orderIds);
    notifyListeners();

    try {
      for (final orderId in orderIds) {
        try {
          await _completePickupInternal(orderId);
          count++;
        } catch (e) {
          debugPrint('Bulk complete error for $orderId: $e');
        }
      }
    } finally {
      _processingOrders.removeAll(orderIds);
      notifyListeners();
    }
    return count;
  }

  Future<int> bulkCancelOrders(List<String> orderIds, {String? reason}) async {
    int count = 0;
    _processingOrders.addAll(orderIds);
    notifyListeners();

    try {
      for (final orderId in orderIds) {
        try {
          await _cancelOrderInternal(orderId, reason: reason);
          count++;
        } catch (e) {
          debugPrint('Bulk cancel error for $orderId: $e');
        }
      }
    } finally {
      _processingOrders.removeAll(orderIds);
      notifyListeners();
    }
    return count;
  }
}
