import 'package:flutter/material.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/loss_record.dart';
import '../models/transaction.dart';
import '../models/store_settings.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../shared/services/admin_messaging_service.dart';
import '../shared/services/time_service.dart';
import '../utils/pricing_engine.dart';
import '../utils/format.dart';

import 'base_provider.dart';

/// Provider for managing online customer pre-orders, order fulfillment workflow, and notification dispatching.
class OrderProvider extends BaseProvider {
  final _fs = FirestoreService();

  List<PreOrder> _orders = [];
  final List<CartItem> _preCart = [];
  Timer? _expirationTimer;
  String _adminName = 'Admin';
  final Set<String> _processingOrders = {};
  final Set<String> _knownOrderIds = {};
  final Set<String> _processedCancelledOrderIds = {};

  final StreamController<PreOrder> _newOrderStreamController =
      StreamController<PreOrder>.broadcast();

  /// Event stream emitting newly received customer pre-orders.
  Stream<PreOrder> get onNewOrderReceived => _newOrderStreamController.stream;

  final Set<String> _newlyArrivedOrderIds = {};

  /// Current pre-orders list.
  List<PreOrder> get orders => _orders;

  /// Temporary pre-cart items.
  List<CartItem> get preCart => _preCart;

  /// Active processing admin display name.
  String get adminName => _adminName;

  bool isOrderProcessing(String orderId) => _processingOrders.contains(orderId);
  bool isNewlyArrived(String orderId) =>
      _newlyArrivedOrderIds.contains(orderId);

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

      // Remote cancellations are now released idempotently inside the cancelling transaction
      // (no per-device diff restock loop that causes N× decrements across open admin devices).

