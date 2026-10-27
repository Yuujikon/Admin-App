import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../models/supplier.dart';
import '../models/product.dart';
import '../models/restock_inquiry.dart';
import '../providers/inventory_provider.dart';
import '../providers/restock_provider.dart';
import '../services/notification_service.dart';
import '../config/theme.dart';
import '../utils/format.dart';
import '../widgets/supplier_sheet.dart';
import '../widgets/restock_inquiry_sheet.dart';
import '../widgets/receive_delivery_sheet.dart';
import '../widgets/add_product_sheet.dart';
import '../widgets/product_edit_sheet.dart';

class SupplierDetailScreen extends StatefulWidget {
  final Supplier supplier;
  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    // Refresh supplier data in case it was edited
    final currentSupplier = inventory.suppliers.firstWhere(
        (s) => s.id == widget.supplier.id,
        orElse: () => widget.supplier);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(currentSupplier.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Products'),
            Tab(text: 'Restock'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(
            supplier: currentSupplier,
            onNavigateToProductsTab: () => _tabController.animateTo(1),
          ),
          _ProductsTab(supplier: currentSupplier),
          _RestockTab(supplier: currentSupplier),
          _HistoryTab(supplierId: currentSupplier.id),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onNavigateToProductsTab;

  const _OverviewTab({
    required this.supplier,
    required this.onNavigateToProductsTab,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).semantic;
    final inventory = context.watch<InventoryProvider>();
    final suppliedProducts =
        inventory.products.where((p) => p.supplierId == supplier.id).toList();
    final lowStockCount = suppliedProducts
        .where((p) =>
            p.status == ProductStatus.published &&
            p.stock <= p.lowStockThreshold)
        .length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Header Card ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6))
            ],
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(supplier.name[0].toUpperCase(),
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              const SizedBox(height: 16),
              Text(supplier.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 22)),
              Text(supplier.category,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Supplied Products Summary ──────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('SUPPLIED PRODUCTS',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1)),
            TextButton(
              onPressed: onNavigateToProductsTab,
              child: const Text('View All',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.inventory_2_outlined,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${suppliedProducts.length} Products Assigned',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          lowStockCount > 0
                              ? '$lowStockCount item(s) low in stock'
                              : 'All stock levels healthy',
                          style: TextStyle(
                            fontSize: 12,
                            color: lowStockCount > 0
                                ? Colors.orange.shade800
                                : Colors.grey,
                            fontWeight: lowStockCount > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showAddProductSheet(context, supplier.id),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('New Product',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showLinkExistingModal(context, supplier),
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Link Existing',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Contact Section ──────────────────────────────────────────────────
        Text('CONTACT INFORMATION',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        _infoTile(context, Icons.person_outline, 'Contact Person',
            supplier.contactName.isEmpty ? 'Not set' : supplier.contactName),
        _infoTile(context, Icons.phone_outlined, 'Phone', supplier.phone,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _launchAction('tel:${supplier.phone}'),
                  icon: Icon(Icons.call_rounded, color: semantic.success),
                  tooltip: 'Call Supplier',
                ),
                IconButton(
                  onPressed: () {
                    final msg =
                        'Hello ${supplier.name}, this is GDC Store regarding inventory supply restocking.';
                    _launchAction(
                        'sms:${supplier.phone}?body=${Uri.encodeComponent(msg)}');
                  },
                  icon: Icon(Icons.message_rounded, color: semantic.info),
                  tooltip: 'Send SMS',
                ),
              ],
            )),
        _infoTile(context, Icons.email_outlined, 'Email', supplier.email,
            trailing: IconButton(
              onPressed: () => _launchAction('mailto:${supplier.email}'),
              icon: Icon(Icons.email_rounded, color: semantic.info),
            )),
        const SizedBox(height: 24),

        // ── Settings Section ─────────────────────────────────────────────────
        Text('SETTINGS',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2)),
          ),
          child: SwitchListTile(
            title: const Text('Auto-Notify Low Stock',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: const Text('Sends internal alert when items are low',
                style: TextStyle(fontSize: 12)),
            value: supplier.autoNotifyLowStock,
            onChanged: (v) {
              context
                  .read<InventoryProvider>()
                  .saveSupplier(supplier.copyWith(autoNotifyLowStock: v));
            },
          ),
        ),
        const SizedBox(height: 32),

