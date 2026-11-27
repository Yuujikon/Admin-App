import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/order.dart';
import '../models/product.dart';
import '../models/purchase_order.dart';
import '../models/receiving_record.dart';
import '../models/refund_request.dart';
import '../models/store_settings.dart';
import '../models/supplier.dart';
import '../models/transaction.dart';
import '../utils/inventory_allocation.dart';
import '../utils/pricing_engine.dart';

/// Pure result of computing a FIFO deduction across sorted active batches.
class FifoDeductionPlan {
  final List<BatchAllocation> allocations;
  final List<ProductBatch> updatedBatches;
  final List<ProductBatch> newlyDepletedBatches;
  final List<ProductBatch> newlyExpiredBatches;
  final double totalCogs;

  const FifoDeductionPlan({
    required this.allocations,
    required this.updatedBatches,
    required this.newlyDepletedBatches,
    this.newlyExpiredBatches = const [],
    required this.totalCogs,
  });
}

/// Pure result representing a single backtracked batch segment for a refund.
class RefundBacktrackAllocation {
  final String batchId;
  final int qtyReturned;
  final DateTime? datePurchased;
  final DateTime? dateArrived;
  final double costPrice;
  final String? supplierName;
  final String? poNumber;
  final bool isLegacyFallback;

  const RefundBacktrackAllocation({
    required this.batchId,
    required this.qtyReturned,
    this.datePurchased,
    this.dateArrived,
    this.costPrice = 0.0,
    this.supplierName,
    this.poNumber,
    this.isLegacyFallback = false,
  });
}

/// Item payload describing one product line being refunded.
class RefundLineInput {
  final String productId;
  final String? variantId;
  final String productName;
  final String barcode;
  final int qty;
  final double price;

  /// Canonical condition: `'SELLABLE'` or `'DAMAGED'`.
  /// Also accepts legacy values: `'restock'`, `'restockable'`, `'damaged'`, `'expired'`, `'other'`.
  final String condition;

  /// Optional explicit batch ID confirmed by the admin for partial refunds on multi-batch items.
  final String? preferredBatchId;

  const RefundLineInput({
    required this.productId,
    this.variantId,
    required this.productName,
    this.barcode = '',
    required this.qty,
    required this.price,
    this.condition = 'SELLABLE',
    this.preferredBatchId,
  });

  bool get isSellable {
    final c = condition.trim().toLowerCase();
    return c == 'sellable' ||
        c == 'restock' ||
        c == 'restockable' ||
        c == 'good';
  }

  String get canonicalCondition => isSellable ? 'SELLABLE' : 'DAMAGED';

  String get lossType {
    final c = condition.trim().toLowerCase();
    return c == 'expired' ? 'expired' : 'damaged';
  }
}

/// Result returned from [InventoryBatchService.deductStockFIFO].
class FifoCheckoutResult {
  final List<CartItem> processedItems;
  final List<ProductBatch> depletedBatches;
  final StoreTransaction? transaction;

  const FifoCheckoutResult({
    required this.processedItems,
    required this.depletedBatches,
    this.transaction,
  });
}

/// Result returned from [InventoryBatchService.restoreBatchOnRefund].
class RefundRestorationResult {
  final List<RefundBacktrackAllocation> restoredAllocations;
  final List<RefundBacktrackAllocation> writtenOffAllocations;

  const RefundRestorationResult({
    required this.restoredAllocations,
    required this.writtenOffAllocations,
  });
}

/// Validated supplier identity resolved inside a Firestore transaction.
class ValidatedSupplierLink {
  final String supplierId;
  final String supplierName;

  const ValidatedSupplierLink({
    required this.supplierId,
    required this.supplierName,
  });
}

/// Single line item input for [InventoryBatchService.receiveRestockInquiryAtomic].
class InquiryDeliveryBatchInput {
  final String productId;
  final String productName;
  final int qtyReceived;
  final double unitCost;
  final DateTime datePurchased;
  final DateTime dateArrived;
  final DateTime? expiryDate;
  final String? customBatchId;
  final String? invoiceNumber;
  final String? discrepancyNote;
  final int? orderedQty;
  final double? orderedUnitCost;

  const InquiryDeliveryBatchInput({
    required this.productId,
    required this.productName,
    required this.qtyReceived,
    required this.unitCost,
    required this.datePurchased,
    required this.dateArrived,
    this.expiryDate,
    this.customBatchId,
    this.invoiceNumber,
    this.discrepancyNote,
    this.orderedQty,
    this.orderedUnitCost,
  });
}

/// Audit finding for a batch missing a valid supplier linkage.
class OrphanBatchFinding {
  final String productId;
  final String productName;
  final String batchId;
  final int remainingQty;
  final String? currentSupplierId;
  final String reason;
  final String? suggestedSupplierId;
  final String? suggestedSupplierName;

  const OrphanBatchFinding({
    required this.productId,
    required this.productName,
    required this.batchId,
    required this.remainingQty,
    this.currentSupplierId,
    required this.reason,
    this.suggestedSupplierId,
    this.suggestedSupplierName,
  });
}

/// Audit finding for a product whose stored `stock` or `reservedStock` diverges from active batches/orders.
class StockDriftFinding {
  final String productId;
  final String productName;
  final int storedStock;
  final int activeBatchSum;
  final int storedReservedStock;
  final int expectedReservedStock;
  final int expiredBatchesDetected;
  final int depletedBatchesDetected;
  final bool embeddedMirrorOutOfSync;

  const StockDriftFinding({
    required this.productId,
    required this.productName,
    required this.storedStock,
    required this.activeBatchSum,
    this.storedReservedStock = 0,
    this.expectedReservedStock = 0,
    this.expiredBatchesDetected = 0,
    this.depletedBatchesDetected = 0,
    this.embeddedMirrorOutOfSync = false,
  });

  int get delta => activeBatchSum - storedStock;
  bool get hasReservedDrift => storedReservedStock != expectedReservedStock;
}

/// Result returned by [InventoryBatchService.reconcileProductStock].
class ProductStockReconciliationResult {
  final String productId;
  final String productName;
  final int oldStock;
  final int newStock;
  final int oldReservedStock;
  final int newReservedStock;
  final int expiredBatchesMarked;
  final int depletedBatchesMarked;
  final int batchesScanned;
  final bool dryRun;

  const ProductStockReconciliationResult({
    required this.productId,
    required this.productName,
    required this.oldStock,
    required this.newStock,
    required this.oldReservedStock,
    required this.newReservedStock,
    required this.expiredBatchesMarked,
    required this.depletedBatchesMarked,
    required this.batchesScanned,
    this.dryRun = false,
  });

  bool get changed =>
      oldStock != newStock ||
      oldReservedStock != newReservedStock ||
      expiredBatchesMarked > 0 ||
      depletedBatchesMarked > 0;
}

/// Summary report returned by [InventoryBatchService.auditAndReconcileInventory]
/// and [InventoryBatchService.reconcileAllStock].
class InventoryReconciliationReport {
  final int productsScanned;
  final int batchesScanned;
  final List<OrphanBatchFinding> orphanBatches;
  final List<StockDriftFinding> stockDrifts;
  final int batchesSupplierFixed;
  final int productsStockFixed;
  final int reservedStockFixed;
  final int expiredBatchesMarked;
  final int depletedBatchesMarked;
  final bool dryRun;

  const InventoryReconciliationReport({
    required this.productsScanned,
    required this.batchesScanned,
    required this.orphanBatches,
    required this.stockDrifts,
    this.batchesSupplierFixed = 0,
    this.productsStockFixed = 0,
    this.reservedStockFixed = 0,
    this.expiredBatchesMarked = 0,
    this.depletedBatchesMarked = 0,
    this.dryRun = true,
  });

  bool get hasIssues => orphanBatches.isNotEmpty || stockDrifts.isNotEmpty;
}

class _ActorInfo {
  final String uid;
  final String email;
  final String name;
  final String role;

  const _ActorInfo({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
  });

  Map<String, dynamic> toPerformedByMap() => {
        'uid': uid,
        'name': name,
        'email': email,
        'role': role,
      };
}

