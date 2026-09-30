import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/supplier.dart';
import '../models/product.dart';
import '../models/restock_inquiry.dart';
import '../providers/inventory_provider.dart';
import '../providers/restock_provider.dart';
import '../widgets/pending_deliveries_list.dart';
import '../widgets/responsive_layout.dart';
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
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text('Suppliers & Restocks'),
          backgroundColor: Theme.of(context).colorScheme.surface,
          bottom: TabBar(
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

            // Tab 2: Arriving Supplier Deliveries & Verification Cards
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: const PendingDeliveriesList(),
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

  Future<void> _sendSms(BuildContext context, String phone) async {
    if (phone.isEmpty) return;
    final Uri uri = Uri(scheme: 'sms', path: phone);
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SupplierDetailScreen(supplier: supplier))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    child: Text(
                      supplier.name.isNotEmpty
                          ? supplier.name[0].toUpperCase()
                          : 'S',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(supplier.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(supplier.category,
                            style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                  if (lowStockCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 12, color: Colors.orange.shade800),
                          const SizedBox(width: 4),
                          Text('$lowStockCount LOW',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    supplier.contactName.isEmpty
                        ? 'No contact name'
                        : supplier.contactName,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.phone_rounded,
                        size: 18, color: Colors.green),
                    tooltip: 'Call Supplier',
                    onPressed: () => _makeCall(context, supplier.phone),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sms_rounded,
                        size: 18, color: Colors.blue),
                    tooltip: 'SMS Supplier',
                    onPressed: () => _sendSms(context, supplier.phone),
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
