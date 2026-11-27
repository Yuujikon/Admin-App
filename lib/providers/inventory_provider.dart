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
import '../models/delivery_log.dart';
import '../models/daily_resupply_log.dart';
import '../services/audit_log_service.dart';
import '../services/firestore_service.dart';
import '../services/inventory_batch_service.dart';
import '../services/notification_service.dart';
import '../shared/services/admin_messaging_service.dart';
import '../shared/services/time_service.dart';
import '../utils/inventory_allocation.dart';
import '../utils/pricing_engine.dart';

import 'base_provider.dart';

/// Central provider managing inventory stock, product catalog, sales checkout transactions,
/// supplier records, customer profiles, and store settings.
class InventoryProvider extends BaseProvider {
  final _fs = FirestoreService();
  final _batchService = InventoryBatchService();

  List<Product> _rawProducts = [];
  Map<String, List<ProductBatch>> _liveBatchesByProductId = {};
  bool _hasLiveBatchStream = false;
  List<Product> _products = [];
  List<CatalogProduct> _catalog = [];
  List<StoreTransaction> _transactions = [];
  List<RefundRequest> _refundRequests = [];
  List<Supplier> _suppliers = [];
  List<LossRecord> _lossRecords = [];
  List<Customer> _customers = [];
  List<ProductBundle> _bundles = [];
  List<DeliveryLog> _deliveryLogs = [];
  List<Map<String, dynamic>> _appeals = [];
  List<Map<String, dynamic>> _adminNotifications = [];
  DailyResupplyLog? _todayResupplyLog;
  String? _subscribedResupplyDateKey;
  StreamSubscription<DailyResupplyLog>? _resupplyLogSub;
  bool _isSendingDailyResupplyEmail = false;
  bool _isCheckingEodEmail = false;
  bool _isEvaluatingLowStock = false;
  bool _lowStockReevalQueued = false;
  Timer? _lowStockSyncDebounceTimer;
  final Map<String, String> _alertedLowStockLevelToday = {};
  final Set<String> _seenAboveThresholdInSession = {};
  bool _seededResupplyAlertState = false;
  StoreSettings _settings = const StoreSettings(isClosed: false);
  String _adminName = 'Admin';
  bool _isProcessingSale = false;

  // Granular Loading Flags
  bool _isProductsLoading = true;
  bool _isCatalogLoading = true;
  bool _isTransactionsLoading = true;
  bool _isRefundRequestsLoading = true;
  bool _isSuppliersLoading = true;
  bool _isLossRecordsLoading = true;
  bool _isCustomersLoading = true;
  bool _isBundlesLoading = true;
  bool _isDeliveryLogsLoading = true;
  bool _isSettingsLoading = true;

  List<Product> get products => _products;
  List<Map<String, dynamic>> get adminNotifications => _adminNotifications;
  int get unreadAdminNotificationCount =>
      _adminNotifications.where((n) => n['isRead'] != true).length;
  DailyResupplyLog get todayResupplyLog =>
      _todayResupplyLog ??
      DailyResupplyLog.empty(
        InventoryAllocation.dateKeyFor(TimeService.now),
        storeEmail: AdminMessagingService().storeEmailSync,
      );
  List<DailyResupplyItem> get todayResupplyItems =>
      todayResupplyLog.sortedItems;
  bool get isSendingDailyResupplyEmail => _isSendingDailyResupplyEmail;

  Stream<List<DailyResupplyLog>> dailyResupplyLogsHistoryStream({
    int limit = 30,
  }) =>
      _fs.dailyResupplyLogsHistoryStream(limit: limit);

  Future<void> refreshTodayResupplyLog() => _evaluatePhysicalLowStockResupply();

  Future<void> markAdminNotificationRead(String id) =>
      _fs.markAdminNotificationRead(id);

  Future<void> markAllAdminNotificationsRead() =>
      _fs.markAllAdminNotificationsRead();
  List<CatalogProduct> get catalog => _catalog;
  List<StoreTransaction> get transactions => _transactions;
  List<RefundRequest> get refundRequests => _refundRequests;
  List<Supplier> get suppliers => _suppliers;
  List<LossRecord> get lossRecords => _lossRecords;
  List<Customer> get customers => _customers;
  List<ProductBundle> get bundles => _bundles;
  List<DeliveryLog> get deliveryLogs => _deliveryLogs;
  List<Map<String, dynamic>> get appeals => _appeals;
  StoreSettings get settings => _settings;
  String get adminName => _adminName;
  bool get isProcessingSale => _isProcessingSale;

  bool get isProductsLoading => _isProductsLoading;
  bool get isCatalogLoading => _isCatalogLoading;
  bool get isTransactionsLoading => _isTransactionsLoading;
  bool get isRefundRequestsLoading => _isRefundRequestsLoading;
  bool get isSuppliersLoading => _isSuppliersLoading;
  bool get isLossRecordsLoading => _isLossRecordsLoading;
  bool get isDeliveryLogsLoading => _isDeliveryLogsLoading;
  bool get isCustomersLoading => _isCustomersLoading;
  bool get isBundlesLoading => _isBundlesLoading;
  bool get isSettingsLoading => _isSettingsLoading;

  @override
  bool get isLoading =>
      _isProductsLoading ||
      _isTransactionsLoading ||
      _isCatalogLoading ||
      _isSuppliersLoading ||
      _isLossRecordsLoading ||
      _isSettingsLoading;

  List<Product>? _cachedSortedProducts;
  DateTime? _lastSortTime;

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
          recentCounts[item.productId] =
              (recentCounts[item.productId] ?? 0) + item.qty;
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
        if (p.isPhysicalThresholdHit) return 2; // Low stock (<= 30%) second
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