        ElevatedButton.icon(
          onPressed: () => _showEditSheet(context),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('EDIT SUPPLIER DETAILS'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Widget _infoTile(
      BuildContext context, IconData icon, String label, String value,
      {Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold)),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  void _launchAction(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SupplierSheet(supplier: supplier),
    );
  }
}

// ── PRODUCTS TAB ─────────────────────────────────────────────────────────────

class _ProductsTab extends StatefulWidget {
  final Supplier supplier;
  const _ProductsTab({required this.supplier});

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final supplierProducts = inventory.products
        .where((p) => p.supplierId == widget.supplier.id)
        .toList();

    final filteredProducts = supplierProducts.where((p) {
      final q = _searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          (p.brand != null && p.brand!.toLowerCase().contains(q)) ||
          (p.barcode != null && p.barcode!.contains(q));
    }).toList();

    return Column(
      children: [
        // ── Search & Actions Bar ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search supplied products...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _searchQuery = '';
                          }),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showAddProductSheet(context, widget.supplier.id),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add New Product',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showLinkExistingModal(context, widget.supplier),
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Link Existing',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // ── Products List ────────────────────────────────────────────────────
        Expanded(
          child: filteredProducts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _searchQuery.isNotEmpty
                              ? Icons.search_off_rounded
                              : Icons.inventory_2_outlined,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No products match "$_searchQuery"'
                              : 'No products assigned to ${widget.supplier.name} yet.',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'Try searching with another keyword.'
                              : 'Create a new product or link existing inventory products to this supplier.',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        if (_searchQuery.isEmpty) ...[
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _showAddProductSheet(
                                    context, widget.supplier.id),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('ADD NEW PRODUCT'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _showLinkExistingModal(
                                    context, widget.supplier),
                                icon: const Icon(Icons.link_rounded, size: 18),
                                label: const Text('LINK EXISTING PRODUCTS'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredProducts.length,
                  itemBuilder: (ctx, index) {
                    final p = filteredProducts[index];
                    final bool isLowStock = p.totalStock <= p.lowStockThreshold;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isLowStock
                            ? BorderSide(color: Colors.orange.shade200)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(Icons.inventory_2_outlined,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                        title: Text(p.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              '${p.category}${p.brand != null && p.brand!.isNotEmpty ? ' • ${p.brand}' : ''}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('Stock: ${p.formattedBulkStock}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isLowStock
                                          ? Colors.orange.shade900
                                          : Colors.black87,
                                    )),
                                if (isLowStock) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('LOW STOCK',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange)),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(formatPeso(p.price),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                Text('Cost: ${formatPeso(p.costPrice)}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            PopupMenuButton<String>(
                              icon:
                                  const Icon(Icons.more_vert_rounded, size: 20),
                              onSelected: (val) {
                                if (val == 'edit') {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(24))),
                                    builder: (_) =>
                                        ProductEditSheet(product: p),
                                  );
                                } else if (val == 'unlink') {
                                  _confirmUnlinkProduct(
                                      context, p, widget.supplier.name);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(width: 12),
                                      Text('Edit Product'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'unlink',
                                  child: Row(
                                    children: [
                                      Icon(Icons.link_off_rounded,
                                          size: 18, color: Colors.red),
                                      SizedBox(width: 12),
                                      Text('Unlink from Supplier',
                                          style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
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

  void _confirmUnlinkProduct(
      BuildContext context, Product p, String supplierName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Product?'),
        content: Text(
            'Remove "${p.name}" from supplier "$supplierName"? The product will remain in store inventory without an assigned supplier.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context
                  .read<InventoryProvider>()
                  .saveProduct(p.copyWith(supplierId: ''));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Unlinked "${p.name}" from $supplierName.')),
                );
              }
            },
            child: const Text('UNLINK',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── LINK EXISTING PRODUCTS MODAL ─────────────────────────────────────────────

class _LinkExistingProductsModal extends StatefulWidget {
  final Supplier supplier;
  const _LinkExistingProductsModal({required this.supplier});

  @override
  State<_LinkExistingProductsModal> createState() =>
      _LinkExistingProductsModalState();
}

class _LinkExistingProductsModalState
    extends State<_LinkExistingProductsModal> {
  final Set<String> _selectedIds = {};
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  bool _unassignedOnly = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final allProducts = inventory.products;

    // Filter available products
    final eligibleProducts = allProducts.where((p) {
      if (_unassignedOnly && p.supplierId != null && p.supplierId!.isNotEmpty) {
        return false;
      }
      final q = _searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          (p.brand != null && p.brand!.toLowerCase().contains(q));
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, sc) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle Bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Link Products to Supplier',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Target Supplier: ${widget.supplier.name}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            // Search & Filter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search products by name, category...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() {
                                _searchCtrl.clear();
                                _searchQuery = '';
                              }),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilterChip(
                        selected: _unassignedOnly,
                        label: const Text('Unassigned Only',
                            style: TextStyle(fontSize: 11)),
                        onSelected: (v) => setState(() => _unassignedOnly = v),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedIds.length ==
                                eligibleProducts.length) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds
                                  .addAll(eligibleProducts.map((p) => p.id));
                            }
                          });
                        },
                        child: Text(
                          _selectedIds.length == eligibleProducts.length &&
                                  eligibleProducts.isNotEmpty
                              ? 'Deselect All'
                              : 'Select All (${eligibleProducts.length})',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 16),

            // Product List
            Expanded(
              child: eligibleProducts.isEmpty
                  ? const Center(
                      child: Text('No matching products found.',
                          style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.builder(
                      controller: sc,
                      itemCount: eligibleProducts.length,
                      itemBuilder: (c, i) {
                        final p = eligibleProducts[i];
                        final isSelected = _selectedIds.contains(p.id);
                        final isCurrentSupplier =
                            p.supplierId == widget.supplier.id;

                        // Lookup other supplier name if assigned
                        String? otherSupplierName;
                        if (p.supplierId != null &&
                            p.supplierId!.isNotEmpty &&
                            !isCurrentSupplier) {
                          otherSupplierName = inventory.suppliers
                              .firstWhere((s) => s.id == p.supplierId,
                                  orElse: () =>
                                      Supplier(id: '', name: 'Unknown'))
                              .name;
                        }

                        return CheckboxListTile(
                          value: isSelected || isCurrentSupplier,
                          onChanged: isCurrentSupplier
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedIds.add(p.id);
                                    } else {
                                      _selectedIds.remove(p.id);
                                    }
                                  });
                                },
                          title: Text(p.name,
                              style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                          subtitle: Text(
                            isCurrentSupplier
                                ? 'Already assigned to this supplier'
                                : otherSupplierName != null
                                    ? 'Current supplier: $otherSupplierName'
                                    : 'Stock: ${p.formattedBulkStock} • ${formatPeso(p.price)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isCurrentSupplier
                                  ? Colors.green
                                  : otherSupplierName != null
                                      ? Colors.orange.shade800
                                      : Colors.grey,
                            ),
                          ),
                          secondary: isCurrentSupplier
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green)
                              : null,
                        );
                      },
                    ),
            ),

            // Bottom Action
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _selectedIds.isEmpty || _isSaving
                    ? null
                    : () async {
                        setState(() => _isSaving = true);
                        try {
                          await context
                              .read<InventoryProvider>()
                              .bulkAssignSupplier(
                                  _selectedIds.toList(), widget.supplier.id);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Successfully linked ${_selectedIds.length} product(s) to ${widget.supplier.name}!')),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Error linking products: $e')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isSaving = false);
                        }
                      },
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.link_rounded),
                label: Text(_isSaving
                    ? 'LINKING PRODUCTS...'
                    : 'LINK ${_selectedIds.length} PRODUCT${_selectedIds.length == 1 ? '' : 'S'} TO SUPPLIER'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper Sheet Launchers
void _showAddProductSheet(BuildContext context, String supplierId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => AddProductSheet(initialSupplierId: supplierId),
  );
}

void _showLinkExistingModal(BuildContext context, Supplier supplier) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LinkExistingProductsModal(supplier: supplier),
  );
}

