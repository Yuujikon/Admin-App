import 'dart:async';
import 'package:flutter/material.dart';
import '../models/restock_inquiry.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../services/firestore_service.dart';
import 'base_provider.dart';

/// Provider for managing auto-generated and manual supplier restock order inquiries.
class RestockProvider extends BaseProvider {
  final _fs = FirestoreService();

  List<RestockInquiry> _inquiries = [];
  DateTime? _lastUpdated;

  /// Active list of supplier restock inquiries.
  List<RestockInquiry> get inquiries => _inquiries;

  /// Timestamp when restock data was last synced.
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

  Future<int> generateInquiries(List<Product> lowStockProducts,
      List<Supplier> suppliers, String adminName) async {
    if (lowStockProducts.isEmpty) return 0;

    final batchId = DateTime.now().millisecondsSinceEpoch.toString();
    final groups = <String, List<Product>>{};

    final defaultSupplierId = suppliers.length == 1 ? suppliers.first.id : null;

    for (final p in lowStockProducts) {
      final suppId = (p.supplierId != null && p.supplierId!.isNotEmpty)
          ? p.supplierId!
          : defaultSupplierId;
      if (suppId == null || suppId.isEmpty) continue;
      groups.putIfAbsent(suppId, () => []).add(p);
    }

    int createdCount = 0;

    for (final supplierId in groups.keys) {
      final products = groups[supplierId]!;
      if (products.isEmpty) continue;

      final supplier = suppliers.firstWhere((s) => s.id == supplierId,
          orElse: () => Supplier(id: supplierId, name: 'Unknown Supplier'));

      // Check if there is an existing DRAFT inquiry for this supplier to append to
      final existingDrafts = _inquiries
          .where((ri) =>
              ri.supplierId == supplierId &&
              ri.status == RestockInquiryStatus.draft)
          .toList();

      if (existingDrafts.isNotEmpty) {
        final draft = existingDrafts.first;
        final updatedItems = List<RestockInquiryItem>.from(draft.items);

        for (final p in products) {
          final existingIdx =
              updatedItems.indexWhere((i) => i.productId == p.id);
          final suggested = p.calculateSuggestedRestock();

          if (existingIdx >= 0) {
            final existingItem = updatedItems[existingIdx];
            updatedItems[existingIdx] = existingItem.copyWith(
              requestedQty: suggested > existingItem.requestedQty
                  ? suggested
                  : existingItem.requestedQty,
              costPrice: p.costPrice > 0 ? p.costPrice : existingItem.costPrice,
            );
          } else {
            updatedItems.add(RestockInquiryItem(
              productId: p.id,
              productName: p.name,
              sku: (p.barcode != null && p.barcode!.isNotEmpty)
                  ? p.barcode!
                  : p.id,
              currentStock: p.totalStock,
              lowStockThreshold: p.lowStockThreshold,
              unit: p.unit,
              suggestedQty: suggested,
              requestedQty: suggested,
              costPrice: p.costPrice,
            ));
          }
        }

        final updatedDraft = draft.copyWith(items: updatedItems);
        await _fs.updateRestockInquiry(updatedDraft);
        createdCount++;
      } else {
        final inquiryItems = products.map((p) {
          final suggested = p.calculateSuggestedRestock();

          return RestockInquiryItem(
            productId: p.id,
            productName: p.name,
            sku: (p.barcode != null && p.barcode!.isNotEmpty)
                ? p.barcode!
                : p.id,
            currentStock: p.totalStock,
            lowStockThreshold: p.lowStockThreshold,
            unit: p.unit,
            suggestedQty: suggested,
            requestedQty: suggested,
            costPrice: p.costPrice,
          );
        }).toList();

        final suppPrefix = supplierId.length >= 4
            ? supplierId.substring(0, 4).toUpperCase()
            : supplierId.toUpperCase().padRight(4, 'X');

        final ri = RestockInquiry(
          id: '',
          inquiryNumber:
              'RI-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-$suppPrefix-${inquiryItems.length}',
          supplierId: supplierId,
          supplierName: supplier.name,
          supplierContact:
              supplier.email.isNotEmpty ? supplier.email : supplier.phone,
          createdAt: DateTime.now(),
          status: RestockInquiryStatus.draft,
          items: inquiryItems,
          createdBy: adminName,
          batchId: batchId,
        );

        await _fs.addRestockInquiry(ri);
        createdCount++;
      }
    }

    notifyListeners();
    return createdCount;
  }

  Future<void> updateInquiry(RestockInquiry ri) => _fs.updateRestockInquiry(ri);
  Future<void> deleteInquiry(String id) => _fs.deleteRestockInquiry(id);

  Future<void> sendInquiry(RestockInquiry ri) async {
    await _fs.updateRestockInquiryStatus(ri.id, RestockInquiryStatus.sent,
        sentAt: DateTime.now());
  }

  Future<void> resendInquiry(RestockInquiry ri) async {
    await _fs.updateRestockInquiryStatus(ri.id, RestockInquiryStatus.sent,
        sentAt: DateTime.now());
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