    final slow = _products.where((p) => (counts[p.name] ?? 0) <= 2).toList();
    slow.sort((a, b) => (counts[a.name] ?? 0).compareTo(counts[b.name] ?? 0));
    return slow;
  }

  Map<String, int> get recentMovementCounts => _cachedRecentCounts ?? {};

  // ── Dynamic Velocity-Based Markup Engine Helpers ──────────────────────────

  /// Computes normalized velocity scores (`0.0` slowest to `1.0` fastest) across all products
  /// using the configured rolling window (`7` or `30` days) from [StoreSettings].
  Map<String, double> get liveVelocityScores =>
      PricingEngine.computeVelocityScores(
        products: _products,
        transactions: _transactions,
        windowDays: _settings.velocityWindowDays,
      );

  /// Returns the live normalized sales velocity score (`0.0`–`1.0`) for [product].
  double getLiveVelocityScore(Product product) {
    final scores = liveVelocityScores;
    return scores[product.id] ?? product.salesVelocityScore;
  }

  /// Products missing a valid unit cost (`activeFifoUnitCost <= 0`) that need admin attention.
  List<Product> get zeroCostProducts =>
      _products.where((p) => p.hasInvalidUnitCost).toList();

  /// Syncs rolling sales velocity scores and recalculates selling prices for all
  /// `'auto'` priced products in Firestore while strictly preserving `'manual'` overrides
  /// and safely skipping zero-cost items (`unitCost <= 0`).
  Future<VelocitySyncSummary> syncVelocityBasedPricing({
    int? windowDays,
  }) async {
    final int effectiveWindow = windowDays ?? _settings.velocityWindowDays;
    final Map<String, double> scores = PricingEngine.computeVelocityScores(
      products: _products,
      transactions: _transactions,
      windowDays: effectiveWindow,
    );

    final List<Map<String, dynamic>> batchUpdates = [];
    int updatedAutoCount = 0;
    int preservedManualCount = 0;
    int skippedZeroCostCount = 0;

    for (final p in _products) {
      final double newVelocity = scores[p.id] ?? p.salesVelocityScore;

      // Priority 1: Admin Override — NEVER overwrite manualMarkupPercent or price during velocity syncs.
      if (p.pricingMode == Product.pricingModeManual &&
          p.manualMarkupPercent != null) {
        preservedManualCount++;
        if ((newVelocity - p.salesVelocityScore).abs() > 0.001) {
          batchUpdates.add({
            'id': p.id,
            'data': {
              'salesVelocityScore': newVelocity,
            },
          });
        }
        continue;
      }

      // Priority 2 & 3: Auto-Scale Markup
      final updatedCandidate = p.copyWith(salesVelocityScore: newVelocity);
      final double newMarkup = calculateItemMarkup(
        updatedCandidate,
        useGlobalBenchmarkOnly: _settings.useGlobalVelocityBenchmarkOnly,
      );
      final double activeCost = p.activeFifoUnitCost;

      if (!activeCost.isFinite || activeCost <= 0) {
        skippedZeroCostCount++;
        if ((newVelocity - p.salesVelocityScore).abs() > 0.001 ||
            (newMarkup - p.computedMarkupPercent).abs() > 0.001) {
          batchUpdates.add({
            'id': p.id,
            'data': {
              'salesVelocityScore': newVelocity,
              'computedMarkupPercent': newMarkup,
            },
          });
        }
        continue;
      }

      final double newSellingPrice = PricingEngine.calculateFinalSellingPrice(
        unitCost: activeCost,
        markupPercent: newMarkup,
        roundingStep: _settings.priceRoundingStep,
      );

      final bool changed = (newVelocity - p.salesVelocityScore).abs() > 0.001 ||
          (newMarkup - p.computedMarkupPercent).abs() > 0.001 ||
          (newSellingPrice - p.price).abs() > 0.001;

      if (changed && newSellingPrice > 0) {
        updatedAutoCount++;
        batchUpdates.add({
          'id': p.id,
          'data': {
            'salesVelocityScore': newVelocity,
            'computedMarkupPercent': newMarkup,
            'price': newSellingPrice,
            'sellingPrice': newSellingPrice,
          },
        });
      }
    }

    if (batchUpdates.isNotEmpty) {
      await _fs.batchUpdateProductPricing(batchUpdates);
    }

    return VelocitySyncSummary(
      updatedAutoCount: updatedAutoCount,
      preservedManualCount: preservedManualCount,
      skippedZeroCostCount: skippedZeroCostCount,
    );
  }

  // ── Physical Low-Stock Monitoring & Daily Resupply Log ────────────────────

  static String _sanitizeDocIdSegment(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }

  static String _buildLowStockNotifDocId(
    String dateKey,
    String itemKey,
    bool isOos,
  ) =>
      'low30_${dateKey}_${_sanitizeDocIdSegment(itemKey)}_${isOos ? 'oos' : 'low'}';

  void _scheduleLowStockCheck() {
    if (_isProductsLoading) return;
    _lowStockSyncDebounceTimer?.cancel();
    _lowStockSyncDebounceTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_evaluatePhysicalLowStockResupply()),
    );
  }

  void _emitLowStockInventoryAlert({
    required String todayKey,
    required DailyResupplyItem resupplyItem,
  }) {
    final bool isPhysOos = resupplyItem.availableStock <= 0;
    final int orig = resupplyItem.effectiveOriginalStock;
    final String alertTitle = isPhysOos
        ? 'Out of Stock: ${resupplyItem.displayName}'
        : 'Low Stock (30%): ${resupplyItem.displayName}';
    final String alertMsg = isPhysOos
        ? '${resupplyItem.displayName} is out of stock (0/$orig ${resupplyItem.unit}). Queued for End-of-Day Resupply Summary Email.'
        : '${resupplyItem.displayName} is low on stock (${resupplyItem.availableStock}/$orig ${resupplyItem.unit} left; ≤ 30% alert at ${resupplyItem.lowStockThreshold}). Queued for End-of-Day Resupply Summary Email.';
    final String notifDocId = _buildLowStockNotifDocId(
      todayKey,
      resupplyItem.itemKey,
      isPhysOos,
    );

    unawaited(
      NotificationService.showSmsNotificationPopUp(
        id: 'physical_low_${resupplyItem.itemKey}'.hashCode,
        title: alertTitle,
        body: alertMsg,
      ),
    );
    unawaited(
      _fs.addAdminNotification(
        {
          'title': alertTitle,
          'message': alertMsg,
          'body': alertMsg,
          'type': isPhysOos ? 'out_of_stock' : 'physical_low_stock_alert',
          'severity': isPhysOos ? 'critical' : 'warning',
          'status': isPhysOos
              ? 'Out of Stock'
              : 'Low Stock ≤ 30% (${resupplyItem.availableStock}/$orig)',
          'suggestedRestock': resupplyItem.suggestedResupplyQty,
          'relatedId': resupplyItem.productId,
          'productId': resupplyItem.productId,
          if (resupplyItem.variantId != null)
            'variantId': resupplyItem.variantId,
        },
        docId: notifDocId,
      ).catchError((e) => debugPrint(
          '[InventoryProvider] Failed writing admin notification: $e')),
    );
    unawaited(
      AuditLogService()
          .logAction(
            module: 'Inventory',
            action: 'PHYSICAL_LOW_STOCK_30_PCT_HIT',
            targetId: resupplyItem.productId,
            targetName: resupplyItem.displayName,
            summary: alertMsg,
          )
          .catchError((_) {}),
    );
  }

  /// Checks active products/variants to see whether 100% physical store stock
  /// has reached 30% of its original stock, emitting an immediate Inventory
  /// Alert and queueing the item in today's `daily_resupply_logs/{YYYY-MM-DD}`
  /// for the Store-Closing Resupply Summary Email.
  Future<void> _evaluatePhysicalLowStockResupply() async {
    if (_isProductsLoading) return;
    if (_isEvaluatingLowStock) {
      _lowStockReevalQueued = true;
      return;
    }

    _isEvaluatingLowStock = true;
    try {
      _ensureTodayResupplySubscription();
      final now = TimeService.now;
      final todayKey = InventoryAllocation.dateKeyFor(now);
      final storeEmail = AdminMessagingService().storeEmailSync;

      final List<DailyResupplyItem> triggeredResupplyItems = [];
      final List<String> recoveredItemKeys = [];

      for (final liveP in _products) {
        if (liveP.status == ProductStatus.archived) continue;

        if (liveP.hasVariants) {
          for (final v in liveP.variants) {
            final int vOrig = v.effectiveOriginalStock;
            final int vThreshold = v.lowStockAlertThreshold;
            final String itemKey =
                DailyResupplyItem.buildItemKey(liveP.id, v.id);
            if (v.isPhysicalThresholdHit) {
              triggeredResupplyItems.add(
                DailyResupplyItem(
                  itemKey: itemKey,
                  productId: liveP.id,
                  variantId: v.id,
                  productName: liveP.name,
                  variantName: v.name,
                  category: liveP.category,
                  unit: liveP.unit,
                  originalStock: vOrig,
                  lowStockThreshold: vThreshold,
                  physicalStock: v.availableStock,
                  onlineStock: v.onlineAvailableStock,
                  totalStock: v.stock,
                  availableStock: v.availableStock,
                  suggestedResupplyQty: v.calculateSuggestedRestock(),
                  onlineOutOfStock: v.isOnlineOutOfStock,
                  firstTriggeredAt: now,
                  lastUpdatedAt: now,
                ),
              );
            } else {
              recoveredItemKeys.add(itemKey);
            }
          }
        } else {
          final String itemKey = DailyResupplyItem.buildItemKey(liveP.id);
          if (liveP.isPhysicalThresholdHit) {
            triggeredResupplyItems.add(
              DailyResupplyItem(
                itemKey: itemKey,
                productId: liveP.id,
                productName: liveP.name,
                category: liveP.category,
                unit: liveP.unit,
                originalStock: liveP.effectiveOriginalStock,
                lowStockThreshold: liveP.lowStockAlertThreshold,
                physicalStock: liveP.availableStock,
                onlineStock: liveP.onlineAvailableStock,
                totalStock: liveP.totalStock,
                availableStock: liveP.availableStock,
                suggestedResupplyQty: liveP.calculateSuggestedRestock(),
                onlineOutOfStock: liveP.isOnlineOutOfStock,
                firstTriggeredAt: now,
                lastUpdatedAt: now,
              ),
            );
          } else {
            recoveredItemKeys.add(itemKey);
          }
        }
      }

      // Clear restocked items from in-memory alert state and unsent daily logs
      for (final itemKey in recoveredItemKeys) {
        _seenAboveThresholdInSession.add(itemKey);
        _alertedLowStockLevelToday.remove('$todayKey::$itemKey');
        final log = _todayResupplyLog;
        if (log != null &&
            log.dateKey == todayKey &&
            !log.summaryEmailSent &&
            log.items.containsKey(itemKey)) {
          unawaited(
            _fs
                .removeDailyResupplyItem(dateKey: todayKey, itemKey: itemKey)
                .catchError((e) => debugPrint(
                    '[InventoryProvider] Failed clearing restocked item $itemKey: $e')),
          );
        }
      }

      for (final resupplyItem in triggeredResupplyItems) {
        final bool isPhysOos = resupplyItem.availableStock <= 0;
        final String nextLevel = isPhysOos ? 'oos' : 'low';
        final String memKey = '$todayKey::${resupplyItem.itemKey}';
        final String? prevLevel = _alertedLowStockLevelToday[memKey];
        final bool transitionedInSession =
            _seenAboveThresholdInSession.contains(resupplyItem.itemKey);

        bool isNewInDb = false;
        bool escalatedInDb = false;
        bool dbWriteFailed = false;
        try {
          final result = await _fs.recordDailyResupplyItem(
            dateKey: todayKey,
            item: resupplyItem,
            storeEmail: storeEmail,
          );
          isNewInDb = result.isNew;
          escalatedInDb = result.escalatedToOos;
        } catch (e) {
          dbWriteFailed = true;
          debugPrint(
            '[InventoryProvider] Failed recording daily resupply item ${resupplyItem.displayName}: $e',
          );
        }

        final bool escalatedInMem = prevLevel == 'low' && nextLevel == 'oos';
        final bool shouldEmitAlert = (prevLevel == null &&
                (isNewInDb || transitionedInSession || dbWriteFailed)) ||
            escalatedInMem ||
            (escalatedInDb && prevLevel != 'oos');

        _alertedLowStockLevelToday[memKey] = nextLevel;
        _seenAboveThresholdInSession.remove(resupplyItem.itemKey);

        if (shouldEmitAlert) {
          _emitLowStockInventoryAlert(
            todayKey: todayKey,
            resupplyItem: resupplyItem,
          );
        }
      }
    } finally {
      _isEvaluatingLowStock = false;
      if (_lowStockReevalQueued) {
        _lowStockReevalQueued = false;
        _scheduleLowStockCheck();
      }
    }
  }

  void _ensureTodayResupplySubscription() {
    final dateKey = InventoryAllocation.dateKeyFor(TimeService.now);
    if (_subscribedResupplyDateKey == dateKey && _resupplyLogSub != null) {
      return;
    }
    _resupplyLogSub?.cancel();
    _subscribedResupplyDateKey = dateKey;
    _seededResupplyAlertState = false;
    _alertedLowStockLevelToday.clear();
    final storeEmail = AdminMessagingService().storeEmailSync;
    _resupplyLogSub = _fs
        .dailyResupplyLogStream(dateKey, defaultStoreEmail: storeEmail)
        .listen((log) {
      _todayResupplyLog = log;
      // Seed alert state ONLY on initial snapshot so Cloud Functions writing
      // faster than our local debounce never suppresses in-session alerts.
      if (!_seededResupplyAlertState) {
        _seededResupplyAlertState = true;
        for (final entry in log.items.entries) {
          if (!_seenAboveThresholdInSession.contains(entry.key)) {
            _alertedLowStockLevelToday['$dateKey::${entry.key}'] =
                entry.value.isOutOfStock ? 'oos' : 'low';
          }
        }
      }
      notifyListeners();
    }, onError: (e) {
      debugPrint('Daily Resupply Log Stream Error: $e');
    });
  }

  /// Checks whether the store has closed for the day (manual store close,
  /// custom special-hours end time, scheduled closure, or regular daily closing
  /// time from [StoreSettings]) and dispatches the Store-Closing Resupply
  /// Summary Email listing all stocks that reached 30% of original stock.
  ///
  /// Uses an atomic Firestore claim lock so the email is sent at most once per day.
  Future<void> checkAndDispatchEndOfDayResupplyEmail() async {
    if (_isCheckingEodEmail) return;
    _isCheckingEodEmail = true;
    try {
      final now = TimeService.now;
      final todayKey = InventoryAllocation.dateKeyFor(now);
      final yesterdayKey = InventoryAllocation.dateKeyFor(
        now.subtract(const Duration(days: 1)),
      );

      // 1. Catch up on yesterday's unsent resupply log if the app was closed when the store closed
      final yesterdayLog = await _fs.getDailyResupplyLog(yesterdayKey);
      if (yesterdayLog != null &&
          yesterdayLog.itemCount > 0 &&
          !yesterdayLog.summaryEmailSent) {
        await _dispatchResupplyEmailForDate(
          dateKey: yesterdayKey,
          triggeredBy: 'admin_store_close_catchup',
          forceResend: false,
        );
      }

      // 2. Dispatch today's summary email immediately when the store closes
      if (!_isProductsLoading && _settings.hasStoreClosedForDayAt(now)) {
        // Ensure every item currently at <= 30% of original stock is recorded first
        await _evaluatePhysicalLowStockResupply();

        final current = await _fs.getDailyResupplyLog(todayKey);
        if (current != null &&
            current.itemCount > 0 &&
            !current.summaryEmailSent) {
          await _dispatchResupplyEmailForDate(
            dateKey: todayKey,
            triggeredBy: _settings.isClosed
                ? 'admin_manual_store_close'
                : 'admin_scheduled_store_close',
            forceResend: false,
          );
        }
      }
    } catch (e) {
      debugPrint('[InventoryProvider] Store-closing resupply check error: $e');
    } finally {
      _isCheckingEodEmail = false;
    }
  }

  /// Manually triggers (or resends) the Store-Closing Resupply Summary Email for
  /// today's 30%-triggered products to the GDC Sari-Sari Store email account.
  Future<({bool sent, String message})> sendDailyResupplySummaryEmailNow({
    String? triggeredBy,
    bool forceResend = false,
  }) async {
    if (_isSendingDailyResupplyEmail) {
      return (
        sent: false,
        message: 'Resupply summary email is already sending.'
      );
    }
    _isSendingDailyResupplyEmail = true;
    notifyListeners();
    try {
      final now = TimeService.now;
      final todayKey = InventoryAllocation.dateKeyFor(now);

      // Ensure any currently <= 30% products are synced into today's log first
      await _evaluatePhysicalLowStockResupply();

      final log = await _fs.getDailyResupplyLog(todayKey);
      if (log == null || log.itemCount == 0) {
        return (
          sent: false,
          message:
              'No products have reached 30% of their original stock today ($todayKey).',
        );
      }

      if (log.summaryEmailSent && !forceResend) {
        return (
          sent: false,
          message:
              'Store-Closing Resupply Summary email for $todayKey was already sent.',
        );
      }

      final actor = (triggeredBy != null && triggeredBy.trim().isNotEmpty)
          ? triggeredBy.trim()
          : _adminName;

      final ok = await _dispatchResupplyEmailForDate(
        dateKey: todayKey,
        triggeredBy: actor,
        forceResend: forceResend,
      );
      if (ok) {
        final targetEmail = await AdminMessagingService().resolveStoreEmail();
        return (
          sent: true,
          message:
              'End-of-Day Resupply Summary (${log.itemCount} item${log.itemCount == 1 ? '' : 's'}) sent to $targetEmail.',
        );
      }
      final errDetail = AdminMessagingService().lastBrevoError;
      return (
        sent: false,
        message: errDetail != null && errDetail.isNotEmpty
            ? 'Failed to send Resupply Summary email: $errDetail'
            : 'Failed to send End-of-Day Resupply Summary email. Check Brevo API key or network connection.',
      );
    } finally {
      _isSendingDailyResupplyEmail = false;
      notifyListeners();
    }
  }

  Future<bool> _dispatchResupplyEmailForDate({
    required String dateKey,
    required String triggeredBy,
    required bool forceResend,
  }) async {
    final claimedLog = await _fs.claimDailyResupplyEmailDispatch(
      dateKey: dateKey,
      triggeredBy: triggeredBy,
      forceResend: forceResend,
    );
    if (claimedLog == null) return false;

    try {
      final messaging = AdminMessagingService();
      final sent = await messaging.sendDailyResupplySummaryEmail(
        log: claimedLog,
      );
      final brevoError = messaging.lastBrevoError;
      await _fs.markDailyResupplyEmailResult(
        dateKey: dateKey,
        success: sent,
        sentBy: triggeredBy,
        error:
            sent ? null : (brevoError ?? 'Brevo email delivery returned false'),
      );
      if (sent) {
        final storeEmail = claimedLog.storeEmail;
        final sorted = claimedLog.sortedItems;
        final previewNames = sorted.take(3).map((i) => i.displayName).toList();
        final remainingCount = sorted.length - previewNames.length;
        final itemsPreview = previewNames.isEmpty
            ? ''
            : ' (${previewNames.join(', ')}${remainingCount > 0 ? ' +$remainingCount more' : ''})';
        final summaryMsg =
            'End-of-Day Resupply Summary ($dateKey) for ${claimedLog.itemCount} low-stock item${claimedLog.itemCount == 1 ? '' : 's'}$itemsPreview (+${claimedLog.totalSuggestedUnits} suggested units) was emailed to $storeEmail.';
        unawaited(
          _fs.addAdminNotification(
            {
              'title': 'End-of-Day Resupply Email Sent ($dateKey)',
              'message': summaryMsg,
              'body': summaryMsg,
              'type': 'daily_resupply_summary',
              'severity': 'info',
              'status': '${claimedLog.itemCount} items summarized',
              'relatedId': dateKey,
              'dateKey': dateKey,
              'itemCount': claimedLog.itemCount,
            },
            docId: 'eod_resupply_${_sanitizeDocIdSegment(dateKey)}',
          ).catchError((_) {}),
        );
        unawaited(
          AuditLogService()
              .logAction(
                module: 'Inventory',
                action: 'DAILY_RESUPPLY_SUMMARY_EMAILED',
                targetId: dateKey,
                targetName: 'Resupply Summary ($dateKey)',
                summary: summaryMsg,
              )
              .catchError((_) {}),
        );
      }
      return sent;
    } catch (e) {
      await _fs.markDailyResupplyEmailResult(
        dateKey: dateKey,
        success: false,
        sentBy: triggeredBy,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Get all child products belonging to a parent variant group ID
  List<Product> getProductsByParentId(String parentId) {
    final cleanId = parentId.trim().toLowerCase();
    if (cleanId.isEmpty) return [];
    return _products
        .where((p) =>
            p.parentId != null && p.parentId!.trim().toLowerCase() == cleanId)
        .toList();
  }

  /// Get list of all unique Parent Group IDs present in the store inventory
  List<String> get uniqueParentIds {
    return _products
        .map((p) => p.parentId?.trim())
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
  }

  Timer? _statusTransitionTimer;

  void _checkAutomaticStoreTransitions() {
    final now = TimeService.now;

    // Auto-clear schedule if reopening time has passed
    if (_settings.scheduledOpenAt != null &&
        now.isAfter(_settings.scheduledOpenAt!)) {
      debugPrint(
          'Scheduled store outage expired. Automatically clearing schedule.');
      clearExpiredSchedule();
      return;
    }

    _ensureTodayResupplySubscription();
    unawaited(checkAndDispatchEndOfDayResupplyEmail());
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

  void _rebuildProductsWithLiveBatches() {
    _products = _rawProducts.map((p) {
      if (_hasLiveBatchStream && !p.hasVariants) {
        final liveBatches = _liveBatchesByProductId[p.id];
        if (liveBatches != null && liveBatches.isNotEmpty) {
          return p.copyWith(batches: liveBatches);
        }
      }
      return p;
    }).toList();
    _cachedSortedProducts = null;
  }

  void initialize() {
    cancelSubscriptions();
    _statusTransitionTimer?.cancel();
    _lowStockSyncDebounceTimer?.cancel();
    _resupplyLogSub?.cancel();
    _resupplyLogSub = null;
    _subscribedResupplyDateKey = null;
    _cachedSortedProducts = null;
    _cachedRecentCounts = null;
    _rawProducts = [];
    _liveBatchesByProductId = {};
    _hasLiveBatchStream = false;
    _todayResupplyLog = null;
    _alertedLowStockLevelToday.clear();
    _seenAboveThresholdInSession.clear();
    _seededResupplyAlertState = false;

    _ensureTodayResupplySubscription();
    TimeService.instance.removeListener(_onTimeServiceChanged);
    TimeService.instance.addListener(_onTimeServiceChanged);

    _isProductsLoading = true;
    _isCatalogLoading = true;
    _isTransactionsLoading = true;
    _isRefundRequestsLoading = true;
    _isSuppliersLoading = true;
    _isLossRecordsLoading = true;
    _isCustomersLoading = true;
    _isBundlesLoading = true;
    _isDeliveryLogsLoading = true;
    _isSettingsLoading = true;

    _statusTransitionTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkAutomaticStoreTransitions(),
    );

    Timer(const Duration(seconds: 3), () {
      if (isLoading) {
        _isProductsLoading = false;
        _isCatalogLoading = false;
        _isTransactionsLoading = false;
        _isRefundRequestsLoading = false;
        _isSuppliersLoading = false;
        _isLossRecordsLoading = false;
        _isCustomersLoading = false;
        _isBundlesLoading = false;
        _isDeliveryLogsLoading = false;
        _isSettingsLoading = false;
        notifyListeners();
      }
    });

    registerSubscription(_fs.productsStream().handleError((e) {
      debugPrint('Products Stream Error: $e');
      _isProductsLoading = false;
      notifyListeners();
    }).listen((list) {
      _rawProducts = list;
      _rebuildProductsWithLiveBatches();
      _isProductsLoading = false;
      notifyListeners();
      _scheduleLowStockCheck();
      if (_settings.hasStoreClosedForDayAt(TimeService.now)) {
        unawaited(checkAndDispatchEndOfDayResupplyEmail());
      }
    }));

    registerSubscription(_fs.adminNotificationsStream().handleError((e) {
      debugPrint('Admin Notifications Stream Error: $e');
    }).listen((list) {
      _adminNotifications = list;
      notifyListeners();
    }));

    // Live collectionGroup stream of products/{productId}/batches so Inventory,
    // POS, and View Batches always derive sellable stock from the exact same live batches.
    // Gracefully falls back to parent document batches mirror if rules aren't deployed yet.
    registerSubscription(_fs.allBatchesGroupStream().handleError((e) {
      debugPrint(
          'Live batches collectionGroup stream unavailable (falling back to product mirror): $e');
    }).listen((batchesMap) {
      _liveBatchesByProductId = batchesMap;
      _hasLiveBatchStream = true;
      if (_rawProducts.isNotEmpty) {
        _rebuildProductsWithLiveBatches();
        notifyListeners();
        _scheduleLowStockCheck();
      }
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
            !_refundRequests.any((old) => old.id == req.id));
        for (var req in newOnes) {
          NotificationService.showRefundRequestAlert(
              req.transactionId, req.customerName);
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

    registerSubscription(_fs.appealsStream().handleError((e) {
      debugPrint('Appeals Stream Error: $e');
      notifyListeners();
    }).listen((list) {
      _appeals = list;
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

    registerSubscription(_fs.deliveryLogsStream().handleError((e) {
      debugPrint('DeliveryLogs Stream Error: $e');
      _isDeliveryLogsLoading = false;
      notifyListeners();
    }).listen((list) {
      _deliveryLogs = list;
      _isDeliveryLogsLoading = false;
      notifyListeners();
    }));
  }

  void _onTimeServiceChanged() {
    _ensureTodayResupplySubscription();
    _scheduleLowStockCheck();
    unawaited(checkAndDispatchEndOfDayResupplyEmail());
  }

  @override
  void dispose() {
    _statusTransitionTimer?.cancel();
    _lowStockSyncDebounceTimer?.cancel();
    _resupplyLogSub?.cancel();
    TimeService.instance.removeListener(_onTimeServiceChanged);
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

  Future<void> toggleStoreStatus(bool isClosed,
      {String? message, DateTime? closeAt, DateTime? openAt}) async {
    await _fs.updateStoreStatus(isClosed,
        message: message, closeAt: closeAt, openAt: openAt);
    _settings = _settings.copyWith(
      isClosed: isClosed,
      closureMessage: message,
      clearClosureMessage: message == null,
      scheduledCloseAt: closeAt,
      scheduledOpenAt: openAt,
      clearScheduledOutage: closeAt == null && openAt == null,
      updatedAt: TimeService.now,
    );
    notifyListeners();
    if (_settings.hasStoreClosedForDayAt(TimeService.now)) {
      unawaited(checkAndDispatchEndOfDayResupplyEmail());
    }
  }

  Future<void> saveStoreSettings(StoreSettings s) async {
    await _fs.saveStoreSettings(s);
    _settings = s.copyWith(updatedAt: s.updatedAt ?? TimeService.now);
    notifyListeners();
    if (_settings.hasStoreClosedForDayAt(TimeService.now)) {
      unawaited(checkAndDispatchEndOfDayResupplyEmail());
    }
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
        if (old.totalStock <= 0 && product.totalStock > 0) {
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

  Future<void> bulkAssignSupplier(
      List<String> productIds, String? supplierId) async {
    if (productIds.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final id in productIds) {
      final ref = FirebaseFirestore.instance.collection('products').doc(id);
      batch.update(ref, {
        'supplierId': supplierId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> saveProductWithBatch({
    required Product product,
    required ProductBatch initialBatch,
    String? supplierName,
    String? receivedBy,
    String? notes,
  }) async {
    String? resolvedSupplierName = supplierName ?? initialBatch.supplierName;
    if ((resolvedSupplierName == null || resolvedSupplierName.isEmpty) &&
        product.supplierId != null &&
        product.supplierId!.isNotEmpty) {
      try {
        resolvedSupplierName =
            _suppliers.firstWhere((s) => s.id == product.supplierId).name;
      } catch (_) {}
    }

    await _fs.saveProductWithBatch(
      product: product,
      initialBatch: initialBatch,
      supplierName: resolvedSupplierName,
      receivedBy: receivedBy ?? _adminName,
      notes: notes,
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

  /// Receives stock delivery with optional Bulk-to-Single UOM conversion and FIFO batch tracking.
  Future<void> receiveDeliveryWithUom({
    required Product product,
    required int inputQuantity, // Could be 50 pieces OR 2 boxes
    required double inputCost, // Could be ₱20/pc OR ₱480/box
    int extraLooseUnits = 0, // Optional loose base units alongside bulk boxes
    bool isBulkDelivery = false,
    DateTime? datePurchased,
    DateTime? dateArrived,
    DateTime? batchExpiryDate,
    String? supplierId,
    String? supplierName,
    String? invoiceNumber,
    String? notes,
  }) async {
    final int sanitizedQty = inputQuantity < 0 ? 0 : inputQuantity;
    final int sanitizedExtra = extraLooseUnits < 0 ? 0 : extraLooseUnits;
    final double sanitizedCost = inputCost < 0 ? 0.0 : inputCost;

    // 1. Convert to Base Units (Pieces), preserving any extra loose units in bulk mode
    final int totalBaseUnits = isBulkDelivery
        ? (product.convertBulkToUnits(sanitizedQty) + sanitizedExtra)
        : sanitizedQty;

    // 2. Convert to Unit Cost (COGS per piece)
    final double calculatedPieceCost = isBulkDelivery
        ? (sanitizedExtra > 0 && totalBaseUnits > 0
            ? double.parse(
                ((sanitizedQty * sanitizedCost) / totalBaseUnits)
                    .toStringAsFixed(2),
              )
            : product.calculateUnitCostFromPack(sanitizedCost))
        : sanitizedCost;

    final DateTime effectiveArrived = dateArrived ?? DateTime.now();
    final DateTime effectivePurchased = datePurchased ?? effectiveArrived;
    final String? effectiveSupplierId =
        (supplierId != null && supplierId.trim().isNotEmpty)
            ? supplierId.trim()
            : product.supplierId?.trim();
    String? effectiveSupplierName = supplierName;
    if ((effectiveSupplierName == null || effectiveSupplierName.isEmpty) &&
        effectiveSupplierId != null &&
        effectiveSupplierId.isNotEmpty) {
      try {
        effectiveSupplierName =
            _suppliers.firstWhere((s) => s.id == effectiveSupplierId).name;
      } catch (_) {}
    }

    // 3. Create the FIFO Batch with human-readable BATCH-YYYYMMDD-XXXX ID
    final newBatch = ProductBatch(
      batchId: InventoryBatchService.generateBatchId(effectiveArrived),
      productId: product.id,
      productName: product.name,
      supplierId: effectiveSupplierId,
      supplierName: effectiveSupplierName,
      datePurchased: effectivePurchased,
      dateArrived: effectiveArrived,
      expiryDate: batchExpiryDate,
      costPrice: calculatedPieceCost,
      initialQty: totalBaseUnits,
      remainingQty: totalBaseUnits,
      status: BatchStatus.active,
      invoiceNumber: invoiceNumber,
    );

    Product updatedProduct = product;
    if (isBulkDelivery && sanitizedCost > 0) {
      updatedProduct = product.copyWith(packCost: sanitizedCost);
    }

    // 4. Execute atomic Firestore transaction via InventoryBatchService
    await _fs.processSingleDeliveryAtomic(
      product: updatedProduct,
      newBatch: newBatch,
      receivedBy: _adminName,
      supplierName: effectiveSupplierName,
      invoiceNumber: invoiceNumber,
      notes: notes,
      settings: _settings,
    );

    notifyListeners();
  }

  /// Synchronizes a single product's `stock`, `reservedStock`, and batch statuses
  /// from its authoritative `products/{productId}/batches` subcollection.
  Future<int> syncProductStockFromBatches(String productId) async {
    final result = await _batchService.reconcileProductStock(
      productId,
      dryRun: false,
    );
    notifyListeners();
    return result.newStock;
  }

  /// Admin utility to safely reconcile a single product's stock, expired/depleted
  /// batch statuses, and `reservedStock` from open orders.
  Future<ProductStockReconciliationResult> reconcileProductStock(
    String productId, {
    bool dryRun = false,
  }) async {
    final result = await _batchService.reconcileProductStock(
      productId,
      dryRun: dryRun,
    );
    if (!dryRun) {
      notifyListeners();
    }
    return result;
  }

  /// Admin utility to safely reconcile ALL products across the store.
  Future<InventoryReconciliationReport> reconcileAllStock({
    bool dryRun = false,
    String? defaultFallbackSupplierId,
  }) async {
    final report = await _batchService.reconcileAllStock(
      dryRun: dryRun,
      defaultFallbackSupplierId: defaultFallbackSupplierId,
    );
    if (!dryRun) {
      notifyListeners();
    }
    return report;
  }

  /// Atomically reconciles physical shelf counts against `products/{productId}/batches`.
  Future<int> reconcileProductBatches({
    required String productId,
    required Map<String, int> physicalQtyByBatchId,
  }) async {
    final synced = await _batchService.reconcileProductBatchesAtomic(
      productId: productId,
      physicalQtyByBatchId: physicalQtyByBatchId,
      performedByName: _adminName,
      settings: _settings,
    );
    notifyListeners();
    return synced;
  }

  /// Runs global orphan-supplier and batch-to-stock reconciliation audit.
  Future<InventoryReconciliationReport> auditAndReconcileInventory({
    bool dryRun = true,
    String? defaultFallbackSupplierId,
  }) async {
    final report = await _batchService.auditAndReconcileInventory(
      dryRun: dryRun,
      defaultFallbackSupplierId: defaultFallbackSupplierId,
    );
    if (!dryRun) {
      notifyListeners();
    }
    return report;
  }

  /// Synchronous lookup of a cached [Supplier] by ID, or null if not found.
  Supplier? findSupplierById(String? supplierId) {
    final id = supplierId?.trim() ?? '';
    if (id.isEmpty) return null;
    for (final s in _suppliers) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> receiveDelivery({
    required Product product,
    required int qtyReceived,
    required double unitCost,
    bool isBulkDelivery = false,
    DateTime? datePurchased,
    DateTime? dateArrived,
    DateTime? batchExpiryDate,
    String? supplierId,
    String? supplierName,
    String? invoiceNumber,
    String? notes,
  }) async {
    return receiveDeliveryWithUom(
      product: product,
      inputQuantity: qtyReceived,
      inputCost: unitCost,
      isBulkDelivery: isBulkDelivery,
      datePurchased: datePurchased,
      dateArrived: dateArrived,
      batchExpiryDate: batchExpiryDate,
      supplierId: supplierId,
      supplierName: supplierName,
      invoiceNumber: invoiceNumber,
      notes: notes,
    );
  }

  Future<void> processInquiryDelivery({
    required RestockInquiry inquiry,
    required List<Map<String, dynamic>> receivedItemData,
    DateTime? datePurchased,
    DateTime? dateArrived,
    String? invoiceNumber,
    String? notes,
  }) async {
    bool isShortDelivery = false;
    final List<DeliveryItemPayload> deliveryPayloads = [];
    final List<RestockInquiryItem> updatedInquiryItems = [];
    final DateTime effectivePurchased = datePurchased ?? inquiry.createdAt;
    final DateTime effectiveArrived = dateArrived ?? DateTime.now();

    for (final expectedItem in inquiry.items) {
      final itemMap = receivedItemData.firstWhere(
        (m) => m['productId'] == expectedItem.productId,
        orElse: () => <String, dynamic>{},
      );

      final int qtyRec = itemMap['receivedQty'] != null
          ? (itemMap['receivedQty'] as num).toInt()
          : expectedItem.requestedQty;
      final double unitCost =
          itemMap['costPrice'] != null && (itemMap['costPrice'] as num) > 0
              ? (itemMap['costPrice'] as num).toDouble()
              : expectedItem.costPrice;
      final DateTime? expDate = itemMap['expiryDate'] as DateTime?;
      final String? itemNote = itemMap['discrepancyNote']?.toString();

      updatedInquiryItems.add(expectedItem.copyWith(
        receivedQty: qtyRec,
        receivedCostPrice: unitCost,
        discrepancyNote: itemNote,
      ));

      if (qtyRec < expectedItem.requestedQty) {
        isShortDelivery = true;
      }

      if (qtyRec <= 0) continue;

      try {
        final prod =
            _products.firstWhere((p) => p.id == expectedItem.productId);

        final newBatch = ProductBatch(
          batchId: InventoryBatchService.generateBatchId(effectiveArrived),
          productId: prod.id,
          productName: prod.name,
          supplierId: inquiry.supplierId,
          supplierName: inquiry.supplierName,
          datePurchased: effectivePurchased,
          dateArrived: effectiveArrived,
          expiryDate: expDate,
          costPrice: unitCost > 0 ? unitCost : prod.costPrice,
          initialQty: qtyRec,
          remainingQty: qtyRec,
          status: BatchStatus.active,
          invoiceNumber: invoiceNumber,
        );

        deliveryPayloads.add(DeliveryItemPayload(
          product: prod,
          qtyReceived: qtyRec,
          unitCost: unitCost > 0 ? unitCost : prod.costPrice,
          newBatch: newBatch,
          orderedQty: expectedItem.requestedQty,
          orderedUnitCost: expectedItem.costPrice,
          discrepancyNote: itemNote,
          supplierId: inquiry.supplierId,
          supplierName: inquiry.supplierName,
        ));
      } catch (e) {
        debugPrint('Error preparing product payload for delivery: $e');
      }
    }

    final RestockInquiryStatus newStatus = isShortDelivery
        ? RestockInquiryStatus.partiallyFulfilled
        : RestockInquiryStatus.fulfilled;

    await _fs.processInquiryDeliveryAtomic(
      inquiryId: inquiry.id,
      newStatus: newStatus,
      items: deliveryPayloads,
      receivedBy: _adminName,
      supplierId: inquiry.supplierId,
      supplierName: inquiry.supplierName,
      updatedInquiryItems: updatedInquiryItems.map((i) => i.toMap()).toList(),
      invoiceNumber: invoiceNumber,
      notes: notes,
      settings: _settings,
    );

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

  /// Hydrates the latest supplier profile directly from Firestore, falling back to cached state on offline error.
  Future<Supplier?> fetchSupplierFresh(String id) async {
    try {
      final fresh = await _fs.fetchSupplierById(id);
      if (fresh != null) return fresh;
    } catch (e) {
      debugPrint('fetchSupplierFresh fallback to cache: $e');
    }
    return getSupplierById(id);
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

  Future<StoreTransaction> completeSale(List<CartItem> cart, double cash,
      {double? totalOverride,
      String? customerId,
      String? customerEmail,
      PaymentMethod paymentMethod = PaymentMethod.cash,
      TransactionType type = TransactionType.inStore}) async {
    if (_isProcessingSale) throw Exception('Transaction in progress');

    // 1. Final stock check against live physical inventory (POS has 100% access to unreserved physical stock)
    for (var item in cart) {
      try {
        final p = _products.firstWhere((p) => p.id == item.productId);
        if (item.variantId != null) {
          final v = p.variants.firstWhere((v) => v.id == item.variantId);
          final int allowedStock = v.availableStock;
          if (allowedStock < item.qty) {
            throw Exception(
                '${p.name} (${v.name}) exceeds available physical stock ($allowedStock available).');
          }
        } else {
          final int allowedStock = p.availableStock;
          if (allowedStock < item.qty) {
            throw Exception(
                '${p.name} exceeds available physical stock ($allowedStock available).');
          }
        }
      } catch (e) {
        if (e is StateError) {
          throw Exception(
              'Product ${item.name} no longer exists in inventory.');
        }
        rethrow;
      }
    }

    _isProcessingSale = true;
    notifyListeners();

    try {
      final double total = totalOverride ??
          cart.fold<double>(0.0, (s, i) => s + i.price * i.qty);
      final double change =
          paymentMethod == PaymentMethod.cash ? (cash - total) : 0.0;

      final txDraft = StoreTransaction(
        id: const Uuid().v4(),
        items: cart,
        total: total,
        cashTendered: paymentMethod == PaymentMethod.cash ? cash : 0.0,
        changeGiven: change,
        createdAt: DateTime.now(),
        customerId: customerId,
        customerEmail: customerEmail,
        paymentMethod: paymentMethod,
        type: type,
      );

      // Atomic Firestore transaction FIFO batch deduction + batchAllocations stamping
      final checkoutResult = await _batchService.deductStockFIFO(
        items: cart,
        transactionToWrite: txDraft,
        settings: _settings,
        performedByName: _adminName,
      );

      final tx = checkoutResult.transaction ??
          StoreTransaction(
            id: txDraft.id,
            items: checkoutResult.processedItems,
            total: total,
            cashTendered: paymentMethod == PaymentMethod.cash ? cash : 0.0,
            changeGiven: change,
            createdAt: txDraft.createdAt,
            customerId: customerId,
            customerEmail: customerEmail,
            paymentMethod: paymentMethod,
            type: type,
          );

      // Trigger heads-up payment pop-up alert (catch errors so notification issues never block sale)
      try {
        await NotificationService.showPaymentReceivedAlert(
            tx.id.length >= 8 ? tx.id.substring(0, 8) : tx.id,
            total,
            customerEmail ?? 'Walk-in Customer');
      } catch (e) {
        debugPrint('Notification alert error: $e');
      }

      // Immediately evaluate Low Stock (<= 30% of original stock) / Out of Stock
      // after POS deduction so alerts + daily resupply logs fire without waiting
      // for stream debounce.
      final now = TimeService.now;
      final todayKey = InventoryAllocation.dateKeyFor(now);
      final storeEmail = AdminMessagingService().storeEmailSync;

      for (var item in cart) {
        try {
          final p = _products.firstWhere((p) => p.id == item.productId);
          final ProductVariant? variant = item.variantId != null
              ? p.variants.firstWhere((v) => v.id == item.variantId)
              : null;
          final int remainingTotal = variant != null
              ? (variant.stock - item.qty).clamp(0, 999999)
              : (p.totalStock - item.qty).clamp(0, 999999);
          final int reserved = variant != null
              ? variant.effectiveReservedStock
              : p.effectiveReservedStock;
          final int remainingAvail =
              (remainingTotal - reserved).clamp(0, 999999);
          final int origStock = variant != null
              ? variant.effectiveOriginalStock
              : p.effectiveOriginalStock;
          final int alertThreshold =
              InventoryAllocation.calculateLowStockTrigger(origStock);
          if (origStock > 0 && remainingAvail <= alertThreshold) {
            final bool isOos = remainingAvail <= 0;
            final String itemKey =
                DailyResupplyItem.buildItemKey(p.id, variant?.id);
            final String nextLevel = isOos ? 'oos' : 'low';
            final String memKey = '$todayKey::$itemKey';
            final int reserve = variant != null
                ? variant.effectivePhysicalReserve
                : p.effectivePhysicalReserve;
            final int onlineAvail =
                InventoryAllocation.calculateOnlineAvailable(
              totalStock: remainingTotal,
              physicalReserve: reserve,
              reservedStock: reserved,
            );
            final resupplyItem = DailyResupplyItem(
              itemKey: itemKey,
              productId: p.id,
              variantId: variant?.id,
              productName: p.name,
              variantName: variant?.name,
              category: p.category,
              unit: p.unit,
              originalStock: origStock,
              lowStockThreshold: alertThreshold,
              physicalStock: remainingAvail,
              onlineStock: onlineAvail,
              totalStock: remainingTotal,
              availableStock: remainingAvail,
              suggestedResupplyQty:
                  InventoryAllocation.calculateSuggestedResupplyQty(
                availableStock: remainingAvail,
                originalStock: origStock,
              ),
              onlineOutOfStock: onlineAvail <= 0,
              firstTriggeredAt: now,
              lastUpdatedAt: now,
            );

            final String? prevLevel = _alertedLowStockLevelToday[memKey];
            if (prevLevel == null || (prevLevel == 'low' && isOos)) {
              _alertedLowStockLevelToday[memKey] = nextLevel;
              _seenAboveThresholdInSession.remove(itemKey);
              _emitLowStockInventoryAlert(
                todayKey: todayKey,
                resupplyItem: resupplyItem,
              );
            }
            unawaited(
              _fs
                  .recordDailyResupplyItem(
                dateKey: todayKey,
                item: resupplyItem,
                storeEmail: storeEmail,
              )
                  .catchError((e) {
                debugPrint(
                    '[InventoryProvider] Failed recording POS resupply item: $e');
                return (isNew: false, escalatedToOos: false);
              }),
            );
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

  void _notifySupplierLowStock(Product p) {
    if (p.supplierId == null) return;
    try {
      final supplier = _suppliers.firstWhere((s) => s.id == p.supplierId);
      if (supplier.autoNotifyLowStock) {
        NotificationService.showLowStockSupplierAlert(
            p.name, supplier.name, supplier.phone);
      }
    } catch (_) {}
  }

  Future<void> refundTransaction(StoreTransaction tx) async {
    await _fs.refundTransaction(tx);
  }

  Future<void> approveRefundRequest(RefundRequest request,
      {required RefundCondition condition, String? notes}) async {
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

    await _fs.processApprovedRefund(
      updatedReq,
      _adminName,
      settings: _settings,
    );

    // Send notification to customer with store response
    await NotificationService.sendRefundUpdate(
        request.transactionId, request.customerEmail, true,
        storeResponse: notes);
  }

  Future<void> rejectRefundRequest(RefundRequest request, String reason,
      {String? notes}) async {
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

    await _fs.updateRefundStatus(request.id, RefundStatus.rejected, _adminName,
        reason: reason, notes: notes ?? reason);

    final orderSnap = await FirebaseFirestore.instance
        .collection('orders')
        .where('orderId', isEqualTo: request.transactionId)
        .limit(1)
        .get();

    if (orderSnap.docs.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderSnap.docs.first.id)
          .update({
        'status': OrderStatus.refundRejected.name,
        'rejectionReason': reason,
      });
    }

    await NotificationService.sendRefundUpdate(
        request.transactionId, request.customerEmail, false,
        storeResponse: reason);
  }
}
