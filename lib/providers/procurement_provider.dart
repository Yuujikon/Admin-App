import 'dart:async';
import 'package:flutter/material.dart';
import '../models/rfq.dart';
import '../models/purchase_order.dart';
import '../models/receiving_record.dart';
import '../models/inventory_batch_record.dart';
import '../models/product.dart';
import '../models/store_settings.dart';
import '../models/supplier.dart';
import '../services/firestore_service.dart';
import 'base_provider.dart';

/// Dedicated state provider for managing RFQs, Purchase Orders, Receiving Records, and Inventory Batches.
class ProcurementProvider extends BaseProvider {
  final _fs = FirestoreService();

  List<Rfq> _rfqs = [];
  List<PurchaseOrder> _purchaseOrders = [];
  List<ReceivingRecord> _receivingRecords = [];
  List<InventoryBatchRecord> _inventoryBatches = [];

  bool _isRfqsLoading = true;
  bool _isPurchaseOrdersLoading = true;
  bool _isReceivingRecordsLoading = true;
  bool _isInventoryBatchesLoading = true;

  List<Rfq> get rfqs => _rfqs;
  List<PurchaseOrder> get purchaseOrders => _purchaseOrders;
  List<ReceivingRecord> get receivingRecords => _receivingRecords;
  List<InventoryBatchRecord> get inventoryBatches => _inventoryBatches;

  bool get isRfqsLoading => _isRfqsLoading;
  bool get isPurchaseOrdersLoading => _isPurchaseOrdersLoading;
  bool get isReceivingRecordsLoading => _isReceivingRecordsLoading;
  bool get isInventoryBatchesLoading => _isInventoryBatchesLoading;

  @override
  bool get isLoading =>
      _isRfqsLoading ||
      _isPurchaseOrdersLoading ||
      _isReceivingRecordsLoading ||
      _isInventoryBatchesLoading;

  /// RFQs filtered by status
  List<Rfq> get draftRfqs =>
      _rfqs.where((r) => r.status == RfqStatus.draft).toList();
  List<Rfq> get sentRfqs =>
      _rfqs.where((r) => r.status == RfqStatus.sent).toList();
  List<Rfq> get quotedRfqs =>
      _rfqs.where((r) => r.status == RfqStatus.quoted).toList();

  /// FIFO sorted pending purchase orders (oldest order date first)
  List<PurchaseOrder> get fifoPendingPurchaseOrders {
    final pending = _purchaseOrders
        .where((po) =>
            po.status == PurchaseOrderStatus.pendingDelivery ||
            po.status == PurchaseOrderStatus.partiallyReceived)
        .toList();

    // FIFO sort: orderDate ASC (oldest order at the top of the queue)
    pending.sort((a, b) => a.orderDate.compareTo(b.orderDate));
    return pending;
  }

  /// Resolves the matching [PurchaseOrder] for a [ProductBatch], checking
  /// explicit `poId` / `poNumber`, legacy `receiving_records`, and
  /// `inventory_batches` links.
  PurchaseOrder? findPurchaseOrderForBatch(ProductBatch batch) {
    if (batch.poId != null && batch.poId!.trim().isNotEmpty) {
      final poId = batch.poId!.trim();
      for (final po in _purchaseOrders) {
        if (po.id == poId) return po;
      }
    }

    if (batch.poNumber != null && batch.poNumber!.trim().isNotEmpty) {
      final poNum = batch.poNumber!.trim().toLowerCase();
      for (final po in _purchaseOrders) {
        if (po.poNumber.trim().toLowerCase() == poNum) return po;
      }
    }

    // Match via receiving records (supports legacy UUID batches received from POs)
    for (final rec in _receivingRecords) {
      final matched = rec.itemsReceived.any((item) =>
          item.productId == batch.productId &&
          (item.batchId == batch.batchId ||
              item.splitBatches.any((s) => s.batchTag == batch.batchId)));
      if (matched) {
        for (final po in _purchaseOrders) {
          if (po.id == rec.poId ||
              (rec.poNumber.isNotEmpty && po.poNumber == rec.poNumber)) {
            return po;
          }
        }
      }
    }

    // Match via legacy top-level inventory_batches mirror
    for (final ib in _inventoryBatches) {
      if (ib.batchId == batch.batchId &&
          ib.poId != null &&
          ib.poId!.trim().isNotEmpty) {
        for (final po in _purchaseOrders) {
          if (po.id == ib.poId!.trim()) return po;
        }
      }
    }

    return null;
  }

