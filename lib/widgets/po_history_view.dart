import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/purchase_order.dart';
import '../models/supplier.dart';
import '../models/audit_log.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../providers/auth_provider.dart';
import '../services/audit_log_service.dart';
import '../shared/services/admin_messaging_service.dart';
import '../utils/po_pdf_printer.dart';
import '../utils/notice_pdf_printer.dart';
import '../utils/format.dart';
import 'po_receiving_sheet.dart';
import 'close_short_modal.dart';
import 'document_dispatch_widgets.dart';
import 'premium_components.dart';
import 'supplier_details_card.dart';
import 'supplier_notice_dispatch_sheet.dart';
import 'supplier_quick_edit_sheet.dart';

enum _PoCategoryTab { all, drafts, pending, backorders, completed, closedShort }

/// Unified Purchase Order Dashboard & Delivery History View supporting instant search & 5 category tabs.
class PoHistoryView extends StatefulWidget {
  final String? supplierIdFilter;
  final VoidCallback? onNewOrder;

  const PoHistoryView({
    super.key,
    this.supplierIdFilter,
    this.onNewOrder,
  });

  @override
  State<PoHistoryView> createState() => _PoHistoryViewState();
}

class _PoHistoryViewState extends State<PoHistoryView> {
  String _searchQuery = '';
  _PoCategoryTab _selectedTab = _PoCategoryTab.all;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showPoDetailDialog(BuildContext context, PurchaseOrder po) {
    final inventory = context.read<InventoryProvider>();
    final suppliers = inventory.suppliers;
    final supplier = suppliers.firstWhere(
      (s) => s.id == po.supplierId,
      orElse: () => Supplier(id: po.supplierId, name: po.effectiveSupplierName),
    );
    var activePo = po;
    var activeSnapshot = po.resolveSupplierSnapshot(supplier);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: activePo.isBackOrder
                      ? Colors.orange.shade50
                      : Colors.teal.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  activePo.isBackOrder
                      ? Icons.next_plan_rounded
                      : Icons.description_rounded,
                  color: activePo.isBackOrder
                      ? Colors.orange.shade800
                      : Colors.teal.shade800,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('PO #${activePo.poNumber}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(activeSnapshot.supplierName,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Structured Supplier Snapshot Card with Quick-Edit
                  SupplierDetailsCard(
                    snapshot: activeSnapshot,
                    compact: true,
                    title: 'Order Supplier Snapshot',
                    onQuickEdit: () async {
                      final updated = await SupplierQuickEditSheet.show(
                        context: context,
                        initialSnapshot: activeSnapshot,
                        initialAutoNotifyLowStock: supplier.autoNotifyLowStock,
                        existingPoId: activePo.id,
                      );
                      if (updated != null) {
                        setDialogState(() {
                          activeSnapshot = updated;
                          activePo = activePo.copyWith(
                            supplierName: updated.supplierName,
                            supplierSnapshot: updated,
                          );
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          'Order Date: ${DateFormat('MMM dd, yyyy').format(activePo.orderDate)}',
                          style: const TextStyle(fontSize: 12)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              activePo.status == PurchaseOrderStatus.completed
                                  ? Colors.green.shade50
                                  : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          activePo.status.displayName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color:
                                activePo.status == PurchaseOrderStatus.completed
                                    ? Colors.green.shade800
                                    : Colors.blue.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (activePo.requestedDeliveryDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Requested Delivery: ${DateFormat('MMM dd, yyyy').format(activePo.requestedDeliveryDate!)}',
                      style: const TextStyle(fontSize: 12, color: Colors.teal),
                    ),
                  ],
                  if (activePo.cancelledReason != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Cancelled / Closed Short Reason: ${activePo.cancelledReason}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.red.shade900),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('Item Line Breakdown:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...activePo.items.map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                    'Est. Price: ${formatCurrency(item.unitCost)} ${item.actualUnitCost != null ? " (Actual: ${formatCurrency(item.actualUnitCost!)})" : ""}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Ordered: ${item.orderedQty} | Rec: ${item.receivedQty}',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              if (item.remainingQty > 0)
                                Text(
                                  'Rem: ${item.remainingQty}',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.orange),
                                )
                              else
                                const Text(
                                  'Fully Received',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.green),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Estimated Value:',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      Text(formatCurrency(activePo.totalOrderedValue),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade800)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (activePo.status == PurchaseOrderStatus.partiallyReceived ||
                activePo.status == PurchaseOrderStatus.backordered ||
                activePo.status == PurchaseOrderStatus.shortClosed ||
                activePo.isBackOrder)
              OutlinedButton.icon(
                icon: const Icon(Icons.assignment_return_rounded, size: 16),
                label: const Text('Backorder / Notice'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showNoticePdfOptionsDialog(
                    context,
                    activePo,
                    supplier,
                    snapshot: activeSnapshot,
                  );
                },
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.visibility_rounded, size: 16),
              label: const Text('Preview PO PDF'),
              onPressed: () async {
                final validation = activeSnapshot.validateForDispatch();
                if (!validation.isValid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Complete required supplier details first: ${validation.summaryMessage}'),
                      backgroundColor: Colors.red.shade800,
                    ),
                  );
                  return;
                }
                await showDocumentPdfPreviewModal(
                  context: context,
                  title: 'Purchase Order #${activePo.poNumber}',
                  fileName: 'Purchase_Order_${activePo.poNumber}.pdf',
                  buildPdf: () => PoPdfPrinter.generatePoPdf(
                    activePo,
                    supplier,
                    supplierSnapshot: activeSnapshot,
                    enforceValidation: true,
                  ),
                );
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Resend PO'),
              onPressed: () async {
                final validation = activeSnapshot.validateForDispatch();
                if (!validation.isValid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Fix missing supplier fields before dispatching: ${validation.summaryMessage}'),
                      backgroundColor: Colors.red.shade800,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await DispatchProgressDialog.run(
                  context: context,
                  documentTitle: 'Resend PO #${activePo.poNumber}',
                  onExecute: (onStage) =>
                      AdminMessagingService().dispatchPurchaseOrderWithPdf(
                    po: activePo,
                    supplier: supplier,
                    supplierSnapshot: activeSnapshot,
                    onStageChanged: onStage,
                  ),
                );
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoticePdfOptionsDialog(
    BuildContext context,
    PurchaseOrder po,
    Supplier? supplier, {
    SupplierSnapshot? snapshot,
  }) {
    final auth = context.read<AppAuthProvider>();
    final actorEmail = auth.currentUser?.email ?? 'Admin';
    final effectivePo =
        snapshot != null ? po.copyWith(supplierSnapshot: snapshot) : po;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Theme.of(ctx).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Supplier Notice Documents (${po.poNumber})',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.assignment_return_rounded,
                    color: Colors.orange),
                title: const Text('Partial Delivery & Back-Order Notice'),
                subtitle: const Text(
                    'Review supplier snapshot, preview Back-Order PDF & dispatch to supplier + store'),
                onTap: () {
                  Navigator.pop(ctx);
                  SupplierNoticeDispatchSheet.show(
                    context: context,
                    po: effectivePo,
                    supplier: supplier,
                    noticeType: NoticeType.backorder,
                    actorEmail: actorEmail,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                title: const Text('Remaining Order Cancellation Notice'),
                subtitle: const Text(
                    'Review supplier snapshot, preview Cancellation PDF & dispatch to supplier + store'),
                onTap: () {
                  Navigator.pop(ctx);
                  SupplierNoticeDispatchSheet.show(
                    context: context,
                    po: effectivePo,
                    supplier: supplier,
                    noticeType: NoticeType.cancellation,
                    cancellationReason: effectivePo.cancelledReason,
                    actorEmail: actorEmail,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the unified Cancellation Notice Review, PDF Preview & Dual-Email Dispatch sheet.
  static Future<void> showCancellationNoticePrompt({
    required BuildContext context,
    required PurchaseOrder po,
    Supplier? supplier,
    required String cancellationReason,
    required String actorEmail,
  }) async {
    final result = await SupplierNoticeDispatchSheet.show(
      context: context,
      po: po,
      supplier: supplier,
      noticeType: NoticeType.cancellation,
      cancellationReason: cancellationReason,
      actorEmail: actorEmail,
    );

    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.summaryMessage),
          backgroundColor: result.isFullSuccess
              ? Colors.teal.shade800
              : Colors.orange.shade900,
        ),
      );
    }
  }

  void _showReceiptAndAuditLogDialog(BuildContext context, PurchaseOrder po) {
    final procurement = context.read<ProcurementProvider>();
    final receipts = procurement.receivingRecords
        .where((r) => r.poId == po.id || r.poNumber == po.poNumber)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_rounded,
                  color: Colors.teal.shade800, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Delivery Receipt & Audit Log',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('PO #${po.poNumber} — ${po.supplierName}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: DefaultTabController(
            length: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Delivery Receipts'),
                    Tab(text: 'Audit Logs'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 350,
                  child: TabBarView(
                    children: [
                      // Tab 1: Delivery Receipts
                      receipts.isEmpty
                          ? const Center(
                              child: Text('No delivery receipts recorded yet.'))
                          : ListView.separated(
                              itemCount: receipts.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, idx) {
                                final r = receipts[idx];
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'DR #: ${r.deliveryReceiptNo}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13),
                                        ),
                                        Text(
                                          DateFormat('MMM d, y h:mm a')
                                              .format(r.receivedAt),
                                          style: const TextStyle(
                                              fontSize: 10, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    Text('Received By: ${r.receivedBy}',
                                        style: const TextStyle(fontSize: 11)),
                                    if (r.actualDeliveryCost > 0)
                                      Text(
                                        'Actual Delivery Cost: ${formatCurrency(r.actualDeliveryCost)}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal.shade800),
                                      ),
                                    if (r.discrepancyNote != null)
                                      Text(
                                          'Discrepancy Note: ${r.discrepancyNote}',
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.orange)),
                                    const SizedBox(height: 6),
                                    ...r.itemsReceived.map((item) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 2.0),
                                        child: Text(
                                          '• ${item.productName}: Accepted ${item.acceptedQty} @ ₱${item.actualUnitPrice.toStringAsFixed(2)}${item.rejectedQty > 0 ? " (Rejected ${item.rejectedQty} - ${item.rejectionReason})" : ""}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      );
                                    }),
                                  ],
                                );
                              },
                            ),

                      // Tab 2: Audit Logs
                      StreamBuilder<List<AuditLog>>(
                        stream: AuditLogService().getAuditLogs(limit: 50),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final logs = (snapshot.data ?? []).where((l) {
                            return l.targetId == po.id ||
                                l.summary.contains(po.poNumber);
                          }).toList();

                          if (logs.isEmpty) {
                            return const Center(
                                child: Text('No audit logs for this PO.'));
                          }

                          return ListView.separated(
                            itemCount: logs.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final log = logs[idx];
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(log.action,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: Colors.teal)),
                                        Text(
                                          DateFormat('MMM d, h:mm a')
                                              .format(log.timestamp.toDate()),
                                          style: const TextStyle(
                                              fontSize: 10, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(log.summary,
                                        style: const TextStyle(fontSize: 11)),
                                    Text('Actor: ${log.actorEmail}',
                                        style: const TextStyle(
                                            fontSize: 9, color: Colors.grey)),
                                    if (log.afterData != null)
                                      _buildPoAuditLogItemizedSummary(
                                          log.afterData!),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPoAuditLogItemizedSummary(Map<String, dynamic> afterData) {
    final List<dynamic> received =
        List.from(afterData['itemsReceivedSummary'] as List<dynamic>? ?? []);
    final List<dynamic> missing =
        List.from(afterData['itemsMissingSummary'] as List<dynamic>? ?? []);

    if (received.isEmpty && missing.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (received.isNotEmpty) ...[
            Text(
                'Received: ${received.map((i) => "${i['productName']} (${i['receivedQty']})").join(", ")}',
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.green,
                    fontWeight: FontWeight.bold)),
          ],
          if (missing.isNotEmpty) ...[
            Text(
                'Missing: ${missing.map((i) => "${i['productName']} (${i['missingQty'] ?? (i['orderedQty'] - i['receivedQty'])})").join(", ")}',
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.red,
                    fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final procurement = context.watch<ProcurementProvider>();
    final inventory = context.watch<InventoryProvider>();
    final allPos = procurement.purchaseOrders;

    // Filter by supplier if passed
    var baseList = widget.supplierIdFilter != null
        ? allPos.where((p) => p.supplierId == widget.supplierIdFilter).toList()
        : allPos;

    // Calculate category tab counts
    final draftPos =
        baseList.where((p) => p.status == PurchaseOrderStatus.draft).toList();
    final draftRfqs = procurement.draftRfqs.where((r) {
      if (widget.supplierIdFilter != null) {
        return r.supplierId == widget.supplierIdFilter;
      }
      return true;
    }).toList();

    final int countAll = baseList.length;
    final int countDrafts = draftPos.length + draftRfqs.length;
    final int countPending = baseList
        .where((p) =>
            p.status == PurchaseOrderStatus.sent ||
            p.status == PurchaseOrderStatus.pendingDelivery)
        .length;
    final int countBackorders = baseList
        .where((p) =>
            p.status == PurchaseOrderStatus.partiallyReceived ||
            p.status == PurchaseOrderStatus.backordered ||
            p.isBackOrder)
        .length;
    final int countCompleted =
        baseList.where((p) => p.status == PurchaseOrderStatus.completed).length;
    final int countClosedShort = baseList
        .where((p) =>
            p.status == PurchaseOrderStatus.shortClosed ||
            p.status == PurchaseOrderStatus.cancelled)
        .length;

    // Search query filter
    var filteredList = baseList.where((po) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return po.poNumber.toLowerCase().contains(q) ||
          po.supplierName.toLowerCase().contains(q) ||
          po.items.any((i) =>
              i.productName.toLowerCase().contains(q) ||
              i.sku.toLowerCase().contains(q));
    }).toList();

    // Category Tab Filter
    switch (_selectedTab) {
      case _PoCategoryTab.drafts:
        filteredList = filteredList
            .where((p) => p.status == PurchaseOrderStatus.draft)
            .toList();
        break;
      case _PoCategoryTab.pending:
        filteredList = filteredList
            .where((p) =>
                p.status == PurchaseOrderStatus.sent ||
                p.status == PurchaseOrderStatus.pendingDelivery)
            .toList();
        break;
      case _PoCategoryTab.backorders:
        filteredList = filteredList
            .where((p) =>
                p.status == PurchaseOrderStatus.partiallyReceived ||
                p.status == PurchaseOrderStatus.backordered ||
                p.isBackOrder)
            .toList();
        break;
      case _PoCategoryTab.completed:
        filteredList = filteredList
            .where((p) => p.status == PurchaseOrderStatus.completed)
            .toList();
        break;
      case _PoCategoryTab.closedShort:
        filteredList = filteredList
            .where((p) =>
                p.status == PurchaseOrderStatus.shortClosed ||
                p.status == PurchaseOrderStatus.cancelled)
            .toList();
        break;
      case _PoCategoryTab.all:
        break;
    }

    // Sort newest order date first
    filteredList.sort((a, b) => b.orderDate.compareTo(a.orderDate));

    return Column(
      children: [
        // Top Search Bar & Category Filter Chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search by PO #, supplier, or product...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  if (widget.onNewOrder != null) ...[
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: widget.onNewOrder,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New Order'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // Category Tabs: All, Drafts, Pending, Backorders, Completed, Closed Short
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabChip(_PoCategoryTab.all, 'All ($countAll)'),
                    const SizedBox(width: 8),
                    _buildTabChip(
                        _PoCategoryTab.drafts, 'Drafts ($countDrafts)'),
                    const SizedBox(width: 8),
                    _buildTabChip(_PoCategoryTab.pending,
                        'Sent / Pending ($countPending)'),
                    const SizedBox(width: 8),
                    _buildTabChip(_PoCategoryTab.backorders,
                        'Backorders ($countBackorders)'),
                    const SizedBox(width: 8),
                    _buildTabChip(_PoCategoryTab.completed,
                        'Completed ($countCompleted)'),
                    const SizedBox(width: 8),
                    _buildTabChip(_PoCategoryTab.closedShort,
                        'Closed Short ($countClosedShort)'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Purchase Orders List View
        Expanded(
          child: filteredList.isEmpty
              ? const PremiumEmptyState(
                  icon: Icons.history_rounded,
                  title: 'No Purchase Orders Found',
                  subtitle:
                      'No purchase orders match the selected category filter or search query.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, idx) {
                    final po = filteredList[idx];
                    final supplier = inventory.suppliers.firstWhere(
                      (s) => s.id == po.supplierId,
                      orElse: () =>
                          Supplier(id: po.supplierId, name: po.supplierName),
                    );

                    return PremiumCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Card Header: PO Number & Status Badge
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: po.isBackOrder
                                      ? Colors.orange.shade50
                                      : Colors.teal.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  po.isBackOrder
                                      ? Icons.next_plan_rounded
                                      : Icons.shopping_bag_outlined,
                                  color: po.isBackOrder
                                      ? Colors.orange.shade800
                                      : Colors.teal.shade800,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'PO #${po.poNumber}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (po.isBackOrder) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'BACKORDER',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      '${po.supplierName} • ${DateFormat('MMM dd, yyyy').format(po.orderDate)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: po.status ==
                                          PurchaseOrderStatus.completed
                                      ? Colors.green.shade50
                                      : po.status ==
                                              PurchaseOrderStatus.shortClosed
                                          ? Colors.red.shade50
                                          : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  po.status.displayName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: po.status ==
                                            PurchaseOrderStatus.completed
                                        ? Colors.green.shade900
                                        : po.status ==
                                                PurchaseOrderStatus.shortClosed
                                            ? Colors.red.shade900
                                            : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Delivery Progress Bar & Count
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Progress: ${po.totalReceivedQty} / ${po.totalOrderedQty} units received (${po.items.length} items)',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                formatCurrency(po.totalOrderedValue),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: po.deliveryProgress,
                              minHeight: 8,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              color: po.status == PurchaseOrderStatus.completed
                                  ? Colors.green.shade700
                                  : Colors.teal.shade700,
                            ),
                          ),

                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 8),

                          // Context Action Buttons Bar
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.info_outline_rounded,
                                    size: 16),
                                label: const Text('Details'),
                                onPressed: () {
                                  _showPoDetailDialog(context, po);
                                },
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.print_rounded, size: 16),
                                label: const Text('View PDF'),
                                onPressed: () {
                                  PoPdfPrinter.showPoPdfOptionsDialog(
                                      context, po, supplier);
                                },
                              ),
                              const SizedBox(width: 8),

                              // Context Button 1: On Pending or Backorders -> Receive Delivery / Receive Backorder
                              if (po.status.isActive) ...[
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: Colors.teal.shade800,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 16),
                                  label: Text(
                                    po.status.isBackorder
                                        ? 'Receive Backorder'
                                        : 'Receive Delivery',
                                  ),
                                  onPressed: () {
                                    PoReceivingSheet.show(
                                      context: context,
                                      purchaseOrder: po,
                                    );
                                  },
                                ),
                              ],

                              // Context Button 2: On Backorders -> Close Short
                              if (po.status.isBackorder) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: Colors.red.shade800,
                                    side:
                                        BorderSide(color: Colors.red.shade300),
                                  ),
                                  icon: const Icon(
                                      Icons.close_fullscreen_rounded,
                                      size: 16),
                                  label: const Text('Close Short'),
                                  onPressed: () async {
                                    final closed =
                                        await CloseShortModal.show(context, po);
                                    if (closed == true && context.mounted) {
                                      final auth =
                                          context.read<AppAuthProvider>();
                                      final actorEmail =
                                          auth.currentUser?.email ?? 'Admin';
                                      final reason = po.cancelledReason ??
                                          'Supplier out of stock / Discontinued';

                                      showCancellationNoticePrompt(
                                        context: context,
                                        po: po,
                                        supplier: supplier,
                                        cancellationReason: reason,
                                        actorEmail: actorEmail,
                                      );
                                    }
                                  },
                                ),
                              ],

                              // Context Button 3: On Completed / Closed Short -> View Receipt & Audit Log
                              if (!po.status.isActive) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: Colors.teal.shade800,
                                  ),
                                  icon: const Icon(Icons.receipt_long_rounded,
                                      size: 16),
                                  label: const Text('Receipt & Audit Log'),
                                  onPressed: () {
                                    _showReceiptAndAuditLogDialog(context, po);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTabChip(_PoCategoryTab tab, String label) {
    final isSelected = _selectedTab == tab;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedTab = tab),
      selectedColor: Colors.teal.shade100,
      checkmarkColor: Colors.teal.shade800,
    );
  }
}
