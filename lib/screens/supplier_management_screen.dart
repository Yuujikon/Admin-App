import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../models/supplier.dart';
import '../models/product.dart';
import '../models/restock_inquiry.dart';
import '../models/rfq.dart';
import '../models/purchase_order.dart';
import '../providers/inventory_provider.dart';
import '../providers/restock_provider.dart';
import '../providers/procurement_provider.dart';
import '../utils/format.dart';
import '../widgets/pending_deliveries_list.dart';
import '../widgets/receive_delivery_sheet.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/restock_inquiry_sheet.dart';
import '../widgets/supplier_sheet.dart';
import '../widgets/rfq_builder_sheet.dart';
import '../widgets/rfq_detail_dialog.dart';
import '../widgets/fifo_receiving_queue_view.dart';
import 'supplier_detail_screen.dart';

class SupplierManagementScreen extends StatefulWidget {
  const SupplierManagementScreen({super.key});

  @override
  State<SupplierManagementScreen> createState() =>
      _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen> {
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final procurement = context.watch<ProcurementProvider>();

    final allSuppliers = inventory.suppliers;
    final allProducts = inventory.products;

    final activeRfqs = procurement.rfqs
        .where((r) =>
            r.status == RfqStatus.draft ||
            r.status == RfqStatus.sent ||
            r.status == RfqStatus.quoted)
        .toList();

    final pendingPos = procurement.fifoPendingPurchaseOrders;

    final filteredSuppliers = allSuppliers.where((s) {
      final query = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(query) ||
          s.category.toLowerCase().contains(query) ||
          s.contactName.toLowerCase().contains(query);
    }).toList();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text('Suppliers & Procurement'),
          backgroundColor: Theme.of(context).colorScheme.surface,
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Suppliers'),
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('${allSuppliers.length}'),
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      textColor: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('RFQs'),
                    if (activeRfqs.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Badge(
                        label: Text('${activeRfqs.length}'),
                        backgroundColor: Colors.teal.shade800,
                        textColor: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('FIFO Receiving Queue'),
                    if (pendingPos.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Badge(
                        label: Text('${pendingPos.length}'),
                        backgroundColor: Colors.orange.shade800,
                        textColor: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(
                child: Text('Restock History'),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            RfqBuilderSheet.show(context: context);
          },
          icon: const Icon(Icons.request_quote_rounded),
          label: const Text('New RFQ'),
          backgroundColor: Colors.teal.shade800,
          foregroundColor: Colors.white,
        ),
        body: TabBarView(
          children: [
            // Tab 1: Suppliers Directory & Search
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText:
                                'Search suppliers by name, category, or contact...',
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () => setState(() {
                                          _searchCtrl.clear();
                                          _searchQuery = '';
                                        }))
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => _showSupplierSheet(context, null),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Supplier'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filteredSuppliers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_shipping_outlined,
                                  size: 64,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.1)),
                              const SizedBox(height: 16),
                              Text(
                                  _searchQuery.isEmpty
                                      ? 'No suppliers added yet.'
                                      : 'No matches found.',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                          child: ResponsiveCardGrid(
                            children: filteredSuppliers.map((s) {
                              final lowStockCount = allProducts
                                  .where((p) =>
                                      p.status == ProductStatus.published &&
                                      p.stock <= p.lowStockThreshold &&
                                      p.supplierId == s.id)
                                  .length;
                              return _SupplierCard(
                                  supplier: s, lowStockCount: lowStockCount);
                            }).toList(),
                          ),
                        ),
                ),
              ],
            ),

            // Tab 2: RFQs (Request For Quotation) Module
            const _RfqsTab(),

            // Tab 3: FIFO Receiving Queue (Purchase Orders)
            const FifoReceivingQueueView(),

            // Tab 4: Legacy Restocks & Deliveries History
            const SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: PendingDeliveriesList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupplierSheet(BuildContext context, Supplier? supplier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SupplierSheet(supplier: supplier),
    );
  }
}

// ── RFQS TAB ──────────────────────────────────────────────────────────────────

class _RfqsTab extends StatefulWidget {
  const _RfqsTab();

  @override
  State<_RfqsTab> createState() => _RfqsTabState();
}

class _RfqsTabState extends State<_RfqsTab> {
  String _searchQuery = '';
  RfqStatus? _selectedStatusFilter;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final procurement = context.watch<ProcurementProvider>();
    final allRfqs = procurement.rfqs;

    final filtered = allRfqs.where((r) {
      if (_selectedStatusFilter != null && r.status != _selectedStatusFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchNo = r.rfqNumber.toLowerCase().contains(q);
        final matchSupp = r.supplierName.toLowerCase().contains(q);
        final matchItem = r.items.any(
            (i) => i.productName.toLowerCase().contains(q) || i.sku.contains(q));
        if (!matchNo && !matchSupp && !matchItem) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Filter Controls Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search RFQ #, supplier, or product...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() {
                                _searchCtrl.clear();
                                _searchQuery = '';
                              }))
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All RFQs'),
                      selected: _selectedStatusFilter == null,
                      onSelected: (_) =>
                          setState(() => _selectedStatusFilter = null),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Draft'),
                      selected: _selectedStatusFilter == RfqStatus.draft,
                      onSelected: (_) => setState(
                          () => _selectedStatusFilter = RfqStatus.draft),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Sent'),
                      selected: _selectedStatusFilter == RfqStatus.sent,
                      onSelected: (_) =>
                          setState(() => _selectedStatusFilter = RfqStatus.sent),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Quoted'),
                      selected: _selectedStatusFilter == RfqStatus.quoted,
                      onSelected: (_) => setState(
                          () => _selectedStatusFilter = RfqStatus.quoted),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Converted to PO'),
                      selected: _selectedStatusFilter == RfqStatus.converted,
                      onSelected: (_) => setState(
                          () => _selectedStatusFilter = RfqStatus.converted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Cards List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.request_quote_outlined,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.15)),
                      const SizedBox(height: 16),
                      const Text('No RFQs found',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Tap "+ New RFQ" below to ask suppliers for price quotes.',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, idx) {
                    final rfq = filtered[idx];
                    return _RfqCard(rfq: rfq);
                  },
                ),
        ),
      ],
    );
  }
}