// ── RESTOCK TAB ──────────────────────────────────────────────────────────────

class _RestockTab extends StatefulWidget {
  final Supplier supplier;
  const _RestockTab({required this.supplier});

  @override
  State<_RestockTab> createState() => _RestockTabState();
}

class _RestockTabState extends State<_RestockTab> {
  final Set<String> _manualIds = {};

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final restockProvider = context.watch<RestockProvider>();

    final lowStockItems = inventory.products
        .where((p) =>
            p.status == ProductStatus.published &&
            p.totalStock <= p.lowStockThreshold &&
            p.supplierId == widget.supplier.id)
        .toList();

    final manualItems =
        inventory.products.where((p) => _manualIds.contains(p.id)).toList();

    // Combine and remove duplicates just in case
    final allToRestock = {...lowStockItems, ...manualItems}.toList();

    // Active inquiries for this supplier
    final activeInquiries = restockProvider.inquiries
        .where((ri) =>
            ri.supplierId == widget.supplier.id &&
            (ri.status == RestockInquiryStatus.draft ||
                ri.status == RestockInquiryStatus.pending ||
                ri.status == RestockInquiryStatus.sent ||
                ri.status == RestockInquiryStatus.acknowledged ||
                ri.status == RestockInquiryStatus.partiallyFulfilled))
        .toList();

