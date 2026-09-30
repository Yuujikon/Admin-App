import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/product.dart';
import '../../widgets/scanner_dialog.dart';
import '../../widgets/product_edit_sheet.dart';
import '../../widgets/add_product_sheet.dart';
import '../../widgets/receive_delivery_sheet.dart';
import '../../widgets/batch_audit_sheet.dart';
import '../../widgets/barcode_print_dialog.dart';
import '../../providers/inventory_provider.dart';
import '../../utils/barcode_routing.dart';
import '../../utils/responsive.dart';
import 'product_detail_screen.dart';
import 'supplier_management_screen.dart';
import 'inventory_records_screen.dart';
import '../config/theme.dart';
import '../../utils/format.dart';

class InventoryScreen extends StatefulWidget {
  final String? initialCategory;
  const InventoryScreen({super.key, this.initialCategory});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
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
  }

  @override
  void didUpdateWidget(InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategory != oldWidget.initialCategory &&
        widget.initialCategory != null) {
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
    final products = inventory.sortedProducts;
    final cats = ['All', 'Low Stock', ...settings.masterCategories];
    final filtered = products.where((p) {
      final threshold = p.lowStockThreshold;
      if (_cat == 'Low Stock') return p.totalStock <= threshold;
      return _cat == 'All' || p.category == _cat;
    }).where((p) {
      final query = _search.toLowerCase();
      return query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          (p.brand != null && p.brand!.toLowerCase().contains(query)) ||
          (p.parentId != null && p.parentId!.toLowerCase().contains(query)) ||
          (p.barcode != null && p.barcode!.toLowerCase().contains(query));
    }).toList();

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double availableWidth = constraints.maxWidth;
          final bool isCompact = availableWidth < Responsive.compactBreakpoint;

          return Container(
            color: Theme.of(context).colorScheme.surface,
            child: RefreshIndicator(
              onRefresh: () async {
                context.read<InventoryProvider>().initialize();
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Page Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          Text(
                            'Inventory',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const InventoryRecordsScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.history_edu_rounded,
                                    size: 18),
                                label: const Text('Records'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(100, 44),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _showAddProductSheet(context),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('New Product'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: GdcColors.emeraldPrimary,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(110, 44),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _showReceiveDeliverySheet(context, null),
                                icon: const Icon(Icons.move_to_inbox_rounded,
                                    size: 18),
                                label: const Text('Quick Restock'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: GdcColors.darkEmerald,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(120, 44),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Search Bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onChanged: (v) => setState(() => _search = v),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
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
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                                onPressed: () async {
                                  final res = await showDialog<String>(
                                      context: context,
                                      useRootNavigator: true,
                                      builder: (_) => const ScannerDialog());
                                  if (res != null) {
                                    String searchText = res;
                                    try {
                                      final p = products.firstWhere(
                                          (p) => p.barcode == res);
                                      searchText = p.name;
                                    } catch (_) {}

                                    _searchCtrl.text = searchText;
                                    setState(() => _search = searchText);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // Category Chips Row
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: cats.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => FilterChip(
                          label: Text(cats[i]),
                          selected: _cat == cats[i],
                          onSelected: (_) => setState(() {
                            _cat = cats[i];
                            if (_cat == 'All') {
                              _searchCtrl.clear();
                              _search = '';
                            }
                          }),
                        ),
                      ),
                    ),
                  ),

                  // Low Stock Restock Banner
                  if (_cat == 'Low Stock')
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const SupplierManagementScreen())),
                          icon: const Icon(Icons.local_shipping_rounded,
                              size: 18),
                          label: const Text('MANAGE RESTOCKS BY SUPPLIER'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GdcColors.warningAmber,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // Product List
                  if (products.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text('No products matching filters',
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500)),
                            TextButton(
                              onPressed: () => setState(() {
                                _search = '';
                                _cat = 'All';
                              }),
                              child: const Text('Clear all filters'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final product = filtered[index];
                            return _ProductRow(
                              key: ValueKey(product.id),
                              product: product,
                              isCompact: isCompact,
                              onEdit: () => _showSheet(context, product),
                            );
                          },
                          childCount: filtered.length,
                        ),
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

  void _showAddProductSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddProductSheet(),
    );
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

  void _showReceiveDeliverySheet(BuildContext context, Product? product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReceiveDeliverySheet(initialProduct: product),
    );
  }
}

// ── Product Row ─────────────────────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  final Product product;
  final bool isCompact;
  final VoidCallback onEdit;

  const _ProductRow({
    super.key,
    required this.product,
    required this.isCompact,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final threshold = product.lowStockThreshold;
    final int effectiveStock = product.totalStock;
    final isLow = effectiveStock <= threshold;
    final now = DateTime.now();
    final isExpired =
        product.expiryDate != null && product.expiryDate!.isBefore(now);
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailScreen(product: product),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Thumbnail
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isLow || isExpired
                            ? Theme.of(context)
                                .colorScheme
                                .errorContainer
                                .withValues(alpha: 0.15)
                            : isNearExpiry
                                ? Theme.of(context)
                                    .semantic
                                    .warning
                                    .withValues(alpha: 0.15)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Opacity(
                        opacity:
                            product.status == ProductStatus.draft ? 0.5 : 1.0,
                        child: product.photoBase64 != null
                            ? Image.memory(base64Decode(product.photoBase64!),
                                fit: BoxFit.cover)
                            : Icon(
                                isExpired
                                    ? Icons.event_busy_rounded
                                    : (isLow
                                        ? Icons.warning_amber_rounded
                                        : Icons.inventory_2_rounded),
                                color: isExpired || isLow
                                    ? Theme.of(context).colorScheme.error
                                    : isNearExpiry
                                        ? Theme.of(context).semantic.warning
                                        : Theme.of(context).colorScheme.primary,
                                size: 26,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Product Information
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.brand != null &&
                              product.brand!.isNotEmpty)
                            Text(
                              product.brand!.toUpperCase(),
                              style: BrandStyling.getStyle(product.brand,
                                      fontSize: 10)
                                  .copyWith(letterSpacing: 0.8),
                            ),
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Badges Wrap
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  product.category,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (product.expiryDate != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isExpired
                                        ? Theme.of(context)
                                            .colorScheme
                                            .errorContainer
                                            .withValues(alpha: 0.15)
                                        : (isNearExpiry
                                            ? Theme.of(context)
                                                .semantic
                                                .warning
                                                .withValues(alpha: 0.15)
                                            : Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withValues(alpha: 0.15)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isExpired
                                        ? 'EXPIRED'
                                        : 'Exp: ${DateFormat('MM/dd/yy').format(product.expiryDate!)}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isExpired
                                          ? Theme.of(context).colorScheme.error
                                          : (isNearExpiry
                                              ? Theme.of(context)
                                                  .semantic
                                                  .warning
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .primary),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Price, Stock & Actions
                    if (!isCompact) ...[
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            priceRange,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isLow
                                  ? Theme.of(context)
                                      .colorScheme
                                      .errorContainer
                                      .withValues(alpha: 0.15)
                                  : Theme.of(context)
                                      .semantic
                                      .success
                                      .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$effectiveStock ${product.unit}',
                              style: TextStyle(
                                fontSize: 10,
                                color: isLow
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).semantic.success,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.qr_code_2_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20),
                            tooltip: 'Print Barcode Sticker',
                            onPressed: () =>
                                BarcodePrintDialog.show(context, product),
                          ),
                          IconButton(
                            icon: Icon(Icons.history_toggle_off_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20),
                            tooltip: 'Inspect Batches',
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) =>
                                    BatchAuditSheet(product: product),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_note_rounded,
                                size: 22, color: Colors.grey),
                            tooltip: 'Edit Product',
                            onPressed: onEdit,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                // Compact layout second line for Price, Stock, and Popup Actions
                if (isCompact) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        priceRange,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isLow
                              ? Theme.of(context)
                                  .colorScheme
                                  .errorContainer
                                  .withValues(alpha: 0.15)
                              : Theme.of(context)
                                  .semantic
                                  .success
                                  .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$effectiveStock ${product.unit}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isLow
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).semantic.success,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        constraints: const BoxConstraints(
                            minWidth: 40, minHeight: 40),
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.qr_code_2_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20),
                        tooltip: 'Print Barcode',
                        onPressed: () =>
                            BarcodePrintDialog.show(context, product),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                            minWidth: 40, minHeight: 40),
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.history_toggle_off_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20),
                        tooltip: 'Batches',
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => BatchAuditSheet(product: product),
                          );
                        },
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                            minWidth: 40, minHeight: 40),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.edit_note_rounded,
                            size: 22, color: Colors.grey),
                        tooltip: 'Edit',
                        onPressed: onEdit,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