  /// Resolves the human-readable Purchase Order number for [batch], or `null`
  /// if the batch came from direct/manual stock rather than a PO.
  String? resolvePoNumberForBatch(ProductBatch batch) {
    if (batch.poNumber != null && batch.poNumber!.trim().isNotEmpty) {
      return batch.poNumber!.trim();
    }

    final po = findPurchaseOrderForBatch(batch);
    if (po != null && po.poNumber.trim().isNotEmpty) {
      return po.poNumber.trim();
    }

    for (final rec in _receivingRecords) {
      final matched = rec.itemsReceived.any((item) =>
          item.productId == batch.productId &&
          (item.batchId == batch.batchId ||
              item.splitBatches.any((s) => s.batchTag == batch.batchId)));
      if (matched && rec.poNumber.trim().isNotEmpty) {
        return rec.poNumber.trim();
      }
    }

    return null;
  }

  /// Resolves the supplier ID for [batch], checking the batch itself, its linked
  /// Purchase Order, and optionally the parent product's `supplierId`.
  String? resolveSupplierIdForBatch(
    ProductBatch batch, {
    String? fallbackProductSupplierId,
  }) {
    if (batch.supplierId != null && batch.supplierId!.trim().isNotEmpty) {
      return batch.supplierId!.trim();
    }
    final po = findPurchaseOrderForBatch(batch);
    if (po != null && po.supplierId.trim().isNotEmpty) {
      return po.supplierId.trim();
    }
    if (fallbackProductSupplierId != null &&
        fallbackProductSupplierId.trim().isNotEmpty) {
      return fallbackProductSupplierId.trim();
    }
    return null;
  }

  /// Resolves supplier display name for [batch], checking:
  /// 1. `batch.supplierName`
  /// 2. Live [suppliers] registry matched by `batch.supplierId`
  /// 3. Linked Purchase Order's `effectiveSupplierName` / `supplierId`
  /// 4. Live [suppliers] registry matched by [fallbackProductSupplierId]
  String? resolveSupplierNameForBatch(
    ProductBatch batch, {
    List<Supplier> suppliers = const [],
    String? fallbackProductSupplierId,
  }) {
    if (batch.supplierName != null && batch.supplierName!.trim().isNotEmpty) {
      return batch.supplierName!.trim();
    }

    String? lookupSupplierName(String? id) {
      final cleanId = id?.trim() ?? '';
      if (cleanId.isEmpty) return null;
      for (final s in suppliers) {
        if (s.id == cleanId && s.name.trim().isNotEmpty) {
          return s.name.trim();
        }
      }
      return null;
    }

    final fromBatchId = lookupSupplierName(batch.supplierId);
    if (fromBatchId != null) return fromBatchId;

    final po = findPurchaseOrderForBatch(batch);
    if (po != null) {
      final fromPoId = lookupSupplierName(po.supplierId);
      if (fromPoId != null) return fromPoId;
      if (po.effectiveSupplierName.trim().isNotEmpty) {
        return po.effectiveSupplierName.trim();
      }
    }

    final fromProductId = lookupSupplierName(fallbackProductSupplierId);
    if (fromProductId != null) return fromProductId;

    return null;
  }

