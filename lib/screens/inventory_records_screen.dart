import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/delivery_log.dart';
import '../models/product.dart';
import '../models/loss_record.dart';
import '../providers/inventory_provider.dart';
import '../config/theme.dart';
import '../utils/format.dart';
import '../widgets/premium_components.dart';
import 'product_detail_screen.dart';
import 'stock_reconciliation_screen.dart';

enum _RecordTab { deliveryLogs, batchLots, lossWaste, allTimeline }

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

    final deliveryLogs = inventory.deliveryLogs;
    final products = inventory.products;
    final lossRecords = inventory.lossRecords;

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
              // ── KPI Summary Cards ──────────────────────────────────────
              _buildMetricCardsRow(
                context,
                totalDeliveryVal: totalDeliveryVal,
                totalDeliveryQty: totalDeliveryQty,
                activeLotsCount: activeLotsCount,
                totalLossVal: totalLossVal,
              ),
              const SizedBox(height: 12),

              // ── Action Buttons Header Row ──────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StockReconciliationScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.fact_check_rounded, size: 18),
                  label: const Text('SHELF AUDIT',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade900,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Search & Filter Controls ─────────────────────────────────
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search by product name, invoice #, received by…',
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
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
          itemBuilder: (ctx, i) => _buildTimelineRow(ctx, timelineItems[i]),
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
              Row(
                children: [
                  Text('Unit Cost: ${formatPeso(log.unitCost)}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
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
    );
  }

  Widget _buildTimelineRow(BuildContext context, _TimelineItem item) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: item.isPositive
                ? Colors.green.shade800.withValues(alpha: 0.12)
                : Colors.red.shade800.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            item.isPositive
                ? Icons.add_shopping_cart_rounded
                : Icons.remove_shopping_cart_rounded,
            color:
                item.isPositive ? Colors.green.shade800 : Colors.red.shade800,
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
                color: item.isPositive
                    ? Colors.green.shade800
                    : Colors.red.shade800,
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

enum _TimelineType { delivery, loss }

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
