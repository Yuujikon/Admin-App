import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/delivery_log.dart';
import '../models/product.dart';
import '../models/loss_record.dart';
import '../models/shift_session.dart';
import '../models/restock_inquiry.dart';
import '../providers/inventory_provider.dart';
import '../providers/shift_provider.dart';
import '../providers/restock_provider.dart';
import '../config/theme.dart';
import '../utils/format.dart';
import '../widgets/premium_components.dart';
import 'product_detail_screen.dart';
import 'stock_reconciliation_screen.dart';

enum _RecordTab { deliveryLogs, batchLots, lossWaste, registerShifts, supplierInquiries, allTimeline }

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
    final shiftProvider = context.watch<ShiftProvider>();
    final restockProvider = context.watch<RestockProvider>();

    final deliveryLogs = inventory.deliveryLogs;
    final products = inventory.products;
    final lossRecords = inventory.lossRecords;
    final inquiries = restockProvider.inquiries;

    final allShifts = shiftProvider.allShifts;

    // Filtered Supplier Restock Inquiries
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

    // Filtered Register Shifts
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

    // Filtered Delivery Logs
    final filteredLogs = deliveryLogs.where((log) {
      if (!_matchesDateFilter(log.createdAt)) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return log.productName.toLowerCase().contains(q) ||
          (log.invoiceNumber?.toLowerCase().contains(q) ?? false) ||
          log.receivedBy.toLowerCase().contains(q) ||
          (log.notes?.toLowerCase().contains(q) ?? false);
    }).toList();

    // Aggregated Batch Lots from all products
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
      return wrapper.product.name.toLowerCase().contains(q) ||
          wrapper.batch.id.toLowerCase().contains(q) ||
          (wrapper.batch.invoiceNumber?.toLowerCase().contains(q) ?? false);
    }).toList();

    // Sort batches FEFO or newest received
    filteredBatches
        .sort((a, b) => b.batch.dateReceived.compareTo(a.batch.dateReceived));

    // Filtered Loss/Waste Records
    final filteredLosses = lossRecords.where((loss) {
      if (!_matchesDateFilter(loss.createdAt)) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return loss.productName.toLowerCase().contains(q) ||
          loss.type.name.toLowerCase().contains(q) ||
          loss.notes.toLowerCase().contains(q);
    }).toList();

    // Combined Timeline Items
    final List<_TimelineItem> timelineItems = [];
    for (final l in filteredLogs) {
      timelineItems.add(_TimelineItem(
        title: 'Stock Delivery Received',
        productName: l.productName,
        qtyText: '+${l.qtyReceived}',
        isPositive: true,
        costText: formatPeso(l.totalValue),
        subText: 'Invoice: ${l.invoiceNumber ?? "N/A"} • By ${l.receivedBy}',
        timestamp: l.createdAt,
        type: _TimelineType.delivery,
        originalData: l,
      ));
    }
    for (final loss in filteredLosses) {
      timelineItems.add(_TimelineItem(
        title: 'Inventory Loss / Waste',
        productName: loss.productName,
        qtyText: '-${loss.qty}',
        isPositive: false,
        costText: formatPeso(loss.totalLoss),
        subText: 'Reason: ${loss.type.name.capitalize()}',
        timestamp: loss.createdAt,
        type: _TimelineType.loss,
        originalData: loss,
      ));
    }
    for (final shift in filteredShifts) {
      timelineItems.add(_TimelineItem(
        title: 'Register Shift Started',
        productName: 'Cashier: ${shift.cashierName}',
        qtyText: 'Float: ${formatPeso(shift.openingFloat)}',
        isPositive: true,
        costText: formatPeso(shift.openingFloat),
        subText:
            'Opened: ${DateFormat('h:mm a').format(shift.openedAt)} • Status: ${shift.status == ShiftStatus.active ? "ACTIVE SHIFT" : "Closed"}',
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
          costText:
              'Sales: ${formatPeso(shift.cashSales + shift.gcashSales)}',
          subText:
              'Closed: ${DateFormat('h:mm a').format(shift.closedAt!)} • Variance: $varText',
          timestamp: shift.closedAt!,
          type: _TimelineType.shiftEnd,
          originalData: shift,
        ));
      }
    }
    for (final inquiry in filteredInquiries) {
      final date = inquiry.sentAt ?? inquiry.createdAt;
      final itemsSummary = inquiry.items
          .map((i) => '${i.productName} (${i.requestedQty} ${i.unit})')
          .join(', ');

      timelineItems.add(_TimelineItem(
        title: 'Supplier Restock Inquiry Sent',
        productName: 'Supplier: ${inquiry.supplierName}',
        qtyText: '${inquiry.totalRequestedQty} requested',
        isPositive: true,
        costText: formatPeso(inquiry.totalOrderedValue),
        subText:
            'Inquiry #${inquiry.inquiryNumber} • Items: ${inquiry.items.length} ($itemsSummary)',
        timestamp: date,
        type: _TimelineType.supplierInquiry,
        originalData: inquiry,
      ));
    }
    timelineItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // KPI Metrics
    final totalDeliveryVal =
        deliveryLogs.fold<double>(0, (sum, l) => sum + l.totalValue);
    final totalDeliveryQty =
        deliveryLogs.fold<int>(0, (sum, l) => sum + l.qtyReceived);
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
                  activeLotsCount: activeLotsCount,
                  totalLossVal: totalLossVal,
                ),
                const SizedBox(height: 10),
              ],

              // ── Search & Audit Action Controls ──────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText:
                            'Search by product name, invoice #, received by…',
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
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
                    _buildTabChip('Loss & Spoilage (${filteredLosses.length})',
                        _RecordTab.lossWaste, Icons.delete_outline_rounded),
                    const SizedBox(width: 6),
                    _buildTabChip('Register Shifts (${filteredShifts.length})',
                        _RecordTab.registerShifts, Icons.point_of_sale_rounded),
                    const SizedBox(width: 6),
                    _buildTabChip('Supplier Inquiries (${filteredInquiries.length})',
                        _RecordTab.supplierInquiries, Icons.mark_email_read_outlined),
                    const SizedBox(width: 6),
                    _buildTabChip('Combined Timeline', _RecordTab.allTimeline,
                        Icons.history_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Main Content View ─────────────────────────────────────────
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    context.read<InventoryProvider>().initialize();
                    await Future.delayed(const Duration(milliseconds: 500));
                  },
                  child: _buildTabContent(
                    context,
                    filteredLogs: filteredLogs,
                    filteredBatches: filteredBatches,
                    filteredLosses: filteredLosses,
                    filteredShifts: filteredShifts,
                    filteredInquiries: filteredInquiries,
                    timelineItems: timelineItems,
                    products: products,
                  ),
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
        return 'Date: Today';
      case _DateFilter.thisWeek:
        return 'Date: This Week';
      case _DateFilter.thisMonth:
        return 'Date: This Month';
      case _DateFilter.all:
        return 'Date: All Time';
    }
  }

  Widget _buildTabChip(String label, _RecordTab tab, IconData icon) {
    final isSelected = _activeTab == tab;
    final colorScheme = Theme.of(context).colorScheme;

    return ChoiceChip(
      showCheckmark: false,
      avatar: Icon(icon,
          size: 16,
          color: isSelected ? Colors.white : colorScheme.onSurfaceVariant),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
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
              title: 'Active FEFO Lots',
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
            _metricCard(
              context,
              width: cardWidth,
              title: 'Stock Records',
              value:
                  '${context.watch<InventoryProvider>().deliveryLogs.length}',
              subtext: 'Total logged entries',
              icon: Icons.assignment_turned_in_rounded,
              color: Colors.purple.shade700,
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

  Widget _buildTabContent(
    BuildContext context, {
    required List<DeliveryLog> filteredLogs,
    required List<_BatchRecordWrapper> filteredBatches,
    required List<LossRecord> filteredLosses,
    required List<ShiftSession> filteredShifts,
    required List<RestockInquiry> filteredInquiries,
    required List<_TimelineItem> timelineItems,
    required List<Product> products,
  }) {
    switch (_activeTab) {
      case _RecordTab.deliveryLogs:
        if (filteredLogs.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'No Delivery Logs Found',
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
            title: 'No Batch Lots Found',
            subtitle:
                'No active or historical inventory lots match your search query.',
          );
        }
        return ListView.separated(
          itemCount: filteredBatches.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) => _buildBatchLotRow(ctx, filteredBatches[i]),
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

      case _RecordTab.registerShifts:
        if (filteredShifts.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.point_of_sale_rounded,
            title: 'No Register Shift Sessions',
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
          itemBuilder: (ctx, i) => _buildTimelineRow(ctx, timelineItems[i], products),
        );
    }
  }

  Widget _buildDeliveryLogRow(
      BuildContext context, DeliveryLog log, List<Product> products) {
    final theme = Theme.of(context);
    final isExpired = log.isExpired;
    final isNearExpiry = log.isNearExpiration;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
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
                    Text('Unit Cost: ${formatPeso(log.unitCost)}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    Text('• Total: ${formatPeso(log.totalValue)}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary)),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(formatDate(log.createdAt),
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant)),
                    if (log.invoiceNumber != null &&
                        log.invoiceNumber!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Inv #${log.invoiceNumber}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary)),
                      ),
                    ],
                    if (isExpired)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text('Expired',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900)),
                      )
                    else if (isNearExpiry)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text('Near Expiry (${log.daysUntilExpiration}d)',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          trailing:
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
        ),
      ),
    );
  }

  Widget _buildBatchLotRow(BuildContext context, _BatchRecordWrapper wrapper) {
    final theme = Theme.of(context);
    final batch = wrapper.batch;
    final product = wrapper.product;

    final isExpired = batch.isExpired;
    final isNearExpiry = batch.isNearExpiration;
    final hasStock = batch.quantityRemaining > 0;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasStock
                  ? (isExpired
                      ? Colors.red.shade50
                      : (isNearExpiry
                          ? Colors.amber.shade50
                          : Colors.blue.shade50))
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              color: hasStock
                  ? (isExpired
                      ? Colors.red.shade800
                      : (isNearExpiry
                          ? Colors.amber.shade900
                          : Colors.blue.shade800))
                  : Colors.grey,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: hasStock ? Colors.blue.shade800 : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${batch.quantityRemaining} rem.',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 12),
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
                    'Received: ${formatDate(batch.dateReceived)} • Unit Cost: ${formatPeso(batch.unitCost)}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (batch.invoiceNumber != null &&
                        batch.invoiceNumber!.isNotEmpty)
                      Text('Inv: #${batch.invoiceNumber}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey)),
                    if (batch.expirationDate != null)
                      Text(
                        'Expires: ${DateFormat('MMM d, y').format(batch.expirationDate!)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isExpired
                              ? Colors.red.shade800
                              : (isNearExpiry
                                  ? Colors.amber.shade900
                                  : Colors.grey.shade700),
                        ),
                      )
                    else
                      const Text('No Expiry Date',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailScreen(product: product),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLossRecordRow(BuildContext context, LossRecord loss) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade800.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.delete_outline_rounded,
                color: Colors.red.shade800, size: 24),
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
                    color: Colors.red.shade800,
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
                    'Type: ${loss.type.name.capitalize()} • Total: ${formatPeso(loss.totalLoss)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(formatDate(loss.createdAt),
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineRow(
      BuildContext context, _TimelineItem item, List<Product> products) {
    final theme = Theme.of(context);

    final isShift = item.type == _TimelineType.shiftStart ||
        item.type == _TimelineType.shiftEnd;
    final isInquiry = item.type == _TimelineType.supplierInquiry;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: item.originalData is RestockInquiry
              ? () => _showInquiryDetailModal(context, item.originalData as RestockInquiry)
              : (item.originalData is ShiftSession
                  ? () => _showShiftDetailModal(context, item.originalData as ShiftSession)
                  : (item.originalData is DeliveryLog
                      ? () => _showDeliveryLogDetailModal(
                          context, item.originalData as DeliveryLog, products)
                      : null)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isInquiry
                  ? Colors.blue.shade800.withValues(alpha: 0.12)
                  : (item.type == _TimelineType.shiftStart
                      ? Colors.amber.shade800.withValues(alpha: 0.12)
                      : (item.type == _TimelineType.shiftEnd
                          ? Colors.purple.shade800.withValues(alpha: 0.12)
                          : (item.isPositive
                              ? Colors.green.shade800.withValues(alpha: 0.12)
                              : Colors.red.shade800.withValues(alpha: 0.12)))),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isInquiry
                  ? Icons.mark_email_read_outlined
                  : (item.type == _TimelineType.shiftStart
                      ? Icons.point_of_sale_rounded
                      : (item.type == _TimelineType.shiftEnd
                          ? Icons.lock_clock_rounded
                          : (item.isPositive
                              ? Icons.add_shopping_cart_rounded
                              : Icons.remove_shopping_cart_rounded))),
              color: isInquiry
                  ? Colors.blue.shade800
                  : (item.type == _TimelineType.shiftStart
                      ? Colors.amber.shade800
                      : (item.type == _TimelineType.shiftEnd
                          ? Colors.purple.shade800
                          : (item.isPositive
                              ? Colors.green.shade800
                              : Colors.red.shade800))),
              size: 24,
            ),
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
                      : (item.isPositive
                          ? Colors.green.shade800
                          : Colors.red.shade800),
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
      ),
    );
  }

  Widget _buildShiftRow(BuildContext context, ShiftSession shift) {
    final theme = Theme.of(context);
    final isActive = shift.status == ShiftStatus.active;
    final isShort = shift.isShortage;
    final isOver = shift.isOverage;

    final totalSales = shift.cashSales + shift.gcashSales;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
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
                          : (isOver ? Colors.blue.shade700 : Colors.green.shade800)),
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

    final itemsSummary = inquiry.items
        .map((i) => '${i.productName} (${i.requestedQty} ${i.unit})')
        .join(', ');

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
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
                  'Inquiry #${inquiry.inquiryNumber} • Est. Value: ${formatPeso(inquiry.totalOrderedValue)}',
                  style:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Items (${inquiry.items.length}): $itemsSummary',
                  style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Sent/Created: ${DateFormat('MMM d, yyyy • h:mm a').format(inquiry.sentAt ?? inquiry.createdAt)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          trailing:
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
        ),
      ),
    );
  }

  void _showInquiryDetailModal(BuildContext context, RestockInquiry inquiry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
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
                  child: Icon(
                    Icons.mark_email_read_outlined,
                    color: Colors.blue.shade800,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Supplier: ${inquiry.supplierName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 18)),
                      Text('Restock Inquiry #${inquiry.inquiryNumber}',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _detailRow('Inquiry Status', inquiry.status.name.toUpperCase(),
                isBold: true, color: Colors.blue.shade800),
            _detailRow('Supplier Name', inquiry.supplierName),
            if (inquiry.supplierContact != null &&
                inquiry.supplierContact!.isNotEmpty)
              _detailRow('Supplier Contact', inquiry.supplierContact!),
            _detailRow('Date Created',
                DateFormat('MMM d, yyyy • h:mm a').format(inquiry.createdAt)),
            if (inquiry.sentAt != null)
              _detailRow('Date Sent',
                  DateFormat('MMM d, yyyy • h:mm a').format(inquiry.sentAt!)),
            _detailRow('Total Items Requested',
                '${inquiry.totalRequestedQty} units',
                isBold: true),
            _detailRow(
                'Total Estimated Value', formatPeso(inquiry.totalOrderedValue),
                isBold: true, color: GdcColors.primaryGreen),
            const SizedBox(height: 16),
            const Text('Requested Items Breakdown',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.3)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                itemCount: inquiry.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final item = inquiry.items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.productName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              Text('Unit Cost: ${formatPeso(item.costPrice)}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Text(
                          '${item.requestedQty} ${item.unit}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showDeliveryLogDetailModal(
      BuildContext context, DeliveryLog log, List<Product> products) {
    Product? matchedProduct;
    try {
      matchedProduct = products.firstWhere((p) => p.id == log.productId);
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
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
                  child: Icon(Icons.local_shipping_rounded,
                      color: Colors.green.shade800, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log.productName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 18)),
                      Text('Stock Delivery Record',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _detailRow('Quantity Received', '+${log.qtyReceived} units',
                isBold: true),
            _detailRow('Unit Cost (COGS)', formatPeso(log.unitCost)),
            _detailRow('Total Delivery Value', formatPeso(log.totalValue),
                isBold: true, color: GdcColors.primaryGreen),
            _detailRow('Invoice Number', log.invoiceNumber ?? 'Not specified'),
            _detailRow(
                'Expiration Date',
                log.expiryDate != null
                    ? DateFormat('MMM d, yyyy').format(log.expiryDate!)
                    : 'No expiration date'),
            _detailRow('Received By', log.receivedBy),
            _detailRow('Date & Time', formatDate(log.createdAt)),
            if (log.notes != null && log.notes!.isNotEmpty)
              _detailRow('Notes', log.notes!),
            const SizedBox(height: 20),
            if (matchedProduct != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ProductDetailScreen(product: matchedProduct!),
                      ),
                    );
                  },
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('View Product Stock & Batches'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GdcColors.primaryGreen,
                    foregroundColor: Colors.white,
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

  void _showShiftDetailModal(BuildContext context, ShiftSession shift) {
    final isActive = shift.status == ShiftStatus.active;
    final totalSales = shift.cashSales + shift.gcashSales;
    final variance = shift.cashDifference;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
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
                    color: isActive
                        ? Colors.amber.shade800.withValues(alpha: 0.12)
                        : Colors.purple.shade800.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isActive
                        ? Icons.point_of_sale_rounded
                        : Icons.lock_clock_rounded,
                    color:
                        isActive ? Colors.amber.shade800 : Colors.purple.shade800,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Shift: ${shift.cashierName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 18)),
                      Text(
                        isActive
                            ? 'Active Cashier Register Shift'
                            : 'Closed Register Shift Session',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _detailRow('Cashier Name', shift.cashierName, isBold: true),
            _detailRow('Session Status', isActive ? 'ACTIVE SHIFT' : 'CLOSED',
                color: isActive ? Colors.amber.shade800 : Colors.purple.shade800),
            _detailRow('Opened At', DateFormat('MMM d, yyyy • h:mm a').format(shift.openedAt)),
            if (shift.closedAt != null)
              _detailRow('Closed At', DateFormat('MMM d, yyyy • h:mm a').format(shift.closedAt!)),
            _detailRow('Opening Float', formatPeso(shift.openingFloat)),
            _detailRow('Cash Sales', formatPeso(shift.cashSales)),
            _detailRow('GCash / E-Wallet Sales', formatPeso(shift.gcashSales)),
            _detailRow('Total Shift Sales', formatPeso(totalSales), isBold: true),
            if (shift.totalCashDrops > 0)
              _detailRow('Mid-Shift Cash Drops', '-${formatPeso(shift.totalCashDrops)}', color: Colors.orange.shade800),
            _detailRow('Expected Cash Drawer', formatPeso(shift.expectedCash)),
            if (shift.actualCashCounted != null)
              _detailRow('Actual Cash Counted', formatPeso(shift.actualCashCounted!), isBold: true),
            if (!isActive && shift.actualCashCounted != null)
              _detailRow(
                'Drawer Variance',
                variance == 0
                    ? '₱0.00 (Balanced)'
                    : (variance > 0
                        ? '+${formatPeso(variance)} (Overage)'
                        : '-${formatPeso(variance.abs())} (Shortage)'),
                isBold: true,
                color: variance == 0
                    ? Colors.green.shade800
                    : (variance > 0 ? Colors.blue.shade800 : Colors.red.shade800),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                fontSize: isBold ? 14 : 13,
                color: color,
              ),
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

enum _TimelineType { delivery, loss, shiftStart, shiftEnd, supplierInquiry }

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
