import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/purchase_order.dart';
import '../providers/procurement_provider.dart';
import '../utils/format.dart';
import 'premium_components.dart';
import 'po_receiving_sheet.dart';

class FifoReceivingQueueView extends StatefulWidget {
  const FifoReceivingQueueView({super.key});

  @override
  State<FifoReceivingQueueView> createState() => _FifoReceivingQueueViewState();
}

class _FifoReceivingQueueViewState extends State<FifoReceivingQueueView> {
  String _searchQuery = '';
  String? _selectedSupplierFilter;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final procurement = context.watch<ProcurementProvider>();
    final pendingOrders = procurement.fifoPendingPurchaseOrders;

    // Extract unique suppliers for filter chips
    final suppliersMap = <String, String>{};
    for (var po in pendingOrders) {
      suppliersMap[po.supplierId] = po.supplierName;
    }

    // Filter by search query and supplier filter while preserving FIFO order (orderDate ASC)
    final filteredOrders = pendingOrders.where((po) {
      final matchesSearch = _searchQuery.isEmpty ||
          po.poNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          po.supplierName.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesSupplier = _selectedSupplierFilter == null ||
          po.supplierId == _selectedSupplierFilter;

      return matchesSearch && matchesSupplier;
    }).toList();

    if (pendingOrders.isEmpty) {
      return const PremiumEmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No Pending Supplier Deliveries in FIFO Queue',
        subtitle:
            'All purchase orders have been fully received or reconciled.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Search Bar & FIFO Notice Banner
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search PO Number or Supplier...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),

              const SizedBox(height: 10),

              // Supplier Filter Chips
              if (suppliersMap.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All Suppliers'),
                        selected: _selectedSupplierFilter == null,
                        onSelected: (_) {
                          setState(() => _selectedSupplierFilter = null);
                        },
                      ),
                      const SizedBox(width: 8),
                      ...suppliersMap.entries.map((e) {
                        final isSelected = _selectedSupplierFilter == e.key;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text(e.value),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedSupplierFilter =
                                    selected ? e.key : null;
                              });
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // FIFO Ordering Indicator Badge
              Row(
                children: [
                  const Icon(Icons.swap_vert_rounded,
                      size: 16, color: Colors.teal),
                  const SizedBox(width: 4),
                  Text(
                    'Sorted by FIFO Queue (Oldest Order Date First)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // FIFO Pending PO Cards List
        Expanded(
          child: filteredOrders.isEmpty
              ? const Center(child: Text('No matching pending purchase orders'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredOrders.length,
                  itemBuilder: (context, index) {
                    final po = filteredOrders[index];
                    final bool isPartial =
                        po.status == PurchaseOrderStatus.partiallyReceived;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: PremiumCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Queue Rank, Supplier & PO Number
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Text(
                                    '#${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              po.supplierName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: (isPartial
                                                      ? Colors.orange
                                                      : Colors.blue)
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                  color: isPartial
                                                      ? Colors.orange.shade400
                                                      : Colors.blue.shade300),
                                            ),
                                            child: Text(
                                              isPartial
                                                  ? 'PARTIALLY RECEIVED'
                                                  : 'PENDING DELIVERY',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: isPartial
                                                    ? Colors.orange.shade900
                                                    : Colors.blue.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'PO #${po.poNumber} • Ordered ${DateFormat('MMM d, yyyy hh:mm a').format(po.orderDate)}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Progress Bar & Item Count Badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Delivery Progress: ${po.totalReceivedQty} / ${po.totalOrderedQty} units (${po.items.length} line items)',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Valuation: ${formatPeso(po.totalOrderedValue)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade800),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: po.totalOrderedQty > 0
                                    ? (po.totalReceivedQty / po.totalOrderedQty)
                                        .clamp(0.0, 1.0)
                                    : 0.0,
                                minHeight: 8,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh,
                                color: isPartial
                                    ? Colors.orange.shade700
                                    : Colors.blue.shade700,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Line Items Chips Preview
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: po.items.map((item) {
                                final isDone = item.isComplete;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDone
                                        ? Colors.green.shade50
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: isDone
                                            ? Colors.green.shade300
                                            : Theme.of(context)
                                                .colorScheme
                                                .outlineVariant
                                                .withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    '${item.productName}: ${item.receivedQty}/${item.orderedQty}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isDone
                                          ? Colors.green.shade900
                                          : null,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            const Divider(height: 24),

                            // Action Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  PoReceivingSheet.show(
                                    context: context,
                                    purchaseOrder: po,
                                  );
                                },
                                icon: const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 18),
                                label: const Text('RECEIVE & VERIFY DELIVERY',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade800,
                                  foregroundColor: Colors.white,
                                  elevation: 1,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
