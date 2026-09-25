import 'dart:async';
import 'package:flutter/material.dart';
import '../models/restock_inquiry.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../services/firestore_service.dart';
import 'base_provider.dart';

class RestockProvider extends BaseProvider {
  final _fs = FirestoreService();

  List<RestockInquiry> _inquiries = [];
  DateTime? _lastUpdated;

  List<RestockInquiry> get inquiries => _inquiries;
  DateTime? get lastUpdated => _lastUpdated;

  void initialize() {
    cancelSubscriptions();
    setLoading(true);

    Timer(const Duration(seconds: 3), () {
      if (isLoading) setLoading(false);
    });

    registerSubscription(_fs.restockInquiriesStream().listen((list) {
      _inquiries = list;
      setLoading(false);
      _lastUpdated = DateTime.now();
    }, onError: (e) {
      setLoading(false);
      debugPrint('RestockInquiry Stream Error: $e');
    }));
  }

  Future<int> generateInquiries(List<Product> lowStockProducts, List<Supplier> suppliers, String adminName) async {
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();
    final groups = <String, List<Product>>{};

    for (final p in lowStockProducts) {
      if (p.supplierId == null || p.supplierId!.isEmpty) continue;
      groups.putIfAbsent(p.supplierId!, () => []).add(p);
    }

    int createdCount = 0;
    for (final supplierId in groups.keys) {
      final items = groups[supplierId]!;
      final supplier = suppliers.firstWhere((s) => s.id == supplierId, 
          orElse: () => Supplier(id: supplierId, name: 'Unknown Supplier'));
      
      // Duplicate prevention: check if items already have a pending/sent inquiry
      final activeInquiries = _inquiries.where((ri) => 
        ri.supplierId == supplierId && 
        (ri.status == RestockInquiryStatus.draft || 
         ri.status == RestockInquiryStatus.pending || 
         ri.status == RestockInquiryStatus.sent)
      ).toList();

      final filteredItems = items.where((p) {
        return !activeInquiries.any((ri) => ri.items.any((rii) => rii.productId == p.id));
      }).toList();

      if (filteredItems.isEmpty) continue;

      final inquiryItems = filteredItems.map((p) {
        final suggested = p.calculateSuggestedRestock();

        return RestockInquiryItem(
          productId: p.id,
          productName: p.name,
          sku: p.barcode ?? p.id,
          currentStock: p.stock,
          lowStockThreshold: p.lowStockThreshold,
          unit: p.unit,
          suggestedQty: suggested,
          requestedQty: suggested,
        );
      }).toList();

      final ri = RestockInquiry(
        id: '',
        inquiryNumber: 'RI-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-${supplierId.substring(0, 4).toUpperCase()}-${items.length}',
        supplierId: supplierId,
        supplierName: supplier.name,
        supplierContact: supplier.email,
        createdAt: DateTime.now(),
        status: RestockInquiryStatus.draft,
        items: inquiryItems,
        createdBy: adminName,
        batchId: batchId,
      );

      await _fs.addRestockInquiry(ri);
      createdCount++;
    }
    return createdCount;
  }

  Future<void> updateInquiry(RestockInquiry ri) => _fs.updateRestockInquiry(ri);
  Future<void> deleteInquiry(String id) => _fs.deleteRestockInquiry(id);
  
  Future<void> sendInquiry(RestockInquiry ri) async {
    await _fs.updateRestockInquiryStatus(ri.id, RestockInquiryStatus.sent, sentAt: DateTime.now());
  }

  Future<void> resendInquiry(RestockInquiry ri) async {
    await _fs.updateRestockInquiryStatus(ri.id, RestockInquiryStatus.sent, sentAt: DateTime.now());
    notifyListeners();
  }

  Future<void> refresh() async {
    setLoading(true);
    // The stream listener will update the list automatically, 
    // but we can provide a small delay for UI feedback
    await Future.delayed(const Duration(milliseconds: 500));
    setLoading(false);
  }

  Future<void> updateStatus(String id, RestockInquiryStatus status) => 
      _fs.updateRestockInquiryStatus(id, status);
}
