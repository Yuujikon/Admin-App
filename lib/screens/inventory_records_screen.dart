import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/delivery_log.dart';
import '../models/product.dart';
import '../models/loss_record.dart';
import '../models/shift_session.dart';
import '../models/restock_inquiry.dart';
import '../models/transaction.dart';
import '../models/refund_request.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../providers/shift_provider.dart';
import '../providers/restock_provider.dart';
import '../config/theme.dart';
import '../utils/format.dart';
import '../widgets/premium_components.dart';
import 'product_detail_screen.dart';
import 'stock_reconciliation_screen.dart';
import '../widgets/admin_filter_bar.dart';

enum _RecordTab {
  deliveryLogs,
  batchLots,
  salesTransactions,
  lossWaste,
  refundRecords,
  registerShifts,
  supplierInquiries,
  auditReconciliations,
  allTimeline
}

enum _DateFilter { all, today, thisWeek, thisMonth }

class InventoryRecordsScreen extends StatefulWidget {
  final String? initialSearch;

  const InventoryRecordsScreen({super.key, this.initialSearch});

  @override
  State<InventoryRecordsScreen> createState() => _InventoryRecordsScreenState();
}

class _InventoryRecordsScreenState extends State<InventoryRecordsScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  _RecordTab _activeTab = _RecordTab.deliveryLogs;
  _DateFilter _dateFilter = _DateFilter.all;
  bool _showSummaryCards = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _searchCtrl.text = widget.initialSearch!;
      _searchQuery = widget.initialSearch!;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesDateFilter(DateTime date) {
    final now = DateTime.now();
    switch (_dateFilter) {
      case _DateFilter.today:
        return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
      case _DateFilter.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final resetStart =
            DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        return date.isAfter(resetStart) || date.isAtSameMomentAs(resetStart);
      case _DateFilter.thisMonth:
        return date.year == now.year && date.month == now.month;
      case _DateFilter.all:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final inventory = context.watch<InventoryProvider>();
    final procurement = context.watch<ProcurementProvider>();
    final shiftProvider = context.watch<ShiftProvider>();
    final restockProvider = context.watch<RestockProvider>();

    final deliveryLogs = inventory.deliveryLogs;
    final products = inventory.products;
    final lossRecords = inventory.lossRecords;
    final inquiries = restockProvider.inquiries;
    final transactions = inventory.transactions;
    final refundRequests = inventory.refundRequests;
    final allShifts = shiftProvider.allShifts;

    // 1. Filtered Delivery Logs
    final filteredLogs = deliveryLogs.where((log) {
      if (!_matchesDateFilter(log.createdAt)) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return log.productName.toLowerCase().contains(q) ||
          (log.invoiceNumber?.toLowerCase().contains(q) ?? false) ||
          (log.supplierName?.toLowerCase().contains(q) ?? false) ||
          log.receivedBy.toLowerCase().contains(q) ||
          (log.notes?.toLowerCase().contains(q) ?? false);
    }).toList();
    filteredLogs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // 2. Aggregated Batch Lots from all products
    final List<_BatchRecordWrapper> allBatches = [];
    for (final p in products) {
      for (final b in p.batches) {
        allBatches.add(_BatchRecordWrapper(product: p, batch: b));
      }
    }
    final filteredBatches = allBatches.where((wrapper) {
      if (!_matchesDateFilter(wrapper.batch.dateReceived)) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final supplierName = procurement.resolveSupplierNameForBatch(
        wrapper.batch,
        suppliers: inventory.suppliers,
        fallbackProductSupplierId: wrapper.product.supplierId,
      );
      final poNumber = procurement.resolvePoNumberForBatch(wrapper.batch);
      return wrapper.product.name.toLowerCase().contains(q) ||
          wrapper.batch.id.toLowerCase().contains(q) ||
          (supplierName?.toLowerCase().contains(q) ?? false) ||
          (poNumber?.toLowerCase().contains(q) ?? false) ||
          (wrapper.batch.invoiceNumber?.toLowerCase().contains(q) ?? false);
    }).toList();
    filteredBatches
        .sort((a, b) => b.batch.dateReceived.compareTo(a.batch.dateReceived));

    // 3. Filtered Sales Stock Depletion Transactions
    final filteredSales = transactions.where((tx) {
      if (!_matchesDateFilter(tx.createdAt)) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final itemsStr = tx.items.map((i) => i.name).join(' ').toLowerCase();
      return tx.id.toLowerCase().contains(q) ||
          (tx.orderId?.toLowerCase().contains(q) ?? false) ||
          (tx.customerEmail?.toLowerCase().contains(q) ?? false) ||
          tx.paymentMethod.name.toLowerCase().contains(q) ||
          itemsStr.contains(q);
    }).toList();
    filteredSales.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // 4. Filtered Loss/Waste Records
    final filteredLosses = lossRecords.where((loss) {
      if (!_matchesDateFilter(loss.createdAt)) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return loss.productName.toLowerCase().contains(q) ||
          loss.type.name.toLowerCase().contains(q) ||
          loss.notes.toLowerCase().contains(q);
    }).toList();
    filteredLosses.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // 5. Filtered Refund Records & Stock Returns
    final filteredRefunds = refundRequests.where((ref) {
      if (!_matchesDateFilter(ref.createdAt)) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final itemsStr = ref.items.map((i) => i.name).join(' ').toLowerCase();
      return ref.id.toLowerCase().contains(q) ||
          ref.transactionId.toLowerCase().contains(q) ||
          ref.customerEmail.toLowerCase().contains(q) ||
          ref.customerName.toLowerCase().contains(q) ||
          ref.reason.toLowerCase().contains(q) ||
          itemsStr.contains(q);
    }).toList();
    filteredRefunds.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // 6. Filtered Register Shifts
    final filteredShifts = allShifts.where((shift) {
      final matchStart = _matchesDateFilter(shift.openedAt);
      final matchEnd =
          shift.closedAt != null ? _matchesDateFilter(shift.closedAt!) : false;
      if (!matchStart && !matchEnd) return false;

      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return shift.cashierName.toLowerCase().contains(q) ||
          shift.status.name.toLowerCase().contains(q) ||
          'shift'.contains(q) ||
          'register'.contains(q);
    }).toList();
    filteredShifts.sort((a, b) => b.openedAt.compareTo(a.openedAt));

    // 7. Filtered Supplier Restock Inquiries
    final filteredInquiries = inquiries.where((inquiry) {
      final date = inquiry.sentAt ?? inquiry.createdAt;
      if (!_matchesDateFilter(date)) return false;

      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return inquiry.supplierName.toLowerCase().contains(q) ||
          inquiry.inquiryNumber.toLowerCase().contains(q) ||
          inquiry.items.any((i) => i.productName.toLowerCase().contains(q));
    }).toList();
    filteredInquiries.sort((a, b) {
      final dateA = a.sentAt ?? a.createdAt;
      final dateB = b.sentAt ?? b.createdAt;
      return dateB.compareTo(dateA);
    });

    // 8. Filtered Shelf Audit Reconciliations (Overages & Shortages)
    final List<_AuditRecordWrapper> filteredAudits = [];
    for (final log in deliveryLogs) {
      if ((log.notes?.toLowerCase().contains('audit') ?? false) ||
          log.receivedBy.toLowerCase().contains('audit')) {
        if (!_matchesDateFilter(log.createdAt)) continue;
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          if (!log.productName.toLowerCase().contains(q) &&
              !(log.notes?.toLowerCase().contains(q) ?? false) &&
              !log.receivedBy.toLowerCase().contains(q)) {
            continue;
          }
        }
        filteredAudits.add(_AuditRecordWrapper(
          title: 'Shelf Audit Overage',
          productName: log.productName,
          qty: log.qtyReceived,
          isOverage: true,
          cost: log.totalValue,
          notes: log.notes ?? 'Stock surplus verified during physical audit',
          auditor: log.receivedBy,
          timestamp: log.createdAt,
          originalData: log,
        ));
      }
    }
    for (final loss in lossRecords) {
      if (loss.notes.toLowerCase().contains('audit')) {
        if (!_matchesDateFilter(loss.createdAt)) continue;
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          if (!loss.productName.toLowerCase().contains(q) &&
              !loss.notes.toLowerCase().contains(q)) {
            continue;
          }
        }
        filteredAudits.add(_AuditRecordWrapper(
          title: 'Shelf Audit Shortage',
          productName: loss.productName,
          qty: loss.qty,
          isOverage: false,
          cost: loss.totalLoss,
          notes: loss.notes,
          auditor: loss.processedBy ?? 'Shelf Audit',
          timestamp: loss.createdAt,
          originalData: loss,
        ));
      }
    }
    filteredAudits.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // 9. Combined Chronological Activity Timeline ("RECORD EVERYTHING")
    final List<_TimelineItem> timelineItems = [];

    // Deliveries
    for (final l in filteredLogs) {
      final isAuditLog = (l.notes?.toLowerCase().contains('audit') ?? false) ||
          l.receivedBy.toLowerCase().contains('audit');
      timelineItems.add(_TimelineItem(
        title: isAuditLog ? 'Shelf Audit Overage' : 'Stock Delivery Received',
        productName: l.productName,
        qtyText: '+${l.qtyReceived}',
        isPositive: true,
        costText: formatPeso(l.totalValue),
        subText: isAuditLog
            ? 'Audit Overage • ${l.notes ?? "Surplus added"}'
            : 'Invoice: ${l.invoiceNumber ?? "N/A"} • By ${l.receivedBy}',
        timestamp: l.createdAt,
        type: isAuditLog ? _TimelineType.audit : _TimelineType.delivery,
        originalData: l,
      ));
    }

    // Sales Outflows
    for (final tx in filteredSales) {
      final totalQtySold = tx.items.fold<int>(
          0,
          (sum, i) =>
              sum +
              (tx.isRefunded ? 0 : (i.qty - i.returnedQty).clamp(0, 999999)));
      final itemSnippet =
          tx.items.map((i) => '${i.name} (x${i.qty})').join(', ');
      final shortTxId =
          tx.id.length >= 8 ? tx.id.substring(0, 8).toUpperCase() : tx.id;

      timelineItems.add(_TimelineItem(
        title: 'Sales Checkout Depletion',
        productName: itemSnippet.isNotEmpty ? itemSnippet : 'Store Items',
        qtyText: '-$totalQtySold items',
        isPositive: false,
        costText: formatPeso(tx.total),
        subText:
            'Tx #$shortTxId • Pay: ${tx.paymentMethod.name.toUpperCase()} • ${tx.customerEmail ?? "Walk-in"}',
        timestamp: tx.createdAt,
        type: _TimelineType.sale,
        originalData: tx,
      ));
    }

    // Loss Write-offs & Shortages
    for (final loss in filteredLosses) {
      final isAuditLoss = loss.notes.toLowerCase().contains('audit');
      timelineItems.add(_TimelineItem(
        title: isAuditLoss ? 'Shelf Audit Shortage' : 'Inventory Write-off',
        productName: loss.productName,
        qtyText: '-${loss.qty}',
        isPositive: false,
        costText: formatPeso(loss.totalLoss),
        subText: isAuditLoss
            ? 'Audit Shortage • ${loss.notes}'
            : 'Reason: ${loss.type.name.capitalize()}',
        timestamp: loss.createdAt,
        type: isAuditLoss ? _TimelineType.audit : _TimelineType.loss,
        originalData: loss,
      ));
    }

    // Customer Refunds
    for (final ref in filteredRefunds) {
      final totalQtyRef = ref.items.fold<int>(0, (sum, i) => sum + i.qty);
      final itemSnippet =
          ref.items.map((i) => '${i.name} (x${i.qty})').join(', ');
      final shortRefId =
          ref.id.length >= 8 ? ref.id.substring(0, 8).toUpperCase() : ref.id;

      timelineItems.add(_TimelineItem(
        title: 'Customer Refund / Stock Return',
        productName: itemSnippet.isNotEmpty ? itemSnippet : 'Refund Items',
        qtyText: '+$totalQtyRef items',
        isPositive: true,
        costText: formatPeso(ref.total),
        subText:
            'Refund #$shortRefId • Status: ${ref.status.name.toUpperCase()} • ${ref.customerName}',
        timestamp: ref.createdAt,
        type: _TimelineType.refund,
        originalData: ref,
      ));
    }

    // Register Shifts
    for (final shift in filteredShifts) {
      timelineItems.add(_TimelineItem(
        title: 'Register Shift Started',
        productName: 'Cashier: ${shift.cashierName}',
        qtyText: 'Float: ${formatPeso(shift.openingFloat)}',
        isPositive: true,
        costText: formatPeso(shift.openingFloat),
        subText:
            'Opened: ${DateFormat('h:mm a').format(shift.openedAt)} • Status: ${shift.status == ShiftStatus.active ? "ACTIVE" : "Closed"}',
        timestamp: shift.openedAt,
        type: _TimelineType.shiftStart,
        originalData: shift,
      ));

      if (shift.closedAt != null) {
        final variance = shift.cashDifference;
        final varText = variance == 0
            ? 'No variance'
            : (variance > 0
                ? 'Over +${formatPeso(variance)}'
                : 'Short -${formatPeso(variance.abs())}');

        timelineItems.add(_TimelineItem(
          title: 'Register Shift Closed',
          productName: 'Cashier: ${shift.cashierName}',
          qtyText: 'Drawer: ${formatPeso(shift.actualCashCounted ?? 0)}',
          isPositive: !shift.isShortage,
          costText: 'Sales: ${formatPeso(shift.cashSales)}',
          subText:
              'Closed: ${DateFormat('h:mm a').format(shift.closedAt!)} • Variance: $varText',
          timestamp: shift.closedAt!,
          type: _TimelineType.shiftEnd,
          originalData: shift,
        ));
      }
    }

    // Restock Inquiries
    for (final inquiry in filteredInquiries) {
      final date = inquiry.sentAt ?? inquiry.createdAt;
      final itemsSummary = inquiry.items
          .map((i) => '${i.productName} (${i.requestedQty} ${i.unit})')
          .join(', ');

      timelineItems.add(_TimelineItem(
        title: 'Supplier Restock Order Sent',
        productName: 'Supplier: ${inquiry.supplierName}',
        qtyText: '${inquiry.totalRequestedQty} items',
        isPositive: true,
        costText: formatPeso(inquiry.totalOrderedValue),
        subText:
            'Inquiry #${inquiry.inquiryNumber} • Items: ${inquiry.items.length} ($itemsSummary)',
        timestamp: date,
        type: _TimelineType.supplierInquiry,
        originalData: inquiry,
      ));
    }

    // Sort complete timeline descending by timestamp
    timelineItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // KPI Summary Metrics
    final totalDeliveryVal =
        deliveryLogs.fold<double>(0, (sum, l) => sum + l.totalValue);
    final totalDeliveryQty =
        deliveryLogs.fold<int>(0, (sum, l) => sum + l.qtyReceived);
    final totalSalesVal =
        filteredSales.fold<double>(0, (sum, s) => sum + s.total);
    final totalSalesQty = filteredSales.fold<int>(
        0,
        (sum, s) =>
            sum + s.items.fold<int>(0, (iSum, item) => iSum + item.qty));
    final activeLotsCount =
        allBatches.where((b) => b.batch.quantityRemaining > 0).length;
    final totalLossVal =
        lossRecords.fold<double>(0, (sum, l) => sum + l.totalLoss);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Records & History'),
        actions: [
          IconButton(
            icon: Icon(_showSummaryCards
                ? Icons.unfold_less_rounded
                : Icons.unfold_more_rounded),
            tooltip: _showSummaryCards
                ? 'Minimize Summary Metrics'
                : 'Expand Summary Metrics',
            onPressed: () =>
                setState(() => _showSummaryCards = !_showSummaryCards),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Records',
            onPressed: () => context.read<InventoryProvider>().initialize(),
          ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthContainer(
          maxWidth: 1000,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Collapsible Summary Header Row ─────────────────────────
              Text(
                'SUMMARY METRICS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),

              // ── KPI Summary Cards (Collapsible) ─────────────────────────
              if (_showSummaryCards) ...[
                _buildMetricCardsRow(
                  context,
                  totalDeliveryVal: totalDeliveryVal,
                  totalDeliveryQty: totalDeliveryQty,
                  totalSalesVal: totalSalesVal,
                  totalSalesQty: totalSalesQty,
                  activeLotsCount: activeLotsCount,
                  totalLossVal: totalLossVal,
                ),
                const SizedBox(height: 10),
              ],

              // ── Automated Search & Audit Action Controls ──────────────────
              AdminFilterBar(
                searchQuery: _searchQuery,
                searchHint:
                    'Search product, invoice #, cashier, customer, supplier…',
                dateFilter: switch (_dateFilter) {
                  _DateFilter.today => AdminDateFilter.today,
                  _DateFilter.thisWeek => AdminDateFilter.thisWeek,
                  _DateFilter.thisMonth => AdminDateFilter.thisMonth,
                  _DateFilter.all => AdminDateFilter.all,
                },
                onDateFilterChanged: (adf) {
                  setState(() {
                    _dateFilter = switch (adf) {
                      AdminDateFilter.today => _DateFilter.today,
                      AdminDateFilter.thisWeek => _DateFilter.thisWeek,
                      AdminDateFilter.thisMonth => _DateFilter.thisMonth,
                      AdminDateFilter.all => _DateFilter.all,
                    };
                  });
                },
                onSearchChanged: (v) => setState(() => _searchQuery = v),
                totalCount: timelineItems.length,
                filteredCount: timelineItems.length,
                itemUnit: 'records',
                extraActions: [
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StockReconciliationScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.fact_check_rounded, size: 16),
                    label: const Text('SHELF AUDIT',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Date Filters & Tabs Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Date range selection
                    PopupMenuButton<_DateFilter>(
                      initialValue: _dateFilter,
                      onSelected: (val) => setState(() => _dateFilter = val),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              _getDateFilterLabel(_dateFilter),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded, size: 18),
                          ],
                        ),
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: _DateFilter.all, child: Text('All Time')),
                        const PopupMenuItem(
                            value: _DateFilter.today, child: Text('Today')),
                        const PopupMenuItem(
                            value: _DateFilter.thisWeek,
                            child: Text('This Week')),
                        const PopupMenuItem(
                            value: _DateFilter.thisMonth,
                            child: Text('This Month')),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(
                        height: 24, child: VerticalDivider(width: 1)),
                    const SizedBox(width: 8),

                    // Navigation Tabs
                    _buildTabChip('Delivery Logs (${filteredLogs.length})',
                        _RecordTab.deliveryLogs, Icons.local_shipping_outlined),
                    const SizedBox(width: 6),
                    _buildTabChip('Active Lots (${filteredBatches.length})',
                        _RecordTab.batchLots, Icons.inventory_2_outlined),
                    const SizedBox(width: 6),
                    _buildTabChip(
                        'Sales & Depletions (${filteredSales.length})',
                        _RecordTab.salesTransactions,
                        Icons.shopping_cart_checkout_rounded),
                    const SizedBox(width: 6),
                    _buildTabChip('Loss & Spoilage (${filteredLosses.length})',
                        _RecordTab.lossWaste, Icons.delete_outline_rounded),
                    const SizedBox(width: 6),
                    _buildTabChip(
                        'Refund Records (${filteredRefunds.length})',
                        _RecordTab.refundRecords,
                        Icons.published_with_changes_rounded),
                    const SizedBox(width: 6),
                    _buildTabChip('Register Shifts (${filteredShifts.length})',
                        _RecordTab.registerShifts, Icons.point_of_sale_rounded),
                    const SizedBox(width: 6),
                    _buildTabChip(
                        'Supplier Inquiries (${filteredInquiries.length})',
                        _RecordTab.supplierInquiries,
                        Icons.mark_email_read_outlined),
                    const SizedBox(width: 6),
                    _buildTabChip(
                        'Audit Reconciliations (${filteredAudits.length})',
                        _RecordTab.auditReconciliations,
                        Icons.fact_check_outlined),
                    const SizedBox(width: 6),
                    _buildTabChip('Combined Timeline (${timelineItems.length})',
                        _RecordTab.allTimeline, Icons.history_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Main Active Tab View Content
              Expanded(
                child: _buildTabContent(
                  filteredLogs: filteredLogs,
                  filteredBatches: filteredBatches,
                  filteredSales: filteredSales,
                  filteredLosses: filteredLosses,
                  filteredRefunds: filteredRefunds,
                  filteredShifts: filteredShifts,
                  filteredInquiries: filteredInquiries,
                  filteredAudits: filteredAudits,
                  timelineItems: timelineItems,
                  products: products,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDateFilterLabel(_DateFilter filter) {
    switch (filter) {
      case _DateFilter.today:
        return 'Today';
      case _DateFilter.thisWeek:
        return 'This Week';
      case _DateFilter.thisMonth:
        return 'This Month';
      case _DateFilter.all:
        return 'All Time';
    }
  }

  Widget _buildTabChip(String label, _RecordTab tab, IconData icon) {
    final isSelected = _activeTab == tab;
    final colorScheme = Theme.of(context).colorScheme;

    return FilterChip(
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : colorScheme.onSurface,
        ),
      ),
      selected: isSelected,
      selectedColor: GdcColors.primaryGreen,
      backgroundColor: colorScheme.surfaceContainerLow,
      onSelected: (_) => setState(() => _activeTab = tab),
    );
  }

  Widget _buildMetricCardsRow(
    BuildContext context, {
    required double totalDeliveryVal,
    required int totalDeliveryQty,
    required double totalSalesVal,
    required int totalSalesQty,
    required int activeLotsCount,
    required double totalLossVal,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final cardWidth = isCompact
            ? (constraints.maxWidth - 8) / 2
            : (constraints.maxWidth - 24) / 4;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metricCard(
              context,
              width: cardWidth,
              title: 'Total Stock Delivered',
              value: formatPeso(totalDeliveryVal),
              subtext: '$totalDeliveryQty items received',
              icon: Icons.unarchive_rounded,
              color: Colors.green.shade800,
            ),
            _metricCard(
              context,
              width: cardWidth,
              title: 'Total Sales Depleted',
              value: formatPeso(totalSalesVal),
              subtext: '$totalSalesQty units sold',
              icon: Icons.shopping_cart_checkout_rounded,
              color: Colors.orange.shade800,
            ),
            _metricCard(
              context,
              width: cardWidth,
              title: 'Active FIFO Lots',
              value: '$activeLotsCount Lots',
              subtext: 'In active rotation',
              icon: Icons.inventory_2_rounded,
              color: Colors.blue.shade700,
            ),
            _metricCard(
              context,
              width: cardWidth,
              title: 'Recorded Loss',
              value: formatPeso(totalLossVal),
              subtext: 'Expired/Damaged',
              icon: Icons.remove_shopping_cart_rounded,
              color: Colors.red.shade700,
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required double width,
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent({
    required List<DeliveryLog> filteredLogs,
    required List<_BatchRecordWrapper> filteredBatches,
    required List<StoreTransaction> filteredSales,
    required List<LossRecord> filteredLosses,
    required List<RefundRequest> filteredRefunds,
    required List<ShiftSession> filteredShifts,
    required List<RestockInquiry> filteredInquiries,
    required List<_AuditRecordWrapper> filteredAudits,
    required List<_TimelineItem> timelineItems,
    required List<Product> products,
  }) {
    switch (_activeTab) {
      case _RecordTab.deliveryLogs:
        if (filteredLogs.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'No Stock Arrivals Recorded',
            subtitle:
                'No stock arrivals match your filters. Use "Receive Delivery" to record incoming stock.',
          );
        }
        return ListView.separated(
          itemCount: filteredLogs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) =>
              _buildDeliveryLogRow(ctx, filteredLogs[i], products),
        );

      case _RecordTab.batchLots:
        if (filteredBatches.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No Active Product Lots',
            subtitle: 'No inventory product batches match your filter.',
          );
        }
        return ListView.separated(
          itemCount: filteredBatches.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) => _buildBatchLotRow(
            ctx,
            filteredBatches[i],
            ctx.read<InventoryProvider>(),
            ctx.read<ProcurementProvider>(),
          ),
        );

      case _RecordTab.salesTransactions:
        if (filteredSales.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.shopping_cart_checkout_rounded,
            title: 'No Sales Transactions Recorded',
            subtitle:
                'No POS sales or order checkout stock depletions match your filter.',
          );
        }
        return ListView.separated(
          itemCount: filteredSales.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) =>
              _buildSaleTransactionRow(ctx, filteredSales[i]),
        );

      case _RecordTab.lossWaste:
        if (filteredLosses.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.delete_outline_rounded,
            title: 'No Loss / Spoilage Records',
            subtitle:
                'No damage or spoilage write-offs recorded for the selected filter.',
          );
        }
        return ListView.separated(
          itemCount: filteredLosses.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) => _buildLossRecordRow(ctx, filteredLosses[i]),
        );

      case _RecordTab.refundRecords:
        if (filteredRefunds.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.published_with_changes_rounded,
            title: 'No Refund Records Found',
            subtitle:
                'No itemized refund records match your search or date filter.',
          );
        }
        return ListView.separated(
          itemCount: filteredRefunds.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) =>
              _buildRefundRecordRow(ctx, filteredRefunds[i]),
        );

      case _RecordTab.registerShifts:
        if (filteredShifts.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.point_of_sale_rounded,
            title: 'No Register Shifts Logged',
            subtitle:
                'No cashier register shift sessions match your search or date filter.',
          );
        }
        return ListView.separated(
          itemCount: filteredShifts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) => _buildShiftRow(ctx, filteredShifts[i]),
        );

      case _RecordTab.supplierInquiries:
        if (filteredInquiries.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.mark_email_read_outlined,
            title: 'No Supplier Inquiries Recorded',
            subtitle:
                'No supplier restock order inquiries match your search or date filter.',
          );
        }
        return ListView.separated(
          itemCount: filteredInquiries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) => _buildInquiryRow(ctx, filteredInquiries[i]),
        );

      case _RecordTab.auditReconciliations:
        if (filteredAudits.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.fact_check_outlined,
            title: 'No Shelf Audits Recorded',
            subtitle:
                'No physical count discrepancy reconciliations match your filter.',
          );
        }
        return ListView.separated(
          itemCount: filteredAudits.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) =>
              _buildAuditReconciliationRow(ctx, filteredAudits[i]),
        );

      case _RecordTab.allTimeline:
        if (timelineItems.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.history_rounded,
            title: 'No Timeline Events',
            subtitle: 'No inventory movements or records available.',
          );
        }
        return ListView.separated(
          itemCount: timelineItems.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) =>
              _buildTimelineRow(ctx, timelineItems[i], products),
        );
    }
  }

  Widget _buildDeliveryLogRow(
      BuildContext context, DeliveryLog log, List<Product> products) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showDeliveryLogDetailModal(context, log, products),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green.shade800.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.move_to_inbox_rounded,
              color: Colors.green.shade800, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                log.productName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Text(
              '+${log.qtyReceived} units',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.green.shade800,
                  fontSize: 14),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    'Cost: ${formatPeso(log.unitCost)} • Total: ${formatPeso(log.totalValue)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  if (log.invoiceNumber != null &&
                      log.invoiceNumber!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Inv #${log.invoiceNumber}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Received by ${log.receivedBy} • ${DateFormat('MMM d, yyyy • h:mm a').format(log.createdAt)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildBatchLotRow(
    BuildContext context,
    _BatchRecordWrapper wrapper,
    InventoryProvider inventory,
    ProcurementProvider procurement,
  ) {
    final theme = Theme.of(context);
    final batch = wrapper.batch;
    final product = wrapper.product;
    final isDepleted = batch.remainingQty <= 0;
    final isExpired = batch.isExpired;
    final isNearExpiry = batch.isNearExpiration;
    final resolvedPo = procurement.resolvePoNumberForBatch(batch);
    final supplierName = procurement.resolveSupplierNameForBatch(
          batch,
          suppliers: inventory.suppliers,
          fallbackProductSupplierId: product.supplierId,
        ) ??
        'Unlinked Supplier';
    final int displayInitialQty = batch.initialQty >= batch.remainingQty
        ? batch.initialQty
        : batch.remainingQty;
    final bool isUnlinkedSupplier = !batch.hasValidSupplier;

    final statusColor = isDepleted
        ? Colors.grey
        : (isExpired
            ? Colors.red
            : (isNearExpiry ? Colors.orange.shade800 : Colors.green.shade800));

    final statusLabel = isDepleted
        ? 'DEPLETED'
        : (isExpired
            ? 'EXPIRED'
            : (isNearExpiry ? 'NEAR EXPIRY' : 'ACTIVE LOT'));

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: product),
            ),
          );
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            isDepleted
                ? Icons.inventory_2_outlined
                : (isExpired ? Icons.event_busy : Icons.inventory_rounded),
            color: statusColor,
            size: 24,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${batch.primaryReference(resolvedPoNumber: resolvedPo)} • Stock: ${batch.remainingQty} / $displayInitialQty ${product.unit}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    'Supplier: $supplierName',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isUnlinkedSupplier
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isUnlinkedSupplier
                          ? Colors.orange.shade900
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '• Unit Cost: ${formatPeso(batch.costPrice)}',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (batch.invoiceNumber != null &&
                      batch.invoiceNumber!.isNotEmpty)
                    Text('• Inv: #${batch.invoiceNumber}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.blue)),
                  if (batch.expiryDate != null)
                    Text(
                      '• Expiry: ${DateFormat('MMM d, yyyy').format(batch.expiryDate!)}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: isExpired || isNearExpiry
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isExpired || isNearExpiry
                              ? statusColor
                              : theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildSaleTransactionRow(BuildContext context, StoreTransaction tx) {
    final theme = Theme.of(context);
    final totalQty = tx.items.fold<int>(0, (sum, i) => sum + i.qty);
    final shortTxId =
        tx.id.length >= 8 ? tx.id.substring(0, 8).toUpperCase() : tx.id;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showSaleTransactionDetailModal(context, tx),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.shade800.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.shopping_cart_checkout_rounded,
              color: Colors.orange.shade800, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Sale Tx #$shortTxId',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Text(
              '-$totalQty items',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.orange.shade800,
                  fontSize: 14),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total: ${formatPeso(tx.total)} • Payment: ${tx.paymentMethod.name.toUpperCase()}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Customer: ${tx.customerEmail ?? "Walk-in"} • ${DateFormat('MMM d, yyyy • h:mm a').format(tx.createdAt)}',
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildLossRecordRow(BuildContext context, LossRecord loss) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showLossRecordDetailModal(context, loss),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.shade700.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.remove_shopping_cart_rounded,
              color: Colors.red.shade700, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                loss.productName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Text(
              '-${loss.qty} units',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.red.shade700,
                  fontSize: 14),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Loss Val: ${formatPeso(loss.totalLoss)} • Reason: ${loss.type.name.capitalize()}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${loss.notes.isNotEmpty ? loss.notes : "No notes"} • ${DateFormat('MMM d, yyyy • h:mm a').format(loss.createdAt)}',
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildRefundRecordRow(BuildContext context, RefundRequest refund) {
    final theme = Theme.of(context);
    final totalQty = refund.items.fold<int>(0, (sum, i) => sum + i.qty);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showRefundRecordDetailModal(context, refund),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.shade700.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.published_with_changes_rounded,
              color: Colors.blue.shade700, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Refund #${refund.id.length >= 8 ? refund.id.substring(0, 8).toUpperCase() : refund.id}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Text(
              '+$totalQty returned',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.blue.shade700,
                  fontSize: 14),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Refund Val: ${formatPeso(refund.total)} • Status: ${refund.status.name.toUpperCase()}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Customer: ${refund.customerName} • ${DateFormat('MMM d, yyyy • h:mm a').format(refund.createdAt)}',
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildAuditReconciliationRow(
      BuildContext context, _AuditRecordWrapper audit) {
    final theme = Theme.of(context);
    final color =
        audit.isOverage ? Colors.teal.shade700 : Colors.amber.shade900;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showAuditReconciliationDetailModal(context, audit),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.fact_check_rounded, color: color, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                audit.productName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Text(
              '${audit.isOverage ? "+" : "-"}${audit.qty} units',
              style: TextStyle(
                  fontWeight: FontWeight.w900, color: color, fontSize: 14),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${audit.title} • Valuation: ${formatPeso(audit.cost)}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Auditor: ${audit.auditor} • ${DateFormat('MMM d, yyyy • h:mm a').format(audit.timestamp)}',
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildTimelineRow(
      BuildContext context, _TimelineItem item, List<Product> products) {
    final theme = Theme.of(context);

    final isShift = item.type == _TimelineType.shiftStart ||
        item.type == _TimelineType.shiftEnd;
    final isInquiry = item.type == _TimelineType.supplierInquiry;
    final isAudit = item.type == _TimelineType.audit;
    final isSale = item.type == _TimelineType.sale;
    final isRefund = item.type == _TimelineType.refund;

    final IconData icon = isAudit
        ? Icons.fact_check_rounded
        : (isSale
            ? Icons.shopping_cart_checkout_rounded
            : (isRefund
                ? Icons.published_with_changes_rounded
                : (isInquiry
                    ? Icons.mark_email_read_outlined
                    : (item.type == _TimelineType.shiftStart
                        ? Icons.point_of_sale_rounded
                        : (item.type == _TimelineType.shiftEnd
                            ? Icons.lock_clock_rounded
                            : (item.isPositive
                                ? Icons.move_to_inbox_rounded
                                : Icons.remove_shopping_cart_rounded))))));

    final Color color = isAudit
        ? (item.isPositive ? Colors.teal.shade700 : Colors.amber.shade900)
        : (isSale
            ? Colors.orange.shade800
            : (isRefund
                ? Colors.blue.shade700
                : (isInquiry
                    ? Colors.blue.shade800
                    : (item.type == _TimelineType.shiftStart
                        ? Colors.amber.shade800
                        : (item.type == _TimelineType.shiftEnd
                            ? Colors.purple.shade800
                            : (item.isPositive
                                ? Colors.green.shade800
                                : Colors.red.shade700))))));

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () {
          if (item.originalData is RestockInquiry) {
            _showInquiryDetailModal(
                context, item.originalData as RestockInquiry);
          } else if (item.originalData is ShiftSession) {
            _showShiftDetailModal(context, item.originalData as ShiftSession);
          } else if (item.originalData is DeliveryLog) {
            _showDeliveryLogDetailModal(
                context, item.originalData as DeliveryLog, products);
          } else if (item.originalData is StoreTransaction) {
            _showSaleTransactionDetailModal(
                context, item.originalData as StoreTransaction);
          } else if (item.originalData is LossRecord) {
            _showLossRecordDetailModal(
                context, item.originalData as LossRecord);
          } else if (item.originalData is RefundRequest) {
            _showRefundRecordDetailModal(
                context, item.originalData as RefundRequest);
          }
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.productName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Text(
              item.qtyText,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: isShift
                    ? (item.type == _TimelineType.shiftStart
                        ? Colors.amber.shade800
                        : Colors.purple.shade800)
                    : (item.isPositive ? Colors.green.shade800 : color),
                fontSize: 14,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${item.title} • ${item.costText}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                      child: Text(item.subText,
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  Text(formatTimeAgo(item.timestamp),
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildShiftRow(BuildContext context, ShiftSession shift) {
    final theme = Theme.of(context);
    final isActive = shift.status == ShiftStatus.active;
    final isShort = shift.isShortage;
    final isOver = shift.isOverage;
    final totalSales = shift.cashSales;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showShiftDetailModal(context, shift),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.amber.shade800.withValues(alpha: 0.12)
                : Colors.purple.shade800.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            isActive ? Icons.point_of_sale_rounded : Icons.lock_clock_rounded,
            color: isActive ? Colors.amber.shade800 : Colors.purple.shade800,
            size: 24,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Shift: ${shift.cashierName}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.amber.shade800
                    : (isShort
                        ? Colors.red.shade700
                        : (isOver
                            ? Colors.blue.shade700
                            : Colors.green.shade800)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive
                    ? 'ACTIVE'
                    : (isShort ? 'SHORT' : (isOver ? 'OVER' : 'BALANCED')),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 10),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Float: ${formatPeso(shift.openingFloat)} • Sales: ${formatPeso(totalSales)}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    'Opened: ${DateFormat('MMM d, h:mm a').format(shift.openedAt)}',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (shift.closedAt != null)
                    Text(
                      '• Closed: ${DateFormat('MMM d, h:mm a').format(shift.closedAt!)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildInquiryRow(BuildContext context, RestockInquiry inquiry) {
    final theme = Theme.of(context);
    final statusColor = switch (inquiry.status) {
      RestockInquiryStatus.draft => Colors.grey,
      RestockInquiryStatus.pending => Colors.orange.shade800,
      RestockInquiryStatus.sent => Colors.blue.shade700,
      RestockInquiryStatus.acknowledged => Colors.cyan.shade700,
      RestockInquiryStatus.partiallyFulfilled => Colors.purple.shade700,
      RestockInquiryStatus.fulfilled => Colors.green.shade800,
      RestockInquiryStatus.cancelled => Colors.red.shade700,
    };

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showInquiryDetailModal(context, inquiry),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.mark_email_read_outlined,
            color: statusColor,
            size: 24,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Supplier: ${inquiry.supplierName}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                inquiry.status.name.toUpperCase(),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 10),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inquiry #${inquiry.inquiryNumber} • Val: ${formatPeso(inquiry.totalOrderedValue)}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Items: ${inquiry.items.length} requested • ${DateFormat('MMM d, yyyy').format(inquiry.sentAt ?? inquiry.createdAt)}',
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        trailing:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      ),
    );
  }

  // ── Detail Modals ──────────────────────────────────────────────────────────

  void _showDeliveryLogDetailModal(
      BuildContext context, DeliveryLog log, List<Product> products) {
    Product? linkedProduct;
    try {
      linkedProduct = products.firstWhere((p) => p.id == log.productId);
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade800.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.move_to_inbox_rounded,
                      color: Colors.green.shade800, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log.productName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 2),
                      Text('Stock Delivery Arrival Entry',
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(ctx).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _detailRow('Quantity Received', '+${log.qtyReceived} units'),
            _detailRow('Unit Cost Price', formatPeso(log.unitCost)),
            _detailRow('Total Valuation', formatPeso(log.totalValue)),
            _detailRow('Received By', log.receivedBy),
            _detailRow('Invoice / DR Number', log.invoiceNumber ?? 'N/A'),
            _detailRow('Received Timestamp',
                DateFormat('EEEE, MMM d, yyyy • h:mm a').format(log.createdAt)),
            if (log.expiryDate != null)
              _detailRow('Expiry Date',
                  DateFormat('MMM d, yyyy').format(log.expiryDate!)),
            if (log.notes != null && log.notes!.isNotEmpty)
              _detailRow('Notes / Discrepancies', log.notes!),
            const SizedBox(height: 20),
            if (linkedProduct != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ProductDetailScreen(product: linkedProduct!),
                      ),
                    );
                  },
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('View Product Profile'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSaleTransactionDetailModal(
      BuildContext context, StoreTransaction tx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade800.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.shopping_cart_checkout_rounded,
                      color: Colors.orange.shade800, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Sale Tx #${tx.id.length >= 8 ? tx.id.substring(0, 8).toUpperCase() : tx.id}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 2),
                      const Text('POS / Checkout Stock Depletion Record',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _detailRow('Transaction Total', formatPeso(tx.total)),
            _detailRow('Payment Method', tx.paymentMethod.name.toUpperCase()),
            _detailRow('Cash Tendered', formatPeso(tx.cashTendered)),
            _detailRow('Change Given', formatPeso(tx.changeGiven)),
            _detailRow(
                'Customer Email', tx.customerEmail ?? 'Walk-in Customer'),
            _detailRow('Timestamp',
                DateFormat('EEEE, MMM d, yyyy • h:mm a').format(tx.createdAt)),
            const SizedBox(height: 12),
            const Text('Line Items Sold:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            ...tx.items.map((i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${i.name} (x${i.qty})',
                          style: const TextStyle(fontSize: 13)),
                      Text(formatPeso(i.price * i.qty),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _showLossRecordDetailModal(BuildContext context, LossRecord loss) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.remove_shopping_cart_rounded,
                      color: Colors.red.shade700, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loss.productName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 2),
                      const Text('Inventory Write-off / Loss Log',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _detailRow('Quantity Written Off', '-${loss.qty} units'),
            _detailRow('Unit Valuation', formatPeso(loss.unitPrice)),
            _detailRow('Total Loss Cost', formatPeso(loss.totalLoss)),
            _detailRow('Loss Category', loss.type.name.capitalize()),
            _detailRow('Processed By', loss.processedBy ?? 'System / Staff'),
            _detailRow('Notes / Reason',
                loss.notes.isNotEmpty ? loss.notes : 'No extra notes'),
            _detailRow(
                'Logged Timestamp',
                DateFormat('EEEE, MMM d, yyyy • h:mm a')
                    .format(loss.createdAt)),
          ],
        ),
      ),
    );
  }

  void _showRefundRecordDetailModal(
      BuildContext context, RefundRequest refund) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.published_with_changes_rounded,
                      color: Colors.blue.shade700, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Refund #${refund.id.length >= 8 ? refund.id.substring(0, 8).toUpperCase() : refund.id}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 2),
                      const Text('Customer Return & Inventory Stock Return',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _detailRow('Refund Total', formatPeso(refund.total)),
            _detailRow('Status', refund.status.name.toUpperCase()),
            _detailRow('Customer Name', refund.customerName),
            _detailRow('Customer Email', refund.customerEmail),
            _detailRow('Reason', refund.reason),
            _detailRow('Processed By', refund.processedByEmail ?? 'Admin'),
            _detailRow(
                'Timestamp',
                DateFormat('EEEE, MMM d, yyyy • h:mm a')
                    .format(refund.createdAt)),
            const SizedBox(height: 12),
            const Text('Returned Items:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            ...refund.items.map((i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${i.name} (x${i.qty})',
                          style: const TextStyle(fontSize: 13)),
                      Text(formatPeso(i.price * i.qty),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _showShiftDetailModal(BuildContext context, ShiftSession shift) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade800.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.point_of_sale_rounded,
                      color: Colors.purple.shade800, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cashier Shift: ${shift.cashierName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(
                          'Session Status: ${shift.status == ShiftStatus.active ? "Active" : "Closed"}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _detailRow('Opening Float', formatPeso(shift.openingFloat)),
            _detailRow('Cash Sales Recorded', formatPeso(shift.cashSales)),
            _detailRow('Actual Cash Counted',
                formatPeso(shift.actualCashCounted ?? 0)),
            _detailRow(
                'Cash Difference / Variance', formatPeso(shift.cashDifference)),
            _detailRow(
                'Opened At',
                DateFormat('EEEE, MMM d, yyyy • h:mm a')
                    .format(shift.openedAt)),
            if (shift.closedAt != null)
              _detailRow(
                  'Closed At',
                  DateFormat('EEEE, MMM d, yyyy • h:mm a')
                      .format(shift.closedAt!)),
          ],
        ),
      ),
    );
  }

  void _showInquiryDetailModal(BuildContext context, RestockInquiry inquiry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade800.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.mark_email_read_outlined,
                      color: Colors.blue.shade800, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Supplier: ${inquiry.supplierName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(
                          'Request for Quotation (RFQ) #${inquiry.inquiryNumber}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _detailRow('Status', inquiry.status.name.toUpperCase()),
            _detailRow(
                'Total Ordered Value', formatPeso(inquiry.totalOrderedValue)),
            _detailRow('Total Items Requested', '${inquiry.totalRequestedQty}'),
            _detailRow(
                'Date Created',
                DateFormat('EEEE, MMM d, yyyy • h:mm a')
                    .format(inquiry.createdAt)),
          ],
        ),
      ),
    );
  }

  void _showAuditReconciliationDetailModal(
      BuildContext context, _AuditRecordWrapper audit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (audit.isOverage
                            ? Colors.teal.shade700
                            : Colors.amber.shade900)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.fact_check_rounded,
                      color: audit.isOverage
                          ? Colors.teal.shade700
                          : Colors.amber.shade900,
                      size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(audit.productName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(audit.title,
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(ctx).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _detailRow('Discrepancy Quantity',
                '${audit.isOverage ? "+" : "-"}${audit.qty} units'),
            _detailRow('Audit Valuation', formatPeso(audit.cost)),
            _detailRow('Auditor / Staff', audit.auditor),
            _detailRow('Discrepancy Notes', audit.notes),
            _detailRow(
                'Audit Timestamp',
                DateFormat('EEEE, MMM d, yyyy • h:mm a')
                    .format(audit.timestamp)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchRecordWrapper {
  final Product product;
  final ProductBatch batch;

  _BatchRecordWrapper({required this.product, required this.batch});
}

class _AuditRecordWrapper {
  final String title;
  final String productName;
  final int qty;
  final bool isOverage;
  final double cost;
  final String notes;
  final String auditor;
  final DateTime timestamp;
  final dynamic originalData;

  _AuditRecordWrapper({
    required this.title,
    required this.productName,
    required this.qty,
    required this.isOverage,
    required this.cost,
    required this.notes,
    required this.auditor,
    required this.timestamp,
    required this.originalData,
  });
}

enum _TimelineType {
  delivery,
  sale,
  loss,
  refund,
  shiftStart,
  shiftEnd,
  supplierInquiry,
  audit
}

class _TimelineItem {
  final String title;
  final String productName;
  final String qtyText;
  final bool isPositive;
  final String costText;
  final String subText;
  final DateTime timestamp;
  final _TimelineType type;
  final dynamic originalData;

  _TimelineItem({
    required this.title,
    required this.productName,
    required this.qtyText,
    required this.isPositive,
    required this.costText,
    required this.subText,
    required this.timestamp,
    required this.type,
    required this.originalData,
  });
}