class _RfqCard extends StatelessWidget {
  final Rfq rfq;

  const _RfqCard({required this.rfq});

  @override
  Widget build(BuildContext context) {
    final bool isDraft = rfq.status == RfqStatus.draft;
    final bool isSent = rfq.status == RfqStatus.sent;
    final bool isQuoted = rfq.status == RfqStatus.quoted;
    final bool isConverted = rfq.status == RfqStatus.converted;

    Color badgeColor = Colors.grey;
    if (isSent) badgeColor = Colors.blue;
    if (isQuoted) badgeColor = Colors.orange;
    if (isConverted) badgeColor = Colors.teal;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: badgeColor.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Supplier Name, RFQ #, Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      rfq.supplierName.isNotEmpty
                          ? rfq.supplierName[0].toUpperCase()
                          : 'R',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                rfq.supplierName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: badgeColor),
                              ),
                              child: Text(
                                rfq.status.displayName.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: badgeColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'RFQ #${rfq.rfqNumber} • ${DateFormat('MMM d, yyyy').format(rfq.createdAt)}',
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

              const SizedBox(height: 10),

              // Item Breakdown Chips Preview
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: rfq.items.map((item) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${item.productName}: ${item.requestedQty} pcs' +
                          (item.quotedUnitPrice != null
                              ? ' (${formatPeso(item.quotedUnitPrice!)})'
                              : ''),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
              ),

              const Divider(height: 20),

              // Footer: Totals & Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${rfq.items.length} items (${rfq.totalRequestedQty} total pcs)',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontWeight: FontWeight.bold),
                      ),
                      if (rfq.totalQuotedValue > 0)
                        Text(
                          'Quoted: ${formatPeso(rfq.totalQuotedValue)}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.green.shade800),
                        ),
                    ],
                  ),

                  Row(
                    children: [
                      if (isDraft)
                        ElevatedButton.icon(
                          onPressed: () {
                            RfqBuilderSheet.show(
                              context: context,
                              initialRfq: rfq,
                            );
                          },
                          icon: const Icon(Icons.edit_rounded, size: 14),
                          label: const Text('EDIT RFQ',
                              style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      else if (isSent || isQuoted)
                        ElevatedButton.icon(
                          onPressed: () {
                            RfqDetailDialog.show(
                              context: context,
                              rfq: rfq,
                            );
                          },
                          icon: const Icon(
                              Icons.shopping_cart_checkout_rounded,
                              size: 14),
                          label: Text(
                              isQuoted ? 'CONVERT TO PO' : 'ENTER QUOTES',
                              style: const TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      else if (isConverted)
                        OutlinedButton.icon(
                          onPressed: () {
                            RfqDetailDialog.show(
                              context: context,
                              rfq: rfq,
                            );
                          },
                          icon: const Icon(Icons.visibility_outlined, size: 14),
                          label: const Text('VIEW PO DETAILS',
                              style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SUPPLIER CARD ─────────────────────────────────────────────────────────────

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final int lowStockCount;
  const _SupplierCard({required this.supplier, required this.lowStockCount});

  Future<void> _makeCall(BuildContext context, String phone) async {
    if (phone.isEmpty) return;
    final Uri uri = Uri(scheme: 'tel', path: phone);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _sendEmail(BuildContext context, String email) async {
    if (email.isEmpty) return;
    final Uri uri = Uri(scheme: 'mailto', path: email);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SupplierDetailScreen(supplier: supplier),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      supplier.name.isNotEmpty
                          ? supplier.name[0].toUpperCase()
                          : 'S',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (supplier.contactName.isNotEmpty)
                          Text(
                            supplier.contactName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'edit') {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(24))),
                          builder: (_) => SupplierSheet(supplier: supplier),
                        );
                      } else if (val == 'rfq') {
                        RfqBuilderSheet.show(
                          context: context,
                          initialSupplier: supplier,
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rfq',
                        child: Row(
                          children: [
                            Icon(Icons.request_quote_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Create RFQ'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit Details'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  supplier.category,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              if (lowStockCount > 0) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 14, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Text(
                        '$lowStockCount low stock item${lowStockCount > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (supplier.phone.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.phone_outlined, size: 20),
                      onPressed: () => _makeCall(context, supplier.phone),
                    ),
                  if (supplier.email.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.email_outlined, size: 20),
                      onPressed: () => _sendEmail(context, supplier.email),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.add_shopping_cart, size: 16),
                    label: const Text('RFQ'),
                    onPressed: () {
                      RfqBuilderSheet.show(
                        context: context,
                        initialSupplier: supplier,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