    // Show manually picked items always, and low-stock items not already in active inquiries
    final filteredToRestock = allToRestock.where((p) {
      if (_manualIds.contains(p.id)) return true;
      return !activeInquiries
          .any((ri) => ri.items.any((rii) => rii.productId == p.id));
    }).toList();

    final supplierProducts = inventory.products
        .where((p) => p.supplierId == widget.supplier.id)
        .toList();

    return RefreshIndicator(
      onRefresh: () => restockProvider.refresh(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (activeInquiries.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ACTIVE INQUIRIES',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold, letterSpacing: 1)),
                Text('${activeInquiries.length} pending',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...activeInquiries.map((ri) => _InquiryCard(inquiry: ri, supplierPhone: widget.supplier.phone)),
            const SizedBox(height: 24),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ITEMS TO RESTOCK',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold, letterSpacing: 1)),
              TextButton.icon(
                onPressed: () =>
                    _showManualPicker(supplierProducts, inventory.products),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('ADD MANUALLY',
                    style:
                        TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredToRestock.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: Colors.green, size: 48),
                      const SizedBox(height: 12),
                      const Text('No items selected for restock.',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text(
                          'All low-stock items are added to active inquiries above or are fully available.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                          textAlign: TextAlign.center),
                      if (supplierProducts.isEmpty) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () =>
                              _showLinkExistingModal(context, widget.supplier),
                          icon: const Icon(Icons.link_rounded, size: 16),
                          label: const Text('LINK PRODUCTS TO SUPPLIER'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: filteredToRestock
                    .map((p) => ListTile(
                          dense: true,
                          title: Text(p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              'Stock: ${p.totalStock} / Min: ${p.lowStockThreshold} ${p.unit}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(formatPeso(p.costPrice),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey)),
                              if (_manualIds.contains(p.id))
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _manualIds.remove(p.id)),
                                  icon: const Icon(Icons.close_rounded,
                                      size: 16, color: Colors.red),
                                ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                if (filteredToRestock.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'No items to restock. Selected items already have active inquiries.')),
                  );
                  return;
                }

                final count = await restockProvider.generateInquiries(
                  filteredToRestock,
                  [widget.supplier],
                  inventory.adminName,
                );

                if (context.mounted) {
                  if (count > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Generated $count restock inquiry draft(s) under Active Inquiries.'),
                        backgroundColor: Colors.green.shade800,
                      ),
                    );
                    setState(() => _manualIds.clear());
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'No new inquiry created. Selected items are already in an active inquiry.'),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('GENERATE INQUIRY'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                _showPurchaseOrderDialog(
                  context,
                  widget.supplier,
                  filteredToRestock,
                  inventory.adminName,
                );
              },
              icon: const Icon(Icons.description_outlined),
              label: const Text('GENERATE & SHARE SUPPLIER RESTOCK ORDER'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showPurchaseOrderDialog(
    BuildContext context,
    Supplier supplier,
    List<Product> products,
    String adminName,
  ) {
    final buffer = StringBuffer('[GDC SARI-SARI STORE] SUPPLIER RESTOCK ORDER\n');
    buffer.writeln('Supplier: ${supplier.name}');
    if (supplier.contactName.isNotEmpty) {
      buffer.writeln('Contact Person: ${supplier.contactName}');
    }
    buffer.writeln('Phone: ${supplier.phone}');
    buffer.writeln('Date: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}');
    buffer.writeln('----------------------------------------');
    buffer.writeln('Requested Supply Items:');

    double totalEstimatedCost = 0;

    for (final p in products) {
      final int reorderUnits = p.calculateSuggestedRestock();
      final int boxQty = (p.itemsPerCase != null && p.itemsPerCase! > 0)
          ? (reorderUnits / p.itemsPerCase!).ceil()
          : 1;
      final int totalUnits = (p.itemsPerCase != null && p.itemsPerCase! > 0)
          ? (boxQty * p.itemsPerCase!)
          : reorderUnits;

      final double itemCost = totalUnits * p.costPrice;
      totalEstimatedCost += itemCost;

      if (p.itemsPerCase != null && p.itemsPerCase! > 0) {
        buffer.writeln(
            '- ${p.name}: $boxQty Boxes ($totalUnits ${p.unit}) ~ ${formatPeso(itemCost)}');
      } else {
        buffer.writeln(
            '- ${p.name}: $totalUnits ${p.unit} ~ ${formatPeso(itemCost)}');
      }
    }

    buffer.writeln('----------------------------------------');
    buffer.writeln('Estimated Supply Total: ${formatPeso(totalEstimatedCost)}');
    buffer.writeln('Authorized By: $adminName');

    final poText = buffer.toString();

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Supplier Restock Order Summary'),
        content: Container(
          width: 480,
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.3)),
                  ),
                  child: SelectableText(
                    poText,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: poText));
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Supplier Restock Order copied to clipboard! 📋')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Restock Order'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: poText));
              final smsUrl =
                  'sms:${supplier.phone}?body=${Uri.encodeComponent(poText)}';
              final uri = Uri.parse(smsUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Restock Order copied to clipboard! Paste directly into messaging app.')),
                );
              }
            },
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Share via SMS'),
          ),
        ],
      ),
    );
  }

  void _showManualPicker(
      List<Product> supplierProducts, List<Product> allProducts) {
    bool showAll = supplierProducts.isEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final displayProducts = showAll ? allProducts : supplierProducts;

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.9,
            builder: (ctx, sc) => Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Select Products to Restock',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded)),
                      ],
                    ),
                  ),
                  if (supplierProducts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Supplier Products'),
                            selected: !showAll,
                            onSelected: (v) =>
                                setModalState(() => showAll = !v),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('All Store Products'),
                            selected: showAll,
                            onSelected: (v) => setModalState(() => showAll = v),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Expanded(
                    child: displayProducts.isEmpty
                        ? const Center(
                            child: Text('No products available to select.'),
                          )
                        : ListView.builder(
                            controller: sc,
                            itemCount: displayProducts.length,
                            itemBuilder: (c, i) {
                              final p = displayProducts[i];
                              final bool isSelected = _manualIds.contains(p.id);
                              final bool isLowStock =
                                  p.totalStock <= p.lowStockThreshold;

                              return CheckboxListTile(
                                title: Text(p.name,
                                    style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal)),
                                subtitle: Text(
                                    'Stock: ${p.formattedBulkStock} • Cost: ${formatPeso(p.costPrice)}'),
                                secondary: isLowStock
                                    ? const Icon(Icons.warning_amber_rounded,
                                        color: Colors.orange)
                                    : null,
                                value: isSelected,
                                onChanged: (v) {
                                  setModalState(() {
                                    if (v == true) {
                                      _manualIds.add(p.id);
                                      // If product belongs to another or no supplier, assign it to this supplier on manual restock select
                                      if (p.supplierId != widget.supplier.id) {
                                        context
                                            .read<InventoryProvider>()
                                            .saveProduct(p.copyWith(
                                                supplierId:
                                                    widget.supplier.id));
                                      }
                                    } else {
                                      _manualIds.remove(p.id);
                                    }
                                  });
                                  setState(() {});
                                },
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('DONE SELECTING'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final String supplierId;
  const _HistoryTab({required this.supplierId});

  @override
  Widget build(BuildContext context) {
    final restock = context.watch<RestockProvider>();
    final history = restock.inquiries
        .where((ri) =>
            ri.supplierId == supplierId &&
            (ri.status == RestockInquiryStatus.fulfilled ||
                ri.status == RestockInquiryStatus.cancelled))
        .toList();

    if (history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 64, color: Colors.black12),
            SizedBox(height: 16),
            Text('No restock history for this supplier.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final ri = history[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(ri.inquiryNumber,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                'Sent: ${DateFormat('MMM dd, yyyy').format(ri.sentAt ?? ri.createdAt)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () =>
                      sendRestockEmail(context, ri, updateStatus: false),
                  icon: const Icon(Icons.email_outlined,
                      color: Colors.blue, size: 20),
                  tooltip: 'Resend Email',
                ),
                _StatusBadge(status: ri.status),
              ],
            ),
            onTap: () => _showHistoryDetails(context, ri),
          ),
        );
      },
    );
  }

  void _showHistoryDetails(BuildContext context, RestockInquiry ri) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restock Order #${ri.inquiryNumber}'),
        content: Container(
          width: 480,
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusBadge(status: ri.status),
                const SizedBox(height: 12),
                Text('Total Ordered Value: ${formatPeso(ri.totalOrderedValue)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                Text(
                    'Total Received Value: ${formatPeso(ri.totalReceivedValue)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.green)),
                const Divider(height: 20),
                const Text('AUDITED ITEMS:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                ...ri.items.map((i) {
                  final int recQty = i.receivedQty ?? i.requestedQty;
                  final int diff = recQty - i.requestedQty;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.productName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Ordered: ${i.requestedQty} ${i.unit}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              Text('Received: $recQty ${i.unit}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green)),
                            ],
                          ),
                          if (diff != 0)
                            Text(
                              diff < 0
                                  ? 'Shortage: ${diff.abs()} ${i.unit}'
                                  : 'Surplus: +$diff ${i.unit}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: diff < 0
                                      ? Colors.orange.shade900
                                      : Colors.blue),
                            ),
                          if (i.discrepancyNote != null &&
                              i.discrepancyNote!.isNotEmpty)
                            Text('Note: ${i.discrepancyNote}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              sendRestockEmail(context, ri, updateStatus: false);
            },
            child: const Text('RESEND EMAIL'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
        ],
      ),
    );
  }
}