/// Centralized First-In, First-Out (FIFO) Inventory Batch Service.
///
/// Manages the `products/{productId}/batches/{batchId}` subcollection atomically
/// inside Firestore `runTransaction` blocks while keeping top-level `products/{id}.stock`,
/// embedded `products/{id}.batches`, and legacy `inventory_batches` synchronized
/// for zero breaking changes across Admin POS and Customer Storefront.
class InventoryBatchService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  static const Uuid _uuid = Uuid();

  InventoryBatchService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('products');
  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get _transactions =>
      _db.collection('transactions');
  CollectionReference<Map<String, dynamic>> get _auditLogs =>
      _db.collection('audit_logs');
  CollectionReference<Map<String, dynamic>> get _inventoryBatches =>
      _db.collection('inventory_batches');

  /// Returns the `physicalReserve` (and backfilled `initialStock`) update fields
  /// for a standard product.
  ///
  /// - When [isRestock] is `true` (PO receiving, manual stock-in, restock
  ///   inquiry, or stock increase), recalculates `physicalReserve = (syncedStock * 0.25).ceil()`.
  /// - Otherwise (POS sale, refund, write-off, reconciliation, reservation),
  ///   preserves the stored `physicalReserve` and backfills `initialStock` from
  ///   the pre-deduction baseline if missing on legacy documents so the 30%
  ///   low-stock alert always evaluates against the true original stock.
  Map<String, dynamic> _physicalReserveFields(
    Product product,
    int syncedStock, {
    required bool isRestock,
  }) {
    final int baselineBeforeChange = product.effectiveOriginalStock > 0
        ? product.effectiveOriginalStock
        : syncedStock;
    final int nextReserve = isRestock
        ? InventoryAllocation.calculatePhysicalReserve(syncedStock)
        : InventoryAllocation.resolvePhysicalReserve(
            totalStock: baselineBeforeChange,
            storedPhysicalReserve: product.physicalReserve,
          );
    final Map<String, dynamic> fields = {'physicalReserve': nextReserve};
    if (!isRestock &&
        (product.initialStock == null || product.initialStock! <= 0) &&
        baselineBeforeChange > 0) {
      fields['initialStock'] = baselineBeforeChange;
    }
    return fields;
  }

  /// Returns `physicalReserve` (and backfilled `initialStock`) update fields
  /// for variant products (per-variant dot-paths + parent aggregate).
  Map<String, dynamic> _variantPhysicalReserveFields(
    Product product, {
    Map<String, int>? stockOverrides,
    Set<String> restockedVariantIds = const {},
  }) {
    int totalReserve = 0;
    final Map<String, dynamic> fields = {};

    for (final v in product.variants) {
      final int vStock = (stockOverrides?[v.id] ?? v.stock).clamp(0, 999999999);
      final bool isRestock = restockedVariantIds.contains(v.id);
      final int baselineBeforeChange =
          v.effectiveOriginalStock > 0 ? v.effectiveOriginalStock : vStock;
      final int nextReserve = isRestock
          ? InventoryAllocation.calculatePhysicalReserve(vStock)
          : InventoryAllocation.resolvePhysicalReserve(
              totalStock: baselineBeforeChange,
              storedPhysicalReserve: v.physicalReserve,
            );
      totalReserve += nextReserve;
      fields['variants.${v.id}.physicalReserve'] = nextReserve;
      if (isRestock && vStock > 0) {
        fields['variants.${v.id}.initialStock'] = vStock;
      } else if ((v.initialStock == null || v.initialStock! <= 0) &&
          baselineBeforeChange > 0) {
        fields['variants.${v.id}.initialStock'] = baselineBeforeChange;
      }
    }

    fields['physicalReserve'] = totalReserve;
    return fields;
  }

  /// Computes the updated original stock baseline (`initialStock`) whenever
  /// new stock is added/restocked so both the 25% walk-in reserve and the
  /// 30% low-stock alert track the current restock cycle accurately.
  int _nextInitialStockOnRestock(Product product, int syncedStock) {
    if (syncedStock <= 0) return product.effectiveInitialStock;
    return syncedStock;
  }

  CollectionReference<Map<String, dynamic>> get _deliveryLogs =>
      _db.collection('delivery_logs');
  CollectionReference<Map<String, dynamic>> get _receivingRecords =>
      _db.collection('receiving_records');
  CollectionReference<Map<String, dynamic>> get _purchaseOrders =>
      _db.collection('purchase_orders');
  CollectionReference<Map<String, dynamic>> get _lossRecords =>
      _db.collection('loss_records');
  CollectionReference<Map<String, dynamic>> get _refundRecords =>
      _db.collection('refund_records');
  CollectionReference<Map<String, dynamic>> get _refundRequests =>
      _db.collection('refund_requests');
  CollectionReference<Map<String, dynamic>> get _customers =>
      _db.collection('customers');
  CollectionReference<Map<String, dynamic>> get _suppliers =>
      _db.collection('suppliers');
  CollectionReference<Map<String, dynamic>> get _restockInquiries =>
      _db.collection('restock_inquiries');

  CollectionReference<Map<String, dynamic>> _batchesCol(String productId) =>
      _products.doc(productId).collection('batches');

  // ── Batch ID Generators ───────────────────────────────────────────────────

  /// Generates a unique human-readable batch ID (`BATCH-YYYYMMDD-XXXX`).
  static String generateBatchId([DateTime? date]) {
    final d = date ?? DateTime.now();
    final datePart = DateFormat('yyyyMMdd').format(d);
    final suffix = _uuid.v4().replaceAll('-', '').substring(0, 4).toUpperCase();
    return 'BATCH-$datePart-$suffix';
  }

  /// Generates a unique PO-referenced batch ID (`PO-YYYYMMDD-XXX-XXXX`) so
  /// batches received via Purchase Orders immediately reference their PO number
  /// while remaining unique across products, split expiries, and partial deliveries.
  static String generatePoBatchId(String poNumber, {DateTime? date}) {
    final cleaned = poNumber
        .trim()
        .replaceFirst(RegExp(r'^#+'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (cleaned.isEmpty) {
      return generateBatchId(date);
    }
    final normalizedPo = ProductBatch.formatPoNumber(cleaned);
    final suffix = _uuid.v4().replaceAll('-', '').substring(0, 4).toUpperCase();
    return '$normalizedPo-$suffix';
  }

  /// Generates a fallback batch ID for legacy refunds (`RETURN-RESTORE-YYYYMMDD-XXXX`).
  static String generateReturnRestoreBatchId([DateTime? date]) {
    final d = date ?? DateTime.now();
    final datePart = DateFormat('yyyyMMdd').format(d);
    final suffix = _uuid.v4().replaceAll('-', '').substring(0, 4).toUpperCase();
    return 'RETURN-RESTORE-$datePart-$suffix';
  }

  // ── Pure FIFO & Refund Backtrack Algorithms (Unit-Testable) ───────────────

  /// Pure FIFO deduction algorithm.
  ///
  /// Enforces the unified Sellable Stock rule:
  /// - `status == 'ACTIVE'` (case-insensitive)
  /// - `remainingQty > 0`
  /// - not expired (`expiryDate == null || expiryDate.isAfter(now)`)
  ///
  /// Automatically transitions expired batches to `'EXPIRED'` and zero-qty batches
  /// to `'DEPLETED'`, sorts sellable batches by earliest `expiryDate` then `dateArrived`
  /// (`createdAt`) then `batchId`, verifies total sellable stock >= [requestedQty],
  /// and deducts sequentially with zero possibility of negative stock.
  static FifoDeductionPlan computeFifoDeduction({
    required List<ProductBatch> batches,
    required int requestedQty,
    String productName = 'Product',
    DateTime? now,
  }) {
    final DateTime effectiveNow = now ?? DateTime.now();
    final List<ProductBatch> normalized = [];
    final List<ProductBatch> newlyExpired = [];

    for (final b in batches) {
      final norm = b.normalizedForPersistence(now: effectiveNow);
      if (norm.status == BatchStatus.expired &&
          b.status != BatchStatus.expired) {
        newlyExpired.add(norm);
      }
      normalized.add(norm);
    }
    normalized.sort(ProductBatch.compareFifo);

    if (requestedQty <= 0) {
      return FifoDeductionPlan(
        allocations: const [],
        updatedBatches: normalized,
        newlyDepletedBatches: const [],
        newlyExpiredBatches: newlyExpired,
        totalCogs: 0.0,
      );
    }

    final int totalAvailable =
        ProductBatch.sumSellableStock(normalized, now: effectiveNow);

    if (totalAvailable < requestedQty) {
      throw Exception(
        'Insufficient sellable stock for $productName. Available in valid active batches: $totalAvailable, Requested: $requestedQty.',
      );
    }

    int needed = requestedQty;
    double totalCogs = 0.0;
    final List<BatchAllocation> allocations = [];
    final List<ProductBatch> updated = [];
    final List<ProductBatch> newlyDepleted = [];

    for (final b in normalized) {
      if (needed <= 0 || !b.isSellableAt(effectiveNow)) {
        updated.add(b);
        continue;
      }

      if (b.remainingQty >= needed) {
        final int take = needed;
        final int nextRem = (b.remainingQty - take).clamp(0, b.remainingQty);
        final String nextStatus =
            nextRem == 0 ? BatchStatus.depleted : BatchStatus.active;

        final updatedBatch = b.copyWith(
          remainingQty: nextRem,
          status: nextStatus,
        );
        updated.add(updatedBatch);
        if (nextRem == 0) {
          newlyDepleted.add(updatedBatch);
        }

        allocations.add(BatchAllocation(
          batchId: b.batchId,
          quantity: take,
          unitCost: b.costPrice,
          datePurchased: b.datePurchased,
          dateArrived: b.dateArrived,
          supplierName: b.supplierName,
          poNumber: b.poNumber,
        ));
        totalCogs += take * b.costPrice;
        needed = 0;
      } else {
        final int take = b.remainingQty;
        final updatedBatch = b.copyWith(
          remainingQty: 0,
          status: BatchStatus.depleted,
        );
        updated.add(updatedBatch);
        newlyDepleted.add(updatedBatch);

        allocations.add(BatchAllocation(
          batchId: b.batchId,
          quantity: take,
          unitCost: b.costPrice,
          datePurchased: b.datePurchased,
          dateArrived: b.dateArrived,
          supplierName: b.supplierName,
          poNumber: b.poNumber,
        ));
        totalCogs += take * b.costPrice;
        needed -= take;
      }
    }

    return FifoDeductionPlan(
      allocations: allocations,
      updatedBatches: updated,
      newlyDepletedBatches: newlyDepleted,
      newlyExpiredBatches: newlyExpired,
      totalCogs: totalCogs,
    );
  }

  /// Pure refund backtracking algorithm.
  ///
  /// Matches [refundQty] against the original receipt's [batchAllocations]
  /// (accounting for [alreadyReturnedQty] from any earlier partial returns).
  /// When [preferredBatchId] is provided, prioritizes that batch first; otherwise
  /// restores in reverse allocation order so the most recently split batch is
  /// unwound cleanly (or full quantity across all allocated batches on full refund).
  static List<RefundBacktrackAllocation> computeRefundBacktrack({
    required List<BatchAllocation> batchAllocations,
    required int refundQty,
    int alreadyReturnedQty = 0,
    String? preferredBatchId,
  }) {
    if (refundQty <= 0 || batchAllocations.isEmpty) return const [];

    // Filter out synthetic/non-batch IDs from very old legacy transactions
    final List<BatchAllocation> validAllocations = batchAllocations
        .where((a) =>
            a.batchId.isNotEmpty &&
            !a.batchId.startsWith('fallback-') &&
            !a.batchId.startsWith('variant-'))
        .toList();

    if (validAllocations.isEmpty) return const [];

    // Compute remaining refundable capacity per allocation (reverse order skips alreadyReturnedQty)
    final List<int> remainingCap =
        validAllocations.map((a) => a.qtyDeducted).toList();
    int prevReturned = alreadyReturnedQty;
    for (int i = validAllocations.length - 1; i >= 0 && prevReturned > 0; i--) {
      final int consume =
          remainingCap[i] >= prevReturned ? prevReturned : remainingCap[i];
      remainingCap[i] -= consume;
      prevReturned -= consume;
    }

    int needed = refundQty;
    final List<RefundBacktrackAllocation> result = [];

    // 1. If admin explicitly picked a batch, allocate from it first
    if (preferredBatchId != null && preferredBatchId.trim().isNotEmpty) {
      for (int i = validAllocations.length - 1; i >= 0 && needed > 0; i--) {
        if (validAllocations[i].batchId != preferredBatchId.trim()) continue;
        if (remainingCap[i] <= 0) continue;
        final int take = remainingCap[i] >= needed ? needed : remainingCap[i];
        remainingCap[i] -= take;
        needed -= take;
        final a = validAllocations[i];
        result.add(RefundBacktrackAllocation(
          batchId: a.batchId,
          qtyReturned: take,
          datePurchased: a.datePurchased,
          dateArrived: a.dateArrived,
          costPrice: a.costPrice,
          supplierName: a.supplierName,
          poNumber: a.poNumber,
        ));
      }
    }

    // 2. Allocate any remaining units in reverse allocation order
    for (int i = validAllocations.length - 1; i >= 0 && needed > 0; i--) {
      if (remainingCap[i] <= 0) continue;
      final int take = remainingCap[i] >= needed ? needed : remainingCap[i];
      remainingCap[i] -= take;
      needed -= take;
      final a = validAllocations[i];
      result.add(RefundBacktrackAllocation(
        batchId: a.batchId,
        qtyReturned: take,
        datePurchased: a.datePurchased,
        dateArrived: a.dateArrived,
        costPrice: a.costPrice,
        supplierName: a.supplierName,
        poNumber: a.poNumber,
      ));
    }

    return result;
  }

  /// Sums `remainingQty` across all valid sellable (active, > 0, non-expired) batches.
  static int sumActiveBatchStock(
    Iterable<ProductBatch> batches, {
    DateTime? now,
  }) {
    return ProductBatch.sumSellableStock(batches, now: now);
  }

  /// Normalizes statuses (`DEPLETED` / `EXPIRED`), deduplicates by `batchId`,
  /// and sorts in canonical FIFO order.
  static List<ProductBatch> normalizeAndMergeBatches(
    Iterable<ProductBatch> batches, {
    DateTime? now,
  }) {
    final DateTime effectiveNow = now ?? DateTime.now();
    return mergeBatchesById(
      batches.map((b) => b.normalizedForPersistence(now: effectiveNow)),
    );
  }

  /// Deduplicates batches by `batchId` (later entries override earlier ones)
  /// and sorts in canonical FIFO order (`dateArrived ASC, batchId ASC`).
  ///
  /// Prevents duplicate-ID double-counting when recalculating parent stock.
  static List<ProductBatch> mergeBatchesById(Iterable<ProductBatch> batches) {
    final Map<String, ProductBatch> byId = {};
    for (final b in batches) {
      final key = b.batchId.trim();
      if (key.isEmpty) continue;
      byId[key] = b;
    }
    final merged = byId.values.toList()..sort(ProductBatch.compareFifo);
    return merged;
  }

  /// Ensures [desiredId] does not collide with any batch ID in [existingIds].
  /// If a collision occurs, appends a 4-char random suffix so an existing
  /// distinct batch document is never silently overwritten.
  static String resolveUniqueBatchId(
    String desiredId,
    Set<String> existingIds, {
    DateTime? date,
  }) {
    String candidate = desiredId.trim();
    if (candidate.isEmpty) {
      candidate = generateBatchId(date);
    }
    while (existingIds.contains(candidate)) {
      final suffix =
          _uuid.v4().replaceAll('-', '').substring(0, 4).toUpperCase();
      candidate = '$candidate-$suffix';
    }
    return candidate;
  }

  /// Builds the canonical mirror payload for top-level `inventory_batches/{batchId}`.
  static Map<String, dynamic> buildInventoryBatchMirror(
    ProductBatch batch, {
    String? receiptId,
  }) {
    return {
      'batchId': batch.batchId,
      'productId': batch.productId,
      'productName': batch.productName,
      'supplierId': batch.supplierId,
      'supplierName': batch.supplierName,
      'poId': batch.poId,
      'poNumber': batch.poNumber,
      if (receiptId != null) 'receiptId': receiptId,
      'initialQty': batch.initialQty,
      'quantityRemaining': batch.remainingQty,
      'remainingQty': batch.remainingQty,
      'unitCost': batch.costPrice,
      'costPrice': batch.costPrice,
      'datePurchased': Timestamp.fromDate(batch.datePurchased),
      'dateArrived': Timestamp.fromDate(batch.dateArrived),
      'receivedAt': Timestamp.fromDate(batch.dateArrived),
      'expiryDate': batch.expiryDate != null
          ? Timestamp.fromDate(batch.expiryDate!)
          : null,
      'status': batch.status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Validates that [supplierId] exists inside `suppliers/{supplierId}` during a
  /// Firestore transaction READ phase and resolves the authoritative supplier name.
  Future<ValidatedSupplierLink?> _validateAndResolveSupplierInTx(
    Transaction transaction, {
    required String? supplierId,
    String? fallbackSupplierName,
    bool requireSupplier = true,
  }) async {
    final cleanId = supplierId?.trim() ?? '';
    if (cleanId.isEmpty) {
      if (requireSupplier) {
        throw StateError(
          'A valid supplier is required to create an inventory batch. Please select a supplier before saving.',
        );
      }
      return null;
    }

    final suppSnap = await transaction.get(_suppliers.doc(cleanId));
    if (!suppSnap.exists) {
      if (requireSupplier) {
        throw StateError(
          'Selected supplier (ID: $cleanId) does not exist in the suppliers registry. Please assign a valid supplier.',
        );
      }
      return null;
    }

    final suppData = suppSnap.data() ?? const <String, dynamic>{};
    final rawName =
        (suppData['name'] ?? suppData['supplierName'] ?? '').toString().trim();
    final resolvedName = rawName.isNotEmpty
        ? rawName
        : (fallbackSupplierName?.trim().isNotEmpty == true
            ? fallbackSupplierName!.trim()
            : 'Supplier $cleanId');

    return ValidatedSupplierLink(
      supplierId: cleanId,
      supplierName: resolvedName,
    );
  }

  static DateTime? _earliestActiveExpiry(
    Iterable<ProductBatch> batches, {
    DateTime? now,
  }) {
    final DateTime effectiveNow = now ?? DateTime.now();
    DateTime? earliest;
    for (final b in batches) {
      if (b.isSellableAt(effectiveNow) && b.expiryDate != null) {
        if (earliest == null || b.expiryDate!.isBefore(earliest)) {
          earliest = b.expiryDate;
        }
      }
    }
    return earliest;
  }

  // ── Streams & Queries ─────────────────────────────────────────────────────

  /// Real-time collectionGroup stream of all `products/{productId}/batches` documents,
  /// grouped by parent `productId` and sorted in canonical FIFO order.
  ///
  /// Enables Inventory, POS, and Batch Audit UIs to share the exact same live
  /// subcollection batch Single Source of Truth.
  Stream<Map<String, List<ProductBatch>>> allBatchesGroupStream() {
    return _db.collectionGroup('batches').snapshots().map((snap) {
      final Map<String, List<ProductBatch>> grouped = {};
      for (final doc in snap.docs) {
        try {
          final parentProductId = doc.reference.parent.parent?.id ?? '';
          final parsed = ProductBatch.fromFirestore(doc);
          final productId =
              parentProductId.isNotEmpty ? parentProductId : parsed.productId;
          if (productId.isEmpty) continue;
          final normalized = parsed.productId.isEmpty
              ? parsed.copyWith(productId: productId)
              : parsed;
          grouped.putIfAbsent(productId, () => []).add(normalized);
        } catch (e) {
          debugPrint('Error parsing collectionGroup batch ${doc.id}: $e');
        }
      }
      for (final list in grouped.values) {
        list.sort(ProductBatch.compareFifo);
      }
      return grouped;
    });
  }

  /// Live stream of all batches for [productId], ordered by `dateArrived ASC`
  /// with `batchId ASC` tie-breaker.
  Stream<List<ProductBatch>> batchesStream(String productId) {
    return _batchesCol(productId)
        .orderBy('dateArrived', descending: false)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(ProductBatch.fromFirestore).toList();
      list.sort(ProductBatch.compareFifo);
      return list;
    });
  }

  /// Fetches all batches for [productId] once, sorted by FIFO order.
  Future<List<ProductBatch>> fetchBatches(String productId) async {
    final snap = await _batchesCol(productId)
        .orderBy('dateArrived', descending: false)
        .get();
    final list = snap.docs.map(ProductBatch.fromFirestore).toList();
    list.sort(ProductBatch.compareFifo);
    return list;
  }

  /// Fetches active batch document snapshots using the composite index
  /// (`status == 'ACTIVE'`, `orderBy('dateArrived', descending: false)`),
  /// gracefully falling back to single-field ordering if the composite index
  /// has not finished building yet.
  Future<List<DocumentReference<Map<String, dynamic>>>> _fetchActiveBatchRefs(
      String productId) async {
    try {
      final snap = await _batchesCol(productId)
          .where('status', isEqualTo: BatchStatus.active)
          .orderBy('dateArrived', descending: false)
          .get();
      return snap.docs.map((d) => d.reference).toList();
    } catch (e) {
      debugPrint(
          'Active batch composite index fallback for product $productId: $e');
      final snap = await _batchesCol(productId)
          .orderBy('dateArrived', descending: false)
          .get();
      return snap.docs.map((d) => d.reference).toList();
    }
  }

  Future<List<DocumentReference<Map<String, dynamic>>>> _fetchAllBatchRefs(
      String productId) async {
    final snap = await _batchesCol(productId).get();
    return snap.docs.map((d) => d.reference).toList();
  }

  /// Resolves the current admin actor outside of Firestore transactions.
  Future<_ActorInfo> _resolveActor({String? fallbackName}) async {
    final user = _auth.currentUser;
    if (user == null) {
      final name = fallbackName ?? 'System Admin';
      return _ActorInfo(
        uid: 'system',
        email: name,
        name: name,
        role: 'admin',
      );
    }

    String role = 'admin';
    String name = user.displayName ?? fallbackName ?? user.email ?? 'Admin';
    try {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? const {};
        role = data['role']?.toString() ?? 'admin';
        final docName = data['name']?.toString().trim();
        if (docName != null && docName.isNotEmpty) {
          name = docName;
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve actor profile: $e');
    }

    return _ActorInfo(
      uid: user.uid,
      email: user.email ?? fallbackName ?? 'admin',
      name: name,
      role: role,
    );
  }

  /// Helper that builds a legacy initialization list when a product has
  /// `stock > 0` and zero documents in `products/{productId}/batches`.
  List<ProductBatch> _buildLegacyFallbackBatches({
    required Product product,
    required Map<String, dynamic> productData,
    Map<String, _LegacyPoHydration> poHydrationByBatchId = const {},
  }) {
    final int currentStock = product.stock;
    if (currentStock <= 0) return const [];

    final DateTime fallbackDate = _parseProductCreatedAt(productData);
    final List<ProductBatch> migrated = [];

    // 1. Preserve any legacy embedded batches on the product document first
    final embeddedActive =
        product.batches.where((b) => b.remainingQty > 0).toList();
    embeddedActive.sort(ProductBatch.compareFifo);

    int coveredQty = 0;
    for (final b in embeddedActive) {
      final String id = b.batchId.trim().isNotEmpty
          ? b.batchId.trim()
          : generateBatchId(b.dateArrived);
      final hydration = poHydrationByBatchId[id];
      final int qty = b.remainingQty;
      coveredQty += qty;
      migrated.add(ProductBatch(
        batchId: id,
        productId: product.id,
        productName: product.name,
        supplierId: b.supplierId ?? hydration?.supplierId ?? product.supplierId,
        supplierName: b.supplierName ?? hydration?.supplierName,
        poId: b.poId ?? hydration?.poId,
        poNumber: b.poNumber ?? hydration?.poNumber,
        datePurchased: hydration?.datePurchased ?? b.datePurchased,
        dateArrived: b.dateArrived,
        expiryDate: b.expiryDate ?? product.expiryDate,
        costPrice: b.costPrice > 0 ? b.costPrice : product.effectiveUnitCost,
        initialQty: b.initialQty >= qty ? b.initialQty : qty,
        remainingQty: qty,
        status: BatchStatus.active,
        invoiceNumber: b.invoiceNumber,
      ));
    }

    // 2. If stock exceeds embedded batches (or none existed), create LEGACY-INIT
    final int deficit = currentStock - coveredQty;
    if (deficit > 0) {
      migrated.add(ProductBatch(
        batchId: 'LEGACY-INIT',
        productId: product.id,
        productName: product.name,
        supplierId: product.supplierId,
        supplierName: null,
        datePurchased: fallbackDate,
        dateArrived: fallbackDate,
        expiryDate: product.expiryDate,
        costPrice: product.effectiveUnitCost,
        initialQty: deficit,
        remainingQty: deficit,
        status: BatchStatus.active,
        invoiceNumber: 'LEGACY-INIT',
      ));
    }

    migrated.sort(ProductBatch.compareFifo);
    return migrated;
  }

  /// Best-effort lookup of PO metadata from legacy `inventory_batches` and
  /// `purchase_orders` so migrated batches automatically carry their PO number,
  /// supplier name, and purchase date.
  Future<Map<String, _LegacyPoHydration>> _fetchLegacyPoHydration(
      String productId) async {
    final Map<String, _LegacyPoHydration> result = {};
    try {
      final invSnap = await _inventoryBatches
          .where('productId', isEqualTo: productId)
          .get();
      if (invSnap.docs.isEmpty) return result;

      final Set<String> poIdsToFetch = {};
      final Map<String, Map<String, dynamic>> batchDocsById = {};
      for (final d in invSnap.docs) {
        final data = d.data();
        final bId = data['batchId']?.toString().trim().isNotEmpty == true
            ? data['batchId'].toString().trim()
            : d.id;
        batchDocsById[bId] = data;
        final poId = data['poId']?.toString().trim();
        if (poId != null && poId.isNotEmpty) {
          poIdsToFetch.add(poId);
        }
      }

      final Map<String, PurchaseOrder> poById = {};
      for (final poId in poIdsToFetch) {
        try {
          final poSnap = await _purchaseOrders.doc(poId).get();
          if (poSnap.exists) {
            poById[poId] = PurchaseOrder.fromFirestore(poSnap);
          }
        } catch (_) {}
      }

      for (final entry in batchDocsById.entries) {
        final data = entry.value;
        final poId = data['poId']?.toString().trim();
        final po = (poId != null && poId.isNotEmpty) ? poById[poId] : null;
        final rawPoNumber = data['poNumber']?.toString().trim();
        final poNumber = (rawPoNumber != null && rawPoNumber.isNotEmpty)
            ? rawPoNumber
            : po?.poNumber;
        final rawSuppName = data['supplierName']?.toString().trim();
        final suppName = (rawSuppName != null && rawSuppName.isNotEmpty)
            ? rawSuppName
            : (po != null && po.effectiveSupplierName.isNotEmpty
                ? po.effectiveSupplierName
                : null);

        if (poId != null || poNumber != null || suppName != null) {
          result[entry.key] = _LegacyPoHydration(
            poId: poId,
            poNumber: poNumber,
            supplierId: data['supplierId']?.toString() ?? po?.supplierId,
            supplierName: suppName,
            datePurchased: po?.orderDate,
          );
        }
      }
    } catch (e) {
      debugPrint('Legacy PO hydration skipped for product $productId: $e');
    }
    return result;
  }

  DateTime _parseProductCreatedAt(Map<String, dynamic> data) {
    final raw = data['createdAt'] ?? data['updatedAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw != null) {
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  // ── Legacy Auto-Init Utility (for UI View Fallback) ───────────────────────

  /// Ensures a legacy product with `stock > 0` and zero documents in
  /// `products/{productId}/batches` gets a `"LEGACY-INIT"` batch atomically
  /// so UI views and checkouts never encounter empty-list exceptions.
  Future<List<ProductBatch>> ensureLegacyBatchIfNeeded(String productId) async {
    final existingRefs = await _fetchAllBatchRefs(productId);
    if (existingRefs.isNotEmpty) {
      return fetchBatches(productId);
    }

    final actor = await _resolveActor();
    final poHydration = await _fetchLegacyPoHydration(productId);
    final productRef = _products.doc(productId);
    List<ProductBatch> created = const [];

    await _db.runTransaction((transaction) async {
      final prodSnap = await transaction.get(productRef);
      if (!prodSnap.exists) return;

      final prodData = prodSnap.data() ?? const <String, dynamic>{};
      final product = Product.fromMap(prodData, id: productId);
      if (product.stock <= 0) return;

      // Also check if LEGACY-INIT was created concurrently
      final legacyRef = _batchesCol(productId).doc('LEGACY-INIT');
      final legacySnap = await transaction.get(legacyRef);
      if (legacySnap.exists) {
        created = [ProductBatch.fromFirestore(legacySnap)];
        return;
      }

      final fallbackBatches = _buildLegacyFallbackBatches(
        product: product,
        productData: prodData,
        poHydrationByBatchId: poHydration,
      );
      if (fallbackBatches.isEmpty) return;

      for (final b in fallbackBatches) {
        transaction.set(_batchesCol(productId).doc(b.batchId), b.toFirestore());
      }

      final int syncedStock = sumActiveBatchStock(fallbackBatches);
      transaction.update(productRef, {
        'stock': syncedStock,
        'batches': {for (final b in fallbackBatches) b.batchId: b.toMap()},
        ..._physicalReserveFields(product, syncedStock, isRestock: false),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final logRef = _auditLogs.doc();
      transaction.set(logRef, {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name,
        'actorRole': actor.role,
        'performedBy': actor.toPerformedByMap(),
        'module': 'INVENTORY',
        'action': 'BATCH_RECEIVED',
        'targetId': fallbackBatches.first.batchId,
        'targetName': '${product.name} (${fallbackBatches.first.batchId})',
        'productId': productId,
        'productName': product.name,
        'batchId': fallbackBatches.first.batchId,
        'qtyChanged': syncedStock,
        'datePurchased':
            Timestamp.fromDate(fallbackBatches.first.datePurchased),
        'dateArrived': Timestamp.fromDate(fallbackBatches.first.dateArrived),
        'summary':
            'Auto-initialized legacy stock ($syncedStock ${product.unit}) into ${fallbackBatches.length} FIFO batch(es) for ${product.name}.',
      });

      created = fallbackBatches;
    });

    return created;
  }

  // ── 1. Receive Single Batch (Manual Stock-In / Restock) ───────────────────

  /// Atomically validates the supplier, creates a new batch in
  /// `products/{productId}/batches/{batchId}`, mirrors to `inventory_batches`,
  /// synchronizes parent `products/{productId}.stock` as the exact sum of active
  /// batches, and writes a `"BATCH_RECEIVED"` entry to `audit_logs`.
  Future<ProductBatch> receiveBatch({
    required String productId,
    required String productName,
    required int receivedQty,
    required double costPrice,
    required DateTime datePurchased,
    required DateTime dateArrived,
    DateTime? expiryDate,
    String? supplierId,
    String? supplierName,
    String? poId,
    String? poNumber,
    String? invoiceNumber,
    String? customBatchId,
    String? performedByName,
    String? notes,
    StoreSettings? settings,
    double? packCost,
    int? itemsPerCase,
    bool createDeliveryLog = true,
    bool requireSupplier = true,
  }) async {
    if (receivedQty <= 0) {
      throw ArgumentError('receivedQty must be greater than 0.');
    }

    final actor = await _resolveActor(fallbackName: performedByName);
    final existingBatchRefs = await _fetchAllBatchRefs(productId);
    final productRef = _products.doc(productId);

    late ProductBatch createdBatch;

    await _db.runTransaction((transaction) async {
      // ── READ PHASE ──
      final prodSnap = await transaction.get(productRef);
      if (!prodSnap.exists) {
        throw Exception('Product $productName ($productId) not found.');
      }

      final prodData = prodSnap.data() ?? const <String, dynamic>{};
      final product = Product.fromMap(prodData, id: productId);

      final String? candidateSupplierId = (supplierId != null &&
              supplierId.trim().isNotEmpty)
          ? supplierId.trim()
          : (product.supplierId != null && product.supplierId!.trim().isNotEmpty
              ? product.supplierId!.trim()
              : null);

      final validatedSupplier = await _validateAndResolveSupplierInTx(
        transaction,
        supplierId: candidateSupplierId,
        fallbackSupplierName: supplierName,
        requireSupplier: requireSupplier,
      );

      final List<ProductBatch> existingBatches = [];
      for (final ref in existingBatchRefs) {
        final snap = await transaction.get(ref);
        if (snap.exists) {
          existingBatches.add(ProductBatch.fromFirestore(snap));
        }
      }

      // Legacy fallback: if subcollection was empty but stock > 0, seed legacy batches first
      final List<ProductBatch> legacyToCreate = existingBatches.isEmpty
          ? _buildLegacyFallbackBatches(product: product, productData: prodData)
          : const [];

      final existingIds = <String>{
        ...existingBatches.map((b) => b.batchId),
        ...legacyToCreate.map((b) => b.batchId),
      };
      final String desiredId =
          (customBatchId != null && customBatchId.trim().isNotEmpty)
              ? customBatchId.trim()
              : generateBatchId(dateArrived);
      final String batchId =
          resolveUniqueBatchId(desiredId, existingIds, date: dateArrived);

      final String? finalSupplierId = validatedSupplier?.supplierId;
      final String? finalSupplierName =
          validatedSupplier?.supplierName ?? supplierName;

      final newBatch = ProductBatch(
        batchId: batchId,
        productId: productId,
        productName: productName,
        supplierId: finalSupplierId,
        supplierName: finalSupplierName,
        poId: poId,
        poNumber: poNumber,
        datePurchased: datePurchased,
        dateArrived: dateArrived,
        expiryDate: expiryDate,
        costPrice: costPrice,
        initialQty: receivedQty,
        remainingQty: receivedQty,
        status: BatchStatus.active,
        invoiceNumber: invoiceNumber,
      );

      final DateTime now = DateTime.now();
      final Map<String, ProductBatch> existingById = {
        for (final b in existingBatches) b.batchId: b,
      };
      final List<ProductBatch> allBatches = normalizeAndMergeBatches(
        [
          ...existingBatches,
          ...legacyToCreate,
          newBatch,
        ],
        now: now,
      );

      final int syncedStock = sumActiveBatchStock(allBatches, now: now);
      final DateTime? earliestExp = _earliestActiveExpiry(allBatches, now: now);

      final fifoPricing = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: allBatches,
        settings: settings,
      );

      final double updatedCostPrice =
          (fifoPricing != null && !fifoPricing.hasInvalidCost)
              ? fifoPricing.newActiveUnitCost
              : (product.activeFifoUnitCost > 0
                  ? product.activeFifoUnitCost
                  : (costPrice > 0 ? costPrice : product.costPrice));

      // ── WRITE PHASE ──
      for (final legacy in legacyToCreate) {
        final normLegacy = legacy.normalizedForPersistence(now: now);
        transaction.set(
          _batchesCol(productId).doc(normLegacy.batchId),
          normLegacy.toFirestore(),
        );
        transaction.set(
          _inventoryBatches.doc(normLegacy.batchId),
          buildInventoryBatchMirror(normLegacy),
        );
      }

      // Persist any existing batches whose status transitioned to EXPIRED/DEPLETED
      for (final b in allBatches) {
        if (b.batchId == batchId) continue;
        final prev = existingById[b.batchId];
        if (prev != null &&
            (prev.status != b.status || prev.remainingQty != b.remainingQty)) {
          transaction.set(
              _batchesCol(productId).doc(b.batchId), b.toFirestore());
          transaction.set(
            _inventoryBatches.doc(b.batchId),
            buildInventoryBatchMirror(b),
            SetOptions(merge: true),
          );
        }
      }

      final normalizedNewBatch = newBatch.normalizedForPersistence(now: now);
      transaction.set(
        _batchesCol(productId).doc(batchId),
        normalizedNewBatch.toFirestore(),
      );

      // Mirror to top-level inventory_batches atomically
      transaction.set(
        _inventoryBatches.doc(batchId),
        buildInventoryBatchMirror(normalizedNewBatch),
      );

      final Map<String, dynamic> productUpdate = {
        'stock': syncedStock,
        'initialStock': _nextInitialStockOnRestock(product, syncedStock),
        'costPrice': updatedCostPrice,
        'batches': {for (final b in allBatches) b.batchId: b.toMap()},
        'expiryDate':
            earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
        ..._physicalReserveFields(product, syncedStock, isRestock: true),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (product.reservedStock < 0) {
        productUpdate['reservedStock'] = 0;
      }
      if ((product.supplierId == null || product.supplierId!.trim().isEmpty) &&
          finalSupplierId != null &&
          finalSupplierId.isNotEmpty) {
        productUpdate['supplierId'] = finalSupplierId;
      }
      if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
        productUpdate['computedMarkupPercent'] =
            fifoPricing.computedMarkupPercent;
        productUpdate['price'] = fifoPricing.newSellingPrice;
        productUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
      }
      if (packCost != null) {
        productUpdate['packCost'] = packCost;
      }
      if (itemsPerCase != null) {
        productUpdate['itemsPerCase'] = itemsPerCase;
      }
      transaction.update(productRef, productUpdate);

      if (createDeliveryLog) {
        final deliveryRef = _deliveryLogs.doc();
        transaction.set(deliveryRef, {
          'productId': productId,
          'productName': productName,
          'batchId': batchId,
          'qtyReceived': receivedQty,
          'unitCost': costPrice,
          'totalValue': receivedQty * costPrice,
          'datePurchased': Timestamp.fromDate(datePurchased),
          'dateArrived': Timestamp.fromDate(dateArrived),
          'expiryDate':
              expiryDate != null ? Timestamp.fromDate(expiryDate) : null,
          'invoiceNumber': invoiceNumber,
          'receivedBy': performedByName ?? actor.name,
          'notes': notes,
          if (finalSupplierId != null && finalSupplierId.isNotEmpty)
            'supplierId': finalSupplierId,
          if (finalSupplierName != null && finalSupplierName.isNotEmpty)
            'supplierName': finalSupplierName,
          if (poId != null && poId.isNotEmpty) 'poId': poId,
          if (poNumber != null && poNumber.isNotEmpty) 'poNumber': poNumber,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Write mandatory BATCH_RECEIVED audit log
      final logRef = _auditLogs.doc();
      transaction.set(logRef, {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name,
        'actorRole': actor.role,
        'performedBy': actor.toPerformedByMap(),
        'module': 'INVENTORY',
        'action': 'BATCH_RECEIVED',
        'targetId': batchId,
        'targetName': '$productName ($batchId)',
        'productId': productId,
        'productName': productName,
        'batchId': batchId,
        if (finalSupplierId != null) 'supplierId': finalSupplierId,
        if (finalSupplierName != null) 'supplierName': finalSupplierName,
        if (poId != null) 'poId': poId,
        if (poNumber != null) 'poNumber': poNumber,
        'qtyChanged': receivedQty,
        'datePurchased': Timestamp.fromDate(datePurchased),
        'dateArrived': Timestamp.fromDate(dateArrived),
        'summary':
            'Received batch $batchId (+$receivedQty ${product.unit}) for $productName${finalSupplierName != null && finalSupplierName.isNotEmpty ? " from $finalSupplierName" : ""}${poNumber != null && poNumber.isNotEmpty ? " (PO #$poNumber)" : ""}.',
        'afterData': {
          'productId': productId,
          'productName': productName,
          'batchId': batchId,
          'supplierId': finalSupplierId,
          'supplierName': finalSupplierName,
          'poNumber': poNumber,
          'qtyChanged': receivedQty,
          'costPrice': costPrice,
          'datePurchased': datePurchased.toIso8601String(),
          'dateArrived': dateArrived.toIso8601String(),
          'newTotalStock': syncedStock,
        },
      });

      createdBatch = newBatch;
    });

    return createdBatch;
  }

  // ── 2. New Product Creation with Initial Batch ────────────────────────────

  /// Atomically validates the supplier (when [initialBatch.remainingQty] > 0),
  /// creates a new product document, and writes its initial FIFO batch under
  /// `products/{productId}/batches/{batchId}`, `inventory_batches/{batchId}`,
  /// `delivery_logs`, and `audit_logs`.
  Future<ProductBatch?> receiveProductWithInitialBatch({
    required Product product,
    required ProductBatch initialBatch,
    String? supplierName,
    String? receivedBy,
    String? notes,
    bool requireSupplierForStock = true,
  }) async {
    final actor = await _resolveActor(fallbackName: receivedBy);
    final docRef =
        product.id.isEmpty ? _products.doc() : _products.doc(product.id);
    final String finalProductId = docRef.id;

    final int initialQty = initialBatch.remainingQty;
    final String batchId = initialBatch.batchId.trim().isNotEmpty
        ? initialBatch.batchId.trim()
        : generateBatchId(initialBatch.dateArrived);

    ProductBatch? createdBatch;

    await _db.runTransaction((transaction) async {
      // ── READ PHASE ──
      final String? candidateSupplierId = (initialBatch.supplierId != null &&
              initialBatch.supplierId!.trim().isNotEmpty)
          ? initialBatch.supplierId!.trim()
          : (product.supplierId != null && product.supplierId!.trim().isNotEmpty
              ? product.supplierId!.trim()
              : null);

      ValidatedSupplierLink? validatedSupplier;
      if (initialQty > 0 || candidateSupplierId != null) {
        validatedSupplier = await _validateAndResolveSupplierInTx(
          transaction,
          supplierId: candidateSupplierId,
          fallbackSupplierName: initialBatch.supplierName ?? supplierName,
          requireSupplier: initialQty > 0 && requireSupplierForStock,
        );
      }

      final String? finalSupplierId = validatedSupplier?.supplierId;
      final String? finalSupplierName = validatedSupplier?.supplierName ??
          initialBatch.supplierName ??
          supplierName;

      final ProductBatch resolvedBatch = initialBatch.copyWith(
        batchId: batchId,
        productId: finalProductId,
        productName: product.name,
        supplierId: finalSupplierId,
        supplierName: finalSupplierName,
        initialQty: initialQty,
        remainingQty: initialQty,
        status: initialQty > 0 ? BatchStatus.active : BatchStatus.depleted,
      );

      final List<ProductBatch> allBatches = initialQty > 0
          ? mergeBatchesById([...product.batches, resolvedBatch])
          : mergeBatchesById(product.batches);
      final int syncedStock = product.hasVariants
          ? product.totalStock
          : sumActiveBatchStock(allBatches);

      final List<ProductVariant> resolvedVariants = product.hasVariants
          ? product.variants
              .map((v) => v.copyWith(
                    physicalReserve:
                        InventoryAllocation.calculatePhysicalReserve(v.stock),
                  ))
              .toList()
          : product.variants;
      final int initialReserve = product.hasVariants
          ? resolvedVariants.fold(
              0, (acc, v) => acc + v.effectivePhysicalReserve)
          : InventoryAllocation.calculatePhysicalReserve(syncedStock);

      final updatedProduct = product.copyWith(
        stock: syncedStock,
        physicalReserve: initialReserve,
        supplierId: finalSupplierId ?? product.supplierId,
        variants: resolvedVariants,
        batches: allBatches,
      );

      // ── WRITE PHASE ──
      transaction.set(
        docRef,
        {
          ...updatedProduct.toFirestore(),
          'id': finalProductId,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (initialQty > 0) {
        transaction.set(
          _batchesCol(finalProductId).doc(batchId),
          resolvedBatch.toFirestore(),
        );

        transaction.set(
          _inventoryBatches.doc(batchId),
          buildInventoryBatchMirror(resolvedBatch),
        );

        final deliveryLogRef = _deliveryLogs.doc();
        transaction.set(deliveryLogRef, {
          'productId': finalProductId,
          'productName': product.name,
          'batchId': batchId,
          'qtyReceived': initialQty,
          'unitCost': resolvedBatch.costPrice,
          'totalValue': initialQty * resolvedBatch.costPrice,
          'datePurchased': Timestamp.fromDate(resolvedBatch.datePurchased),
          'dateArrived': Timestamp.fromDate(resolvedBatch.dateArrived),
          'expiryDate': resolvedBatch.expiryDate != null
              ? Timestamp.fromDate(resolvedBatch.expiryDate!)
              : null,
          'invoiceNumber': resolvedBatch.invoiceNumber,
          'receivedBy': receivedBy ?? actor.name,
          'notes': notes ?? 'Initial Inventory / Product Creation',
          if (finalSupplierId != null) 'supplierId': finalSupplierId,
          if (finalSupplierName != null) 'supplierName': finalSupplierName,
          'createdAt': FieldValue.serverTimestamp(),
        });

        final logRef = _auditLogs.doc();
        transaction.set(logRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'actorId': actor.uid,
          'actorEmail': actor.email,
          'actorName': actor.name,
          'actorRole': actor.role,
          'performedBy': actor.toPerformedByMap(),
          'module': 'INVENTORY',
          'action': 'BATCH_RECEIVED',
          'targetId': batchId,
          'targetName': '${product.name} ($batchId)',
          'productId': finalProductId,
          'productName': product.name,
          'batchId': batchId,
          if (finalSupplierId != null) 'supplierId': finalSupplierId,
          if (finalSupplierName != null) 'supplierName': finalSupplierName,
          'qtyChanged': initialQty,
          'datePurchased': Timestamp.fromDate(resolvedBatch.datePurchased),
          'dateArrived': Timestamp.fromDate(resolvedBatch.dateArrived),
          'summary':
              'Initial product batch $batchId (+$initialQty ${product.unit}) created for ${product.name}${finalSupplierName != null && finalSupplierName.isNotEmpty ? " from $finalSupplierName" : ""}.',
          'afterData': {
            'productId': finalProductId,
            'productName': product.name,
            'batchId': batchId,
            'supplierId': finalSupplierId,
            'supplierName': finalSupplierName,
            'qtyChanged': initialQty,
            'costPrice': resolvedBatch.costPrice,
            'datePurchased': resolvedBatch.datePurchased.toIso8601String(),
            'dateArrived': resolvedBatch.dateArrived.toIso8601String(),
            'newTotalStock': syncedStock,
          },
        });

        createdBatch = resolvedBatch;
      }
    });

    return createdBatch;
  }

  // ── 3. Supplier Purchase Order Atomic Receiving ───────────────────────────

  /// Atomically receives a Supplier Purchase Order inside `runTransaction`:
  /// - Creates distinct FIFO batches under `products/{productId}/batches/{batchId}`
  ///   with separate `datePurchased` (from PO orderDate or admin pick) and `dateArrived`.
  /// - Synchronizes parent `products/{productId}.stock` as exact sum of active batches.
  /// - Logs `"BATCH_RECEIVED"` in `audit_logs` for every created batch + PO summary log.
  Future<PurchaseOrder> receivePurchaseOrderAtomic({
    required String poId,
    required PurchaseOrder currentPo,
    required String deliveryReceiptNo,
    required Map<String, int> receivedQtyMap,
    required Map<String, DateTime?> expiryDateMap,
    required Map<String, double> unitCostMap,
    required String receivedBy,
    DateTime? datePurchased,
    DateTime? dateArrived,
    Supplier? freshSupplier,
    Map<String, String>? batchNumberMap,
    Map<String, List<SplitBatchEntry>>? splitBatchesMap,
    Map<String, int>? rejectedQtyMap,
    Map<String, String>? rejectionReasonMap,
    String? discrepancyNote,
    bool syncProductCostPrice = false,
    bool shortCloseRemaining = false,
    String overDeliveryAction = 'cap',
    StoreSettings? settings,
  }) async {
    final actor = await _resolveActor(fallbackName: receivedBy);
    final SupplierSnapshot hydratedSnapshot =
        currentPo.resolveSupplierSnapshot(freshSupplier);
    final String effectiveSupplierName =
        hydratedSnapshot.supplierName.isNotEmpty
            ? hydratedSnapshot.supplierName
            : currentPo.supplierName;

    final DateTime effectiveDatePurchased =
        datePurchased ?? currentPo.orderDate;
    final DateTime effectiveDateArrived = dateArrived ?? DateTime.now();

    // Pre-fetch existing batch refs for all products on this PO before entering runTransaction
    final Set<String> affectedProductIds = currentPo.items
        .map((i) => i.productId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final Map<String, List<DocumentReference<Map<String, dynamic>>>>
        batchRefsByProduct = {};
    for (final pid in affectedProductIds) {
      batchRefsByProduct[pid] = await _fetchAllBatchRefs(pid);
    }

    late PurchaseOrder updatedPoResult;

    await _db.runTransaction((transaction) async {
      // ── READ PHASE ──
      final poRef = _purchaseOrders.doc(poId);
      final poSnap = await transaction.get(poRef);
      if (!poSnap.exists) {
        throw StateError('Purchase Order $poId no longer exists.');
      }

      // Atomically validate the PO's linked supplier inside the transaction
      final validatedSupplier = (await _validateAndResolveSupplierInTx(
        transaction,
        supplierId: currentPo.supplierId,
        fallbackSupplierName: effectiveSupplierName,
        requireSupplier: true,
      ))!;
      final String verifiedSupplierId = validatedSupplier.supplierId;
      final String verifiedSupplierName = validatedSupplier.supplierName;
      final SupplierSnapshot verifiedSnapshot = hydratedSnapshot.copyWith(
        supplierId: verifiedSupplierId,
        supplierName: verifiedSupplierName,
      );

      final Map<String, DocumentSnapshot<Map<String, dynamic>>> prodSnaps = {};
      final Map<String, List<ProductBatch>> existingBatchesByProduct = {};
      final Map<String, Set<String>> usedBatchIdsByProduct = {};

      for (final pid in affectedProductIds) {
        prodSnaps[pid] = await transaction.get(_products.doc(pid));
        final list = <ProductBatch>[];
        final ids = <String>{};
        for (final ref in batchRefsByProduct[pid] ?? const []) {
          final bSnap = await transaction.get(ref);
          if (bSnap.exists) {
            final parsed = ProductBatch.fromFirestore(bSnap);
            list.add(parsed);
            ids.add(parsed.batchId);
          }
        }
        existingBatchesByProduct[pid] = list;
        usedBatchIdsByProduct[pid] = ids;
      }

      // ── COMPUTE & PREPARE PHASE ──
      final receivingRecordRef = _receivingRecords.doc();
      final List<ReceivingItem> itemsReceivedForRecord = [];
      final List<PurchaseOrderItem> updatedPoItems = [];

      double totalDeliveryCost = 0.0;
      int totalAcceptedUnitsInDelivery = 0;
      int totalRejectedUnitsInDelivery = 0;
      final List<String> priceVarianceLogs = [];

      // Collect product updates per productId (in case PO has duplicate product rows)
      final Map<String, List<ProductBatch>> newBatchesByProduct = {};
      final Map<String, double> latestActualCostByProduct = {};

      for (final poItem in currentPo.items) {
        final String pid = poItem.productId;
        final usedIds =
            usedBatchIdsByProduct.putIfAbsent(pid, () => <String>{});

        List<SplitBatchEntry> itemSplits =
            List.from(splitBatchesMap?[pid] ?? const []);
        if (itemSplits.isEmpty) {
          final int qtyNow = receivedQtyMap[pid] ?? 0;
          if (qtyNow > 0) {
            final String customTag = batchNumberMap?[pid]?.trim() ?? '';
            final String tag = customTag.isNotEmpty
                ? customTag
                : generatePoBatchId(
                    currentPo.poNumber,
                    date: effectiveDateArrived,
                  );
            itemSplits = [
              SplitBatchEntry(
                acceptedQty: qtyNow,
                expiryDate: expiryDateMap[pid],
                batchTag: tag,
              ),
            ];
          }
        }

        final int totalAcceptedNow =
            itemSplits.fold(0, (acc, s) => acc + s.acceptedQty);
        final int rejectedQty = rejectedQtyMap?[pid] ?? 0;
        final String? rejectionReason = rejectionReasonMap?[pid];
        final double actualPrice = unitCostMap[pid] ?? poItem.unitCost;
        final double priceVariance = actualPrice - poItem.unitCost;

        if (priceVariance != 0) {
          priceVarianceLogs.add(
              '${poItem.productName}: ₱${poItem.unitCost.toStringAsFixed(2)} -> ₱${actualPrice.toStringAsFixed(2)} (${priceVariance > 0 ? "+" : ""}${priceVariance.toStringAsFixed(2)})');
        }

        // Over-delivery safeguard
        int effectiveAccepted = totalAcceptedNow;
        int updatedOrderedQty = poItem.orderedQty;
        if (totalAcceptedNow > poItem.remainingQty) {
          if (overDeliveryAction == 'accept') {
            updatedOrderedQty = poItem.receivedQty + totalAcceptedNow;
          } else {
            effectiveAccepted = poItem.remainingQty;
          }
        }

        // Scale/cap splits if capped and guarantee unique batch IDs
        int remainingAllowance = effectiveAccepted;
        final List<SplitBatchEntry> finalSplits = [];
        for (final s in itemSplits) {
          if (s.acceptedQty <= 0 || remainingAllowance <= 0) continue;
          final int take = s.acceptedQty <= remainingAllowance
              ? s.acceptedQty
              : remainingAllowance;
          remainingAllowance -= take;
          final String desiredTag = s.batchTag.trim().isNotEmpty
              ? s.batchTag.trim()
              : generatePoBatchId(
                  currentPo.poNumber,
                  date: effectiveDateArrived,
                );
          final String bTag = resolveUniqueBatchId(
            desiredTag,
            usedIds,
            date: effectiveDateArrived,
          );
          usedIds.add(bTag);
          finalSplits.add(SplitBatchEntry(
            acceptedQty: take,
            expiryDate: s.expiryDate,
            batchTag: bTag,
          ));
        }

        final int newTotalReceivedQty = poItem.receivedQty + effectiveAccepted;
        final int newTotalRejectedQty = poItem.rejectedQty + rejectedQty;

        updatedPoItems.add(poItem.copyWith(
          orderedQty: updatedOrderedQty,
          receivedQty: newTotalReceivedQty,
          rejectedQty: newTotalRejectedQty,
          rejectionReason: rejectionReason ?? poItem.rejectionReason,
          unitCost: poItem.unitCost,
          actualUnitCost: actualPrice,
        ));

        if (effectiveAccepted > 0 || rejectedQty > 0) {
          totalAcceptedUnitsInDelivery += effectiveAccepted;
          totalRejectedUnitsInDelivery += rejectedQty;
          totalDeliveryCost += (effectiveAccepted * actualPrice);

          itemsReceivedForRecord.add(ReceivingItem(
            productId: pid,
            productName: poItem.productName,
            sku: poItem.sku,
            acceptedQty: effectiveAccepted,
            rejectedQty: rejectedQty,
            rejectionReason: rejectionReason,
            estimatedUnitCost: poItem.unitCost,
            actualUnitPrice: actualPrice,
            priceVariance: priceVariance,
            splitBatches: finalSplits,
            batchId: finalSplits.isNotEmpty ? finalSplits.first.batchTag : '',
          ));

          for (final split in finalSplits) {
            final newBatch = ProductBatch(
              batchId: split.batchTag,
              productId: pid,
              productName: poItem.productName,
              supplierId: verifiedSupplierId,
              supplierName: verifiedSupplierName,
              poId: poId,
              poNumber: currentPo.poNumber,
              datePurchased: effectiveDatePurchased,
              dateArrived: effectiveDateArrived,
              expiryDate: split.expiryDate,
              costPrice: actualPrice,
              initialQty: split.acceptedQty,
              remainingQty: split.acceptedQty,
              status: BatchStatus.active,
              invoiceNumber: deliveryReceiptNo,
            );

            newBatchesByProduct.putIfAbsent(pid, () => []).add(newBatch);
            latestActualCostByProduct[pid] = actualPrice;

            // Subcollection batch write
            transaction.set(
              _batchesCol(pid).doc(newBatch.batchId),
              newBatch.toFirestore(),
            );

            // Top-level inventory_batches mirror write
            transaction.set(
              _inventoryBatches.doc(newBatch.batchId),
              buildInventoryBatchMirror(
                newBatch,
                receiptId: receivingRecordRef.id,
              ),
            );

            // Mandatory BATCH_RECEIVED audit log per received batch
            final batchLogRef = _auditLogs.doc();
            transaction.set(batchLogRef, {
              'timestamp': FieldValue.serverTimestamp(),
              'actorId': actor.uid,
              'actorEmail': actor.email,
              'actorName': actor.name,
              'actorRole': actor.role,
              'performedBy': actor.toPerformedByMap(),
              'module': 'INVENTORY',
              'action': 'BATCH_RECEIVED',
              'targetId': newBatch.batchId,
              'targetName': '${poItem.productName} (${newBatch.batchId})',
              'productId': pid,
              'productName': poItem.productName,
              'batchId': newBatch.batchId,
              'supplierId': verifiedSupplierId,
              'supplierName': verifiedSupplierName,
              'poId': poId,
              'poNumber': currentPo.poNumber,
              'qtyChanged': split.acceptedQty,
              'datePurchased': Timestamp.fromDate(effectiveDatePurchased),
              'dateArrived': Timestamp.fromDate(effectiveDateArrived),
              'summary':
                  'PO #${currentPo.poNumber} batch ${newBatch.batchId} received (+${split.acceptedQty} units) for ${poItem.productName} from $verifiedSupplierName.',
              'afterData': {
                'productId': pid,
                'productName': poItem.productName,
                'batchId': newBatch.batchId,
                'supplierId': verifiedSupplierId,
                'supplierName': verifiedSupplierName,
                'poNumber': currentPo.poNumber,
                'qtyChanged': split.acceptedQty,
                'costPrice': actualPrice,
                'datePurchased': effectiveDatePurchased.toIso8601String(),
                'dateArrived': effectiveDateArrived.toIso8601String(),
              },
            });
          }

          // Legacy delivery log entry
          final deliveryLogRef = _deliveryLogs.doc();
          transaction.set(deliveryLogRef, {
            'productId': pid,
            'productName': poItem.productName,
            'batchId': finalSplits.isNotEmpty ? finalSplits.first.batchTag : '',
            'qtyReceived': effectiveAccepted,
            'qtyRejected': rejectedQty,
            'rejectionReason': rejectionReason,
            'unitCost': actualPrice,
            'totalValue': effectiveAccepted * actualPrice,
            'datePurchased': Timestamp.fromDate(effectiveDatePurchased),
            'dateArrived': Timestamp.fromDate(effectiveDateArrived),
            'invoiceNumber': deliveryReceiptNo,
            'receivedBy': receivedBy,
            'notes': discrepancyNote,
            'orderedQty': poItem.orderedQty,
            'orderedUnitCost': poItem.unitCost,
            'supplierId': verifiedSupplierId,
            'supplierName': verifiedSupplierName,
            'poId': poId,
            'poNumber': currentPo.poNumber,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // Sync each affected parent product document atomically
      for (final entry in newBatchesByProduct.entries) {
        final pid = entry.key;
        final prodSnap = prodSnaps[pid];
        if (prodSnap == null || !prodSnap.exists) continue;

        final prodData = prodSnap.data() ?? const <String, dynamic>{};
        final product = Product.fromMap(prodData, id: pid);
        final existing = existingBatchesByProduct[pid] ?? const [];

        final List<ProductBatch> legacyToCreate = existing.isEmpty
            ? _buildLegacyFallbackBatches(
                product: product, productData: prodData)
            : const [];
        for (final legacy in legacyToCreate) {
          transaction.set(
            _batchesCol(pid).doc(legacy.batchId),
            legacy.toFirestore(),
          );
          transaction.set(
            _inventoryBatches.doc(legacy.batchId),
            buildInventoryBatchMirror(legacy),
          );
        }

        final DateTime now = DateTime.now();
        final Map<String, ProductBatch> existingById = {
          for (final b in existing) b.batchId: b,
        };
        final allBatches = normalizeAndMergeBatches(
          [
            ...existing,
            ...legacyToCreate,
            ...entry.value,
          ],
          now: now,
        );

        // Persist any existing batches whose status transitioned to EXPIRED/DEPLETED
        for (final b in allBatches) {
          final prev = existingById[b.batchId];
          if (prev != null &&
              (prev.status != b.status ||
                  prev.remainingQty != b.remainingQty)) {
            transaction.set(_batchesCol(pid).doc(b.batchId), b.toFirestore());
            transaction.set(
              _inventoryBatches.doc(b.batchId),
              buildInventoryBatchMirror(b),
              SetOptions(merge: true),
            );
          }
        }

        final int syncedStock = sumActiveBatchStock(allBatches, now: now);
        final DateTime? earliestExp =
            _earliestActiveExpiry(allBatches, now: now);
        final double actualPrice = latestActualCostByProduct[pid] ?? 0.0;

        final Map<String, dynamic> prodUpdateData = {
          'stock': syncedStock,
          'initialStock': _nextInitialStockOnRestock(product, syncedStock),
          'batches': {for (final b in allBatches) b.batchId: b.toMap()},
          'expiryDate':
              earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
          ..._physicalReserveFields(product, syncedStock, isRestock: true),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (product.reservedStock < 0) {
          prodUpdateData['reservedStock'] = 0;
        }
        if (product.supplierId == null || product.supplierId!.trim().isEmpty) {
          prodUpdateData['supplierId'] = verifiedSupplierId;
        }

        final fifoPricing = PricingEngine.recalculateForFifoTransition(
          product: product,
          updatedBatches: allBatches,
          settings: settings,
        );
        if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
          prodUpdateData['costPrice'] = fifoPricing.newActiveUnitCost;
          prodUpdateData['computedMarkupPercent'] =
              fifoPricing.computedMarkupPercent;
          prodUpdateData['price'] = fifoPricing.newSellingPrice;
          prodUpdateData['sellingPrice'] = fifoPricing.newSellingPrice;
        } else if (syncProductCostPrice && actualPrice > 0) {
          prodUpdateData['costPrice'] = actualPrice;
        }

        transaction.update(_products.doc(pid), prodUpdateData);
      }

      // Write receiving_records document
      transaction.set(receivingRecordRef, {
        'poId': poId,
        'poNumber': currentPo.poNumber,
        'supplierId': verifiedSupplierId,
        'supplierName': verifiedSupplierName,
        'deliveryReceiptNo': deliveryReceiptNo,
        'datePurchased': Timestamp.fromDate(effectiveDatePurchased),
        'dateArrived': Timestamp.fromDate(effectiveDateArrived),
        'receivedAt': Timestamp.fromDate(effectiveDateArrived),
        'receivedBy': receivedBy,
        'discrepancyNote': discrepancyNote,
        'actualDeliveryCost': totalDeliveryCost,
        'itemsReceived': itemsReceivedForRecord.map((i) => i.toMap()).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Determine new PO status
      PurchaseOrderStatus newStatus;
      if (shortCloseRemaining) {
        newStatus = PurchaseOrderStatus.shortClosed;
      } else {
        final bool allComplete =
            updatedPoItems.every((item) => item.receivedQty >= item.orderedQty);
        newStatus = allComplete
            ? PurchaseOrderStatus.completed
            : PurchaseOrderStatus.partiallyReceived;
      }

      final String? effectiveChildPoId =
          newStatus == PurchaseOrderStatus.partiallyReceived
              ? ((currentPo.childPoId != null &&
                      currentPo.childPoId!.trim().isNotEmpty)
                  ? currentPo.childPoId
                  : 'BO-${currentPo.poNumber}')
              : currentPo.childPoId;

      transaction.update(poRef, {
        'status': newStatus.name,
        'items': updatedPoItems.map((i) => i.toMap()).toList(),
        'actualDeliveryCost': FieldValue.increment(totalDeliveryCost),
        'supplierId': verifiedSupplierId,
        'supplierName': verifiedSupplierName,
        'supplierSnapshot': verifiedSnapshot.toMap(),
        if (effectiveChildPoId != null) 'childPoId': effectiveChildPoId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Write PO Summary Audit Log
      final poLogRef = _auditLogs.doc();
      transaction.set(poLogRef, {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name,
        'actorRole': actor.role,
        'performedBy': actor.toPerformedByMap(),
        'module': 'Suppliers',
        'action': newStatus == PurchaseOrderStatus.completed
            ? 'FULL_DELIVERY'
            : newStatus == PurchaseOrderStatus.shortClosed
                ? 'CLOSED_SHORT'
                : 'PARTIAL_DELIVERY',
        'targetId': poId,
        'targetName': 'PO #${currentPo.poNumber} (DR $deliveryReceiptNo)',
        'summary':
            'Received $totalAcceptedUnitsInDelivery accepted units ($totalRejectedUnitsInDelivery rejected). Delivery Cost: ₱${totalDeliveryCost.toStringAsFixed(2)}. Status: ${newStatus.displayName}.${priceVarianceLogs.isNotEmpty ? " Price Variances: ${priceVarianceLogs.join(', ')}" : ""}',
        'beforeData': currentPo.toFirestore(),
        'afterData': {
          'poNumber': currentPo.poNumber,
          'deliveryReceiptNo': deliveryReceiptNo,
          'datePurchased': effectiveDatePurchased.toIso8601String(),
          'dateArrived': effectiveDateArrived.toIso8601String(),
          'status': newStatus.name,
          if (effectiveChildPoId != null) 'backorderId': effectiveChildPoId,
          'supplierSnapshot': verifiedSnapshot.toMap(),
          'totalAcceptedNow': totalAcceptedUnitsInDelivery,
          'totalRejectedNow': totalRejectedUnitsInDelivery,
          'actualDeliveryCostNow': totalDeliveryCost,
          'priceVariances': priceVarianceLogs,
          'updatedItems': updatedPoItems.map((i) => i.toMap()).toList(),
          'itemsReceivedSummary': updatedPoItems
              .where((i) => i.receivedQty > 0)
              .map((i) => {
                    'productName': i.productName,
                    'sku': i.sku,
                    'receivedQty': i.receivedQty,
                    'actualUnitCost': i.actualUnitCost ?? i.unitCost,
                    'totalCost':
                        i.receivedQty * (i.actualUnitCost ?? i.unitCost),
                  })
              .toList(),
          'itemsMissingSummary': updatedPoItems
              .where((i) => i.remainingQty > 0 || i.rejectedQty > 0)
              .map((i) => {
                    'productName': i.productName,
                    'sku': i.sku,
                    'orderedQty': i.orderedQty,
                    'receivedQty': i.receivedQty,
                    'rejectedQty': i.rejectedQty,
                    'missingQty': i.remainingQty + i.rejectedQty,
                    'rejectionReason':
                        i.rejectionReason ?? 'Unfulfilled balance',
                  })
              .toList(),
        },
      });

      updatedPoResult = currentPo.copyWith(
        status: newStatus,
        items: updatedPoItems,
        supplierId: verifiedSupplierId,
        supplierName: verifiedSupplierName,
        supplierSnapshot: verifiedSnapshot,
        childPoId: effectiveChildPoId,
        actualDeliveryCost:
            (currentPo.actualDeliveryCost ?? 0.0) + totalDeliveryCost,
      );
    });

    return updatedPoResult;
  }

  // ── 4. Atomic FIFO Deduction Engine (POS & Online Checkout) ───────────────

  /// Executes FIFO stock deduction atomically inside a Firestore `runTransaction`.
  ///
  /// - Deducts from oldest arrived active batches first (`dateArrived ASC, batchId ASC`).
  /// - Auto-initializes `"LEGACY-INIT"` batch if a product has `stock > 0` and 0 batch docs.
  /// - Stamps `batchAllocations` (and legacy `depletedBatches`) onto every line item.
  /// - Synchronizes parent `products/{productId}.stock` to the exact sum of active batches.
  /// - Optionally writes `transactions/{txId}`, updates `orders/{orderDocId}` (clearing
  ///   `reservedStock` and marking `collected`), updates customer spend, and logs
  ///   `"BATCH_DEPLETED"` whenever any batch reaches `remainingQty == 0`.
  Future<FifoCheckoutResult> deductStockFIFO({
    required List<CartItem> items,
    StoreTransaction? transactionToWrite,
    String? preOrderDocId,
    PreOrder? preOrderToComplete,
    List<CartItem> preOrderItemsForReservationRelease = const [],
    StoreSettings? settings,
    String? performedByName,
  }) async {
    if (items.isEmpty) {
      return FifoCheckoutResult(
        processedItems: const [],
        depletedBatches: const [],
        transaction: transactionToWrite,
      );
    }

    final actor = await _resolveActor(fallbackName: performedByName);

    // Pre-fetch candidate batch refs for all unique products in the cart/order
    final Set<String> uniqueProductIds =
        items.map((i) => i.productId).where((id) => id.isNotEmpty).toSet();
    final Map<String, List<DocumentReference<Map<String, dynamic>>>>
        batchRefsByProduct = {};

    for (final pid in uniqueProductIds) {
      // Fetch active refs using composite index, plus all refs so parent embedded map stays complete
      final activeRefs = await _fetchActiveBatchRefs(pid);
      final allRefs = await _fetchAllBatchRefs(pid);
      final Map<String, DocumentReference<Map<String, dynamic>>> merged = {};
      for (final r in activeRefs) {
        merged[r.id] = r;
      }
      for (final r in allRefs) {
        merged[r.id] = r;
      }
      batchRefsByProduct[pid] = merged.values.toList();
    }

    // Track reservation releases per product/variant (for Click & Collect pre-orders)
    final Map<String, int> reservedReleaseByProduct = {};
    final Map<String, Map<String, int>> reservedReleaseByVariant = {};
    for (final item in preOrderItemsForReservationRelease) {
      if (item.productId.isEmpty) continue;
      if (item.variantId != null && item.variantId!.isNotEmpty) {
        reservedReleaseByVariant.putIfAbsent(item.productId, () => {}).update(
            item.variantId!, (v) => v + item.qty,
            ifAbsent: () => item.qty);
      } else {
        reservedReleaseByProduct.update(item.productId, (v) => v + item.qty,
            ifAbsent: () => item.qty);
      }
    }

    late FifoCheckoutResult checkoutResult;

    await _db.runTransaction((transaction) async {
      final DateTime now = DateTime.now();

      // ── READ PHASE (ALL READS BEFORE ANY WRITE) ──
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> prodSnaps = {};
      final Map<String, List<ProductBatch>> batchesByProduct = {};

      for (final pid in uniqueProductIds) {
        prodSnaps[pid] = await transaction.get(_products.doc(pid));
        final list = <ProductBatch>[];
        for (final ref in batchRefsByProduct[pid] ?? const []) {
          final bSnap = await transaction.get(ref);
          if (bSnap.exists) {
            list.add(ProductBatch.fromFirestore(bSnap));
          }
        }
        list.sort(ProductBatch.compareFifo);
        batchesByProduct[pid] = list;
      }

      DocumentSnapshot<Map<String, dynamic>>? orderSnap;
      DocumentReference<Map<String, dynamic>>? orderRef;
      if (preOrderDocId != null && preOrderDocId.isNotEmpty) {
        orderRef = _orders.doc(preOrderDocId);
        orderSnap = await transaction.get(orderRef);
        if (orderSnap.exists) {
          final currentStatus =
              orderSnap.data()?['status']?.toString().toLowerCase() ?? '';
          if (currentStatus == OrderStatus.collected.name ||
              currentStatus == OrderStatus.cancelled.name) {
            throw StateError(
              'Order ${preOrderToComplete?.orderId ?? preOrderDocId} is already $currentStatus and cannot be deducted again.',
            );
          }
        }
      }

      // ── VALIDATION & FIFO COMPUTATION PHASE ──
      final Map<String, Product> parsedProducts = {};
      final Map<String, List<ProductBatch>> workingBatchesByProduct = {};
      final Map<String, List<ProductBatch>> newlyCreatedLegacyBatches = {};
      final Map<String, Map<String, int>> variantDeductions = {};
      final List<ProductBatch> allNewlyDepleted = [];
      final List<CartItem> processedItems = [];

      // Initialize per-product working batch lists (with legacy fallback if 0 batch docs & stock > 0)
      for (final pid in uniqueProductIds) {
        final snap = prodSnaps[pid];
        if (snap == null || !snap.exists) {
          throw Exception('Product ($pid) no longer exists in inventory.');
        }
        final data = snap.data() ?? const <String, dynamic>{};
        final product = Product.fromMap(data, id: pid);
        parsedProducts[pid] = product;

        final existing = batchesByProduct[pid] ?? const [];
        if (existing.isEmpty && !product.hasVariants && product.stock > 0) {
          final legacy = _buildLegacyFallbackBatches(
            product: product,
            productData: data,
          );
          newlyCreatedLegacyBatches[pid] = legacy;
          workingBatchesByProduct[pid] =
              normalizeAndMergeBatches(legacy, now: now);
        } else {
          workingBatchesByProduct[pid] =
              normalizeAndMergeBatches(existing, now: now);
        }
      }

      // Pre-check total requested per standard product against unreserved sellable stock
      final Map<String, int> requestedStandardByProduct = {};
      for (final item in items) {
        if (item.productId.isEmpty ||
            (item.variantId != null && item.variantId!.isNotEmpty)) {
          continue;
        }
        requestedStandardByProduct.update(
          item.productId,
          (v) => v + item.qty,
          ifAbsent: () => item.qty,
        );
      }

      for (final entry in requestedStandardByProduct.entries) {
        final pid = entry.key;
        final requestedQty = entry.value;
        final product = parsedProducts[pid];
        if (product == null) continue;
        final int totalSellable = sumActiveBatchStock(
          workingBatchesByProduct[pid] ?? const [],
          now: now,
        );
        final int releaseReserved = reservedReleaseByProduct[pid] ?? 0;
        final int reservedByOthers =
            (product.effectiveReservedStock - releaseReserved)
                .clamp(0, 999999999);
        final int availableForSale =
            (totalSellable - reservedByOthers).clamp(0, totalSellable);
        if (requestedQty > availableForSale) {
          throw Exception(
            'Insufficient available stock for ${product.name}. Sellable: $totalSellable, Reserved by other orders: $reservedByOthers, Available: $availableForSale, Requested: $requestedQty.',
          );
        }
      }

      // Process each line item sequentially so duplicate products in cart share exact remaining batch qty
      for (final item in items) {
        final pid = item.productId;
        final product = parsedProducts[pid];
        if (product == null) {
          processedItems.add(item);
          continue;
        }

        if (item.variantId != null && item.variantId!.isNotEmpty) {
          // Variant product deduction
          final variantIdx =
              product.variants.indexWhere((v) => v.id == item.variantId);
          if (variantIdx < 0) {
            throw Exception(
                'Variant ${item.variantName ?? item.variantId} for ${product.name} not found.');
          }
          final variant = product.variants[variantIdx];
          final int alreadyDeducted = variantDeductions[pid]?[variant.id] ?? 0;
          final int releaseVarReserved =
              reservedReleaseByVariant[pid]?[variant.id] ?? 0;
          final int reservedVarByOthers =
              (variant.effectiveReservedStock - releaseVarReserved)
                  .clamp(0, 999999999);
          final int remainingVariantStock =
              (variant.stock - reservedVarByOthers - alreadyDeducted)
                  .clamp(0, variant.stock);
          if (remainingVariantStock < item.qty) {
            throw Exception(
                'Insufficient available stock for ${product.name} (${variant.name}). Available: $remainingVariantStock, Requested: ${item.qty}.');
          }
          variantDeductions.putIfAbsent(pid, () => {}).update(
              variant.id, (v) => v + item.qty,
              ifAbsent: () => item.qty);

          final double cost =
              variant.costPrice > 0 ? variant.costPrice : item.costPrice;
          final alloc = BatchAllocation(
            batchId: 'variant-${variant.id}',
            quantity: item.qty,
            unitCost: cost,
            datePurchased: now,
            dateArrived: now,
          );
          processedItems.add(item.copyWith(
            unitPriceAtSale: item.unitPriceAtSale,
            barcode: item.barcode.isNotEmpty
                ? item.barcode
                : (variant.barcode ?? product.barcode ?? ''),
            costPrice: cost,
            totalCogs: cost * item.qty,
            batchAllocations: [alloc],
          ));
        } else {
          // Standard product FIFO batch deduction
          final currentWorking = workingBatchesByProduct[pid] ?? const [];
          final plan = computeFifoDeduction(
            batches: currentWorking,
            requestedQty: item.qty,
            productName: product.name,
            now: now,
          );

          workingBatchesByProduct[pid] = plan.updatedBatches;
          allNewlyDepleted.addAll(plan.newlyDepletedBatches);

          final double weightedCost =
              item.qty > 0 ? (plan.totalCogs / item.qty) : item.costPrice;
          processedItems.add(item.copyWith(
            unitPriceAtSale: item.unitPriceAtSale,
            barcode: item.barcode.isNotEmpty
                ? item.barcode
                : (product.barcode ?? ''),
            costPrice: weightedCost,
            totalCogs: plan.totalCogs,
            batchAllocations: plan.allocations,
          ));
        }
      }

      // ── WRITE PHASE ──
      // 1. Write batch subcollection updates & parent product stock synchronization
      for (final pid in uniqueProductIds) {
        final product = parsedProducts[pid]!;
        final prodRef = _products.doc(pid);

        if (variantDeductions.containsKey(pid)) {
          final vMap = variantDeductions[pid]!;
          int newTotalVariantStock = 0;
          int newTotalVariantReserved = 0;
          int newTotalVariantReserve = 0;
          final Map<String, dynamic> updateData = {
            'updatedAt': FieldValue.serverTimestamp(),
          };
          for (final v in product.variants) {
            final int ded = vMap[v.id] ?? 0;
            final int rel = reservedReleaseByVariant[pid]?[v.id] ?? 0;
            final int nextStock = (v.stock - ded).clamp(0, 999999999);
            final int nextRes =
                (v.effectiveReservedStock - rel).clamp(0, 999999999);
            final int preservedOriginal = v.effectiveOriginalStock;
            final int preservedReserve = v.effectivePhysicalReserve;

            newTotalVariantStock += nextStock;
            newTotalVariantReserved += nextRes;
            newTotalVariantReserve += preservedReserve;

            if (ded > 0) {
              updateData['variants.${v.id}.stock'] = nextStock;
            }
            if ((v.initialStock == null || v.initialStock! <= 0) &&
                preservedOriginal > 0) {
              updateData['variants.${v.id}.initialStock'] = preservedOriginal;
            }
            if (v.physicalReserve == null) {
              updateData['variants.${v.id}.physicalReserve'] = preservedReserve;
            }
            if (rel > 0 || v.reservedStock < 0) {
              updateData['variants.${v.id}.reservedStock'] = nextRes;
            }
          }
          updateData['stock'] = newTotalVariantStock;
          updateData['reservedStock'] = newTotalVariantReserved;
          updateData['physicalReserve'] = newTotalVariantReserve;
          if ((product.initialStock == null || product.initialStock! <= 0) &&
              product.effectiveOriginalStock > 0) {
            updateData['initialStock'] = product.effectiveOriginalStock;
          }
          transaction.update(prodRef, updateData);
          continue;
        }

        final updatedBatches = normalizeAndMergeBatches(
          workingBatchesByProduct[pid] ?? const [],
          now: now,
        );
        final legacyBatchIds = (newlyCreatedLegacyBatches[pid] ?? const [])
            .map((b) => b.batchId)
            .toSet();
        final originalById = {
          for (final b in batchesByProduct[pid] ?? const []) b.batchId: b,
        };

        // Write every newly created legacy batch or modified/expired/depleted existing batch
        for (final b in updatedBatches) {
          final prev = originalById[b.batchId];
          final bool changed = legacyBatchIds.contains(b.batchId) ||
              prev == null ||
              prev.remainingQty != b.remainingQty ||
              prev.status != b.status;
          if (changed) {
            transaction.set(_batchesCol(pid).doc(b.batchId), b.toFirestore());
            if (!b.batchId.startsWith('fallback-') &&
                !b.batchId.startsWith('variant-')) {
              transaction.set(
                _inventoryBatches.doc(b.batchId),
                buildInventoryBatchMirror(b),
                SetOptions(merge: true),
              );
            }
          }
        }

        final int syncedStock = sumActiveBatchStock(updatedBatches, now: now);
        final DateTime? earliestExp =
            _earliestActiveExpiry(updatedBatches, now: now);
        final int releaseReserved = reservedReleaseByProduct[pid] ?? 0;
        final int nextReserved =
            (product.effectiveReservedStock - releaseReserved)
                .clamp(0, 999999999);

        final Map<String, dynamic> productUpdate = {
          'stock': syncedStock,
          'batches': {for (final b in updatedBatches) b.batchId: b.toMap()},
          'expiryDate':
              earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
          ..._physicalReserveFields(product, syncedStock, isRestock: false),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (releaseReserved > 0 || product.reservedStock < 0) {
          productUpdate['reservedStock'] = nextReserved;
        }

        // FIFO Batch Transition dynamic pricing recalculation (never alters current tx unitPriceAtSale)
        final fifoPricing = PricingEngine.recalculateForFifoTransition(
          product: product,
          updatedBatches: updatedBatches,
          settings: settings,
        );
        if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
          productUpdate['costPrice'] = fifoPricing.newActiveUnitCost;
          productUpdate['computedMarkupPercent'] =
              fifoPricing.computedMarkupPercent;
          productUpdate['price'] = fifoPricing.newSellingPrice;
          productUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
        }

        transaction.update(prodRef, productUpdate);
      }

      // 2. Write StoreTransaction with stamped batchAllocations
      StoreTransaction? finalTx;
      if (transactionToWrite != null) {
        finalTx = StoreTransaction(
          id: transactionToWrite.id,
          orderId: transactionToWrite.orderId,
          items: processedItems,
          total: transactionToWrite.total,
          cashTendered: transactionToWrite.cashTendered,
          changeGiven: transactionToWrite.changeGiven,
          createdAt: transactionToWrite.createdAt,
          customerId: transactionToWrite.customerId,
          customerEmail: transactionToWrite.customerEmail,
          paymentMethod: transactionToWrite.paymentMethod,
          type: transactionToWrite.type,
          isRefunded: transactionToWrite.isRefunded,
        );
        transaction.set(_transactions.doc(finalTx.id), finalTx.toFirestore());

        if (finalTx.customerId != null && finalTx.customerId!.isNotEmpty) {
          transaction.set(
            _customers.doc(finalTx.customerId),
            {
              'totalSpent': FieldValue.increment(finalTx.total),
              'lastVisit': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        // Sale complete audit log
        final saleLogRef = _auditLogs.doc();
        final shortTxId =
            finalTx.id.length >= 5 ? finalTx.id.substring(0, 5) : finalTx.id;
        transaction.set(saleLogRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'actorId': actor.uid,
          'actorEmail': actor.email,
          'actorName': actor.name,
          'actorRole': actor.role,
          'performedBy': actor.toPerformedByMap(),
          'module': 'POS',
          'action': 'SALE_COMPLETE',
          'targetId': finalTx.id,
          'targetName': 'Tx #$shortTxId',
          'summary':
              'Sale transaction completed (FIFO). Total: [₱${finalTx.total.toStringAsFixed(2)}] for [${finalTx.items.length}] items.',
        });
      }

      // 3. Update PreOrder document with stamped batchAllocations (when fulfilling pickup)
      if (orderRef != null &&
          orderSnap != null &&
          orderSnap.exists &&
          preOrderToComplete != null) {
        // Match the pre-order's original item count from the prefix of processedItems
        final int preOrderCount = preOrderToComplete.items.length;
        final List<CartItem> stampedOrderItems =
            processedItems.length >= preOrderCount
                ? processedItems.sublist(0, preOrderCount)
                : processedItems;

        final updatedOrder = preOrderToComplete.copyWith(
          items: stampedOrderItems,
        );
        transaction.update(orderRef, {
          ...updatedOrder.toFirestore(),
          'reservationReleased': true,
        });
      }

      // 4. Append BATCH_DEPLETED audit log for every batch that reached remainingQty == 0
      final String refOrderOrTxId = preOrderToComplete?.orderId ??
          transactionToWrite?.orderId ??
          transactionToWrite?.id ??
          'CHECKOUT';

      for (final depleted in allNewlyDepleted) {
        final depLogRef = _auditLogs.doc();
        transaction.set(depLogRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'actorId': actor.uid,
          'actorEmail': actor.email,
          'actorName': actor.name,
          'actorRole': actor.role,
          'performedBy': actor.toPerformedByMap(),
          'module': 'INVENTORY',
          'action': 'BATCH_DEPLETED',
          'targetId': depleted.batchId,
          'targetName': '${depleted.productName} (${depleted.batchId})',
          'productId': depleted.productId,
          'productName': depleted.productName,
          'batchId': depleted.batchId,
          if (depleted.supplierName != null)
            'supplierName': depleted.supplierName,
          if (depleted.poNumber != null) 'poNumber': depleted.poNumber,
          'orderId': refOrderOrTxId,
          'qtyChanged': 0,
          'remainingQty': 0,
          'datePurchased': Timestamp.fromDate(depleted.datePurchased),
          'dateArrived': Timestamp.fromDate(depleted.dateArrived),
          'summary':
              'Batch ${depleted.batchId} for ${depleted.productName} was fully depleted during checkout ($refOrderOrTxId).',
        });
      }

      checkoutResult = FifoCheckoutResult(
        processedItems: processedItems,
        depletedBatches: allNewlyDepleted,
        transaction: finalTx,
      );
    });

    return checkoutResult;
  }

  // ── 5. Refund & Return Backtracking Engine ────────────────────────────────

  /// Atomically processes full or partial refunds/returns inside `runTransaction`:
  /// - Reads original sale date (`createdAt`) and `batchAllocations` from the receipt/order.
  /// - Matches exact original `batchId`(s) (with legacy fallback if `batchAllocations` absent).
  /// - Option A (`SELLABLE`): adds `refundQty` back to `products/{productId}/batches/{originalBatchId}.remainingQty`,
  ///   flips `"DEPLETED"` back to `"ACTIVE"` so FIFO puts the older batch back at the front,
  ///   and increments parent `products/{productId}.stock`.
  /// - Option B (`DAMAGED`): does NOT restore stock, records write-off against exact `batchId`.
  /// - Writes `"REFUND_BATCH_RESTORED"` or `"REFUND_BATCH_WRITEOFF"` to `audit_logs`.
  Future<RefundRestorationResult> restoreBatchOnRefund({
    required String transactionId,
    String? orderId,
    required List<RefundLineInput> itemsToRefund,
    required double totalRefundAmount,
    required String processedBy,
    String? customerEmail,
    String? refundRequestId,
    RefundCondition? refundRequestCondition,
    String? adminNotes,
    bool isSwap = false,
    bool isDamagedSwap = false,
    StoreSettings? settings,
  }) async {
    if (itemsToRefund.isEmpty) {
      return const RefundRestorationResult(
        restoredAllocations: [],
        writtenOffAllocations: [],
      );
    }

    final actor = await _resolveActor(fallbackName: processedBy);

    // Resolve transaction & order document references before entering runTransaction
    DocumentReference<Map<String, dynamic>>? txRef;
    if (transactionId.trim().isNotEmpty) {
      final candidateTx = _transactions.doc(transactionId.trim());
      final snap = await candidateTx.get();
      if (snap.exists) {
        txRef = candidateTx;
      } else {
        // Fallback: transactionId might actually be a display orderId like "GDC-0045"
        final byOrder = await _transactions
            .where('orderId', isEqualTo: transactionId.trim())
            .limit(1)
            .get();
        if (byOrder.docs.isNotEmpty) {
          txRef = byOrder.docs.first.reference;
        }
      }
    }

    DocumentReference<Map<String, dynamic>>? orderRef;
    final String lookupOrderKey = (orderId != null && orderId.trim().isNotEmpty)
        ? orderId.trim()
        : transactionId.trim();
    if (lookupOrderKey.isNotEmpty) {
      final directOrder = _orders.doc(lookupOrderKey);
      final snap = await directOrder.get();
      if (snap.exists) {
        orderRef = directOrder;
      } else {
        final byDisplayId = await _orders
            .where('orderId', isEqualTo: lookupOrderKey)
            .limit(1)
            .get();
        if (byDisplayId.docs.isNotEmpty) {
          orderRef = byDisplayId.docs.first.reference;
        }
      }
    }

    // Pre-fetch all batch refs for all refunded products
    final Set<String> uniqueProductIds = itemsToRefund
        .map((i) => i.productId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final Map<String, List<DocumentReference<Map<String, dynamic>>>>
        batchRefsByProduct = {};
    for (final pid in uniqueProductIds) {
      batchRefsByProduct[pid] = await _fetchAllBatchRefs(pid);
    }

    final List<RefundBacktrackAllocation> restoredAll = [];
    final List<RefundBacktrackAllocation> writtenOffAll = [];

    await _db.runTransaction((transaction) async {
      final DateTime now = DateTime.now();
      // ── READ PHASE ──
      final DocumentSnapshot<Map<String, dynamic>>? txSnap =
          txRef != null ? await transaction.get(txRef) : null;
      final DocumentSnapshot<Map<String, dynamic>>? orderSnap =
          orderRef != null ? await transaction.get(orderRef) : null;

      final Map<String, DocumentSnapshot<Map<String, dynamic>>> prodSnaps = {};
      final Map<String, Map<String, ProductBatch>> existingBatchesByProduct =
          {};

      for (final pid in uniqueProductIds) {
        prodSnaps[pid] = await transaction.get(_products.doc(pid));
        final map = <String, ProductBatch>{};
        for (final ref in batchRefsByProduct[pid] ?? const []) {
          final bSnap = await transaction.get(ref);
          if (bSnap.exists) {
            final b = ProductBatch.fromFirestore(bSnap);
            map[b.batchId] = b;
          }
        }
        existingBatchesByProduct[pid] = map;
      }

      // Extract original sale date & line items from transaction (or order fallback)
      final Map<String, dynamic> txData =
          txSnap?.data() ?? const <String, dynamic>{};
      final Map<String, dynamic> orderData =
          orderSnap?.data() ?? const <String, dynamic>{};

      DateTime parseSaleDate(dynamic raw) {
        if (raw is Timestamp) return raw.toDate();
        if (raw is DateTime) return raw;
        if (raw != null) {
          final p = DateTime.tryParse(raw.toString());
          if (p != null) return p;
        }
        return DateTime.now();
      }

      final DateTime originalSaleDate = txData['createdAt'] != null
          ? parseSaleDate(txData['createdAt'])
          : parseSaleDate(orderData['createdAt']);

      final String resolvedOrderId = orderData['orderId']?.toString() ??
          txData['orderId']?.toString() ??
          orderId ??
          transactionId;

      final List<dynamic> sourceRawItems =
          (txData['items'] is List && (txData['items'] as List).isNotEmpty)
              ? (txData['items'] as List)
              : (orderData['items'] is List
                  ? (orderData['items'] as List)
                  : const []);

      final List<CartItem> sourceItems =
          sourceRawItems.map(CartItem.fromMap).toList();

      // Track mutable batch state per product so multiple refund lines on same product stay accurate
      final Map<String, Map<String, ProductBatch>> workingBatchesByProduct = {
        for (final e in existingBatchesByProduct.entries)
          e.key: Map<String, ProductBatch>.from(e.value),
      };
      final Map<String, int> variantRestocks = {};
      final Map<String, Map<String, int>> variantDeltas = {};
      final List<Map<String, dynamic>> refundRecordItems = [];

      // ── BACKTRACK & COMPUTE PHASE ──
      for (final refLine in itemsToRefund) {
        if (refLine.productId.isEmpty || refLine.qty <= 0) continue;

        final pid = refLine.productId;
        final prodSnap = prodSnaps[pid];
        final Product? product = (prodSnap != null && prodSnap.exists)
            ? Product.fromMap(prodSnap.data() ?? const {}, id: pid)
            : null;

        // Match original receipt line item to read its batchAllocations
        CartItem? matchedSource;
        for (final s in sourceItems) {
          final bool sameProduct = s.productId == pid &&
              (s.variantId == refLine.variantId ||
                  (s.variantId == null && refLine.variantId == null));
          final bool sameBarcode = refLine.barcode.isNotEmpty &&
              s.barcode.isNotEmpty &&
              s.barcode == refLine.barcode;
          if (sameProduct || sameBarcode) {
            matchedSource = s;
            break;
          }
        }

        // For 1-to-1 sellable swap (net 0 stock change), do not increment batch remainingQty
        final bool shouldRestockBatch =
            refLine.isSellable && !(isSwap && !isDamagedSwap);

        // Handle variant products cleanly
        if (refLine.variantId != null && refLine.variantId!.isNotEmpty) {
          if (shouldRestockBatch) {
            variantDeltas.putIfAbsent(pid, () => {}).update(
                refLine.variantId!, (v) => v + refLine.qty,
                ifAbsent: () => refLine.qty);
            variantRestocks.update(pid, (v) => v + refLine.qty,
                ifAbsent: () => refLine.qty);
          } else if (isSwap && isDamagedSwap) {
            variantDeltas.putIfAbsent(pid, () => {}).update(
                refLine.variantId!, (v) => v - refLine.qty,
                ifAbsent: () => -refLine.qty);
            variantRestocks.update(pid, (v) => v - refLine.qty,
                ifAbsent: () => -refLine.qty);
          }

          final String vBatchId = 'variant-${refLine.variantId}';
          final alloc = RefundBacktrackAllocation(
            batchId: vBatchId,
            qtyReturned: refLine.qty,
            datePurchased: originalSaleDate,
            dateArrived: originalSaleDate,
            costPrice: product?.costPrice ?? refLine.price,
          );
          if (refLine.isSellable) {
            restoredAll.add(alloc);
          } else {
            writtenOffAll.add(alloc);
          }

          refundRecordItems.add({
            'productId': pid,
            'variantId': refLine.variantId,
            'name': refLine.productName,
            'barcode': refLine.barcode,
            'qty': refLine.qty,
            'price': refLine.price,
            'condition': refLine.canonicalCondition,
            'batchId': vBatchId,
          });

          _writeRefundAuditAndLossInTx(
            transaction: transaction,
            actor: actor,
            isSellable: refLine.isSellable,
            lossType: refLine.lossType,
            orderId: resolvedOrderId,
            transactionId: transactionId,
            originalSaleDate: originalSaleDate,
            productId: pid,
            variantId: refLine.variantId,
            productName: refLine.productName,
            batchId: vBatchId,
            qtyReturned: refLine.qty,
            unitPrice: refLine.price,
            processedBy: processedBy,
          );
          continue;
        }

        // Standard product: backtrack using receipt's batchAllocations
        List<RefundBacktrackAllocation> matchedAllocations =
            computeRefundBacktrack(
          batchAllocations: matchedSource?.batchAllocations ?? const [],
          refundQty: refLine.qty,
          alreadyReturnedQty: matchedSource?.returnedQty ?? 0,
          preferredBatchId: refLine.preferredBatchId,
        );

        final Map<String, ProductBatch> productBatches =
            workingBatchesByProduct.putIfAbsent(pid, () => {});

        // Legacy Order Fallback: if receipt predates batchAllocations (or partial unmatched remainder)
        final int matchedQty =
            matchedAllocations.fold<int>(0, (acc, a) => acc + a.qtyReturned);
        final int unmatchedQty = refLine.qty - matchedQty;

        if (unmatchedQty > 0) {
          if (refLine.isSellable) {
            // Find oldest currently ACTIVE batch; if none exists, create RETURN-RESTORE batch
            final activeList = productBatches.values
                .where((b) => b.isActive)
                .toList()
              ..sort(ProductBatch.compareFifo);

            if (activeList.isNotEmpty) {
              final oldest = activeList.first;
              matchedAllocations = [
                ...matchedAllocations,
                RefundBacktrackAllocation(
                  batchId: oldest.batchId,
                  qtyReturned: unmatchedQty,
                  datePurchased: oldest.datePurchased,
                  dateArrived: oldest.dateArrived,
                  costPrice: oldest.costPrice,
                  supplierName: oldest.supplierName,
                  poNumber: oldest.poNumber,
                  isLegacyFallback: true,
                ),
              ];
            } else {
              final String restoreId =
                  generateReturnRestoreBatchId(originalSaleDate);
              matchedAllocations = [
                ...matchedAllocations,
                RefundBacktrackAllocation(
                  batchId: restoreId,
                  qtyReturned: unmatchedQty,
                  datePurchased: originalSaleDate,
                  dateArrived: originalSaleDate,
                  costPrice: product?.effectiveUnitCost ?? refLine.price,
                  isLegacyFallback: true,
                ),
              ];
            }
          } else {
            // Damaged write-off on legacy order
            matchedAllocations = [
              ...matchedAllocations,
              RefundBacktrackAllocation(
                batchId: 'LEGACY-UNTRACKED',
                qtyReturned: unmatchedQty,
                datePurchased: originalSaleDate,
                dateArrived: originalSaleDate,
                costPrice: product?.effectiveUnitCost ?? refLine.price,
                isLegacyFallback: true,
              ),
            ];
          }
        }

        // Apply each backtracked allocation
        for (final alloc in matchedAllocations) {
          if (shouldRestockBatch) {
            final existingBatch = productBatches[alloc.batchId];
            if (existingBatch != null) {
              final int nextRemaining =
                  existingBatch.remainingQty + alloc.qtyReturned;
              final int nextInitial = nextRemaining > existingBatch.initialQty
                  ? nextRemaining
                  : existingBatch.initialQty;
              // Flip DEPLETED -> ACTIVE if not expired, or EXPIRED if past expiration
              productBatches[alloc.batchId] = existingBatch
                  .copyWith(
                    initialQty: nextInitial,
                    remainingQty: nextRemaining,
                    status: BatchStatus.active,
                  )
                  .normalizedForPersistence(now: now);
            } else {
              // Recreate exact original batch (or new RETURN-RESTORE batch) preserving original dates
              productBatches[alloc.batchId] = ProductBatch(
                batchId: alloc.batchId,
                productId: pid,
                productName: product?.name ?? refLine.productName,
                supplierId: product?.supplierId,
                supplierName: alloc.supplierName,
                poNumber: alloc.poNumber,
                datePurchased: alloc.datePurchased ?? originalSaleDate,
                dateArrived: alloc.dateArrived ?? originalSaleDate,
                expiryDate: product?.expiryDate,
                costPrice: alloc.costPrice > 0
                    ? alloc.costPrice
                    : (product?.effectiveUnitCost ?? 0.0),
                initialQty: alloc.qtyReturned,
                remainingQty: alloc.qtyReturned,
                status: BatchStatus.active,
                invoiceNumber:
                    alloc.isLegacyFallback ? 'RETURN-RESTORE' : alloc.poNumber,
              ).normalizedForPersistence(now: now);
            }

            restoredAll.add(alloc);
          } else if (refLine.isSellable) {
            restoredAll.add(alloc);
          } else {
            // Option B — Damaged / Defective (Write-Off): do NOT add back to remainingQty or stock
            writtenOffAll.add(alloc);
          }

          _writeRefundAuditAndLossInTx(
            transaction: transaction,
            actor: actor,
            isSellable: refLine.isSellable,
            lossType: refLine.lossType,
            orderId: resolvedOrderId,
            transactionId: transactionId,
            originalSaleDate: originalSaleDate,
            productId: pid,
            productName: product?.name ?? refLine.productName,
            batchId: alloc.batchId,
            qtyReturned: alloc.qtyReturned,
            unitPrice: alloc.costPrice > 0 ? alloc.costPrice : refLine.price,
            processedBy: processedBy,
            isLegacyFallback: alloc.isLegacyFallback,
          );
        }

        refundRecordItems.add({
          'productId': pid,
          'name': refLine.productName,
          'barcode': refLine.barcode,
          'qty': refLine.qty,
          'price': refLine.price,
          'condition': refLine.canonicalCondition,
          'restoredBatches': matchedAllocations
              .map((a) => {
                    'batchId': a.batchId,
                    'qtyReturned': a.qtyReturned,
                    'isLegacyFallback': a.isLegacyFallback,
                  })
              .toList(),
        });
      }

      // ── WRITE PHASE: BATCHES & PARENT PRODUCTS ──
      for (final pid in uniqueProductIds) {
        final prodSnap = prodSnaps[pid];
        if (prodSnap == null || !prodSnap.exists) continue;
        final product = Product.fromMap(prodSnap.data() ?? const {}, id: pid);
        final prodRef = _products.doc(pid);

        if (variantDeltas.containsKey(pid)) {
          final Map<String, dynamic> updateData = {
            'updatedAt': FieldValue.serverTimestamp(),
          };
          int newTotalVariantStock = 0;
          final Map<String, int> nextStockByVariant = {};
          for (final v in product.variants) {
            final int delta = variantDeltas[pid]![v.id] ?? 0;
            final int nextStock = (v.stock + delta).clamp(0, 999999999);
            nextStockByVariant[v.id] = nextStock;
            newTotalVariantStock += nextStock;
            if (delta != 0) {
              updateData['variants.${v.id}.stock'] = nextStock;
            }
          }
          updateData['stock'] = newTotalVariantStock;
          updateData.addAll(_variantPhysicalReserveFields(
            product,
            stockOverrides: nextStockByVariant,
          ));
          if (product.reservedStock < 0) {
            updateData['reservedStock'] = 0;
          }
          transaction.update(prodRef, updateData);
          continue;
        }

        final originalMap = existingBatchesByProduct[pid] ?? const {};
        final workingMap = workingBatchesByProduct[pid] ?? const {};
        final allBatches =
            normalizeAndMergeBatches(workingMap.values, now: now);

        bool anyBatchChanged = false;
        for (final curr in allBatches) {
          final prev = originalMap[curr.batchId];
          if (prev == null ||
              prev.remainingQty != curr.remainingQty ||
              prev.status != curr.status) {
            anyBatchChanged = true;
            transaction.set(
              _batchesCol(pid).doc(curr.batchId),
              curr.toFirestore(),
            );
            if (!curr.batchId.startsWith('fallback-') &&
                !curr.batchId.startsWith('variant-')) {
              transaction.set(
                _inventoryBatches.doc(curr.batchId),
                buildInventoryBatchMirror(curr),
                SetOptions(merge: true),
              );
            }
          }
        }

        final int syncedStock = sumActiveBatchStock(allBatches, now: now);
        if (anyBatchChanged ||
            product.stock != syncedStock ||
            product.reservedStock < 0) {
          final DateTime? earliestExp =
              _earliestActiveExpiry(allBatches, now: now);

          final Map<String, dynamic> prodUpdate = {
            'stock': syncedStock,
            'batches': {for (final b in allBatches) b.batchId: b.toMap()},
            'expiryDate':
                earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
            ..._physicalReserveFields(product, syncedStock, isRestock: false),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (product.reservedStock < 0) {
            prodUpdate['reservedStock'] = 0;
          }

          final fifoPricing = PricingEngine.recalculateForFifoTransition(
            product: product,
            updatedBatches: allBatches,
            settings: settings,
          );
          if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
            prodUpdate['costPrice'] = fifoPricing.newActiveUnitCost;
            prodUpdate['computedMarkupPercent'] =
                fifoPricing.computedMarkupPercent;
            prodUpdate['price'] = fifoPricing.newSellingPrice;
            prodUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
          }

          transaction.update(prodRef, prodUpdate);
        }
      }

      // ── WRITE PHASE: TRANSACTIONS, ORDERS, REFUND REQUESTS & REFUND RECORDS ──
      if (txRef != null && txSnap != null && txSnap.exists) {
        final rawItems = (txData['items'] as List? ?? []);
        final updatedTxItems = rawItems.map((raw) {
          if (raw is! Map) return raw;
          final itemMap = Map<String, dynamic>.from(raw);
          final String itemPid = itemMap['productId']?.toString() ?? '';
          final String? itemVid = itemMap['variantId']?.toString();
          final String itemBarcode = itemMap['barcode']?.toString() ?? '';

          int addReturned = 0;
          for (final refLine in itemsToRefund) {
            final bool matchesProd = refLine.productId == itemPid &&
                (refLine.variantId == itemVid ||
                    (refLine.variantId == null && itemVid == null));
            final bool matchesBarcode = refLine.barcode.isNotEmpty &&
                itemBarcode.isNotEmpty &&
                refLine.barcode == itemBarcode;
            if (matchesProd || matchesBarcode) {
              addReturned += refLine.qty;
            }
          }

          if (addReturned > 0) {
            final int currentReturned =
                (itemMap['returnedQty'] as num? ?? 0).toInt();
            itemMap['returnedQty'] = currentReturned + addReturned;
          }
          return itemMap;
        }).toList();

        final bool allItemsFullyReturned = updatedTxItems.isNotEmpty &&
            updatedTxItems.every((raw) {
              if (raw is! Map) return true;
              final int qty = (raw['qty'] as num? ?? 1).toInt();
              final int retQty = (raw['returnedQty'] as num? ?? 0).toInt();
              return retQty >= qty;
            });

        transaction.update(txRef, {
          'items': updatedTxItems,
          if (allItemsFullyReturned) 'isRefunded': true,
        });
      }

      if (orderRef != null && orderSnap != null && orderSnap.exists) {
        final rawOrderItems = (orderData['items'] as List? ?? []);
        final updatedOrderItems = rawOrderItems.map((raw) {
          if (raw is! Map) return raw;
          final itemMap = Map<String, dynamic>.from(raw);
          final String itemPid = itemMap['productId']?.toString() ?? '';
          final String? itemVid = itemMap['variantId']?.toString();

          int addReturned = 0;
          for (final refLine in itemsToRefund) {
            if (refLine.productId == itemPid &&
                (refLine.variantId == itemVid ||
                    (refLine.variantId == null && itemVid == null))) {
              addReturned += refLine.qty;
            }
          }

          if (addReturned > 0) {
            final int currentReturned =
                (itemMap['returnedQty'] as num? ?? 0).toInt();
            itemMap['returnedQty'] = currentReturned + addReturned;
          }
          return itemMap;
        }).toList();

        final bool allOrderReturned = updatedOrderItems.isNotEmpty &&
            updatedOrderItems.every((raw) {
              if (raw is! Map) return true;
              final int qty = (raw['qty'] as num? ?? 1).toInt();
              final int retQty = (raw['returnedQty'] as num? ?? 0).toInt();
              return retQty >= qty;
            });

        transaction.update(orderRef, {
          'items': updatedOrderItems,
          if (allOrderReturned || refundRequestId != null)
            'status': OrderStatus.refunded.name,
        });
      }

      if (refundRequestId != null && refundRequestId.isNotEmpty) {
        transaction.update(_refundRequests.doc(refundRequestId), {
          'status': RefundStatus.approved.name,
          'processedByEmail': processedBy,
          if (refundRequestCondition != null)
            'condition': refundRequestCondition.name,
          if (adminNotes != null) 'adminNotes': adminNotes,
        });
      }

      // Log permanent refund record
      final refundLogRef = _refundRecords.doc();
      transaction.set(refundLogRef, {
        'transactionId': transactionId,
        'orderId': resolvedOrderId,
        'originalSaleDate': Timestamp.fromDate(originalSaleDate),
        'customerEmail': customerEmail ?? txData['customerEmail'] ?? '',
        'refundedAt': FieldValue.serverTimestamp(),
        'items': refundRecordItems,
        'totalAmount': totalRefundAmount,
        'processedBy': processedBy,
      });
    });

    return RefundRestorationResult(
      restoredAllocations: restoredAll,
      writtenOffAllocations: writtenOffAll,
    );
  }

  void _writeRefundAuditAndLossInTx({
    required Transaction transaction,
    required _ActorInfo actor,
    required bool isSellable,
    required String lossType,
    required String orderId,
    required String transactionId,
    required DateTime originalSaleDate,
    required String productId,
    String? variantId,
    required String productName,
    required String batchId,
    required int qtyReturned,
    required double unitPrice,
    required String processedBy,
    bool isLegacyFallback = false,
  }) {
    if (!isSellable) {
      final lossRef = _lossRecords.doc();
      transaction.set(lossRef, {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'productName': productName,
        'batchId': batchId,
        'qty': qtyReturned,
        'unitPrice': unitPrice,
        'unitLossCost': unitPrice,
        'totalLoss': unitPrice * qtyReturned,
        'type': lossType,
        'notes':
            'Refund Write-Off ($lossType) from Batch $batchId (Order #$orderId, Sold ${DateFormat('MMM d, yyyy').format(originalSaleDate)})',
        'processedBy': processedBy,
        'reportedBy': processedBy,
        'referenceId': orderId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final logRef = _auditLogs.doc();
    final String action =
        isSellable ? 'REFUND_BATCH_RESTORED' : 'REFUND_BATCH_WRITEOFF';
    final String conditionStr = isSellable ? 'SELLABLE' : 'DAMAGED';

    transaction.set(logRef, {
      'timestamp': FieldValue.serverTimestamp(),
      'actorId': actor.uid,
      'actorEmail': actor.email,
      'actorName': actor.name,
      'actorRole': actor.role,
      'performedBy': actor.toPerformedByMap(),
      'module': 'INVENTORY',
      'action': action,
      'targetId': batchId,
      'targetName': '$productName ($batchId)',
      'orderId': orderId,
      'transactionId': transactionId,
      'originalSaleDate': Timestamp.fromDate(originalSaleDate),
      'productId': productId,
      'productName': productName,
      'batchId': batchId,
      'qtyReturned': qtyReturned,
      'qtyChanged': isSellable ? qtyReturned : 0,
      'condition': conditionStr,
      'isLegacyFallback': isLegacyFallback,
      'summary': isSellable
          ? 'Restored +$qtyReturned unit(s) of $productName back to original batch $batchId (Order #$orderId, Sold ${DateFormat('MMM d, yyyy').format(originalSaleDate)}).'
          : 'Written off $qtyReturned damaged/defective unit(s) of $productName against batch $batchId (Order #$orderId, Sold ${DateFormat('MMM d, yyyy').format(originalSaleDate)}). Stock NOT restored.',
      'afterData': {
        'orderId': orderId,
        'originalSaleDate': originalSaleDate.toIso8601String(),
        'productId': productId,
        'productName': productName,
        'batchId': batchId,
        'qtyReturned': qtyReturned,
        'condition': conditionStr,
        'isLegacyFallback': isLegacyFallback,
      },
    });
  }

  // ── 6. Parent Stock Synchronization ───────────────────────────────────────

  /// Atomically recalculates `products/{productId}.stock` as the exact sum of
  /// `remainingQty` across all valid sellable (active, non-expired) batches in
  /// `products/{productId}/batches`, auto-marking expired/depleted batches and
  /// mirroring to `products/{productId}.batches` and `inventory_batches`.
  Future<int> syncParentStock(String productId) async {
    final result = await reconcileProductStock(productId, dryRun: false);
    return result.newStock;
  }

  /// Writes off spoiled/damaged units directly from a specific batch inside `runTransaction`
  /// (used by the "Mark Loss / Spoiled" action in Admin Batch Audit Sheet).
  Future<void> writeOffFromBatch({
    required String productId,
    required String productName,
    required String batchId,
    required int qtyLost,
    required String lossType,
    String? notes,
    StoreSettings? settings,
  }) async {
    if (qtyLost <= 0) return;

    final actor = await _resolveActor();
    final batchRefs = await _fetchAllBatchRefs(productId);
    final prodRef = _products.doc(productId);

    await _db.runTransaction((transaction) async {
      final prodSnap = await transaction.get(prodRef);
      if (!prodSnap.exists) return;
      final prodData = prodSnap.data() ?? const <String, dynamic>{};
      final product = Product.fromMap(prodData, id: productId);

      final Map<String, ProductBatch> batchMap = {};
      for (final ref in batchRefs) {
        final snap = await transaction.get(ref);
        if (snap.exists) {
          final b = ProductBatch.fromFirestore(snap);
          batchMap[b.batchId] = b;
        }
      }

      final target = batchMap[batchId];
      if (target == null) {
        throw Exception('Batch $batchId not found for $productName.');
      }
      if (qtyLost > target.remainingQty) {
        throw Exception(
            'Cannot write off $qtyLost units; batch $batchId only has ${target.remainingQty} remaining.');
      }

      final DateTime now = DateTime.now();
      final int nextRem =
          (target.remainingQty - qtyLost).clamp(0, target.remainingQty);
      final updatedTarget = target
          .copyWith(
            remainingQty: nextRem,
            status: nextRem == 0 ? BatchStatus.depleted : BatchStatus.active,
          )
          .normalizedForPersistence(now: now);
      batchMap[batchId] = updatedTarget;

      final allBatches = normalizeAndMergeBatches(batchMap.values, now: now);
      final int syncedStock = sumActiveBatchStock(allBatches, now: now);
      final DateTime? earliestExp = _earliestActiveExpiry(allBatches, now: now);

      for (final b in allBatches) {
        final orig = batchMap[b.batchId];
        if (b.batchId == batchId || (orig != null && orig.status != b.status)) {
          transaction.set(
            _batchesCol(productId).doc(b.batchId),
            b.toFirestore(),
          );
          transaction.set(
            _inventoryBatches.doc(b.batchId),
            buildInventoryBatchMirror(b),
            SetOptions(merge: true),
          );
        }
      }

      final Map<String, dynamic> prodUpdate = {
        'stock': syncedStock,
        'batches': {for (final b in allBatches) b.batchId: b.toMap()},
        'expiryDate':
            earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
        ..._physicalReserveFields(product, syncedStock, isRestock: false),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (product.reservedStock < 0) {
        prodUpdate['reservedStock'] = 0;
      }
      final fifoPricing = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: allBatches,
        settings: settings,
      );
      if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
        prodUpdate['costPrice'] = fifoPricing.newActiveUnitCost;
        prodUpdate['computedMarkupPercent'] = fifoPricing.computedMarkupPercent;
        prodUpdate['price'] = fifoPricing.newSellingPrice;
        prodUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
      }
      transaction.update(prodRef, prodUpdate);

      final lossRef = _lossRecords.doc();
      final double unitCost =
          target.costPrice > 0 ? target.costPrice : product.costPrice;
      transaction.set(lossRef, {
        'productId': productId,
        'productName': productName,
        'batchId': batchId,
        'qty': qtyLost,
        'unitPrice': unitCost,
        'unitLossCost': unitCost,
        'totalLoss': unitCost * qtyLost,
        'type': lossType,
        'notes': notes ?? 'Write-off from Batch $batchId',
        'processedBy': actor.name,
        'reportedBy': actor.name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final logRef = _auditLogs.doc();
      transaction.set(logRef, {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name,
        'actorRole': actor.role,
        'performedBy': actor.toPerformedByMap(),
        'module': 'INVENTORY',
        'action': nextRem == 0 ? 'BATCH_DEPLETED' : 'BATCH_WRITEOFF',
        'targetId': batchId,
        'targetName': '$productName ($batchId)',
        'productId': productId,
        'productName': productName,
        'batchId': batchId,
        'qtyChanged': -qtyLost,
        'remainingQty': nextRem,
        'summary':
            'Written off $qtyLost ${product.unit} ($lossType) from batch $batchId for $productName. Remaining: $nextRem.',
      });
    });
  }

  // ── 7. Atomic Restock Inquiry Receiving (Single Transaction) ──────────────

  /// Atomically validates the supplier, creates batches for every received item
  /// on a restock inquiry, updates all parent product stock totals, mirrors to
  /// `inventory_batches`, logs `delivery_logs` & `audit_logs`, and updates
  /// `restock_inquiries/{inquiryId}` in ONE Firestore `runTransaction`.
  Future<void> receiveRestockInquiryAtomic({
    required String inquiryId,
    required String supplierId,
    String? supplierName,
    required String newStatusName,
    required List<InquiryDeliveryBatchInput> items,
    required String receivedBy,
    List<Map<String, dynamic>>? updatedInquiryItems,
    String? invoiceNumber,
    String? notes,
    StoreSettings? settings,
  }) async {
    final actor = await _resolveActor(fallbackName: receivedBy);
    final activeItems = items.where((i) => i.qtyReceived > 0).toList();
    final affectedProductIds = activeItems
        .map((i) => i.productId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final Map<String, List<DocumentReference<Map<String, dynamic>>>>
        batchRefsByProduct = {};
    for (final pid in affectedProductIds) {
      batchRefsByProduct[pid] = await _fetchAllBatchRefs(pid);
    }

    await _db.runTransaction((transaction) async {
      // ── READ PHASE ──
      final inquiryRef = _restockInquiries.doc(inquiryId);
      final inquirySnap = await transaction.get(inquiryRef);
      if (!inquirySnap.exists) {
        throw StateError('Restock inquiry $inquiryId not found.');
      }

      final validatedSupplier = (await _validateAndResolveSupplierInTx(
        transaction,
        supplierId: supplierId,
        fallbackSupplierName: supplierName,
        requireSupplier: true,
      ))!;

      final Map<String, DocumentSnapshot<Map<String, dynamic>>> prodSnaps = {};
      final Map<String, List<ProductBatch>> existingBatchesByProduct = {};
      final Map<String, Set<String>> usedIdsByProduct = {};

      for (final pid in affectedProductIds) {
        prodSnaps[pid] = await transaction.get(_products.doc(pid));
        final existing = <ProductBatch>[];
        final ids = <String>{};
        for (final ref in batchRefsByProduct[pid] ?? const []) {
          final snap = await transaction.get(ref);
          if (snap.exists) {
            final b = ProductBatch.fromFirestore(snap);
            existing.add(b);
            ids.add(b.batchId);
          }
        }
        existingBatchesByProduct[pid] = existing;
        usedIdsByProduct[pid] = ids;
      }

      // ── COMPUTE & WRITE PHASE ──
      final Map<String, List<ProductBatch>> newBatchesByProduct = {};

      for (final item in activeItems) {
        final pid = item.productId;
        final prodSnap = prodSnaps[pid];
        if (prodSnap == null || !prodSnap.exists) continue;
        final usedIds = usedIdsByProduct.putIfAbsent(pid, () => <String>{});

        final desiredId = (item.customBatchId != null &&
                item.customBatchId!.trim().isNotEmpty)
            ? item.customBatchId!.trim()
            : generateBatchId(item.dateArrived);
        final batchId = resolveUniqueBatchId(
          desiredId,
          usedIds,
          date: item.dateArrived,
        );
        usedIds.add(batchId);

        final newBatch = ProductBatch(
          batchId: batchId,
          productId: pid,
          productName: item.productName,
          supplierId: validatedSupplier.supplierId,
          supplierName: validatedSupplier.supplierName,
          datePurchased: item.datePurchased,
          dateArrived: item.dateArrived,
          expiryDate: item.expiryDate,
          costPrice: item.unitCost,
          initialQty: item.qtyReceived,
          remainingQty: item.qtyReceived,
          status: BatchStatus.active,
          invoiceNumber: invoiceNumber ?? item.invoiceNumber,
        );

        newBatchesByProduct.putIfAbsent(pid, () => []).add(newBatch);

        transaction.set(
          _batchesCol(pid).doc(batchId),
          newBatch.toFirestore(),
        );
        transaction.set(
          _inventoryBatches.doc(batchId),
          buildInventoryBatchMirror(newBatch),
        );

        transaction.set(_deliveryLogs.doc(), {
          'productId': pid,
          'productName': item.productName,
          'batchId': batchId,
          'qtyReceived': item.qtyReceived,
          'unitCost': item.unitCost,
          'totalValue': item.qtyReceived * item.unitCost,
          'datePurchased': Timestamp.fromDate(item.datePurchased),
          'dateArrived': Timestamp.fromDate(item.dateArrived),
          'expiryDate': item.expiryDate != null
              ? Timestamp.fromDate(item.expiryDate!)
              : null,
          'invoiceNumber': invoiceNumber ?? item.invoiceNumber,
          'receivedBy': receivedBy,
          'notes': notes ?? item.discrepancyNote,
          if (item.orderedQty != null) 'orderedQty': item.orderedQty,
          if (item.orderedUnitCost != null)
            'orderedUnitCost': item.orderedUnitCost,
          'supplierId': validatedSupplier.supplierId,
          'supplierName': validatedSupplier.supplierName,
          'inquiryId': inquiryId,
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.set(_auditLogs.doc(), {
          'timestamp': FieldValue.serverTimestamp(),
          'actorId': actor.uid,
          'actorEmail': actor.email,
          'actorName': actor.name,
          'actorRole': actor.role,
          'performedBy': actor.toPerformedByMap(),
          'module': 'INVENTORY',
          'action': 'BATCH_RECEIVED',
          'targetId': batchId,
          'targetName': '${item.productName} ($batchId)',
          'productId': pid,
          'productName': item.productName,
          'batchId': batchId,
          'supplierId': validatedSupplier.supplierId,
          'supplierName': validatedSupplier.supplierName,
          'qtyChanged': item.qtyReceived,
          'datePurchased': Timestamp.fromDate(item.datePurchased),
          'dateArrived': Timestamp.fromDate(item.dateArrived),
          'summary':
              'Received restock inquiry batch $batchId (+${item.qtyReceived} units) for ${item.productName} from ${validatedSupplier.supplierName}.',
        });
      }

      for (final entry in newBatchesByProduct.entries) {
        final pid = entry.key;
        final prodSnap = prodSnaps[pid];
        if (prodSnap == null || !prodSnap.exists) continue;
        final prodData = prodSnap.data() ?? const <String, dynamic>{};
        final product = Product.fromMap(prodData, id: pid);
        final existing = existingBatchesByProduct[pid] ?? const [];

        final legacyToCreate = existing.isEmpty
            ? _buildLegacyFallbackBatches(
                product: product, productData: prodData)
            : const <ProductBatch>[];
        for (final legacy in legacyToCreate) {
          transaction.set(
            _batchesCol(pid).doc(legacy.batchId),
            legacy.toFirestore(),
          );
          transaction.set(
            _inventoryBatches.doc(legacy.batchId),
            buildInventoryBatchMirror(legacy),
          );
        }

        final DateTime now = DateTime.now();
        final existingById = {for (final b in existing) b.batchId: b};
        final allBatches = normalizeAndMergeBatches(
          [
            ...existing,
            ...legacyToCreate,
            ...entry.value,
          ],
          now: now,
        );
        for (final b in allBatches) {
          final prev = existingById[b.batchId];
          if (prev != null &&
              (prev.status != b.status ||
                  prev.remainingQty != b.remainingQty)) {
            transaction.set(_batchesCol(pid).doc(b.batchId), b.toFirestore());
            transaction.set(
              _inventoryBatches.doc(b.batchId),
              buildInventoryBatchMirror(b),
              SetOptions(merge: true),
            );
          }
        }
        final syncedStock = sumActiveBatchStock(allBatches, now: now);
        final earliestExp = _earliestActiveExpiry(allBatches, now: now);

        final Map<String, dynamic> prodUpdate = {
          'stock': syncedStock,
          'initialStock': _nextInitialStockOnRestock(product, syncedStock),
          'batches': {for (final b in allBatches) b.batchId: b.toMap()},
          'expiryDate':
              earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
          ..._physicalReserveFields(product, syncedStock, isRestock: true),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (product.reservedStock < 0) {
          prodUpdate['reservedStock'] = 0;
        }
        if (product.supplierId == null || product.supplierId!.trim().isEmpty) {
          prodUpdate['supplierId'] = validatedSupplier.supplierId;
        }
        final fifoPricing = PricingEngine.recalculateForFifoTransition(
          product: product,
          updatedBatches: allBatches,
          settings: settings,
        );
        if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
          prodUpdate['costPrice'] = fifoPricing.newActiveUnitCost;
          prodUpdate['computedMarkupPercent'] =
              fifoPricing.computedMarkupPercent;
          prodUpdate['price'] = fifoPricing.newSellingPrice;
          prodUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
        }

        transaction.update(_products.doc(pid), prodUpdate);
      }

      final Map<String, dynamic> inquiryUpdate = {
        'status': newStatusName,
        'supplierId': validatedSupplier.supplierId,
        'supplierName': validatedSupplier.supplierName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (updatedInquiryItems != null && updatedInquiryItems.isNotEmpty) {
        inquiryUpdate['items'] = updatedInquiryItems;
      }
      transaction.update(inquiryRef, inquiryUpdate);
    });
  }

  // ── 8. Atomic Shelf Reconciliation, Batch Update, Batch Delete & FIFO Loss ─

  /// Atomically reconciles physical shelf counts against `products/{productId}/batches`,
  /// preserving every batch's `supplierId`, `supplierName`, `poId`, `poNumber`,
  /// `datePurchased`, and `initialQty`, updating `inventory_batches` and parent
  /// `products/{productId}.stock` = exact active sum, and logging shortage losses
  /// or overage deliveries inside ONE `runTransaction`.
  Future<int> reconcileProductBatchesAtomic({
    required String productId,
    required Map<String, int> physicalQtyByBatchId,
    String? performedByName,
    StoreSettings? settings,
  }) async {
    final actor = await _resolveActor(fallbackName: performedByName);
    final batchRefs = await _fetchAllBatchRefs(productId);
    final prodRef = _products.doc(productId);
    int syncedStock = 0;

    await _db.runTransaction((transaction) async {
      final prodSnap = await transaction.get(prodRef);
      if (!prodSnap.exists) {
        throw StateError('Product $productId not found.');
      }
      final prodData = prodSnap.data() ?? const <String, dynamic>{};
      final product = Product.fromMap(prodData, id: productId);

      final Map<String, ProductBatch> batchMap = {};
      for (final ref in batchRefs) {
        final snap = await transaction.get(ref);
        if (snap.exists) {
          final b = ProductBatch.fromFirestore(snap);
          batchMap[b.batchId] = b;
        }
      }

      // If subcollection was empty, seed from legacy embedded batches first
      if (batchMap.isEmpty && product.batches.isNotEmpty) {
        for (final b in product.batches) {
          batchMap[b.batchId] = b;
        }
      }

      int netAdjustment = 0;

      for (final entry in physicalQtyByBatchId.entries) {
        final existing = batchMap[entry.key];
        if (existing == null) continue;
        final int newQty = entry.value < 0 ? 0 : entry.value;
        final int diff = newQty - existing.remainingQty;
        if (diff == 0) continue;

        netAdjustment += diff;
        final int nextInitial =
            newQty > existing.initialQty ? newQty : existing.initialQty;
        final updated = existing.copyWith(
          initialQty: nextInitial,
          remainingQty: newQty,
          status: newQty > 0 ? BatchStatus.active : BatchStatus.depleted,
        );
        batchMap[entry.key] = updated;

        transaction.set(
          _batchesCol(productId).doc(updated.batchId),
          updated.toFirestore(),
        );
        transaction.set(
          _inventoryBatches.doc(updated.batchId),
          buildInventoryBatchMirror(updated),
        );

        final double unitCost =
            existing.costPrice > 0 ? existing.costPrice : product.costPrice;
        final String displayRef = existing.displayBatchId;

        if (diff < 0) {
          final int lostQty = diff.abs();
          transaction.set(_lossRecords.doc(), {
            'productId': productId,
            'productName': product.name,
            'batchId': existing.batchId,
            'qty': lostQty,
            'unitPrice': unitCost,
            'unitLossCost': unitCost,
            'totalLoss': unitCost * lostQty,
            'type': 'damaged',
            'notes': 'Audit Discrepancy Reconciliation on Batch $displayRef',
            'processedBy': actor.name,
            'reportedBy': actor.name,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.set(_deliveryLogs.doc(), {
            'productId': productId,
            'productName': product.name,
            'batchId': existing.batchId,
            'qtyReceived': diff,
            'unitCost': unitCost,
            'totalValue': diff * unitCost,
            'datePurchased': Timestamp.fromDate(existing.datePurchased),
            'dateArrived': Timestamp.fromDate(existing.dateArrived),
            'expiryDate': existing.expiryDate != null
                ? Timestamp.fromDate(existing.expiryDate!)
                : null,
            'invoiceNumber': existing.invoiceNumber,
            'receivedBy': 'Shelf Audit (Overage)',
            'notes':
                'Audit Discrepancy Overage Adjustment on Batch $displayRef',
            if (existing.supplierId != null && existing.supplierId!.isNotEmpty)
              'supplierId': existing.supplierId,
            if (existing.supplierName != null &&
                existing.supplierName!.isNotEmpty)
              'supplierName': existing.supplierName,
            if (existing.poNumber != null && existing.poNumber!.isNotEmpty)
              'poNumber': existing.poNumber,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      final DateTime now = DateTime.now();
      final Map<String, ProductBatch> origBatchMap = Map.from(batchMap);
      final allBatches = normalizeAndMergeBatches(batchMap.values, now: now);
      for (final b in allBatches) {
        final orig = origBatchMap[b.batchId];
        if (orig != null && orig.status != b.status) {
          transaction.set(
            _batchesCol(productId).doc(b.batchId),
            b.toFirestore(),
          );
          transaction.set(
            _inventoryBatches.doc(b.batchId),
            buildInventoryBatchMirror(b),
            SetOptions(merge: true),
          );
        }
      }
      syncedStock = sumActiveBatchStock(allBatches, now: now);
      final DateTime? earliestExp = _earliestActiveExpiry(allBatches, now: now);

      final Map<String, dynamic> prodUpdate = {
        'stock': syncedStock,
        'batches': {for (final b in allBatches) b.batchId: b.toMap()},
        'expiryDate':
            earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
        ..._physicalReserveFields(product, syncedStock, isRestock: false),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (product.reservedStock < 0) {
        prodUpdate['reservedStock'] = 0;
      }
      final fifoPricing = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: allBatches,
        settings: settings,
      );
      if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
        prodUpdate['costPrice'] = fifoPricing.newActiveUnitCost;
        prodUpdate['computedMarkupPercent'] = fifoPricing.computedMarkupPercent;
        prodUpdate['price'] = fifoPricing.newSellingPrice;
        prodUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
      }
      transaction.update(prodRef, prodUpdate);

      transaction.set(_auditLogs.doc(), {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name,
        'actorRole': actor.role,
        'performedBy': actor.toPerformedByMap(),
        'module': 'INVENTORY',
        'action': 'STOCK_RECONCILE',
        'targetId': productId,
        'targetName': product.name,
        'productId': productId,
        'productName': product.name,
        'qtyChanged': netAdjustment,
        'summary':
            'Shelf audit reconciled ${product.name} (${netAdjustment >= 0 ? "+" : ""}$netAdjustment ${product.unit}). Synced stock: $syncedStock ${product.unit}.',
      });
    });

    return syncedStock;
  }

  /// Atomically edits a single batch (quantity, supplier, cost, expiry, invoice)
  /// with transactional supplier validation and parent `products/{productId}.stock`
  /// recalculation.
  Future<ProductBatch> updateBatchAtomic({
    required String productId,
    required String batchId,
    int? remainingQty,
    double? costPrice,
    DateTime? expiryDate,
    String? supplierId,
    String? invoiceNumber,
    bool requireSupplier = true,
    StoreSettings? settings,
  }) async {
    final actor = await _resolveActor();
    final batchRefs = await _fetchAllBatchRefs(productId);
    final prodRef = _products.doc(productId);
    late ProductBatch resultBatch;

    await _db.runTransaction((transaction) async {
      final prodSnap = await transaction.get(prodRef);
      if (!prodSnap.exists) {
        throw StateError('Product $productId not found.');
      }
      final prodData = prodSnap.data() ?? const <String, dynamic>{};
      final product = Product.fromMap(prodData, id: productId);

      final Map<String, ProductBatch> batchMap = {};
      for (final ref in batchRefs) {
        final snap = await transaction.get(ref);
        if (snap.exists) {
          final b = ProductBatch.fromFirestore(snap);
          batchMap[b.batchId] = b;
        }
      }

      final existing = batchMap[batchId];
      if (existing == null) {
        throw StateError('Batch $batchId not found for product $productId.');
      }

      final candidateSupplierId =
          (supplierId != null && supplierId.trim().isNotEmpty)
              ? supplierId.trim()
              : existing.supplierId;
      final validatedSupplier = await _validateAndResolveSupplierInTx(
        transaction,
        supplierId: candidateSupplierId,
        fallbackSupplierName: existing.supplierName,
        requireSupplier: requireSupplier,
      );

      final DateTime now = DateTime.now();
      final int nextRem =
          (remainingQty ?? existing.remainingQty).clamp(0, 999999999);
      final int nextInit =
          nextRem > existing.initialQty ? nextRem : existing.initialQty;
      final updated = existing
          .copyWith(
            supplierId: validatedSupplier?.supplierId ?? existing.supplierId,
            supplierName:
                validatedSupplier?.supplierName ?? existing.supplierName,
            costPrice: costPrice ?? existing.costPrice,
            expiryDate: expiryDate ?? existing.expiryDate,
            initialQty: nextInit,
            remainingQty: nextRem,
            status: nextRem > 0 ? BatchStatus.active : BatchStatus.depleted,
            invoiceNumber: invoiceNumber ?? existing.invoiceNumber,
          )
          .normalizedForPersistence(now: now);
      batchMap[batchId] = updated;

      final allBatches = normalizeAndMergeBatches(batchMap.values, now: now);
      final int syncedStock = sumActiveBatchStock(allBatches, now: now);
      final DateTime? earliestExp = _earliestActiveExpiry(allBatches, now: now);

      for (final b in allBatches) {
        final orig = batchMap[b.batchId];
        if (b.batchId == batchId || (orig != null && orig.status != b.status)) {
          transaction.set(
            _batchesCol(productId).doc(b.batchId),
            b.toFirestore(),
          );
          transaction.set(
            _inventoryBatches.doc(b.batchId),
            buildInventoryBatchMirror(b),
            SetOptions(merge: true),
          );
        }
      }

      final bool isBatchRestock = syncedStock > product.totalStock;
      final Map<String, dynamic> prodUpdate = {
        'stock': syncedStock,
        if (isBatchRestock)
          'initialStock': _nextInitialStockOnRestock(product, syncedStock),
        'batches': {for (final b in allBatches) b.batchId: b.toMap()},
        'expiryDate':
            earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
        ..._physicalReserveFields(
          product,
          syncedStock,
          isRestock: isBatchRestock,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (product.reservedStock < 0) {
        prodUpdate['reservedStock'] = 0;
      }
      final fifoPricing = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: allBatches,
        settings: settings,
      );
      if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
        prodUpdate['costPrice'] = fifoPricing.newActiveUnitCost;
        prodUpdate['computedMarkupPercent'] = fifoPricing.computedMarkupPercent;
        prodUpdate['price'] = fifoPricing.newSellingPrice;
        prodUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
      }
      transaction.update(prodRef, prodUpdate);

      transaction.set(_auditLogs.doc(), {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name,
        'actorRole': actor.role,
        'performedBy': actor.toPerformedByMap(),
        'module': 'INVENTORY',
        'action': 'BATCH_UPDATED',
        'targetId': batchId,
        'targetName': '${product.name} ($batchId)',
        'productId': productId,
        'productName': product.name,
        'batchId': batchId,
        'qtyChanged': nextRem - existing.remainingQty,
        'summary':
            'Updated batch $batchId for ${product.name}. Remaining: $nextRem, Synced stock: $syncedStock.',
      });

      resultBatch = updated;
    });

    return resultBatch;
  }

  /// Atomically deletes a batch from `products/{productId}/batches/{batchId}`
  /// and `inventory_batches/{batchId}`, recalculating parent `products/{productId}.stock`
  /// and updating the embedded `batches` mirror in ONE `runTransaction`.
  Future<int> deleteBatchAtomic({
    required String productId,
    required String batchId,
    String? reason,
    StoreSettings? settings,
  }) async {
    final actor = await _resolveActor();
    final batchRefs = await _fetchAllBatchRefs(productId);
    final prodRef = _products.doc(productId);
    int syncedStock = 0;

    await _db.runTransaction((transaction) async {
      final prodSnap = await transaction.get(prodRef);
      if (!prodSnap.exists) {
        throw StateError('Product $productId not found.');
      }
      final prodData = prodSnap.data() ?? const <String, dynamic>{};
      final product = Product.fromMap(prodData, id: productId);

      final Map<String, ProductBatch> batchMap = {};
      for (final ref in batchRefs) {
        final snap = await transaction.get(ref);
        if (snap.exists) {
          final b = ProductBatch.fromFirestore(snap);
          batchMap[b.batchId] = b;
        }
      }

      final removed = batchMap.remove(batchId);
      if (removed == null) {
        throw StateError('Batch $batchId not found for product $productId.');
      }

      final DateTime now = DateTime.now();
      final remainingBatches =
          normalizeAndMergeBatches(batchMap.values, now: now);
      syncedStock = sumActiveBatchStock(remainingBatches, now: now);
      final DateTime? earliestExp =
          _earliestActiveExpiry(remainingBatches, now: now);

      transaction.delete(_batchesCol(productId).doc(batchId));
      transaction.delete(_inventoryBatches.doc(batchId));

      final Map<String, dynamic> prodUpdate = {
        'stock': syncedStock,
        'batches': {for (final b in remainingBatches) b.batchId: b.toMap()},
        'expiryDate':
            earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
        ..._physicalReserveFields(product, syncedStock, isRestock: false),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (product.reservedStock < 0) {
        prodUpdate['reservedStock'] = 0;
      }
      final fifoPricing = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: remainingBatches,
        settings: settings,
      );
      if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
        prodUpdate['costPrice'] = fifoPricing.newActiveUnitCost;
        prodUpdate['computedMarkupPercent'] = fifoPricing.computedMarkupPercent;
        prodUpdate['price'] = fifoPricing.newSellingPrice;
        prodUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
      }
      transaction.update(prodRef, prodUpdate);

      transaction.set(_auditLogs.doc(), {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name,
        'actorRole': actor.role,
        'performedBy': actor.toPerformedByMap(),
        'module': 'INVENTORY',
        'action': 'BATCH_DELETED',
        'targetId': batchId,
        'targetName': '${product.name} ($batchId)',
        'productId': productId,
        'productName': product.name,
        'batchId': batchId,
        'qtyChanged': -removed.remainingQty,
        'summary':
            'Deleted batch $batchId (-${removed.remainingQty} ${product.unit}) from ${product.name}. New stock: $syncedStock.${reason != null && reason.trim().isNotEmpty ? " Reason: $reason" : ""}',
      });
    });

    return syncedStock;
  }

  /// Atomically deducts a loss/spoilage record from the oldest active FIFO
  /// batches so `products/{productId}.stock` stays 100% synchronized with
  /// `products/{productId}/batches` and `inventory_batches`.
  Future<void> recordLossFIFO({
    required String productId,
    required String productName,
    required int qtyLost,
    required double unitPrice,
    required String lossType,
    required String notes,
    StoreSettings? settings,
  }) async {
    if (qtyLost <= 0) return;

    final actor = await _resolveActor();
    final batchRefs = await _fetchAllBatchRefs(productId);
    final prodRef = _products.doc(productId);

    await _db.runTransaction((transaction) async {
      final prodSnap = await transaction.get(prodRef);
      if (!prodSnap.exists) return;

      final prodData = prodSnap.data() ?? const <String, dynamic>{};
      final product = Product.fromMap(prodData, id: productId);

      if (product.hasVariants) {
        transaction.set(_lossRecords.doc(), {
          'productId': productId,
          'productName': productName,
          'qty': qtyLost,
          'unitPrice': unitPrice,
          'unitLossCost': unitPrice,
          'totalLoss': unitPrice * qtyLost,
          'type': lossType,
          'notes': notes,
          'processedBy': actor.name,
          'reportedBy': actor.name,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(prodRef, {
          'stock': (product.stock - qtyLost).clamp(0, 999999999),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final List<ProductBatch> existing = [];
      for (final ref in batchRefs) {
        final snap = await transaction.get(ref);
        if (snap.exists) {
          existing.add(ProductBatch.fromFirestore(snap));
        }
      }

      final DateTime now = DateTime.now();
      final List<ProductBatch> working = existing.isEmpty && product.stock > 0
          ? _buildLegacyFallbackBatches(product: product, productData: prodData)
          : List<ProductBatch>.from(existing);
      final normalizedWorking = normalizeAndMergeBatches(working, now: now);

      int remainingToDeduct = qtyLost;
      final List<ProductBatch> updatedList = [];
      final Map<String, ProductBatch> origById = {
        for (final b in existing) b.batchId: b,
      };

      for (final b in normalizedWorking) {
        if (remainingToDeduct <= 0 || !b.isSellableAt(now)) {
          updatedList.add(b);
          continue;
        }
        final int take = b.remainingQty >= remainingToDeduct
            ? remainingToDeduct
            : b.remainingQty;
        remainingToDeduct -= take;
        final int nextRem = (b.remainingQty - take).clamp(0, b.remainingQty);
        final updated = b.copyWith(
          remainingQty: nextRem,
          status: nextRem > 0 ? BatchStatus.active : BatchStatus.depleted,
        );
        updatedList.add(updated);
      }

      final allBatches = normalizeAndMergeBatches(updatedList, now: now);
      final int syncedStock = sumActiveBatchStock(allBatches, now: now);
      final DateTime? earliestExp = _earliestActiveExpiry(allBatches, now: now);

      if (existing.isEmpty) {
        for (final b in allBatches) {
          transaction.set(
              _batchesCol(productId).doc(b.batchId), b.toFirestore());
          transaction.set(
            _inventoryBatches.doc(b.batchId),
            buildInventoryBatchMirror(b),
            SetOptions(merge: true),
          );
        }
      } else {
        for (final b in allBatches) {
          final orig = origById[b.batchId];
          if (orig == null ||
              orig.remainingQty != b.remainingQty ||
              orig.status != b.status) {
            transaction.set(
                _batchesCol(productId).doc(b.batchId), b.toFirestore());
            transaction.set(
              _inventoryBatches.doc(b.batchId),
              buildInventoryBatchMirror(b),
              SetOptions(merge: true),
            );
          }
        }
      }

      final Map<String, dynamic> prodUpdate = {
        'stock': syncedStock,
        'batches': {for (final b in allBatches) b.batchId: b.toMap()},
        'expiryDate':
            earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
        ..._physicalReserveFields(product, syncedStock, isRestock: false),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (product.reservedStock < 0) {
        prodUpdate['reservedStock'] = 0;
      }
      final fifoPricing = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: allBatches,
        settings: settings,
      );
      if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
        prodUpdate['costPrice'] = fifoPricing.newActiveUnitCost;
        prodUpdate['computedMarkupPercent'] = fifoPricing.computedMarkupPercent;
        prodUpdate['price'] = fifoPricing.newSellingPrice;
        prodUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
      }
      transaction.update(prodRef, prodUpdate);

      transaction.set(_lossRecords.doc(), {
        'productId': productId,
        'productName': productName,
        'qty': qtyLost,
        'unitPrice': unitPrice,
        'unitLossCost': unitPrice,
        'totalLoss': unitPrice * qtyLost,
        'type': lossType,
        'notes': notes,
        'processedBy': actor.name,
        'reportedBy': actor.name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.set(_auditLogs.doc(), {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name,
        'actorRole': actor.role,
        'performedBy': actor.toPerformedByMap(),
        'module': 'INVENTORY',
        'action': 'STOCK_ADJUST',
        'targetId': productId,
        'targetName': productName,
        'productId': productId,
        'productName': productName,
        'qtyChanged': -qtyLost,
        'summary':
            'Inventory loss recorded via FIFO deduction (-$qtyLost ${product.unit}) for $productName. New synced stock: $syncedStock. Reason: $notes',
      });
    });
  }

  // ── 9. Atomic Manual Stock Adjustment & Reservation Lifecycle ─────────────

  /// Atomically adjusts a product's total sellable stock to [targetStock] via FIFO
  /// batches inside `runTransaction` (replacing direct parent `stock` overwrites).
  ///
  /// - If [targetStock] < current sellable stock: FIFO-deducts from oldest valid batches.
  /// - If [targetStock] > current sellable stock: creates a `MANUAL-ADJ-...` batch.
  /// - Auto-marks expired/depleted batches and overwrites `products/{productId}.stock`.
  Future<int> adjustStockManualAtomic({
    required String productId,
    required int targetStock,
    String? reason,
    String? performedByName,
    StoreSettings? settings,
  }) async {
    final int clampedTarget = targetStock < 0 ? 0 : targetStock;
    final actor = await _resolveActor(fallbackName: performedByName);
    final batchRefs = await _fetchAllBatchRefs(productId);
    final prodRef = _products.doc(productId);
    int syncedStock = 0;

    await _db.runTransaction((transaction) async {
      final DateTime now = DateTime.now();
      final prodSnap = await transaction.get(prodRef);
      if (!prodSnap.exists) {
        throw StateError('Product $productId not found.');
      }
      final prodData = prodSnap.data() ?? const <String, dynamic>{};
      final product = Product.fromMap(prodData, id: productId);

      if (product.hasVariants) {
        syncedStock = clampedTarget;
        transaction.update(prodRef, {
          'stock': syncedStock,
          if (product.reservedStock < 0) 'reservedStock': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final List<ProductBatch> existing = [];
      for (final ref in batchRefs) {
        final snap = await transaction.get(ref);
        if (snap.exists) {
          existing.add(ProductBatch.fromFirestore(snap));
        }
      }

      final List<ProductBatch> seedBatches = existing.isEmpty &&
              product.stock > 0
          ? _buildLegacyFallbackBatches(product: product, productData: prodData)
          : existing;
      final Map<String, ProductBatch> origById = {
        for (final b in existing) b.batchId: b,
      };

      List<ProductBatch> working =
          normalizeAndMergeBatches(seedBatches, now: now);
      final int currentSellable = sumActiveBatchStock(working, now: now);
      final int delta = clampedTarget - currentSellable;

      if (delta < 0) {
        final plan = computeFifoDeduction(
          batches: working,
          requestedQty: delta.abs(),
          productName: product.name,
          now: now,
        );
        working = plan.updatedBatches;
      } else if (delta > 0) {
        final existingIds = working.map((b) => b.batchId).toSet();
        final adjId = resolveUniqueBatchId(
          'MANUAL-ADJ-${DateFormat('yyyyMMdd').format(now)}',
          existingIds,
          date: now,
        );
        final adjBatch = ProductBatch(
          batchId: adjId,
          productId: productId,
          productName: product.name,
          supplierId: product.supplierId,
          datePurchased: now,
          dateArrived: now,
          expiryDate:
              product.expiryDate != null && product.expiryDate!.isAfter(now)
                  ? product.expiryDate
                  : null,
          costPrice: product.effectiveUnitCost,
          initialQty: delta,
          remainingQty: delta,
          status: BatchStatus.active,
          invoiceNumber: 'MANUAL-ADJUST',
        );
        working = normalizeAndMergeBatches([...working, adjBatch], now: now);
      }

      syncedStock = sumActiveBatchStock(working, now: now);
      final DateTime? earliestExp = _earliestActiveExpiry(working, now: now);

      for (final b in working) {
        final prev = origById[b.batchId];
        if (prev == null ||
            prev.remainingQty != b.remainingQty ||
            prev.status != b.status) {
          transaction.set(
            _batchesCol(productId).doc(b.batchId),
            b.toFirestore(),
          );
          transaction.set(
            _inventoryBatches.doc(b.batchId),
            buildInventoryBatchMirror(b),
            SetOptions(merge: true),
          );
        }
      }

      final Map<String, dynamic> prodUpdate = {
        'stock': syncedStock,
        if (delta > 0)
          'initialStock': _nextInitialStockOnRestock(product, syncedStock),
        'batches': {for (final b in working) b.batchId: b.toMap()},
        'expiryDate':
            earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
        ..._physicalReserveFields(
          product,
          syncedStock,
          isRestock: delta > 0,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (product.reservedStock < 0) {
        prodUpdate['reservedStock'] = 0;
      }

      final fifoPricing = PricingEngine.recalculateForFifoTransition(
        product: product,
        updatedBatches: working,
        settings: settings,
      );
      if (fifoPricing != null && !fifoPricing.hasInvalidCost) {
        prodUpdate['costPrice'] = fifoPricing.newActiveUnitCost;
        prodUpdate['computedMarkupPercent'] = fifoPricing.computedMarkupPercent;
        prodUpdate['price'] = fifoPricing.newSellingPrice;
        prodUpdate['sellingPrice'] = fifoPricing.newSellingPrice;
      }
      transaction.update(prodRef, prodUpdate);

      transaction.set(_auditLogs.doc(), {
        'timestamp': FieldValue.serverTimestamp(),
        'actorId': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name,
        'actorRole': actor.role,
        'performedBy': actor.toPerformedByMap(),
        'module': 'Inventory',
        'action': 'STOCK_ADJUST',
        'targetId': productId,
        'targetName': product.name,
        'productId': productId,
        'productName': product.name,
        'qtyChanged': syncedStock - currentSellable,
        'summary':
            'Inventory stock manually adjusted ($currentSellable -> $syncedStock) for ${product.name}.${reason != null && reason.trim().isNotEmpty ? " Reason: $reason" : ""}',
        'afterData': {'stock': syncedStock},
      });
    });

    return syncedStock;
  }

  /// Atomically creates a pre-order and increments `reservedStock` inside `runTransaction`,
  /// ensuring sufficient sellable unreserved stock exists so reservations stay accurate.
  Future<void> reserveStockAtomic({
    required PreOrder order,
    String? performedByName,
  }) async {
    final Set<String> uniqueProductIds = order.items
        .map((i) => i.productId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final Map<String, List<DocumentReference<Map<String, dynamic>>>>
        batchRefsByProduct = {};
    for (final pid in uniqueProductIds) {
      batchRefsByProduct[pid] = await _fetchAllBatchRefs(pid);
    }

    await _db.runTransaction((transaction) async {
      final DateTime now = DateTime.now();
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> prodSnaps = {};
      final Map<String, List<ProductBatch>> batchesByProduct = {};

      for (final pid in uniqueProductIds) {
        prodSnaps[pid] = await transaction.get(_products.doc(pid));
        final list = <ProductBatch>[];
        for (final ref in batchRefsByProduct[pid] ?? const []) {
          final snap = await transaction.get(ref);
          if (snap.exists) {
            list.add(ProductBatch.fromFirestore(snap));
          }
        }
        batchesByProduct[pid] = list;
      }

      final Map<String, int> reserveStdByProduct = {};
      final Map<String, Map<String, int>> reserveVarByProduct = {};
      for (final item in order.items) {
        if (item.productId.isEmpty || item.qty <= 0) continue;
        if (item.variantId != null && item.variantId!.isNotEmpty) {
          reserveVarByProduct.putIfAbsent(item.productId, () => {}).update(
              item.variantId!, (v) => v + item.qty,
              ifAbsent: () => item.qty);
        } else {
          reserveStdByProduct.update(item.productId, (v) => v + item.qty,
              ifAbsent: () => item.qty);
        }
      }

      for (final pid in uniqueProductIds) {
        final snap = prodSnaps[pid];
        if (snap == null || !snap.exists) continue;
        final product = Product.fromMap(snap.data() ?? const {}, id: pid);
        final prodRef = _products.doc(pid);

        if (reserveVarByProduct.containsKey(pid)) {
          final vMap = reserveVarByProduct[pid]!;
          int totalVarRes = 0;
          final Map<String, dynamic> updateData = {
            'updatedAt': FieldValue.serverTimestamp(),
          };
          for (final v in product.variants) {
            final addRes = vMap[v.id] ?? 0;
            final int onlineAvail = v.onlineAvailableStock;
            if (addRes > onlineAvail) {
              throw Exception(
                'Insufficient online available stock to reserve ${product.name} (${v.name}). Online available: $onlineAvail, Requested: $addRes.',
              );
            }
            final nextRes = v.effectiveReservedStock + addRes;
            totalVarRes += nextRes;
            if (addRes > 0 || v.reservedStock < 0) {
              updateData['variants.${v.id}.reservedStock'] = nextRes;
            }
          }
          updateData['reservedStock'] = totalVarRes;
          updateData.addAll(_variantPhysicalReserveFields(product));
          transaction.update(prodRef, updateData);
          continue;
        }

        final addRes = reserveStdByProduct[pid] ?? 0;
        final origBatches = batchesByProduct[pid] ?? const [];
        final normalized = normalizeAndMergeBatches(origBatches, now: now);
        final int sellable = normalized.isNotEmpty
            ? sumActiveBatchStock(normalized, now: now)
            : product.stock.clamp(0, 999999999);
        final int physicalReserve = InventoryAllocation.resolvePhysicalReserve(
          totalStock: sellable,
          storedPhysicalReserve: product.physicalReserve,
        );
        final int onlineAvail = InventoryAllocation.calculateOnlineAvailable(
          totalStock: sellable,
          physicalReserve: physicalReserve,
          reservedStock: product.effectiveReservedStock,
        );
        if (addRes > onlineAvail) {
          throw Exception(
            'Insufficient online available stock to reserve ${product.name}. Online available: $onlineAvail, Requested: $addRes.',
          );
        }

        final origById = {for (final b in origBatches) b.batchId: b};
        for (final b in normalized) {
          final prev = origById[b.batchId];
          if (prev != null && prev.status != b.status) {
            transaction.set(_batchesCol(pid).doc(b.batchId), b.toFirestore());
            transaction.set(
              _inventoryBatches.doc(b.batchId),
              buildInventoryBatchMirror(b),
              SetOptions(merge: true),
            );
          }
        }

        final earliestExp = _earliestActiveExpiry(normalized, now: now);
        final int nextReserved = product.effectiveReservedStock + addRes;
        final Map<String, dynamic> prodUpdate = {
          'stock': sellable,
          'reservedStock': nextReserved,
          if (normalized.isNotEmpty)
            'batches': {for (final b in normalized) b.batchId: b.toMap()},
          'expiryDate':
              earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
          ..._physicalReserveFields(product, sellable, isRestock: false),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        transaction.update(prodRef, prodUpdate);
      }

      transaction.set(_orders.doc(order.id), {
        ...order.toFirestore(),
        'reservationReleased': false,
      });
    });
  }

  /// Atomically releases `reservedStock` inside `runTransaction` with strict `>= 0`
  /// clamping and idempotency protection so `reservedStock` can NEVER go negative.
  Future<void> releaseReservedStockAtomic({
    required List<CartItem> items,
    String? orderDocId,
    PreOrder? updatedOrder,
  }) async {
    if (items.isEmpty && updatedOrder == null) return;

    final Set<String> uniqueProductIds =
        items.map((i) => i.productId).where((id) => id.isNotEmpty).toSet();
    final Map<String, List<DocumentReference<Map<String, dynamic>>>>
        batchRefsByProduct = {};
    for (final pid in uniqueProductIds) {
      batchRefsByProduct[pid] = await _fetchAllBatchRefs(pid);
    }

    await _db.runTransaction((transaction) async {
      final DateTime now = DateTime.now();

      DocumentReference<Map<String, dynamic>>? orderRef;
      DocumentSnapshot<Map<String, dynamic>>? orderSnap;
      bool shouldReleaseStock = true;

      if (orderDocId != null && orderDocId.isNotEmpty) {
        orderRef = _orders.doc(orderDocId);
        orderSnap = await transaction.get(orderRef);
        if (orderSnap.exists) {
          final oData = orderSnap.data() ?? const <String, dynamic>{};
          final bool alreadyReleased = oData['reservationReleased'] == true;
          final String currentStatus =
              oData['status']?.toString().toLowerCase() ?? '';
          if (alreadyReleased || currentStatus == OrderStatus.collected.name) {
            shouldReleaseStock = false;
          }
        }
      }

      final Map<String, DocumentSnapshot<Map<String, dynamic>>> prodSnaps = {};
      final Map<String, List<ProductBatch>> batchesByProduct = {};

      if (shouldReleaseStock) {
        for (final pid in uniqueProductIds) {
          prodSnaps[pid] = await transaction.get(_products.doc(pid));
          final list = <ProductBatch>[];
          for (final ref in batchRefsByProduct[pid] ?? const []) {
            final snap = await transaction.get(ref);
            if (snap.exists) {
              list.add(ProductBatch.fromFirestore(snap));
            }
          }
          batchesByProduct[pid] = list;
        }
      }

      if (shouldReleaseStock) {
        final Map<String, int> releaseStdByProduct = {};
        final Map<String, Map<String, int>> releaseVarByProduct = {};
        for (final item in items) {
          if (item.productId.isEmpty || item.qty <= 0) continue;
          if (item.variantId != null && item.variantId!.isNotEmpty) {
            releaseVarByProduct.putIfAbsent(item.productId, () => {}).update(
                item.variantId!, (v) => v + item.qty,
                ifAbsent: () => item.qty);
          } else {
            releaseStdByProduct.update(item.productId, (v) => v + item.qty,
                ifAbsent: () => item.qty);
          }
        }

        for (final pid in uniqueProductIds) {
          final snap = prodSnaps[pid];
          if (snap == null || !snap.exists) continue;
          final product = Product.fromMap(snap.data() ?? const {}, id: pid);
          final prodRef = _products.doc(pid);

          if (releaseVarByProduct.containsKey(pid)) {
            final vMap = releaseVarByProduct[pid]!;
            int newTotalReserved = 0;
            final Map<String, int> nextResByVariant = {};
            final Map<String, dynamic> updateData = {
              'updatedAt': FieldValue.serverTimestamp(),
            };
            for (final v in product.variants) {
              final rel = vMap[v.id] ?? 0;
              final nextRes =
                  (v.effectiveReservedStock - rel).clamp(0, 999999999);
              nextResByVariant[v.id] = nextRes;
              newTotalReserved += nextRes;
              if (rel > 0 || v.reservedStock < 0) {
                updateData['variants.${v.id}.reservedStock'] = nextRes;
              }
            }
            updateData['reservedStock'] = newTotalReserved;
            updateData.addAll(_variantPhysicalReserveFields(product));
            transaction.update(prodRef, updateData);
            continue;
          }

          final rel = releaseStdByProduct[pid] ?? 0;
          final origBatches = batchesByProduct[pid] ?? const [];
          final normalized = normalizeAndMergeBatches(origBatches, now: now);
          final origById = {for (final b in origBatches) b.batchId: b};

          for (final b in normalized) {
            final prev = origById[b.batchId];
            if (prev != null && prev.status != b.status) {
              transaction.set(_batchesCol(pid).doc(b.batchId), b.toFirestore());
              transaction.set(
                _inventoryBatches.doc(b.batchId),
                buildInventoryBatchMirror(b),
                SetOptions(merge: true),
              );
            }
          }

          final int syncedStock = normalized.isNotEmpty
              ? sumActiveBatchStock(normalized, now: now)
              : product.stock.clamp(0, 999999999);
          final DateTime? earliestExp =
              _earliestActiveExpiry(normalized, now: now);
          final int nextReserved =
              (product.effectiveReservedStock - rel).clamp(0, 999999999);

          transaction.update(prodRef, {
            'stock': syncedStock,
            'reservedStock': nextReserved,
            if (normalized.isNotEmpty)
              'batches': {for (final b in normalized) b.batchId: b.toMap()},
            'expiryDate':
                earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
            ..._physicalReserveFields(product, syncedStock, isRestock: false),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      if (orderRef != null && orderSnap != null && orderSnap.exists) {
        if (updatedOrder != null) {
          transaction.update(orderRef, {
            ...updatedOrder.toFirestore(),
            'reservationReleased': true,
          });
        } else {
          transaction.update(orderRef, {'reservationReleased': true});
        }
      }
    });
  }

  /// Queries open pickup orders (`pending`, `staging`, `ready`) to compute the
  /// authoritative `reservedStock` per product (and per variant) for reconciliation.
  Future<
      ({
        Map<String, int> byProduct,
        Map<String, Map<String, int>> byVariant
      })> _computeExpectedReservationsFromOpenOrders() async {
    final Map<String, int> byProduct = {};
    final Map<String, Map<String, int>> byVariant = {};

    try {
      final snap = await _orders.where('status', whereIn: [
        OrderStatus.pending.name,
        OrderStatus.staging.name,
        OrderStatus.ready.name,
      ]).get();

      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['reservationReleased'] == true) continue;
        final order = PreOrder.fromFirestore(doc);
        for (final item in order.items) {
          if (item.productId.isEmpty || item.qty <= 0) continue;
          if (item.variantId != null && item.variantId!.isNotEmpty) {
            byVariant.putIfAbsent(item.productId, () => {}).update(
                item.variantId!, (v) => v + item.qty,
                ifAbsent: () => item.qty);
          }
          byProduct.update(item.productId, (v) => v + item.qty,
              ifAbsent: () => item.qty);
        }
      }
    } catch (e) {
      debugPrint(
          'Failed to compute expected reservations from open orders: $e');
    }

    return (byProduct: byProduct, byVariant: byVariant);
  }

  // ── 10. One-Time & On-Demand Reconciliation Utilities ─────────────────────

  /// Safely reconciles a single product's inventory inside `runTransaction`:
  /// - Scans `products/{productId}/batches`, marks expired batches `'EXPIRED'`
  ///   and zero-qty batches `'DEPLETED'`.
  /// - Recalculates exact sellable stock (`status == 'ACTIVE' && remainingQty > 0 && not expired`).
  /// - Recalculates exact `reservedStock` from open `pending`/`staging`/`ready` orders
  ///   (fixing negative or leaked reservations).
  /// - Overwrites `products/{productId}.stock`, `reservedStock`, `batches` mirror,
  ///   `expiryDate`, and top-level `inventory_batches/{batchId}`.
  Future<ProductStockReconciliationResult> reconcileProductStock(
    String productId, {
    bool dryRun = false,
  }) async {
    final actor = await _resolveActor();
    final reservations = await _computeExpectedReservationsFromOpenOrders();
    final batchRefs = await _fetchAllBatchRefs(productId);
    final prodRef = _products.doc(productId);

    late ProductStockReconciliationResult result;

    await _db.runTransaction((transaction) async {
      final DateTime now = DateTime.now();
      final prodSnap = await transaction.get(prodRef);
      if (!prodSnap.exists) {
        throw StateError('Product $productId not found.');
      }

      final prodData = prodSnap.data() ?? const <String, dynamic>{};
      final product = Product.fromMap(prodData, id: productId);
      final int expectedReserved = reservations.byProduct[productId] ?? 0;

      if (product.hasVariants) {
        final varResMap =
            reservations.byVariant[productId] ?? const <String, int>{};
        int sumVarStock = 0;
        int sumVarReserved = 0;
        final Map<String, int> nextStockByVariant = {};
        final Map<String, int> nextResByVariant = {};
        final Map<String, dynamic> updateData = {
          'updatedAt': FieldValue.serverTimestamp(),
        };
        for (final v in product.variants) {
          final clampedStock = v.stock.clamp(0, 999999999);
          final targetRes = (varResMap[v.id] ?? 0).clamp(0, 999999999);
          nextStockByVariant[v.id] = clampedStock;
          nextResByVariant[v.id] = targetRes;
          sumVarStock += clampedStock;
          sumVarReserved += targetRes;
          if (v.stock != clampedStock) {
            updateData['variants.${v.id}.stock'] = clampedStock;
          }
          if (v.reservedStock != targetRes) {
            updateData['variants.${v.id}.reservedStock'] = targetRes;
          }
        }
        updateData['stock'] = sumVarStock;
        updateData['reservedStock'] = sumVarReserved;

        if (!dryRun &&
            (product.stock != sumVarStock ||
                product.reservedStock != sumVarReserved ||
                updateData.length > 3)) {
          updateData.addAll(_variantPhysicalReserveFields(
            product,
            stockOverrides: nextStockByVariant,
          ));
          transaction.update(prodRef, updateData);
          transaction.set(_auditLogs.doc(), {
            'timestamp': FieldValue.serverTimestamp(),
            'actorId': actor.uid,
            'actorEmail': actor.email,
            'actorName': actor.name,
            'actorRole': actor.role,
            'performedBy': actor.toPerformedByMap(),
            'module': 'INVENTORY',
            'action': 'INVENTORY_SYNC_REPAIR',
            'targetId': productId,
            'targetName': product.name,
            'productId': productId,
            'productName': product.name,
            'qtyChanged': sumVarStock - product.stock,
            'summary':
                'Reconciled variant product ${product.name}: stock ${product.stock} -> $sumVarStock, reserved ${product.reservedStock} -> $sumVarReserved.',
          });
        }

        result = ProductStockReconciliationResult(
          productId: productId,
          productName: product.name,
          oldStock: product.stock,
          newStock: sumVarStock,
          oldReservedStock: product.reservedStock,
          newReservedStock: sumVarReserved,
          expiredBatchesMarked: 0,
          depletedBatchesMarked: 0,
          batchesScanned: 0,
          dryRun: dryRun,
        );
        return;
      }

      final List<ProductBatch> rawBatches = [];
      for (final ref in batchRefs) {
        final bSnap = await transaction.get(ref);
        if (bSnap.exists) {
          rawBatches.add(ProductBatch.fromFirestore(bSnap));
        }
      }

      final bool seededLegacy = rawBatches.isEmpty && product.stock > 0;
      final List<ProductBatch> sourceBatches = seededLegacy
          ? _buildLegacyFallbackBatches(product: product, productData: prodData)
          : rawBatches;

      final Map<String, ProductBatch> origById = {
        for (final b in rawBatches) b.batchId: b,
      };

      int expiredMarked = 0;
      int depletedMarked = 0;
      final List<ProductBatch> normalizedList = [];

      for (final b in sourceBatches) {
        final norm = b.normalizedForPersistence(now: now);
        if (norm.status == BatchStatus.expired &&
            b.status != BatchStatus.expired) {
          expiredMarked++;
        } else if (norm.status == BatchStatus.depleted &&
            b.status != BatchStatus.depleted) {
          depletedMarked++;
        }
        normalizedList.add(norm);
      }

      final merged = mergeBatchesById(normalizedList);
      final int syncedStock = sumActiveBatchStock(merged, now: now);
      final DateTime? earliestExp = _earliestActiveExpiry(merged, now: now);
      final int syncedReserved = expectedReserved.clamp(0, 999999999);

      if (!dryRun) {
        for (final b in merged) {
          final prev = origById[b.batchId];
          if (seededLegacy ||
              prev == null ||
              prev.status != b.status ||
              prev.remainingQty != b.remainingQty) {
            transaction.set(
              _batchesCol(productId).doc(b.batchId),
              b.toFirestore(),
            );
          }
          transaction.set(
            _inventoryBatches.doc(b.batchId),
            buildInventoryBatchMirror(b),
            SetOptions(merge: true),
          );
        }

        transaction.update(prodRef, {
          'stock': syncedStock,
          'reservedStock': syncedReserved,
          'batches': {for (final b in merged) b.batchId: b.toMap()},
          'expiryDate':
              earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
          ..._physicalReserveFields(product, syncedStock, isRestock: false),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(_auditLogs.doc(), {
          'timestamp': FieldValue.serverTimestamp(),
          'actorId': actor.uid,
          'actorEmail': actor.email,
          'actorName': actor.name,
          'actorRole': actor.role,
          'performedBy': actor.toPerformedByMap(),
          'module': 'INVENTORY',
          'action': 'INVENTORY_SYNC_REPAIR',
          'targetId': productId,
          'targetName': product.name,
          'productId': productId,
          'productName': product.name,
          'qtyChanged': syncedStock - product.stock,
          'summary':
              'Reconciled ${product.name}: stock ${product.stock} -> $syncedStock, reserved ${product.reservedStock} -> $syncedReserved, expired marked: $expiredMarked, depleted marked: $depletedMarked.',
        });
      }

      result = ProductStockReconciliationResult(
        productId: productId,
        productName: product.name,
        oldStock: product.stock,
        newStock: syncedStock,
        oldReservedStock: product.reservedStock,
        newReservedStock: syncedReserved,
        expiredBatchesMarked: expiredMarked,
        depletedBatchesMarked: depletedMarked,
        batchesScanned: merged.length,
        dryRun: dryRun,
      );
    });

    return result;
  }

  /// One-time / on-demand global reconciliation utility across ALL products.
  ///
  /// Scans every product and its `products/{id}/batches` subcollection, cleans up
  /// expired/depleted batch statuses, recalculates exact `reservedStock` from active
  /// open orders, backfills missing supplier linkages where resolvable, and
  /// overwrites `products/{id}.stock`, `reservedStock`, and batch mirrors atomically.
  Future<InventoryReconciliationReport> reconcileAllStock({
    bool dryRun = false,
    String? defaultFallbackSupplierId,
  }) {
    return auditAndReconcileInventory(
      dryRun: dryRun,
      defaultFallbackSupplierId: defaultFallbackSupplierId,
    );
  }

  /// Audits all products and their `products/{id}/batches` subcollections:
  /// (a) Finds batches missing a valid `supplierId` (null/empty or pointing to a deleted supplier).
  /// (b) Finds products where `products/{id}.stock`, `reservedStock`, batch statuses
  ///     (`EXPIRED` / `DEPLETED`), or embedded `batches` mirror diverge from the
  ///     unified sellable FIFO batch Single Source of Truth and active open orders.
  ///
  /// When [dryRun] is `false`, atomically repairs supplier backfills, batch statuses,
  /// `reservedStock`, `products/{id}.stock`, `products/{id}.batches`, and `inventory_batches`.
  Future<InventoryReconciliationReport> auditAndReconcileInventory({
    bool dryRun = true,
    String? defaultFallbackSupplierId,
  }) async {
    final actor = await _resolveActor();
    final DateTime auditNow = DateTime.now();

    // 1. Load authoritative suppliers, purchase orders & active reservations
    final suppliersSnap = await _suppliers.get();
    final Map<String, String> validSuppliersById = {};
    for (final doc in suppliersSnap.docs) {
      final data = doc.data();
      final name = (data['name'] ?? data['supplierName'] ?? 'Unnamed Supplier')
          .toString()
          .trim();
      validSuppliersById[doc.id] =
          name.isNotEmpty ? name : 'Supplier ${doc.id}';
    }

    String? validatedFallbackId;
    String? validatedFallbackName;
    if (defaultFallbackSupplierId != null &&
        defaultFallbackSupplierId.trim().isNotEmpty &&
        validSuppliersById.containsKey(defaultFallbackSupplierId.trim())) {
      validatedFallbackId = defaultFallbackSupplierId.trim();
      validatedFallbackName = validSuppliersById[validatedFallbackId];
    }

    final poSnap = await _purchaseOrders.get();
    final Map<String, PurchaseOrder> poById = {};
    final Map<String, PurchaseOrder> poByNumber = {};
    for (final doc in poSnap.docs) {
      final po = PurchaseOrder.fromFirestore(doc);
      poById[po.id] = po;
      if (po.poNumber.trim().isNotEmpty) {
        poByNumber[po.poNumber.trim().toLowerCase()] = po;
      }
    }

    final reservations = await _computeExpectedReservationsFromOpenOrders();

    final productsSnap = await _products.get();
    final List<OrphanBatchFinding> orphanFindings = [];
    final List<StockDriftFinding> driftFindings = [];
    int productsScanned = 0;
    int batchesScanned = 0;
    int batchesSupplierFixed = 0;
    int productsStockFixed = 0;
    int reservedStockFixed = 0;
    int totalExpiredMarked = 0;
    int totalDepletedMarked = 0;

    for (final prodDoc in productsSnap.docs) {
      final prodData = prodDoc.data();
      final product = Product.fromMap(prodData, id: prodDoc.id);
      productsScanned++;

      final int expectedReserved =
          (reservations.byProduct[product.id] ?? 0).clamp(0, 999999999);

      if (product.hasVariants) {
        final int variantSum = product.variants
            .fold<int>(0, (acc, v) => acc + v.stock.clamp(0, 999999999));
        final bool stockDiffers = product.stock != variantSum;
        final bool reservedDiffers = product.reservedStock != expectedReserved;
        if (stockDiffers || reservedDiffers) {
          driftFindings.add(StockDriftFinding(
            productId: product.id,
            productName: product.name,
            storedStock: product.stock,
            activeBatchSum: variantSum,
            storedReservedStock: product.reservedStock,
            expectedReservedStock: expectedReserved,
          ));
          if (!dryRun) {
            await reconcileProductStock(product.id, dryRun: false);
            if (stockDiffers) productsStockFixed++;
            if (reservedDiffers) reservedStockFixed++;
          }
        }
        continue;
      }

      final subSnap = await _batchesCol(product.id).get();
      final List<ProductBatch> subBatches =
          subSnap.docs.map(ProductBatch.fromFirestore).toList();
      final List<ProductBatch> rawMerged = mergeBatchesById(subBatches);
      batchesScanned += rawMerged.length;

      int prodExpiredCount = 0;
      int prodDepletedCount = 0;
      final List<ProductBatch> canonicalBatches = [];
      for (final b in rawMerged) {
        final norm = b.normalizedForPersistence(now: auditNow);
        if (norm.status == BatchStatus.expired &&
            b.status != BatchStatus.expired) {
          prodExpiredCount++;
        } else if (norm.status == BatchStatus.depleted &&
            b.status != BatchStatus.depleted) {
          prodDepletedCount++;
        }
        canonicalBatches.add(norm);
      }

      final Map<String, ValidatedSupplierLink> supplierRepairsForProduct = {};

      for (final b in canonicalBatches) {
        final sid = b.supplierId?.trim() ?? '';
        final bool hasValidSupplierDoc =
            sid.isNotEmpty && validSuppliersById.containsKey(sid);
        final bool missingSupplierName =
            hasValidSupplierDoc && (b.supplierName?.trim().isEmpty ?? true);

        if (!hasValidSupplierDoc || missingSupplierName) {
          String? suggestedId;
          String? suggestedName;

          if (hasValidSupplierDoc) {
            suggestedId = sid;
            suggestedName = validSuppliersById[sid];
          } else {
            PurchaseOrder? linkedPo;
            if (b.poId != null && b.poId!.trim().isNotEmpty) {
              linkedPo = poById[b.poId!.trim()];
            }
            if (linkedPo == null &&
                b.poNumber != null &&
                b.poNumber!.trim().isNotEmpty) {
              linkedPo = poByNumber[b.poNumber!.trim().toLowerCase()];
            }
            if (linkedPo != null &&
                validSuppliersById.containsKey(linkedPo.supplierId.trim())) {
              suggestedId = linkedPo.supplierId.trim();
              suggestedName = validSuppliersById[suggestedId];
            } else if (product.supplierId != null &&
                validSuppliersById.containsKey(product.supplierId!.trim())) {
              suggestedId = product.supplierId!.trim();
              suggestedName = validSuppliersById[suggestedId];
            } else if (validatedFallbackId != null) {
              suggestedId = validatedFallbackId;
              suggestedName = validatedFallbackName;
            }
          }

          if (!hasValidSupplierDoc) {
            orphanFindings.add(OrphanBatchFinding(
              productId: product.id,
              productName: product.name,
              batchId: b.batchId,
              remainingQty: b.remainingQty,
              currentSupplierId: sid.isEmpty ? null : sid,
              reason: sid.isEmpty
                  ? 'Missing supplierId'
                  : 'Broken reference: supplier "$sid" not found',
              suggestedSupplierId: suggestedId,
              suggestedSupplierName: suggestedName,
            ));
          }

          if (suggestedId != null && suggestedName != null) {
            supplierRepairsForProduct[b.batchId] = ValidatedSupplierLink(
              supplierId: suggestedId,
              supplierName: suggestedName,
            );
          }
        }
      }

      final int activeSum =
          sumActiveBatchStock(canonicalBatches, now: auditNow);
      final int embeddedActiveSum =
          sumActiveBatchStock(product.batches, now: auditNow);
      final bool embeddedCountDiffers =
          product.batches.length != canonicalBatches.length ||
              embeddedActiveSum != activeSum;
      final bool stockDiffers = product.stock != activeSum;
      final bool reservedDiffers = product.reservedStock != expectedReserved;
      final bool statusCleanupNeeded =
          prodExpiredCount > 0 || prodDepletedCount > 0;

      if (stockDiffers ||
          embeddedCountDiffers ||
          reservedDiffers ||
          statusCleanupNeeded) {
        driftFindings.add(StockDriftFinding(
          productId: product.id,
          productName: product.name,
          storedStock: product.stock,
          activeBatchSum: activeSum,
          storedReservedStock: product.reservedStock,
          expectedReservedStock: expectedReserved,
          expiredBatchesDetected: prodExpiredCount,
          depletedBatchesDetected: prodDepletedCount,
          embeddedMirrorOutOfSync: embeddedCountDiffers,
        ));
      }

      final bool needsWrite = !dryRun &&
          (stockDiffers ||
              embeddedCountDiffers ||
              reservedDiffers ||
              statusCleanupNeeded ||
              supplierRepairsForProduct.isNotEmpty);

      if (needsWrite) {
        final batchRefs = subSnap.docs.map((d) => d.reference).toList();
        await _db.runTransaction((transaction) async {
          final DateTime txNow = DateTime.now();
          final pRef = _products.doc(product.id);
          final pSnap = await transaction.get(pRef);
          if (!pSnap.exists) return;

          final List<ProductBatch> liveBatches = [];
          for (final ref in batchRefs) {
            final bSnap = await transaction.get(ref);
            if (bSnap.exists) {
              final raw = ProductBatch.fromFirestore(bSnap);
              var b = raw.normalizedForPersistence(now: txNow);
              final repair = supplierRepairsForProduct[b.batchId];
              if (repair != null) {
                b = b.copyWith(
                  supplierId: repair.supplierId,
                  supplierName: repair.supplierName,
                );
                batchesSupplierFixed++;
              }
              if (b.status == BatchStatus.expired &&
                  raw.status != BatchStatus.expired) {
                totalExpiredMarked++;
              } else if (b.status == BatchStatus.depleted &&
                  raw.status != BatchStatus.depleted) {
                totalDepletedMarked++;
              }
              if (repair != null ||
                  b.status != raw.status ||
                  b.remainingQty != raw.remainingQty) {
                transaction.set(ref, b.toFirestore());
              }
              liveBatches.add(b);
            }
          }

          final merged = mergeBatchesById(liveBatches);
          final syncedStock = sumActiveBatchStock(merged, now: txNow);
          final earliestExp = _earliestActiveExpiry(merged, now: txNow);

          for (final b in merged) {
            transaction.set(
              _inventoryBatches.doc(b.batchId),
              buildInventoryBatchMirror(b),
              SetOptions(merge: true),
            );
          }

          transaction.update(pRef, {
            'stock': syncedStock,
            'reservedStock': expectedReserved,
            'batches': {for (final b in merged) b.batchId: b.toMap()},
            'expiryDate':
                earliestExp != null ? Timestamp.fromDate(earliestExp) : null,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          if (stockDiffers || embeddedCountDiffers) {
            productsStockFixed++;
          }
          if (reservedDiffers) {
            reservedStockFixed++;
          }

          transaction.set(_auditLogs.doc(), {
            'timestamp': FieldValue.serverTimestamp(),
            'actorId': actor.uid,
            'actorEmail': actor.email,
            'actorName': actor.name,
            'actorRole': actor.role,
            'performedBy': actor.toPerformedByMap(),
            'module': 'INVENTORY',
            'action': 'INVENTORY_SYNC_REPAIR',
            'targetId': product.id,
            'targetName': product.name,
            'productId': product.id,
            'productName': product.name,
            'qtyChanged': syncedStock - product.stock,
            'summary':
                'Automated reconciliation for ${product.name}: stock ${product.stock} -> $syncedStock, reserved ${product.reservedStock} -> $expectedReserved, expired marked: $prodExpiredCount, supplier links repaired: ${supplierRepairsForProduct.length}.',
          });
        });
      }
    }

    return InventoryReconciliationReport(
      productsScanned: productsScanned,
      batchesScanned: batchesScanned,
      orphanBatches: orphanFindings,
      stockDrifts: driftFindings,
      batchesSupplierFixed: batchesSupplierFixed,
      productsStockFixed: productsStockFixed,
      reservedStockFixed: reservedStockFixed,
      expiredBatchesMarked: totalExpiredMarked,
      depletedBatchesMarked: totalDepletedMarked,
      dryRun: dryRun,
    );
  }
}

class _LegacyPoHydration {
  final String? poId;
  final String? poNumber;
  final String? supplierId;
  final String? supplierName;
  final DateTime? datePurchased;

  const _LegacyPoHydration({
    this.poId,
    this.poNumber,
    this.supplierId,
    this.supplierName,
    this.datePurchased,
  });
}
