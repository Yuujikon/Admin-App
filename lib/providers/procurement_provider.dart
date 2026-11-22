import 'dart:async';
import 'package:flutter/material.dart';
import '../models/rfq.dart';
import '../models/purchase_order.dart';
import '../models/receiving_record.dart';
import '../models/inventory_batch_record.dart';
import '../models/product.dart';
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

  Future<void> createPurchaseOrder(PurchaseOrder po) async {
    await _fs.createPurchaseOrder(po);
  }

  Future<void> updatePurchaseOrderStatus(
      String id, PurchaseOrderStatus status) async {
    await _fs.updatePurchaseOrderStatus(id, status);
  }

  Future<void> shortClosePurchaseOrder(
      String poId, List<PurchaseOrderItem> items) async {
    await _fs.shortClosePurchaseOrder(poId, items);
  }

  // ── Atomic Receiving Action ─────────────────────────────────────────────────

  Future<void> processPoDeliveryAtomic({
    required String poId,
    required PurchaseOrder currentPo,
    required String deliveryReceiptNo,
    required Map<String, int> receivedQtyMap,
    required Map<String, DateTime?> expiryDateMap,
    required Map<String, double> unitCostMap,
    required List<Product> cachedProducts,
    required String receivedBy,
    String? discrepancyNote,
    bool syncProductCostPrice = false,
    bool shortCloseRemaining = false,
  }) async {
    await _fs.processPoDeliveryAtomic(
      poId: poId,
      currentPo: currentPo,
      deliveryReceiptNo: deliveryReceiptNo,
      receivedQtyMap: receivedQtyMap,
      expiryDateMap: expiryDateMap,
      unitCostMap: unitCostMap,
      cachedProducts: cachedProducts,
      receivedBy: receivedBy,
      discrepancyNote: discrepancyNote,
      syncProductCostPrice: syncProductCostPrice,
      shortCloseRemaining: shortCloseRemaining,
    );
  }
}