class _InquiryCard extends StatefulWidget {
  final RestockInquiry inquiry;
  final String supplierPhone;
  const _InquiryCard({required this.inquiry, required this.supplierPhone});

  @override
  State<_InquiryCard> createState() => _InquiryCardState();
}

class _InquiryCardState extends State<_InquiryCard> {
  Timer? _timer;
  String _timeAgo = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _updateTime();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTime() {
    setState(() {
      _timeAgo =
          formatTimeAgo(widget.inquiry.sentAt ?? widget.inquiry.createdAt);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inquiry = widget.inquiry;
    final bool isSent = inquiry.status == RestockInquiryStatus.sent ||
        inquiry.status == RestockInquiryStatus.acknowledged;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: isSent ? Colors.green.shade100 : Colors.blue.shade100)),
      child: Column(
        children: [
          ListTile(
            title: Text(inquiry.inquiryNumber,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Row(
              children: [
                Text('${inquiry.items.length} items'),
                const SizedBox(width: 8),
                const Text('•', style: TextStyle(color: Colors.grey)),
                const SizedBox(width: 8),
                Text(_timeAgo,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.blueGrey)),
              ],
            ),
            trailing: _StatusBadge(status: inquiry.status),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                if (inquiry.status == RestockInquiryStatus.draft)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => sendRestockEmail(context, inquiry),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('SEND INQUIRY'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                  )
                else ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) =>
                              ReceiveDeliverySheet(inquiry: inquiry),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 16),
                      label: const Text('VERIFY & RECEIVE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade800,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => context
                        .read<RestockProvider>()
                        .updateStatus(
                            inquiry.id, RestockInquiryStatus.cancelled),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                if (inquiry.status == RestockInquiryStatus.draft) ...[
                  IconButton(
                    onPressed: () => _showEditSheet(context),
                    icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                    tooltip: 'Edit Inquiry',
                  ),
                  IconButton(
                    onPressed: () => sendRestockSms(context, inquiry, widget.supplierPhone),
                    icon: const Icon(Icons.message_outlined, color: Colors.blue),
                    tooltip: 'Send via SMS',
                  ),
                  const SizedBox(width: 8),
                ],
                if (inquiry.status == RestockInquiryStatus.sent ||
                    inquiry.status == RestockInquiryStatus.acknowledged ||
                    inquiry.status == RestockInquiryStatus.partiallyFulfilled) ...[
                  IconButton(
                    onPressed: () {
                      sendRestockEmail(context, inquiry);
                      context.read<RestockProvider>().resendInquiry(inquiry);
                    },
                    icon: const Icon(Icons.email_outlined, color: Colors.blue),
                    tooltip: 'Resend Email',
                  ),
                  IconButton(
                    onPressed: () => sendRestockSms(context, inquiry, widget.supplierPhone),
                    icon: const Icon(Icons.message_outlined, color: Colors.blue),
                    tooltip: 'Resend via SMS',
                  ),
                ],
                IconButton(
                  onPressed: () => _confirmDelete(context, inquiry),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.red),
                ),
              ],
            ),
          ),
          if (isSent && widget.inquiry.sentAt != null)
            if (DateTime.now().difference(widget.inquiry.sentAt!).inHours >= 1)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('No response from supplier? Try resending or calling.',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => RestockInquirySheet(inquiry: widget.inquiry),
    );
  }

  void _confirmDelete(BuildContext context, RestockInquiry ri) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Inquiry?'),
        content: const Text(
            'This will remove the tracking record. The items will become eligible for a new restock inquiry.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
              onPressed: () {
                context.read<RestockProvider>().deleteInquiry(ri.id);
                Navigator.pop(ctx);
              },
              child: const Text('DELETE', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}

void sendRestockEmail(BuildContext context, RestockInquiry inquiry,
    {bool updateStatus = true}) async {
  final buffer = StringBuffer('Dear ${inquiry.supplierName},\n\n');
  buffer.writeln(
      'Good day! We would like to request a restock for the following items:\n');
  for (final item in inquiry.items) {
    buffer.writeln('• ${item.productName} (SKU: ${item.sku})');
    buffer.writeln('  Requested Quantity: ${item.requestedQty} ${item.unit}');
    buffer.writeln('');
  }
  buffer.writeln('\nReference Number: ${inquiry.inquiryNumber}');
  buffer.writeln(
      'Please let us know the total amount and estimated delivery date. Thank you!\n\nBest regards,\nGDC Sari-Sari Store');

  final body = buffer.toString();
  final subject = 'Restock Request: ${inquiry.inquiryNumber}';
  final email = inquiry.supplierContact ?? '';

  final String gmailIntent =
      'intent:#Intent;action=android.intent.action.SENDTO;dat=mailto:$email;sub=${Uri.encodeComponent(subject)};body=${Uri.encodeComponent(body)};package=com.google.android.gm;end';

  final Uri mailtoUri = Uri(
    scheme: 'mailto',
    path: email,
    query:
        'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );

  try {
    bool launched = false;

    if (Theme.of(context).platform == TargetPlatform.android) {
      final Uri intentUri = Uri.parse(gmailIntent);
      if (await canLaunchUrl(intentUri)) {
        launched = await launchUrl(intentUri);
      }
    }

    if (!launched) {
      if (await canLaunchUrl(mailtoUri)) {
        launched =
            await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      }
    }

    if (launched) {
      if (updateStatus && context.mounted) {
        context.read<RestockProvider>().sendInquiry(inquiry);
      }
    } else {
      await Clipboard.setData(ClipboardData(text: body));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not open Gmail. Details copied to clipboard.')));
      }
    }
  } catch (e) {
    debugPrint('Gmail Launch Error: $e');
    await Clipboard.setData(ClipboardData(text: body));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error opening email app.')));
    }
  }
}

