import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../models/product.dart';
import '../../widgets/scanner_dialog.dart';
import '../../widgets/product_edit_sheet.dart';
import '../../providers/inventory_provider.dart';
import '../../utils/barcode_routing.dart';
import 'supplier_management_screen.dart';
import '../config/theme.dart';
import '../../utils/format.dart';

class InventoryScreen extends StatefulWidget {
  final String? initialCategory;
  const InventoryScreen({super.key, this.initialCategory});
  @override State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Map<FocusNode, TextEditingController> _focusMap = {};
  String _search = '';
  late String _cat;

  @override
  void initState() {
    super.initState();
    _cat = widget.initialCategory ?? 'All';
    _focusMap = {
      _searchFocus: _searchCtrl,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategory != oldWidget.initialCategory && widget.initialCategory != null) {
      _cat = widget.initialCategory!;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();

    if (inventory.isLoading && inventory.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final settings = inventory.settings;
    final products  = inventory.sortedProducts;
    final cats      = ['All', 'Low Stock', ...settings.masterCategories];
    final filtered = products
        .where((p) {
          final threshold = p.lowStockThreshold;
          if (_cat == 'Low Stock') return p.totalStock <= threshold;
          return _cat == 'All' || p.category == _cat;
        })
        .where((p) {
          final query = _search.toLowerCase();
          return query.isEmpty ||
                 p.name.toLowerCase().contains(query) ||
                 (p.barcode != null && p.barcode!.toLowerCase().contains(query));
        })
        .toList();

    return BarcodeInterceptor(
      controllers: _focusMap,
      barcodeFocus: _searchFocus,
      onBarcodeDetected: (code) {
        String searchText = code;
        try {
          final p = products.firstWhere((p) => p.barcode == code);
          searchText = p.name;
        } catch (_) {}
        _searchCtrl.text = searchText;
        setState(() => _search = searchText);
        _searchFocus.requestFocus();
      },
      onTextDetected: (text) {
        _searchCtrl.text = text;
        setState(() => _search = text);
        _searchFocus.requestFocus();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: GdcColors.primaryGreen,
          foregroundColor: Colors.white,
          heroTag: 'inventory_fab',
          onPressed: () => _showSheet(context, null),
          icon:  const Icon(Icons.add_rounded),
          label: const Text('New Product'),
        ),
        body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text('Inventory',
                style: Theme.of(context).textTheme.headlineMedium)),

        // Search
        Padding(padding: const EdgeInsets.all(12),
            child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search), 
                    hintText: 'Search products…',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_search.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _search = '';
                              _searchFocus.requestFocus();
                            }),
                          ),
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () async {
                            final res = await showDialog<String>(context: context, useRootNavigator: true, builder: (_) => const ScannerDialog());
                            if (res != null) {
                              // If it's a barcode we know, show the name in the search bar
                              String searchText = res;
                              try {
                                final p = products.firstWhere((p) => p.barcode == res);
                                searchText = p.name;
                              } catch (_) {}
                              
                              _searchCtrl.text = searchText;
                              setState(() => _search = searchText);
                            }
                          },
                        ),
                      ],
                    )))),

        // Category filter
        SizedBox(height: 48, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => FilterChip(
                label: Text(cats[i], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                selected: _cat == cats[i],
                onSelected: (_) => setState(() {
                  _cat = cats[i];
                  if (_cat == 'All') {
                    _searchCtrl.clear();
                    _search = '';
                  }
                })))),

        if (_cat == 'Low Stock')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierManagementScreen())),
              icon: const Icon(Icons.local_shipping_rounded, size: 18),
              label: const Text('MANAGE RESTOCKS BY SUPPLIER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

        const SizedBox(height: 8),

        // Product list
        Expanded(child: RefreshIndicator(
          onRefresh: () async {
            // Re-initialize to force fresh stream
            context.read<InventoryProvider>().initialize();
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: products.isEmpty 
              ? const Center(child: CircularProgressIndicator())
              : (filtered.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.5,
                        alignment: Alignment.center,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade200),
                          const SizedBox(height: 16),
                          const Text('No products matching filters', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                          TextButton(onPressed: () => setState(() { _search = ''; _cat = 'All'; }), child: const Text('Clear all filters')),
                        ]),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _ProductRow(
                        product: filtered[i],
                        onEdit:  () => _showSheet(context, filtered[i]),
                      ))),
        )),
      ])),
    ));
  }

  void _showSheet(BuildContext context, Product? product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ProductEditSheet(product: product),
    );
  }
}

