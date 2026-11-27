import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/supplier.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../providers/restock_provider.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/supplier_sheet.dart';
import '../widgets/po_builder_sheet.dart';
import '../widgets/po_history_view.dart';
import 'supplier_detail_screen.dart';

class SupplierManagementScreen extends StatefulWidget {
  const SupplierManagementScreen({super.key});

  @override
  State<SupplierManagementScreen> createState() =>
      _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen>
    with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  late TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging ||
        _tabController.index != _currentTabIndex) {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final procurement = context.watch<ProcurementProvider>();
    final restock = context.watch<RestockProvider>();

    final allSuppliers = inventory.suppliers;
    final allProducts = inventory.products;
    final totalOrdersCount =
        procurement.purchaseOrders.length + restock.inquiries.length;

    final filteredSuppliers = allSuppliers.where((s) {
      final query = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(query) ||
          s.category.toLowerCase().contains(query) ||
          s.contactName.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Suppliers & Procurement'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
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
                  const Text('Purchase Orders'),
                  if (totalOrdersCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('$totalOrdersCount'),
                      backgroundColor: Colors.teal.shade800,
                      textColor: Colors.white,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showSupplierSheet(context, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Supplier'),
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
            )
          : FloatingActionButton.extended(
              onPressed: () => PoBuilderSheet.show(context: context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Order'),
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
            ),
      body: TabBarView(
        controller: _tabController,
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
                                    p.isPhysicalThresholdHit &&
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

          // Tab 2: Merged Purchase Orders & Delivery History
          const PoHistoryView(),
        ],
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
                      }
                    },
                    itemBuilder: (context) => [
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
              const SizedBox(height: 12),
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
                    icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                    label: const Text('Create PO'),
                    onPressed: () {
                      PoBuilderSheet.show(
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