void sendRestockSms(BuildContext context, RestockInquiry inquiry, String phone,
    {bool updateStatus = true}) async {
  if (phone.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier phone number is missing.')),
      );
    }
    return;
  }

  final buffer = StringBuffer('Hello ${inquiry.supplierName},\n\n');
  buffer.writeln(
      'This is GDC Store regarding Restock Supply Inquiry #${inquiry.inquiryNumber}.\n');
  buffer.writeln('Requested supply items:');
  for (final item in inquiry.items) {
    buffer.writeln('• ${item.productName}: ${item.requestedQty} ${item.unit}');
  }
  buffer.writeln('\nPlease confirm supply availability and pricing. Thank you!');

  final msg = buffer.toString();
  final smsUrl = 'sms:$phone?body=${Uri.encodeComponent(msg)}';
  final uri = Uri.parse(smsUrl);

  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      if (updateStatus && context.mounted) {
        context.read<RestockProvider>().sendInquiry(inquiry);
      }
    } else {
      await Clipboard.setData(ClipboardData(text: msg));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not open SMS app. Details copied to clipboard!')),
        );
      }
    }
  } catch (e) {
    debugPrint('SMS Launch Error: $e');
    await Clipboard.setData(ClipboardData(text: msg));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error launching SMS app.')));
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final RestockInquiryStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color = switch (status) {
      RestockInquiryStatus.draft => Colors.grey,
      RestockInquiryStatus.pending => Colors.orange,
      RestockInquiryStatus.sent => Colors.blue,
      RestockInquiryStatus.acknowledged => Colors.cyan,
      RestockInquiryStatus.partiallyFulfilled => Colors.purple,
      RestockInquiryStatus.fulfilled => Colors.green,
      RestockInquiryStatus.cancelled => Colors.red,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(status.name.toUpperCase(),
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
