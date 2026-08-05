import 'package:flutter/material.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/promotion.dart';
import '../models/transaction.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../utils/pricing_engine.dart';

class OrderProvider extends ChangeNotifier {
  final _fs = FirestoreService();
  final List<StreamSubscription> _subs = [];

  List<PreOrder> _orders  = [];
  List<Promotion> _promotions = [];
  final List<CartItem> _preCart = [];
  Timer? _expirationTimer;

  List<PreOrder> get orders  => _orders;
  List<Promotion> get promotions => _promotions;
  List<CartItem> get preCart => _preCart;

  // Stream that auto-updates for admin view
  Stream<List<PreOrder>>? _ordersStream;
  Stream<List<PreOrder>> get ordersStream => _ordersStream ??= _fs.ordersStream().asBroadcastStream();

  void initialize() {
    cancelSubscriptions();
    _ordersStream = null;

    _subs.add(ordersStream.listen((list) {
      _orders = list;
      _checkExpirations(list);
      notifyListeners();
    }, onError: (e) => debugPrint('Orders Stream Error: $e')));

    _subs.add(_fs.promotionsStream().listen((list) {
      _promotions = list;
      notifyListeners();
    }, onError: (e) => debugPrint('Promotions Stream Error: $e')));
    
    // Start a timer to check expirations every minute
    _expirationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkExpirations(_orders);
    });
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
    _expirationTimer?.cancel();
    super.dispose();
  }

  void _checkExpirations(List<PreOrder> list) {
    final now = DateTime.now();
    for (final order in list) {
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
    bool isSeniorPWD = false,
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

    final total = _preCart.fold(0.0, (s, i) => s + i.price * i.qty);
    
    // Calculate breakdown using PricingEngine
    final breakdown = PricingEngine.calculate(
      items: _preCart, 
      allProducts: allProducts, 
      activePromos: _promotions,
    );

    final order = PreOrder(
      id:            const Uuid().v4(),
      orderId:       'GDC-${orderCount.toString().padLeft(4, '0')}',
      customerName:  customerName,
      customerEmail: customerEmail,
      items:         List.from(_preCart),
      subtotal:      breakdown.subtotal,
      discount:      breakdown.promoDiscount + breakdown.seniorDiscount,
      tax:           breakdown.vAtAmount,
      total:         breakdown.total,
      status:        OrderStatus.pending,
      notes:         notes,
      location:      location,
      pickupTime:    pickupSlot,
      createdAt:     DateTime.now(),
      expiresAt:     expiresAt,
      isSeniorPWD:   isSeniorPWD,
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

  Future<void> advanceStatus(String orderId) async {
    final order = _orders.firstWhere((o) => o.id == orderId);
    final next  = switch (order.status) {
      OrderStatus.pending  => OrderStatus.staging,
      OrderStatus.staging  => OrderStatus.ready,
      OrderStatus.ready    => OrderStatus.collected,
      _ => null,
    };
    if (next == null) return;

    // Deduct stock when admin starts packing (moves to staging)
    if (next == OrderStatus.staging) {
      await _fs.decrementStockBatch(order.items);
    }

    await _fs.updateOrderStatus(orderId, next);

    // Record as transaction when collected
    if (next == OrderStatus.collected) {
      final tx = StoreTransaction(
        id: const Uuid().v4(), 
        items: order.items,
        total: order.total,
        cash: order.total,
        change: 0,
        createdAt: DateTime.now(),
        customerEmail: order.customerEmail,
      );
      await _fs.addTransaction(tx);

      // Award points for collected pre-order
      _awardPointsForPreOrder(order);
    }

    // Notify customer when order is ready
    if (next == OrderStatus.ready) {
      await NotificationService.sendOrderReady(order.orderId);
    }
  }

  void _awardPointsForPreOrder(PreOrder order) async {
    final customer = await _fs.getCustomerByEmail(order.customerEmail);
    if (customer != null) {
      final points = (order.total / 100).floor();
      if (points > 0) {
        await _fs.updateCustomerPoints(customer.id, points);
      }
    }
  }

  Future<void> cancelOrder(String orderId, {bool isAuto = false}) async {
    final order = _orders.firstWhere((o) => o.id == orderId);
    if (order.status == OrderStatus.cancelled) return;

    // If order was already packed/ready/collected, replenish stock on cancel
    if (order.status == OrderStatus.staging ||
        order.status == OrderStatus.ready ||
        order.status == OrderStatus.collected) {
      // Create inverted cart items to "increment" stock
      final returnItems = order.items.map((i) => i.copyWith(qty: -i.qty)).toList();
      await _fs.decrementStockBatch(returnItems);
    }

    await _fs.updateOrderStatus(orderId, OrderStatus.cancelled);

    if (isAuto) {
      await NotificationService.sendOrderAutoCancelled(order.orderId);
    }
  }
}
