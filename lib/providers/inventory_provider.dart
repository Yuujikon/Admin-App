import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/catalog_product.dart';
import '../models/bundle.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import '../models/refund_request.dart';
import '../models/store_settings.dart';
import '../models/supplier.dart';
import '../models/loss_record.dart';
import '../models/customer.dart';
import '../models/restock_inquiry.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

import 'base_provider.dart';

class InventoryProvider extends BaseProvider {
  final _fs = FirestoreService();

  List<Product>          _products       = [];
  List<CatalogProduct>   _catalog        = [];
  List<StoreTransaction> _transactions    = [];
  List<RefundRequest>    _refundRequests = [];
  List<Supplier>         _suppliers      = [];
  List<LossRecord>       _lossRecords    = [];
  List<Customer>         _customers      = [];
  List<ProductBundle>    _bundles        = [];
  StoreSettings          _settings       = const StoreSettings(isClosed: false);
  String                 _adminName      = 'Admin';
  bool                   _isProcessingSale = false;

  // Granular Loading Flags
  bool _isProductsLoading     = true;
  bool _isCatalogLoading      = true;
  bool _isTransactionsLoading = true;
  bool _isRefundRequestsLoading = true;
  bool _isSuppliersLoading    = true;
  bool _isLossRecordsLoading  = true;
  bool _isCustomersLoading    = true;
  bool _isBundlesLoading      = true;
  bool _isSettingsLoading     = true;

  List<Product>          get products       => _products;
  List<CatalogProduct>   get catalog        => _catalog;
  List<StoreTransaction> get transactions    => _transactions;
  List<RefundRequest>    get refundRequests => _refundRequests;
  List<Supplier>         get suppliers      => _suppliers;
  List<LossRecord>       get lossRecords    => _lossRecords;
  List<Customer>         get customers      => _customers;
  List<ProductBundle>    get bundles        => _bundles;
  StoreSettings          get settings       => _settings;
  String                 get adminName      => _adminName;
  bool                   get isProcessingSale => _isProcessingSale;

  bool get isProductsLoading     => _isProductsLoading;
  bool get isCatalogLoading      => _isCatalogLoading;
  bool get isTransactionsLoading => _isTransactionsLoading;
  bool get isRefundRequestsLoading => _isRefundRequestsLoading;
  bool get isSuppliersLoading    => _isSuppliersLoading;
  bool get isLossRecordsLoading  => _isLossRecordsLoading;
  bool get isCustomersLoading    => _isCustomersLoading;
  bool get isBundlesLoading      => _isBundlesLoading;
  bool get isSettingsLoading     => _isSettingsLoading;

  @override
  bool get isLoading =>
      _isProductsLoading ||
      _isTransactionsLoading ||
      _isCatalogLoading ||
      _isSuppliersLoading ||
      _isLossRecordsLoading ||
      _isSettingsLoading;

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
        final int stock = p.totalStock;
        if (stock <= 0) return 3; // Out of stock last
        if (stock <= p.lowStockThreshold) return 2; // Low stock second
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

  Timer? _statusTransitionTimer;

  void _checkAutomaticStoreTransitions() {
    final now = DateTime.now();

    // Auto-clear schedule if reopening time has passed
    if (_settings.scheduledOpenAt != null && now.isAfter(_settings.scheduledOpenAt!)) {
      debugPrint('Scheduled store outage expired. Automatically clearing schedule.');
      clearExpiredSchedule();
      return;
    }

    notifyListeners();
  }

  Future<void> clearExpiredSchedule() async {
    await _fs.updateStoreStatus(
      false,
      message: null,
      closeAt: null,
      openAt: null,
    );
  }