  void initialize() {
    cancelSubscriptions();
    setLoading(true);

    Timer(const Duration(seconds: 3), () {
      if (isLoading) setLoading(false);
    });

    registerSubscription(_fs.rfqsStream().listen((list) {
      _rfqs = list;
      _isRfqsLoading = false;
      notifyListeners();
    }, onError: (e) {
      _isRfqsLoading = false;
      debugPrint('RFQs Stream Error: $e');
      notifyListeners();
    }));

    registerSubscription(_fs.purchaseOrdersStream().listen((list) {
      _purchaseOrders = list;
      _isPurchaseOrdersLoading = false;
      notifyListeners();
    }, onError: (e) {
      _isPurchaseOrdersLoading = false;
      debugPrint('PurchaseOrders Stream Error: $e');
      notifyListeners();
    }));

    registerSubscription(_fs.receivingRecordsStream().listen((list) {
      _receivingRecords = list;
      _isReceivingRecordsLoading = false;
      notifyListeners();
    }, onError: (e) {
      _isReceivingRecordsLoading = false;
      debugPrint('ReceivingRecords Stream Error: $e');
      notifyListeners();
    }));

    registerSubscription(_fs.inventoryBatchesStream().listen((list) {
      _inventoryBatches = list;
      _isInventoryBatchesLoading = false;
      notifyListeners();
    }, onError: (e) {
      _isInventoryBatchesLoading = false;
      debugPrint('InventoryBatches Stream Error: $e');
      notifyListeners();
    }));
  }

  // ── RFQ Actions ────────────────────────────────────────────────────────────

  Future<void> addRfq(Rfq rfq) async {
    await _fs.addRfq(rfq);
  }

  Future<void> updateRfq(Rfq rfq) async {
    await _fs.updateRfq(rfq);
  }

  Future<void> updateRfqStatus(String id, RfqStatus status) async {
    await _fs.updateRfqStatus(id, status);
  }

  Future<String> convertRfqToPurchaseOrder(Rfq rfq, String poNumber) async {
    return await _fs.convertRfqToPurchaseOrder(rfq, poNumber);
  }

  // ── Purchase Order Actions ──────────────────────────────────────────────────

  Future<List<PurchaseOrder>> checkActiveDuplicatePo({
    required String supplierId,
    List<String>? productIds,
  }) async {
    return await _fs.checkActiveDuplicatePo(
      supplierId: supplierId,
      productIds: productIds,
    );
  }

  Future<PurchaseOrder> createPurchaseOrder(PurchaseOrder po) async {
    return await _fs.createPurchaseOrder(po);
  }

  Future<void> updatePurchaseOrderSupplierSnapshot(
    String poId,
    SupplierSnapshot snapshot,
  ) async {
    await _fs.updatePurchaseOrderSupplierSnapshot(poId, snapshot);
  }

  Future<void> updatePurchaseOrderStatus(
      String id, PurchaseOrderStatus status) async {
    await _fs.updatePurchaseOrderStatus(id, status);
  }

  Future<void> shortClosePurchaseOrder(
    String poId,
    List<PurchaseOrderItem> items, {
    String reason = 'Supplier short-fulfillment',
    String closedBy = 'Admin',
  }) async {
    await _fs.shortClosePurchaseOrder(
      poId,
      items,
      reason: reason,
      closedBy: closedBy,
    );
  }

  // ── Atomic Receiving Action ─────────────────────────────────────────────────

  Future<PurchaseOrder> processPoDeliveryAtomic({
    required String poId,
    required PurchaseOrder currentPo,
    required String deliveryReceiptNo,
    required Map<String, int> receivedQtyMap,
    required Map<String, DateTime?> expiryDateMap,
    required Map<String, double> unitCostMap,
    required List<Product> cachedProducts,
    required String receivedBy,
    DateTime? datePurchased,
    DateTime? dateArrived,
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
    return await _fs.processPoDeliveryAtomic(
      poId: poId,
      currentPo: currentPo,
      deliveryReceiptNo: deliveryReceiptNo,
      receivedQtyMap: receivedQtyMap,
      expiryDateMap: expiryDateMap,
      unitCostMap: unitCostMap,
      cachedProducts: cachedProducts,
      receivedBy: receivedBy,
      datePurchased: datePurchased,
      dateArrived: dateArrived,
      batchNumberMap: batchNumberMap,
      splitBatchesMap: splitBatchesMap,
      rejectedQtyMap: rejectedQtyMap,
      rejectionReasonMap: rejectionReasonMap,
      discrepancyNote: discrepancyNote,
      syncProductCostPrice: syncProductCostPrice,
      shortCloseRemaining: shortCloseRemaining,
      overDeliveryAction: overDeliveryAction,
      settings: settings,
    );
  }
}