// ── Product row ────────────────────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  const _ProductRow({required this.product, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final threshold = product.lowStockThreshold;
    final int effectiveStock = product.totalStock;
    final isLow = effectiveStock <= threshold;
    final now = DateTime.now();
    final isExpired = product.expiryDate != null && product.expiryDate!.isBefore(now);
    final isNearExpiry = product.expiryDate != null && 
                        !isExpired && 
                        product.expiryDate!.isBefore(now.add(const Duration(days: 7)));

    final priceRange = product.hasVariants 
        ? (product.variants.map((v) => v.price).toSet().length > 1 
            ? '${formatPeso(product.variants.map((v) => v.price).reduce((a, b) => a < b ? a : b))} - ${formatPeso(product.variants.map((v) => v.price).reduce((a, b) => a > b ? a : b))}'
            : formatPeso(product.variants.first.price))
        : formatPeso(product.price);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.light 
                ? Colors.black.withValues(alpha: 0.02) 
                : Colors.transparent,
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isLow || isExpired
                ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1)
                : isNearExpiry ? Theme.of(context).semantic.warning.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Opacity(
            opacity: product.status == ProductStatus.draft ? 0.5 : 1.0,
            child: product.photoBase64 != null
                ? Image.memory(base64Decode(product.photoBase64!), fit: BoxFit.cover)
                : Icon(
                    isExpired ? Icons.event_busy_rounded : (isLow ? Icons.warning_amber_rounded : Icons.inventory_2_rounded),
                    color: isExpired || isLow
                        ? Theme.of(context).colorScheme.error
                        : isNearExpiry ? Theme.of(context).semantic.warning : Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (product.brand != null && product.brand!.isNotEmpty)
              Text(
                product.brand!.toUpperCase(),
                style: BrandStyling.getStyle(product.brand, fontSize: 10).copyWith(letterSpacing: 1),
              ),
            Row(
              children: [
                Expanded(child: Text(product.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.2))),
                if (product.status == ProductStatus.draft)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                    child: const Text('DRAFT', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w900)),
                  ),
              ],
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(6)),
                  child: Text(product.category, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                ),
                if (product.hasVariants)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text('${product.variants.length} VARIANTS', style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w800)),
                  ),
                if (product.isPerishable)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Theme.of(context).semantic.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text('Shelf: ${product.shelfDays}d', style: TextStyle(fontSize: 10, color: Theme.of(context).semantic.warning, fontWeight: FontWeight.w800)),
                  ),
                if (product.expiryDate != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: isExpired ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1) : (isNearExpiry ? Theme.of(context).semantic.warning.withValues(alpha: 0.1) : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(
                        isExpired ? 'EXPIRED' : 'Exp: ${DateFormat('MM/dd/yy').format(product.expiryDate!)}',
                        style: TextStyle(
                            fontSize: 10, 
                            color: isExpired ? Theme.of(context).colorScheme.error : (isNearExpiry ? Theme.of(context).semantic.warning : Theme.of(context).colorScheme.primary),
                            fontWeight: FontWeight.w900)),
                  ),
                if (product.isOutOfStockForCustomer && product.status == ProductStatus.published)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Text('CUSTOMER OOS (15%)', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w800)),
                  ),
              ]),
              if (product.hasVariants)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Text(
                    product.variants.map((v) => '${v.name} (${v.stock})').join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min, children: [
                Text(priceRange,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: product.hasVariants ? 12 : 16, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLow ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1) : Theme.of(context).semantic.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('$effectiveStock ${product.unit}',
                      style: TextStyle(
                          fontSize: 10,
                          color: isLow ? Theme.of(context).colorScheme.error : Theme.of(context).semantic.success,
                          fontWeight: FontWeight.w900)),
                ),
              ]),
          const SizedBox(width: 8),
          IconButton(
              icon: Icon(Icons.edit_note_rounded, color: Colors.grey.shade400),
              onPressed: onEdit),
        ]),
      ),
    );
  }
}