      if (_knownOrderIds.isNotEmpty) {
        final newOrders = list.where((o) =>
            !_knownOrderIds.contains(o.id) && o.status == OrderStatus.pending);
        for (final o in newOrders) {
          _newlyArrivedOrderIds.add(o.id);
          _newOrderStreamController.add(o);
          NotificationService.showSmsNotificationPopUp(
            title: '🛍️ New Pre-Order Received!',
            body:
                'Customer ${o.customerName} placed order #${o.orderId} (P${o.total.toStringAsFixed(2)}).',
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
      debugPrint('Orders Stream Error: $e');
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

  void checkExpirationsNow() {
    _checkExpirations(_orders);
  }

  void _checkExpirations(List<PreOrder> list) {
    final now = TimeService.now;
    for (final order in list) {
      if (_processingOrders.contains(order.id)) continue;

      if (order.status == OrderStatus.awaitingPayment) {
        final paymentDeadline =
            order.expiresAt ?? order.createdAt.add(const Duration(minutes: 15));
        if (paymentDeadline.isBefore(now)) {
          debugPrint(
              'Auto-releasing expired unpaid reservation #${order.orderId}');
          cancelOrder(
            order.id,
            isAuto: true,
            recordOffense: false,
            reason: 'Payment session expired',
          );
        }
      } else if (order.status == OrderStatus.pending ||
          order.status == OrderStatus.staging ||
          order.status == OrderStatus.ready) {
        final effectiveExpiresAt =
            order.expiresAt ?? order.createdAt.add(const Duration(hours: 72));

        if (effectiveExpiresAt.isBefore(now)) {
          debugPrint(
              'Auto-cancelling expired pickup order #${order.orderId} (Expires: $effectiveExpiresAt, Now: $now)');
          cancelOrder(
            order.id,
            isAuto: true,
            recordOffense: true,
            reason: 'Order expired without collection',
          );
        }
      }
    }
  }

  // ── Pre-order cart ─────────────────────────────────────────────────────────

  void clearPreCart() {
    _preCart.clear();
    notifyListeners();
  }

  void addToPreCart(Product p, {int qty = 1}) {
    final idx = _preCart.indexWhere((i) => i.productId == p.id);
    final maxStock = p.stock > 0 ? p.stock : 9999;
    if (idx >= 0) {
      _preCart[idx] = _preCart[idx]
          .copyWith(qty: (_preCart[idx].qty + qty).clamp(1, maxStock));
    } else {
      _preCart.add(CartItem(
        productId: p.id,
        name: p.name,
        price: p.price,
        costPrice: p.costPrice,
        qty: qty.clamp(1, maxStock),
        isPerishable: p.isPerishable,
      ));
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
    _preCart[idx] =
        _preCart[idx].copyWith(qty: (_preCart[idx].qty + delta).clamp(1, 9999));
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
    StoreSettings? settings,
  }) async {
    final orderCount = _orders.length + 45;
    // Determine expiration based on items
    final hasPerishables = _preCart.any(
        (ci) => allProducts.any((p) => p.id == ci.productId && p.isPerishable));
    final onlyPerishables = _preCart.every(
        (ci) => allProducts.any((p) => p.id == ci.productId && p.isPerishable));

    final pWindow = settings?.perishableWindowHours ?? 2;
    final mWindow = settings?.mixedWindowHours ?? 24;
    final sWindow = settings?.standardWindowHours ?? 72;

    DateTime expiresAt;
    if (onlyPerishables) {
      expiresAt = TimeService.now.add(Duration(hours: pWindow));
    } else if (hasPerishables) {
      expiresAt = TimeService.now.add(Duration(hours: mWindow));
    } else {
      expiresAt = TimeService.now.add(Duration(hours: sWindow));
    }

    // Calculate breakdown using PricingEngine
    final breakdown = PricingEngine.calculate(
      items: _preCart,
      allProducts: allProducts,
    );

    final order = PreOrder(
      id: const Uuid().v4(),
      orderId: 'GDC-${orderCount.toString().padLeft(4, '0')}',
      customerName: customerName,
      customerEmail: customerEmail,
      items: List.from(_preCart),
      subtotal: breakdown.subtotal,
      tax: breakdown.vAtAmount,
      total: breakdown.total,
      status: OrderStatus.pending,
      notes: notes,
      location: location,
      pickupTime: pickupSlot,
      createdAt: TimeService.now,
      expiresAt: expiresAt,
      statusTimeline: {OrderStatus.pending.name: TimeService.now},
    );

    await _fs.addOrder(order);

    final hasPerishable = _preCart.any(
        (ci) => allProducts.any((p) => p.id == ci.productId && p.isPerishable));
    if (hasPerishable) {
      await NotificationService.schedulePerishableReminder(
          order.id, order.orderId);
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
    if (order.status == OrderStatus.collected ||
        order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.refunded) {
      return;
    }

    final updatedOrder = order.copyWith(
      status: OrderStatus.collected,
      processedBy: _adminName,
      reservationReleased: true,
    );

    final draftTx = StoreTransaction(
      id: const Uuid().v4(),
      orderId: order.orderId,
      items: order.items,
      total: order.total,
      cashTendered: order.total,
      changeGiven: 0,
      createdAt: DateTime.now(),
      customerId: order.customerId,
      customerEmail: order.customerEmail,
      type: TransactionType.pickup,
    );

    // Atomically deduct stock, run FEFO batch depletion, release reservedStock once,
    // mark order collected, and save transaction under matching doc ID.
    final tx = await _fs.fulfillOrderTransactional(
      order: order,
      updatedOrder: updatedOrder,
      tx: draftTx,
    );

    // Notify customer and send digital receipt email
    await NotificationService.sendOrderCollected(
        order.orderId, order.customerEmail);
    await AdminMessagingService().sendCustomerOrderStatusNotification(
      customerEmail: order.customerEmail,
      customerPhone: order.customerPhone ?? '',
      orderId: order.orderId,
      newStatus: OrderStatus.collected.name,
    );
    if (order.customerEmail.isNotEmpty) {
      AdminMessagingService()
          .sendDigitalReceiptEmail(
            customerEmail: order.customerEmail,
            customerName: order.customerName,
            orderId: order.orderId,
            items: tx.items,
            total: tx.total,
            paymentMethod: tx.paymentMethod.name.toUpperCase(),
            cashTendered: tx.cashTendered,
            changeGiven: tx.changeGiven,
            completedAt: tx.createdAt,
          )
          .catchError((e) {
            debugPrint('Error sending digital receipt email: $e');
            return false;
          });
    }
  }

  /// Fast-checkout protocol for Click & Collect with strict cash tracking & concurrency guard.
  Future<StoreTransaction> completePickupWithCash({
    required String orderId,
    required double cashTendered,
    required double changeGiven,
    List<CartItem> walkInItems = const [],
  }) async {
    if (_processingOrders.contains(orderId)) {
      throw Exception('Order is already being processed.');
    }
    _processingOrders.add(orderId);
    notifyListeners();

    try {
      final order = _orders.firstWhere((o) => o.id == orderId);
      if (order.status == OrderStatus.collected ||
          order.status == OrderStatus.cancelled ||
          order.status == OrderStatus.refunded) {
        throw Exception('Order #${order.orderId} is already ${order.status.name}.');
      }

      final walkInTotal =
          walkInItems.fold<double>(0.0, (s, i) => s + (i.price * i.qty));
      // Preserve order.total (includes tax/discounts) + any walk-in additions
      final grandTotal = order.total + walkInTotal;

      final updatedOrder = order.copyWith(
        status: OrderStatus.collected,
        paymentStatus: 'paid',
        isPaid: true,
        processedBy: _adminName,
        reservationReleased: true,
      );

      final draftTx = StoreTransaction(
        id: const Uuid().v4(),
        orderId: order.orderId,
        items: [...order.items, ...walkInItems],
        total: grandTotal,
        cashTendered: cashTendered,
        changeGiven: changeGiven,
        createdAt: DateTime.now(),
        customerId: order.customerId,
        customerEmail: order.customerEmail,
        paymentMethod: PaymentMethod.cash,
        type: TransactionType.pickup,
      );

      final tx = await _fs.fulfillOrderTransactional(
        order: order,
        updatedOrder: updatedOrder,
        tx: draftTx,
        walkInItems: walkInItems,
      );

      await NotificationService.sendOrderCollected(
          order.orderId, order.customerEmail);
      await AdminMessagingService().sendCustomerOrderStatusNotification(
        customerEmail: order.customerEmail,
        customerPhone: order.customerPhone ?? '',
        orderId: order.orderId,
        newStatus: OrderStatus.collected.name,
      );
      if (order.customerEmail.isNotEmpty) {
        AdminMessagingService()
            .sendDigitalReceiptEmail(
              customerEmail: order.customerEmail,
              customerName: order.customerName,
              orderId: order.orderId,
              items: tx.items,
              total: tx.total,
              paymentMethod: tx.paymentMethod.name.toUpperCase(),
              cashTendered: tx.cashTendered,
              changeGiven: tx.changeGiven,
              completedAt: tx.createdAt,
            )
            .catchError((e) {
              debugPrint('Error sending digital receipt email: $e');
              return false;
            });
      }
      return tx;
    } finally {
      _processingOrders.remove(orderId);
      notifyListeners();
    }
  }

  /// Completes a pre-paid/cashless pickup order with concurrency guard & transactional FEFO fulfillment.
  Future<StoreTransaction> completePrePaidPickup({
    required String orderId,
    List<CartItem> walkInItems = const [],
    double walkInCashTendered = 0.0,
    double walkInChangeGiven = 0.0,
  }) async {
    if (_processingOrders.contains(orderId)) {
      throw Exception('Order is already being processed.');
    }
    _processingOrders.add(orderId);
    notifyListeners();

    try {
      final order = _orders.firstWhere((o) => o.id == orderId);
      if (order.status == OrderStatus.collected ||
          order.status == OrderStatus.cancelled ||
          order.status == OrderStatus.refunded) {
        throw Exception('Order #${order.orderId} is already ${order.status.name}.');
      }

      final walkInTotal =
          walkInItems.fold<double>(0.0, (s, i) => s + (i.price * i.qty));
      // Preserve order.total (includes tax/discounts) + any walk-in additions
      final grandTotal = order.total + walkInTotal;

      final String pm = order.paymentMethod.toLowerCase();
      PaymentMethod pMethod = PaymentMethod.cashless;
      if (pm.contains('gcash')) {
        pMethod = PaymentMethod.gcash;
      } else if (pm.contains('maya')) {
        pMethod = PaymentMethod.maya;
      } else if (pm.contains('card')) {
        pMethod = PaymentMethod.card;
      } else if (pm.contains('online')) {
        pMethod = PaymentMethod.online;
      }

      final updatedOrder = order.copyWith(
        status: OrderStatus.collected,
        paymentStatus: 'paid',
        isPaid: true,
        processedBy: _adminName,
        reservationReleased: true,
      );

      final draftTx = StoreTransaction(
        id: const Uuid().v4(),
        orderId: order.orderId,
        items: [...order.items, ...walkInItems],
        total: grandTotal,
        cashTendered:
            walkInItems.isNotEmpty ? (order.total + walkInCashTendered) : order.total,
        changeGiven: walkInItems.isNotEmpty ? walkInChangeGiven : 0.0,
        createdAt: DateTime.now(),
        customerId: order.customerId,
        customerEmail: order.customerEmail,
        paymentMethod: pMethod,
        type: TransactionType.pickup,
      );

      final tx = await _fs.fulfillOrderTransactional(
        order: order,
        updatedOrder: updatedOrder,
        tx: draftTx,
        walkInItems: walkInItems,
      );

      await NotificationService.sendOrderCollected(
          order.orderId, order.customerEmail);
      await AdminMessagingService().sendCustomerOrderStatusNotification(
        customerEmail: order.customerEmail,
        customerPhone: order.customerPhone ?? '',
        orderId: order.orderId,
        newStatus: OrderStatus.collected.name,
      );
      if (order.customerEmail.isNotEmpty) {
        AdminMessagingService()
            .sendDigitalReceiptEmail(
              customerEmail: order.customerEmail,
              customerName: order.customerName,
              orderId: order.orderId,
              items: tx.items,
              total: tx.total,
              paymentMethod: tx.paymentMethod.name.toUpperCase(),
              cashTendered: tx.cashTendered,
              changeGiven: tx.changeGiven,
              completedAt: tx.createdAt,
            )
            .catchError((e) {
              debugPrint('Error sending digital receipt email: $e');
              return false;
            });
      }
      return tx;
    } finally {
      _processingOrders.remove(orderId);
      notifyListeners();
    }
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
    final next = switch (order.status) {
      OrderStatus.pending => OrderStatus.staging,
      OrderStatus.staging => OrderStatus.ready,
      _ => null,
    };
    if (next == null) return false;

    final updatedOrder = order.copyWith(
      status: next,
      processedBy: _adminName,
    );

    await _fs.updateOrder(updatedOrder);

    await AdminMessagingService().sendCustomerOrderStatusNotification(
      customerEmail: order.customerEmail,
      customerPhone: order.customerPhone ?? '',
      orderId: order.orderId,
      newStatus: next.name,
    );

    if (next == OrderStatus.ready) {
      await NotificationService.sendOrderReady(
          order.orderId, order.customerEmail);
    }

    return true;
  }

  Future<void> cancelOrder(
    String orderId, {
    bool isAuto = false,
    bool recordOffense = false,
    String? reason,
  }) async {
    if (_processingOrders.contains(orderId)) return;
    _processingOrders.add(orderId);

    try {
      await _cancelOrderInternal(
        orderId,
        isAuto: isAuto,
        recordOffense: recordOffense,
        reason: reason,
      );
    } finally {
      _processingOrders.remove(orderId);
      notifyListeners();
    }
  }

  Future<void> _cancelOrderInternal(
    String orderId, {
    bool isAuto = false,
    bool recordOffense = false,
    String? reason,
  }) async {
    final order = _orders.firstWhere((o) => o.id == orderId);
    // Never cancel or release reservations for already cancelled, collected, or refunded orders
    if (order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.collected ||
        order.status == OrderStatus.refunded) {
      return;
    }

    final actor = isAuto ? 'System' : _adminName;

    // 1. Atomically cancel order & release reservedStock ONCE across all devices
    final bool didRelease = await _fs.cancelOrderAndReleaseReservation(
      orderId: order.id,
      processedBy: actor,
      reason: reason,
    );

    if (!didRelease) {
      // Another device or the customer already cancelled & released this order
      return;
    }

    // 2. Evaluate spoilage/loss write-off for unfit items (once, by the device that won the release)
    await _processOrderLossWriteOffs(order, reason: reason, processedBy: actor);

    // 3. Record ghosting offense penalty on Admin side for expired uncollected pickup orders
    if (recordOffense) {
      try {
        await _fs.recordGhostingOffense(
          userId: order.customerId,
          userEmail: order.customerEmail,
          orderId: order.id,
          sixCharOrderId: order.orderId,
        );
      } catch (e) {
        debugPrint('Error recording ghosting offense for #${order.orderId}: $e');
      }
    }

    // 4. Notify customer
    await AdminMessagingService().sendCustomerOrderStatusNotification(
      customerEmail: order.customerEmail,
      customerPhone: order.customerPhone ?? '',
      orderId: order.orderId,
      newStatus: OrderStatus.cancelled.name,
    );

    if (isAuto) {
      await NotificationService.sendOrderAutoCancelled(
          order.orderId, order.customerEmail);
    }
  }

  /// Evaluates whether items in a cancelled order must be written off as inventory loss/spoilage.
  /// Note: `reservedStock` has already been released atomically by `cancelOrderAndReleaseReservation`.
  Future<void> _processOrderLossWriteOffs(
    PreOrder order, {
    String? reason,
    String? processedBy,
  }) async {
    if (_processedCancelledOrderIds.contains(order.id)) return;
    _processedCancelledOrderIds.add(order.id);

    try {
      final allProducts = await _fs.productsStream().first;
      final Map<String, Product> productMap = {
        for (final p in allProducts) p.id: p
      };

      final now = TimeService.now;
      final String adminUser = processedBy ?? _adminName;

      for (final item in order.items) {
        final product = productMap[item.productId];

        bool isFitToRestock = true;
        String unfitReason = 'Expired or unfit item';

        if (product != null) {
          if (product.expiryDate != null && product.expiryDate!.isBefore(now)) {
            isFitToRestock = false;
            unfitReason =
                'Product expiration date (${formatDate(product.expiryDate!)}) has passed';
          } else if (product.isPerishable &&
              order.createdAt
                  .add(Duration(days: product.shelfDays ?? 1))
                  .isBefore(now)) {
            isFitToRestock = false;
            unfitReason = 'Perishable item exceeded shelf life timeframe';
          }
        }

        final lowerReason = reason?.toLowerCase() ?? '';
        if (lowerReason.contains('damaged') ||
            lowerReason.contains('spoiled') ||
            lowerReason.contains('broken') ||
            lowerReason.contains('expired')) {
          isFitToRestock = false;
          unfitReason = 'Cancellation reason: $reason';
        }

        if (!isFitToRestock) {
          final lossRecord = LossRecord(
            id: const Uuid().v4(),
            productId: item.productId,
            productName: item.name,
            qty: item.qty,
            unitPrice: (product != null && product.effectiveUnitCost > 0)
                ? product.effectiveUnitCost
                : (item.costPrice > 0 ? item.costPrice : item.price),
            type: lowerReason.contains('damaged')
                ? LossType.damaged
                : LossType.expired,
            notes:
                'Auto written-off from cancelled order #${order.orderId}: $unfitReason',
            createdAt: now,
            processedBy: adminUser,
            referenceId: order.orderId,
          );
          await _fs.recordLoss(lossRecord);
        }
      }
    } catch (e) {
      debugPrint('Error processing loss write-offs for order ${order.id}: $e');
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