  void initialize() {
    cancelSubscriptions();
    _statusTransitionTimer?.cancel();
    _cachedSortedProducts = null; 
    _cachedRecentCounts = null;

    _isProductsLoading     = true;
    _isCatalogLoading      = true;
    _isTransactionsLoading = true;
    _isRefundRequestsLoading = true;
    _isSuppliersLoading    = true;
    _isLossRecordsLoading  = true;
    _isCustomersLoading    = true;
    _isBundlesLoading      = true;
    _isSettingsLoading     = true;

    _statusTransitionTimer = Timer.periodic(
      const Duration(seconds: 30), 
      (_) => _checkAutomaticStoreTransitions(),
    );

    Timer(const Duration(seconds: 3), () {
      if (isLoading) {
        _isProductsLoading     = false;
        _isCatalogLoading      = false;
        _isTransactionsLoading = false;
        _isRefundRequestsLoading = false;
        _isSuppliersLoading    = false;
        _isLossRecordsLoading  = false;
        _isCustomersLoading    = false;
        _isBundlesLoading      = false;
        _isSettingsLoading     = false;
        notifyListeners();
      }
    });

    registerSubscription(_fs.productsStream().handleError((e) {
      debugPrint('Products Stream Error: $e');
      _isProductsLoading = false;
      notifyListeners();
    }).listen((list) {
      _products = list;
      _cachedSortedProducts = null;
      _isProductsLoading = false;
      notifyListeners();
    }));

    registerSubscription(_fs.catalogStream().handleError((e) {
      debugPrint('Catalog Stream Error: $e');
      _isCatalogLoading = false;
      notifyListeners();
    }).listen((list) {
      _catalog = list;
      if (_catalog.isEmpty && _products.isNotEmpty) {
        _migrateProductsToCatalog();
      }
      _isCatalogLoading = false;
      notifyListeners();
    }));

    registerSubscription(_fs.transactionsStream().handleError((e) {
      debugPrint('Transactions Stream Error: $e');
      _isTransactionsLoading = false;
      notifyListeners();
    }).listen((list) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _transactions = list;
      _cachedSortedProducts = null;
      _cachedRecentCounts = null; 
      _isTransactionsLoading = false;
      notifyListeners();
    }));

