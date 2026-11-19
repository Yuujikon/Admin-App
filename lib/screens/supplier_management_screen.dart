import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../models/supplier.dart';
import '../models/product.dart';
import '../models/restock_inquiry.dart';
import '../providers/inventory_provider.dart';
import '../providers/restock_provider.dart';
import '../utils/format.dart';
import '../widgets/pending_deliveries_list.dart';
import '../widgets/receive_delivery_sheet.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/restock_inquiry_sheet.dart';
import '../widgets/supplier_sheet.dart';
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
    final restockProvider = context.watch<RestockProvider>();

    final allSuppliers = inventory.suppliers;
    final allProducts = inventory.products;

    final activeInquiries = restockProvider.inquiries
        .where((i) =>
            i.status == RestockInquiryStatus.draft ||
            i.status == RestockInquiryStatus.pending ||
            i.status == RestockInquiryStatus.sent ||
            i.status == RestockInquiryStatus.acknowledged ||
            i.status == RestockInquiryStatus.partiallyFulfilled)
        .toList();

    final pendingInquiries = restockProvider.inquiries
        .where((i) =>
            i.status == RestockInquiryStatus.pending ||
            i.status == RestockInquiryStatus.sent ||
            i.status == RestockInquiryStatus.acknowledged ||
            i.status == RestockInquiryStatus.partiallyFulfilled)
        .toList();

    final filteredSuppliers = allSuppliers.where((s) {
      final query = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(query) ||
          s.category.toLowerCase().contains(query) ||
          s.contactName.toLowerCase().contains(query);
    }).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text('Suppliers & Restocks'),
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
                    const Text('Global Inquiries'),
                    if (activeInquiries.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Badge(
                        label: Text('${activeInquiries.length}'),
                        backgroundColor: Colors.blue.shade800,
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
                    const Text('Arriving Deliveries'),
                    if (pendingInquiries.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Badge(
                        label: Text('${pendingInquiries.length}'),
                        backgroundColor: Colors.orange.shade800,
                        textColor: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showSupplierSheet(context, null),
          icon: const Icon(Icons.add),
          label: const Text('New Supplier'),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Suppliers Directory & Search
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText:
                          'Search suppliers by name, category, or contact...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
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

            // Tab 2: Global Pending & Active Restock Inquiries View
            const _GlobalInquiriesTab(),

            // Tab 3: Arriving Supplier Deliveries & Verification Cards
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

// ── GLOBAL INQUIRIES TAB ──────────────────────────────────────────────────────

class _GlobalInquiriesTab extends StatefulWidget {
  const _GlobalInquiriesTab();

  @override
  State<_GlobalInquiriesTab> createState() => _GlobalInquiriesTabState();
}

class _GlobalInquiriesTabState extends State<_GlobalInquiriesTab> {
  String _searchQuery = '';
  String? _selectedSupplierId;
  RestockInquiryStatus? _selectedStatus;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restockProvider = context.watch<RestockProvider>();
    final inventory = context.watch<InventoryProvider>();

    final allInquiries = restockProvider.inquiries;
    final suppliers = inventory.suppliers;

    final filtered = allInquiries.where((i) {
      if (_selectedSupplierId != null && _selectedSupplierId!.isNotEmpty) {
        if (i.supplierId != _selectedSupplierId) return false;
      }

      if (_selectedStatus != null) {
        if (i.status != _selectedStatus) return false;
      } else {
        // Default when no status filter selected: show active/pending inquiries
        final bool isActive = i.status == RestockInquiryStatus.draft ||
            i.status == RestockInquiryStatus.pending ||
            i.status == RestockInquiryStatus.sent ||
            i.status == RestockInquiryStatus.acknowledged ||
            i.status == RestockInquiryStatus.partiallyFulfilled;
        if (!isActive) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchNum = i.inquiryNumber.toLowerCase().contains(q);
        final matchSupp = i.supplierName.toLowerCase().contains(q);
        final matchItem = i.items.any((item) =>
            item.productName.toLowerCase().contains(q) ||
            item.sku.toLowerCase().contains(q));
        if (!matchNum && !matchSupp && !matchItem) return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final double totalEstimatedValue =
        filtered.fold(0.0, (sum, i) => sum + i.totalOrderedValue);
    final int totalItemsCount =
        filtered.fold(0, (sum, i) => sum + i.totalRequestedQty);

    return Column(
      children: [
        // Filter Controls Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search inquiry #, supplier, or item...',
                        prefixIcon: const Icon(Icons.search, size: 20),
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
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String?>(
                      value: _selectedSupplierId,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      hint: const Text('All Suppliers',
                          style: TextStyle(fontSize: 12)),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Suppliers',
                              style: TextStyle(fontSize: 12)),
                        ),
                        ...suppliers.map((s) => DropdownMenuItem<String?>(
                              value: s.id,
                              child: Text(s.name,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedSupplierId = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All Active'),
                      selected: _selectedStatus == null,
                      onSelected: (_) =>
                          setState(() => _selectedStatus = null),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Draft'),
                      selected: _selectedStatus == RestockInquiryStatus.draft,
                      onSelected: (_) => setState(
                          () => _selectedStatus = RestockInquiryStatus.draft),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Sent'),
                      selected: _selectedStatus == RestockInquiryStatus.sent,
                      onSelected: (_) => setState(
                          () => _selectedStatus = RestockInquiryStatus.sent),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Partially Fulfilled'),
                      selected: _selectedStatus ==
                          RestockInquiryStatus.partiallyFulfilled,
                      onSelected: (_) => setState(() => _selectedStatus =
                          RestockInquiryStatus.partiallyFulfilled),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Fulfilled'),
                      selected:
                          _selectedStatus == RestockInquiryStatus.fulfilled,
                      onSelected: (_) => setState(() =>
                          _selectedStatus = RestockInquiryStatus.fulfilled),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Cancelled'),
                      selected:
                          _selectedStatus == RestockInquiryStatus.cancelled,
                      onSelected: (_) => setState(() =>
                          _selectedStatus = RestockInquiryStatus.cancelled),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Summary KPI Strip
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${filtered.length} Inquiry record${filtered.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Text(
                '$totalItemsCount total pcs • Est: ${formatPeso(totalEstimatedValue)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
        ),

        // Global Inquiry Cards List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_outlined,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.15)),
                      const SizedBox(height: 16),
                      const Text('No restock inquiries found.',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, idx) {
                    final inquiry = filtered[idx];
                    return _GlobalInquiryCard(inquiry: inquiry);
                  },
                ),
        ),
      ],
    );
  }
}

// ── GLOBAL INQUIRY CARD ───────────────────────────────────────────────────────

class _GlobalInquiryCard extends StatelessWidget {
  final RestockInquiry inquiry;
  const _GlobalInquiryCard({required this.inquiry});

  @override
  Widget build(BuildContext context) {
    final bool isDraft = inquiry.status == RestockInquiryStatus.draft;
    final bool isSent = inquiry.status == RestockInquiryStatus.sent ||
        inquiry.status == RestockInquiryStatus.acknowledged ||
        inquiry.status == RestockInquiryStatus.partiallyFulfilled;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDraft
              ? Colors.grey.shade300
              : isSent
                  ? Colors.blue.shade200
                  : Colors.green.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Supplier Name, Ref #, and Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    inquiry.supplierName.isNotEmpty
                        ? inquiry.supplierName[0].toUpperCase()
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              inquiry.supplierName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StatusBadge(status: inquiry.status),
                        ],
                      ),
                      Text(
                        'Ref: ${inquiry.inquiryNumber} • Placed ${DateFormat('MMM d, yyyy').format(inquiry.createdAt)}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Item Breakdown Chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: inquiry.items.map((item) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '${item.productName}: ${item.requestedQty} ${item.unit}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
            ),

            const Divider(height: 20),

            // Footer Summary & Actions Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${inquiry.items.length} items (${inquiry.totalRequestedQty} total pcs)',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Total: ${formatPeso(inquiry.totalOrderedValue)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.green.shade800),
                    ),
                  ],
                ),

                Row(
                  children: [
                    if (isDraft) ...[
                      ElevatedButton.icon(
                        onPressed: () => sendRestockEmail(context, inquiry),
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label: const Text('EMAIL',
                            style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await context
                              .read<RestockProvider>()
                              .sendInquiry(inquiry);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Inquiry #${inquiry.inquiryNumber} recorded as Sent.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_rounded, size: 14),
                        label: const Text('MARK SENT',
                            style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 18, color: Colors.blue),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(24))),
                            builder: (_) =>
                                RestockInquirySheet(inquiry: inquiry),
                          );
                        },
                      ),
                    ] else if (isSent) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          ReceiveDeliverySheet.show(
                            context: context,
                            inquiry: inquiry,
                          );
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded,
                            size: 14),
                        label: const Text('VERIFY & RECEIVE',
                            style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.email_outlined,
                            size: 18, color: Colors.blue),
                        onPressed: () {
                          sendRestockEmail(context, inquiry);
                          context
                              .read<RestockProvider>()
                              .resendInquiry(inquiry);
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final RestockInquiryStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case RestockInquiryStatus.draft:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade800;
        label = 'DRAFT';
        break;
      case RestockInquiryStatus.pending:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade900;
        label = 'PENDING';
        break;
      case RestockInquiryStatus.sent:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade900;
        label = 'SENT';
        break;
      case RestockInquiryStatus.acknowledged:
        bg = Colors.cyan.shade50;
        fg = Colors.cyan.shade900;
        label = 'ACKNOWLEDGED';
        break;
      case RestockInquiryStatus.partiallyFulfilled:
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade900;
        label = 'PARTIAL';
        break;
      case RestockInquiryStatus.fulfilled:
        bg = Colors.green.shade50;
        fg = Colors.green.shade900;
        label = 'FULFILLED';
        break;
      case RestockInquiryStatus.cancelled:
        bg = Colors.red.shade50;
        fg = Colors.red.shade900;
        label = 'CANCELLED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

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
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot initiate call to $phone')),
        );
      }
    } catch (_) {}
  }

  Future<void> _sendSms(BuildContext context, String phone,
      [String? supplierName]) async {
    if (phone.isEmpty) return;
    final String message = (supplierName != null &&
            supplierName.trim().isNotEmpty)
        ? 'Hello $supplierName, this is GDC Store regarding inventory supply restocking.'
        : 'Hello, this is GDC Store regarding inventory supply restocking.';
    final Uri uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open SMS to $phone')),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: isDark ? 0.2 : 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SupplierDetailScreen(supplier: supplier))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isDark
                        ? colorScheme.primaryContainer
                        : colorScheme.primary.withValues(alpha: 0.12),
                    child: Text(
                      supplier.name.isNotEmpty
                          ? supplier.name[0].toUpperCase()
                          : 'S',
                      style: TextStyle(
                          color: isDark
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.name,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.onSurface,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          supplier.category,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (lowStockCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber.shade900.withValues(alpha: 0.3)
                            : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? Colors.amber.shade700.withValues(alpha: 0.6)
                              : Colors.amber.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 13,
                            color: isDark
                                ? Colors.amber.shade300
                                : Colors.amber.shade900,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$lowStockCount LOW',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.amber.shade200
                                  : Colors.amber.shade900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      supplier.contactName.isEmpty
                          ? 'No contact person'
                          : supplier.contactName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (supplier.phone.isNotEmpty) ...[
                    Material(
                      color: isDark
                          ? Colors.green.shade900.withValues(alpha: 0.35)
                          : Colors.green.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isDark
                              ? Colors.green.shade800
                              : Colors.green.shade200,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => _makeCall(context, supplier.phone),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.phone_rounded,
                                size: 14,
                                color: isDark
                                    ? Colors.green.shade300
                                    : Colors.green.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Call',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Material(
                      color: isDark
                          ? Colors.blue.shade900.withValues(alpha: 0.35)
                          : Colors.blue.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isDark
                              ? Colors.blue.shade800
                              : Colors.blue.shade200,
                        ),
                      ),
                      child: InkWell(
                        onTap: () =>
                            _sendSms(context, supplier.phone, supplier.name),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sms_rounded,
                                size: 14,
                                color: isDark
                                    ? Colors.blue.shade300
                                    : Colors.blue.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'SMS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.blue.shade300
                                      : Colors.blue.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