    registerSubscription(_fs.refundRequestsStream().handleError((e) {
      debugPrint('RefundRequests Stream Error: $e');
      _isRefundRequestsLoading = false;
      notifyListeners();
    }).listen((list) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
      _isRefundRequestsLoading = false;
      notifyListeners();
    }));

    registerSubscription(_fs.suppliersStream().handleError((e) {
      debugPrint('Suppliers Stream Error: $e');
      _isSuppliersLoading = false;
      notifyListeners();
    }).listen((list) {
      _suppliers = list;
      _isSuppliersLoading = false;
      notifyListeners();
    }));

    registerSubscription(_fs.lossRecordsStream().handleError((e) {
      debugPrint('LossRecords Stream Error: $e');
      _isLossRecordsLoading = false;
      notifyListeners();
    }).listen((list) {
      _lossRecords = list;
      _isLossRecordsLoading = false;
      notifyListeners();
    }));

    registerSubscription(_fs.customersStream().handleError((e) {
      debugPrint('Customers Stream Error: $e');
      _isCustomersLoading = false;
      notifyListeners();
    }).listen((list) {
      _customers = list;
      _isCustomersLoading = false;
      notifyListeners();
    }));

    registerSubscription(_fs.bundlesStream().handleError((e) {
      debugPrint('Bundles Stream Error: $e');
      _isBundlesLoading = false;
      notifyListeners();
    }).listen((list) {
      _bundles = list;
      _isBundlesLoading = false;
      notifyListeners();
    }));

    registerSubscription(_fs.settingsStream().handleError((e) {
      debugPrint('Settings Stream Error: $e');
      _isSettingsLoading = false;
      notifyListeners();
    }).listen((settings) {
      _settings = settings;
      _cachedSortedProducts = null; 
      _checkAutomaticStoreTransitions();
      _isSettingsLoading = false;
      notifyListeners();
    }));
  }

  @override
  void dispose() {
    _statusTransitionTimer?.cancel();
    super.dispose();
  }

  void _migrateProductsToCatalog() async {
    for (final p in _products) {
      if (p.barcode != null) {
        final alreadyInCatalog = _catalog.any((cp) => cp.barcode == p.barcode);
        if (!alreadyInCatalog) {
          await saveCatalogProduct(CatalogProduct(
            id: '',
            name: p.name,
            brand: p.brand,
            category: p.category,
            barcode: p.barcode,
            photoBase64: p.photoBase64,
          ));
        }
      }
    }
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

  Future<void> saveProductWithBatch({
    required Product product,
    required ProductBatch initialBatch,
  }) async {
    await _fs.saveProductWithBatch(
      product: product,
      initialBatch: initialBatch,
    );
    notifyListeners();
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

  // ── Goods Receiving / Restock Delivery ──────────────────────────────────────

  Future<void> receiveDelivery({
    required Product product,
    required int qtyReceived,
    required double unitCost,
    DateTime? batchExpiryDate,
    String? invoiceNumber,
    String? notes,
  }) async {
    final int newStock = product.stock + qtyReceived;

    final newBatch = ProductBatch(
      id: const Uuid().v4(),
      productId: product.id,
      quantity: qtyReceived,
      unitCost: unitCost,
      expiryDate: batchExpiryDate,
      createdAt: DateTime.now(),
      invoiceNumber: invoiceNumber,
    );

    final updatedProduct = product.copyWith(
      stock: newStock,
      costPrice: unitCost > 0 ? unitCost : product.costPrice,
      batches: [...product.batches, newBatch],
    );

    await saveProduct(updatedProduct);

    await _fs.logStockArrival(
      productId: product.id,
      productName: product.name,
      qtyReceived: qtyReceived,
      unitCost: unitCost,
      expiryDate: batchExpiryDate ?? product.expiryDate,
      invoiceNumber: invoiceNumber,
      receivedBy: _adminName,
      notes: notes,
    );

    notifyListeners();
  }

  Future<void> processInquiryDelivery({
    required RestockInquiry inquiry,
    required List<Map<String, dynamic>> receivedItemData,
    String? invoiceNumber,
    String? notes,
  }) async {
    bool isShortDelivery = false;

    for (final itemMap in receivedItemData) {
      final String prodId = itemMap['productId'] ?? '';
      final int qtyRec = itemMap['receivedQty'] ?? 0;
      final double unitCost = (itemMap['costPrice'] as num? ?? 0.0).toDouble();
      final DateTime? expDate = itemMap['expiryDate'] as DateTime?;

      if (qtyRec <= 0) continue;

      try {
        final prod = _products.firstWhere((p) => p.id == prodId);

        final newBatch = ProductBatch(
          id: const Uuid().v4(),
          productId: prod.id,
          quantity: qtyRec,
          unitCost: unitCost > 0 ? unitCost : prod.costPrice,
          expiryDate: expDate,
          createdAt: DateTime.now(),
          invoiceNumber: invoiceNumber,
        );

        final updatedProduct = prod.copyWith(
          stock: prod.stock + qtyRec,
          costPrice: unitCost > 0 ? unitCost : prod.costPrice,
          batches: [...prod.batches, newBatch],
        );

        await saveProduct(updatedProduct);

        await _fs.logStockArrival(
          productId: prod.id,
          productName: prod.name,
          qtyReceived: qtyRec,
          unitCost: unitCost,
          expiryDate: expDate ?? prod.expiryDate,
          invoiceNumber: invoiceNumber,
          receivedBy: _adminName,
          notes: notes,
        );

        final expectedItem = inquiry.items.firstWhere(
          (i) => i.productId == prodId,
          orElse: () => RestockInquiryItem(
            productId: '', productName: '', sku: '', currentStock: 0, lowStockThreshold: 0, unit: '', suggestedQty: 0, requestedQty: 0,
          ),
        );

        if (qtyRec < expectedItem.requestedQty) {
          isShortDelivery = true;
        }
      } catch (e) {
        debugPrint('Error updating product stock during inquiry delivery: $e');
      }
    }

    final RestockInquiryStatus newStatus = isShortDelivery 
        ? RestockInquiryStatus.partiallyFulfilled 
        : RestockInquiryStatus.fulfilled;

    await _fs.updateRestockInquiryStatus(inquiry.id, newStatus);
    notifyListeners();
  }

  // ── Catalog ────────────────────────────────────────────────────────────────

  Future<void> saveCatalogProduct(CatalogProduct p) {
    if (p.id.isEmpty) return _fs.addCatalogProduct(p);
    return _fs.updateCatalogProduct(p);
  }

  Future<void> deleteCatalogProduct(String id) => _fs.deleteCatalogProduct(id);

  Future<void> linkBarcodeToCatalog(String catalogId, String barcode) =>
      _fs.linkBarcodeToCatalog(catalogId, barcode);

  // ── Suppliers ──────────────────────────────────────────────────────────────

  Future<Supplier?> getSupplierById(String id) async {
    try {
      return _suppliers.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
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

  Future<void> saveBundle(ProductBundle b) => _fs.saveBundle(b);
  Future<void> deleteBundle(String id) => _fs.deleteBundle(id);

  Future<StoreTransaction> completeSale(List<CartItem> cart, double cash, {double? totalOverride, String? customerId, String? customerEmail, PaymentMethod paymentMethod = PaymentMethod.cash, TransactionType type = TransactionType.inStore}) async {
    if (_isProcessingSale) throw Exception('Transaction in progress');
    
    // 1. Final stock check against current local state (synced via snapshots)
    for (var item in cart) {
      try {
        final p = _products.firstWhere((p) => p.id == item.productId);
        if (item.variantId != null) {
          final v = p.variants.firstWhere((v) => v.id == item.variantId);
          if (v.stock < item.qty) {
            throw Exception('${p.name} (${v.name}) is now out of stock or has insufficient quantity (${v.stock} remaining).');
          }
        } else {
          if (p.stock < item.qty) {
            throw Exception('${p.name} is now out of stock or has insufficient quantity (${p.stock} remaining).');
          }
        }
      } catch (e) {
        if (e is StateError) throw Exception('Product ${item.name} no longer exists in inventory.');
        rethrow;
      }
    }

    _isProcessingSale = true;
    notifyListeners();

    try {
      final double total  = totalOverride ?? cart.fold<double>(0.0, (s, i) => s + i.price * i.qty);
      final double change = paymentMethod == PaymentMethod.cash ? (cash - total) : 0.0;

      // 1. Apply local optimistic stock deduction & build accurate line items with totalCogs & depletedBatches
      final List<CartItem> processedItems = _applyLocalOptimisticStockDeductionAndBuildLineItems(cart);

      final tx = StoreTransaction(
        id:            const Uuid().v4(),
        items:         processedItems,
        total:         total,
        cashTendered:  paymentMethod == PaymentMethod.cash ? cash : 0.0,
        changeGiven:   change,
        createdAt:     DateTime.now(),
        customerId:    customerId,
        customerEmail: customerEmail,
        paymentMethod: paymentMethod,
        type:          type,
      );

      // 2. Commit WriteBatch to local cache (works 100% offline & auto-syncs)
      await _fs.recordSaleOfflineFirst(tx: tx, cachedProducts: _products);

      // Trigger heads-up payment pop-up alert (catch errors so notification issues never block sale)
      try {
        await NotificationService.showPaymentReceivedAlert(
          tx.id.length >= 8 ? tx.id.substring(0, 8) : tx.id, 
          total, 
          customerEmail ?? 'Walk-in Customer'
        );
      } catch (e) {
        debugPrint('Notification alert error: $e');
      }

      // Check for low stock after decrement
      for (var item in cart) {
        try {
          final p = _products.firstWhere((p) => p.id == item.productId);
          final int remainingStock = item.variantId != null 
              ? p.variants.firstWhere((v) => v.id == item.variantId).stock - item.qty
              : p.stock - item.qty;
          if (remainingStock <= 5) {
            _notifySupplierLowStock(p);
          }
        } catch (_) {}
      }

      return tx;
    } finally {
      _isProcessingSale = false;
      notifyListeners();
    }
  }

  List<CartItem> _applyLocalOptimisticStockDeductionAndBuildLineItems(List<CartItem> cart) {
    final List<CartItem> processedItems = [];

    for (final item in cart) {
      final index = _products.indexWhere((p) => p.id == item.productId);
      if (index >= 0) {
        final p = _products[index];

        if (item.variantId != null) {
          final updatedVariants = p.variants.map((v) {
            if (v.id == item.variantId) {
              return v.copyWith(stock: (v.stock - item.qty).clamp(0, 999999));
            }
            return v;
          }).toList();

          _products[index] = p.copyWith(
            stock: (p.stock - item.qty).clamp(0, 999999),
            variants: updatedVariants,
          );

          final double lineCogs = item.costPrice * item.qty;
          processedItems.add(item.copyWith(
            totalCogs: lineCogs,
            costPrice: item.costPrice,
            depletedBatches: [
              BatchDepletionRecord(batchId: 'variant-${item.variantId}', quantity: item.qty, unitCost: item.costPrice)
            ],
          ));
        } else {
          int remainingToDeduct = item.qty;
          final List<ProductBatch> currentBatches = List.from(p.batches);

          currentBatches.sort((a, b) {
            if (a.expiryDate != null && b.expiryDate != null) {
              return a.expiryDate!.compareTo(b.expiryDate!);
            }
            return a.createdAt.compareTo(b.createdAt);
          });

          final List<ProductBatch> updatedBatches = [];
          final List<BatchDepletionRecord> depletedBatches = [];
          double lineItemTotalCogs = 0.0;

          for (final b in currentBatches) {
            if (remainingToDeduct <= 0) {
              updatedBatches.add(b);
              continue;
            }

            if (b.quantity > remainingToDeduct) {
              final int deductedQty = remainingToDeduct;
              lineItemTotalCogs += (deductedQty * b.unitCost);
              depletedBatches.add(BatchDepletionRecord(
                batchId: b.id,
                quantity: deductedQty,
                unitCost: b.unitCost,
              ));

              updatedBatches.add(ProductBatch(
                id: b.id,
                productId: b.productId,
                quantity: b.quantity - deductedQty,
                unitCost: b.unitCost,
                expiryDate: b.expiryDate,
                createdAt: b.createdAt,
                invoiceNumber: b.invoiceNumber,
              ));
              remainingToDeduct = 0;
            } else {
              final int deductedQty = b.quantity;
              lineItemTotalCogs += (deductedQty * b.unitCost);
              depletedBatches.add(BatchDepletionRecord(
                batchId: b.id,
                quantity: deductedQty,
                unitCost: b.unitCost,
              ));
              remainingToDeduct -= deductedQty;
            }
          }

          if (remainingToDeduct > 0) {
            final double fallbackCost = p.costPrice;
            lineItemTotalCogs += (remainingToDeduct * fallbackCost);
            depletedBatches.add(BatchDepletionRecord(
              batchId: 'fallback-unbatched',
              quantity: remainingToDeduct,
              unitCost: fallbackCost,
            ));
          }

          _products[index] = p.copyWith(
            stock: (p.stock - item.qty).clamp(0, 999999),
            batches: updatedBatches,
          );

          final double weightedCostPrice = item.qty > 0 ? (lineItemTotalCogs / item.qty) : item.costPrice;

          processedItems.add(item.copyWith(
            costPrice: weightedCostPrice,
            totalCogs: lineItemTotalCogs,
            depletedBatches: depletedBatches,
          ));
        }
      } else {
        processedItems.add(item);
      }
    }
    _cachedSortedProducts = null;
    notifyListeners();
    return processedItems;
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

  Future<void> approveRefundRequest(RefundRequest request, {required RefundCondition condition, String? notes}) async {
    // 1. Process the refund in Firestore (updates status and logs Loss)
    final updatedReq = RefundRequest(
      id: request.id,
      transactionId: request.transactionId,
      customerEmail: request.customerEmail,
      customerName: request.customerName,
      items: request.items,
      total: request.total,
      reason: request.reason,
      adminNotes: notes,
      status: RefundStatus.approved,
      condition: condition,
      createdAt: request.createdAt,
      processedByEmail: _adminName,
    );

    final index = _refundRequests.indexWhere((r) => r.id == request.id);
    if (index != -1) {
      _refundRequests[index] = updatedReq;
      notifyListeners();
    }

    await _fs.processApprovedRefund(updatedReq, _adminName);

    // 2. Find and update the original Order status if it exists
    final orderSnap = await FirebaseFirestore.instance.collection('orders')
        .where('orderId', isEqualTo: request.transactionId)
        .limit(1)
        .get();

    if (orderSnap.docs.isNotEmpty) {
      await _fs.updateOrderStatus(orderSnap.docs.first.id, OrderStatus.refunded);
    }

    // 3. Send notification to customer with store response
    await NotificationService.sendRefundUpdate(request.transactionId, request.customerEmail, true, storeResponse: notes);
  }

  Future<void> rejectRefundRequest(RefundRequest request, String reason, {String? notes}) async {
    final index = _refundRequests.indexWhere((r) => r.id == request.id);
    if (index != -1) {
      _refundRequests[index] = RefundRequest(
        id: request.id,
        transactionId: request.transactionId,
        customerEmail: request.customerEmail,
        customerName: request.customerName,
        items: request.items,
        total: request.total,
        reason: request.reason,
        rejectionReason: reason,
        adminNotes: notes ?? reason,
        status: RefundStatus.rejected,
        condition: request.condition,
        createdAt: request.createdAt,
        processedByEmail: _adminName,
      );
      notifyListeners();
    }

    await _fs.updateRefundStatus(request.id, RefundStatus.rejected, _adminName, reason: reason, notes: notes ?? reason);

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

    await NotificationService.sendRefundUpdate(request.transactionId, request.customerEmail, false, storeResponse: reason);
  }
}