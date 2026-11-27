import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../models/restock_inquiry.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../providers/restock_provider.dart';
import '../services/inventory_batch_service.dart';
import '../utils/format.dart';
import '../utils/pricing_engine.dart';
import '../widgets/batch_audit_sheet.dart';
import '../widgets/product_edit_sheet.dart';
import '../widgets/receive_delivery_sheet.dart';
import '../widgets/barcode_print_dialog.dart';
import '../widgets/responsive_layout.dart';

/// A Master Product Detail Screen designed with M3 guidelines,
/// optimized for responsive cross-platform displays (Mobile, Tablet, Desktop/Web).
class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({
    super.key,
    required this.product,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  void _openEditSheet(BuildContext context, Product activeProduct) {
    ProductEditSheet.show(context: context, product: activeProduct);
  }

  void _openReceiveDeliverySheet(BuildContext context, Product activeProduct) {
    RestockInquiry? matchingInquiry;
    if (activeProduct.supplierId != null &&
        activeProduct.supplierId!.isNotEmpty) {
      final inquiries = context.read<RestockProvider>().inquiries;
      try {
        matchingInquiry = inquiries.firstWhere(
          (ri) =>
              ri.supplierId == activeProduct.supplierId &&
              (ri.status == RestockInquiryStatus.pending ||
                  ri.status == RestockInquiryStatus.sent ||
                  ri.status == RestockInquiryStatus.acknowledged ||
                  ri.status == RestockInquiryStatus.partiallyFulfilled) &&
              ri.items.any((item) => item.productId == activeProduct.id),
        );
      } catch (_) {}
    }

    ReceiveDeliverySheet.show(
      context: context,
      initialProduct: activeProduct,
      inquiry: matchingInquiry,
    );
  }

  void _openBatchAuditSheet(BuildContext context, Product activeProduct) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BatchAuditSheet(product: activeProduct),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();

    // Always fetch live product state from InventoryProvider if available
    Product p = widget.product;
    try {
      p = inventory.products.firstWhere(
        (prod) => prod.id == widget.product.id,
        orElse: () => widget.product,
      );
    } catch (_) {}

    Supplier? supplier;
    if (p.supplierId != null && p.supplierId!.isNotEmpty) {
      try {
        supplier = inventory.suppliers.firstWhere((s) => s.id == p.supplierId);
      } catch (_) {}
    }

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2_rounded),
            tooltip: 'Print Barcode / PLU Label',
            onPressed: () => BarcodePrintDialog.show(context, p),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Product',
            onPressed: () => _openEditSheet(context, p),
          ),
          IconButton(
            icon: const Icon(Icons.move_to_inbox_rounded),
            tooltip: 'Receive Stock',
            onPressed: () => _openReceiveDeliverySheet(context, p),
          ),
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'FIFO Batch Audit',
            onPressed: () => _openBatchAuditSheet(context, p),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              physics: const AlwaysScrollableScrollPhysics(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Identity Header Card (Full Width)
                      _IdentityHeaderCard(
                        product: p,
                        supplierName: supplier?.name,
                      ),
                      const SizedBox(height: 16),

                      // 2 & 3. Pricing & UOM Metrics / Live Inventory Health
                      ResponsiveCardGrid(
                        children: [
                          _PricingUomCard(product: p),
                          _LiveInventoryHealthCard(product: p),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // 3.5 Read-Only Inventory Allocation Card (100% POS / 75% Online / 25% Reserve)
                      _InventoryAllocationCard(product: p),

                      const SizedBox(height: 16),

                      // 4. Audit & FIFO Batch History Card
                      _AuditBatchCard(
                        product: p,
                        supplier: supplier,
                      ),

                      if (p.hasParentGroup) ...[
                        const SizedBox(height: 16),
                        _ParentGroupVariantsCard(currentProduct: p),
                      ],

                      const SizedBox(height: 20),

                      // Action Buttons Row
                      _QuickActionsRow(
                        product: p,
                        onEdit: () => _openEditSheet(context, p),
                        onReceive: () => _openReceiveDeliverySheet(context, p),
                        onAudit: () => _openBatchAuditSheet(context, p),
                      ),

                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. IDENTITY HEADER CARD
// ─────────────────────────────────────────────────────────────────────────────

class _IdentityHeaderCard extends StatelessWidget {
  final Product product;
  final String? supplierName;

  const _IdentityHeaderCard({
    required this.product,
    this.supplierName,
  });

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = theme.semantic;

    // Status styling
    final (statusLabel, statusBg, statusFg) = switch (product.status) {
      ProductStatus.published => (
          'Published',
          semantic.success.withValues(alpha: 0.12),
          semantic.success,
        ),
      ProductStatus.draft => (
          'Draft',
          semantic.warning.withValues(alpha: 0.12),
          semantic.warning,
        ),
      ProductStatus.archived => (
          'Archived',
          theme.disabledColor.withValues(alpha: 0.12),
          theme.disabledColor,
        ),
    };

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isStack = constraints.maxWidth < 460;

            final imageWidget = Container(
              width: isStack ? double.infinity : 150,
              height: isStack ? 180 : 150,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child:
                  product.photoBase64 != null && product.photoBase64!.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.memory(
                            base64Decode(product.photoBase64!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                _buildPlaceholderImage(colorScheme),
                          ),
                        )
                      : _buildPlaceholderImage(colorScheme),
            );

            final infoWidget = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Category & Status row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        product.category,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusFg,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Product Name
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),

                if (product.brand != null && product.brand!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Brand: ${product.brand}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],

                if (product.hasParentGroup) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_tree_outlined,
                            size: 12, color: Colors.purple.shade800),
                        const SizedBox(width: 4),
                        Text(
                          'Parent Group: ${product.parentId}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.purple.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // Barcode / SKU Pill
                if (product.barcode != null && product.barcode!.isNotEmpty)
                  InkWell(
                    onTap: () =>
                        _copyToClipboard(context, product.barcode!, 'Barcode'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              product.barcode!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.copy_rounded,
                            size: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    'No Barcode Assigned',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                const SizedBox(height: 10),

                // Supplemental Feature Chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (product.shelfDays != null)
                      _FeatureChip(
                        icon: Icons.timer_outlined,
                        label: 'Shelf: ${product.shelfDays}d',
                        color: semantic.info,
                      ),
                    if (product.isTaxable)
                      _FeatureChip(
                        icon: Icons.receipt_long_outlined,
                        label: 'Taxable',
                        color: colorScheme.primary,
                      ),
                    if (product.wholesalePrice != null &&
                        product.wholesalePrice! > 0)
                      _FeatureChip(
                        icon: Icons.local_offer_outlined,
                        label: 'Wholesale Tier',
                        color: semantic.success,
                      ),
                    if (product.hasVariants)
                      _FeatureChip(
                        icon: Icons.layers_outlined,
                        label: '${product.variants.length} Variants',
                        color: colorScheme.secondary,
                      ),
                  ],
                ),
              ],
            );

            if (isStack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  imageWidget,
                  const SizedBox(height: 14),
                  infoWidget,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                imageWidget,
                const SizedBox(width: 16),
                Expanded(child: infoWidget),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 42,
            color: colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 4),
          Text(
            'No Image',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _FeatureChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. PRICING & UOM METRICS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PricingUomCard extends StatelessWidget {
  final Product product;

  const _PricingUomCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = theme.semantic;

    final inventory = context.watch<InventoryProvider>();
    final liveVelocity = inventory.getLiveVelocityScore(product);
    final eval = PricingEngine.evaluateProductPricing(
      product.copyWith(salesVelocityScore: liveVelocity),
      settings: inventory.settings,
    );

    final activeUnitCost = product.activeFifoUnitCost;
    final profit = product.price - activeUnitCost;
    final marginPct = product.price > 0 ? (profit / product.price * 100) : 0.0;
    final isProfitable = profit >= 0;

    final double packCost = product.packCost ?? 0.0;
    final double derivedUnitCost = product.calculateUnitCostFromPack(packCost);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.payments_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pricing & Wholesale UOM',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Main Selling Price Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selling Price (Retail)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatPeso(product.price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Profit Margin Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isProfitable
                          ? semantic.success.withValues(alpha: 0.1)
                          : colorScheme.errorContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isProfitable
                              ? '+${formatPeso(profit)}'
                              : formatPeso(profit),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isProfitable
                                ? semantic.success
                                : colorScheme.error,
                          ),
                        ),
                        Text(
                          '${marginPct.toStringAsFixed(1)}% margin',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isProfitable
                                ? semantic.success
                                : colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Dynamic Velocity-Based Markup Metadata
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _FeatureChip(
                  icon: product.isManualPricing
                      ? Icons.lock_outline_rounded
                      : Icons.auto_awesome_rounded,
                  label: product.isManualPricing
                      ? 'Custom Admin Markup (${eval.computedMarkupPercent.toStringAsFixed(1)}%)'
                      : 'Auto-Scaled (${eval.computedMarkupPercent.toStringAsFixed(1)}%)',
                  color: product.isManualPricing
                      ? Colors.deepOrange.shade700
                      : colorScheme.primary,
                ),
                _FeatureChip(
                  icon: Icons.speed_rounded,
                  label:
                      '${eval.speedTag} (${eval.velocityScore.toStringAsFixed(2)})',
                  color: eval.speedTag == 'Fast Moving'
                      ? semantic.success
                      : (eval.speedTag == 'Slow Moving'
                          ? semantic.warning
                          : semantic.info),
                ),
              ],
            ),

            if (eval.hasInvalidCost) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Zero or missing unit cost — dynamic markup calculation is paused until a valid cost is set.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Active FIFO Unit Cost
            _DetailRow(
              label: product.activeFifoBatch != null
                  ? 'Active FIFO Unit Cost'
                  : 'Unit Cost (COGS)',
              value: '${formatPeso(activeUnitCost)} / ${product.unit}',
              isBoldValue: true,
            ),
            const SizedBox(height: 6),
            _DetailRow(
              label: 'Category Markup Range',
              value: eval.usedGlobalBenchmarkOnly
                  ? '15.0% – 25.0% (Global)'
                  : '${eval.categoryRange.formattedRange} (${eval.categoryRange.canonicalCategory})',
            ),

            const Divider(height: 16),

            // UOM Wholesale Metrics Header
            Text(
              'Wholesale Math (${product.bulkUnit.toUpperCase()})',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),

            _DetailRow(
              label: 'Items per Box / Case',
              value:
                  '${product.piecesPerPack} ${product.unit} per ${product.bulkUnit}',
            ),

            _DetailRow(
              label: 'Bulk Pack Cost',
              value: packCost > 0
                  ? '${formatPeso(packCost)} / ${product.bulkUnit}'
                  : 'Not Set',
              isBoldValue: packCost > 0,
            ),

            _DetailRow(
              label: 'Derived Pack Unit Cost',
              value: packCost > 0
                  ? '${formatPeso(derivedUnitCost)} / ${product.unit}'
                  : 'N/A',
              valueColor: (packCost > 0 && derivedUnitCost < product.costPrice)
                  ? semantic.success
                  : null,
            ),

            if (product.wholesalePrice != null &&
                product.wholesalePrice! > 0) ...[
              const Divider(height: 16),
              _DetailRow(
                label: 'Wholesale Price Tier',
                value: formatPeso(product.wholesalePrice!),
                isBoldValue: true,
                valueColor: semantic.success,
              ),
              _DetailRow(
                label: 'Min Wholesale Qty',
                value: '>= ${product.wholesaleThreshold ?? 1} ${product.unit}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. LIVE INVENTORY HEALTH CARD
// ─────────────────────────────────────────────────────────────────────────────

class _LiveInventoryHealthCard extends StatelessWidget {
  final Product product;

  const _LiveInventoryHealthCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = theme.semantic;

    final totalStock = product.totalStock;
    final alertThreshold = product.lowStockAlertThreshold;
    final originalStock = product.effectiveOriginalStock;
    final isOutOfStock = totalStock <= 0;
    final isLowStock = !isOutOfStock && product.isPhysicalThresholdHit;

    final (bannerText, bannerBg, bannerFg, bannerIcon) = isOutOfStock
        ? (
            'OUT OF STOCK',
            colorScheme.errorContainer.withValues(alpha: 0.2),
            colorScheme.error,
            Icons.error_outline_rounded,
          )
        : isLowStock
            ? (
                'LOW STOCK WARNING',
                semantic.warning.withValues(alpha: 0.15),
                semantic.warning,
                Icons.warning_amber_rounded,
              )
            : (
                'HEALTHY STOCK',
                semantic.success.withValues(alpha: 0.12),
                semantic.success,
                Icons.check_circle_outline_rounded,
              );

    final reservedStock = product.totalReservedStock;
    final suggestedRestock = product.calculateSuggestedRestock();

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Live Inventory Status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Health Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bannerBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(bannerIcon, size: 18, color: bannerFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bannerText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: bannerFg,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Total Base Stock Highlight
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Base Stock',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$totalStock ${product.unit}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isOutOfStock
                              ? colorScheme.error
                              : (isLowStock
                                  ? semantic.warning
                                  : colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.analytics_outlined,
                    size: 28,
                    color: colorScheme.primary.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _DetailRow(
              label: 'Formatted Bulk Stock',
              value: product.formattedBulkStock,
              isBoldValue: true,
            ),

            _DetailRow(
              label: 'Physical Stock (POS)',
              value: '${product.totalStock} ${product.unit}',
              isBoldValue: true,
              valueColor: semantic.success,
            ),

            _DetailRow(
              label: 'Online Available (75% cap)',
              value: product.isOnlineOutOfStock
                  ? 'Out of Stock (0 ${product.unit})'
                  : '${product.onlineAvailableStock} ${product.unit}',
              isBoldValue: true,
              valueColor: product.isOnlineOutOfStock
                  ? colorScheme.error
                  : colorScheme.primary,
            ),

            _DetailRow(
              label: 'Walk-In Reserve (25%)',
              value: '${product.effectivePhysicalReserve} ${product.unit}',
              isBoldValue: true,
              valueColor: semantic.warning,
            ),

            _DetailRow(
              label: 'Reserved (Pending Pickups)',
              value: '$reservedStock ${product.unit}',
              valueColor: reservedStock > 0 ? semantic.warning : null,
            ),

            _DetailRow(
              label: 'Low Stock Alert (30%)',
              value: '≤ $alertThreshold ${product.unit} (of $originalStock)',
            ),

            const Divider(height: 16),

            _DetailRow(
              label: 'Suggested Restock Qty',
              value: '$suggestedRestock ${product.unit}',
              isBoldValue: true,
              valueColor: suggestedRestock > 0 ? colorScheme.primary : null,
            ),

            if (product.hasVariants) ...[
              const SizedBox(height: 12),
              Text(
                'Variants Breakdown (${product.variants.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Column(
                children: product.variants.map((v) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          v.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${v.stock} pcs • ${formatPeso(v.price)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. AUDIT & FIFO BATCH HISTORY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AuditBatchCard extends StatefulWidget {
  final Product product;
  final Supplier? supplier;

  const _AuditBatchCard({
    required this.product,
    this.supplier,
  });

  @override
  State<_AuditBatchCard> createState() => _AuditBatchCardState();
}

class _AuditBatchCardState extends State<_AuditBatchCard> {
  final InventoryBatchService _batchService = InventoryBatchService();
  bool _showDepleted = false;
  bool _ensuredLegacy = false;

  @override
  void initState() {
    super.initState();
    _initLegacyFallback();
  }

  Future<void> _initLegacyFallback() async {
    if (_ensuredLegacy) return;
    _ensuredLegacy = true;
    if (widget.product.stock > 0 && !widget.product.hasVariants) {
      try {
        await _batchService.ensureLegacyBatchIfNeeded(widget.product.id);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final inventory = context.watch<InventoryProvider>();
    final procurement = context.watch<ProcurementProvider>();
    final product = widget.product;
    final supplier = widget.supplier;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<List<ProductBatch>>(
          stream: _batchService.batchesStream(product.id),
          builder: (context, snapshot) {
            final List<ProductBatch> allBatches = snapshot.hasData
                ? List<ProductBatch>.from(snapshot.data!)
                : List<ProductBatch>.from(product.batches);
            allBatches.sort(ProductBatch.compareFifo);

            final activeBatches = allBatches.where((b) => b.isActive).toList();
            final depletedBatches =
                allBatches.where((b) => !b.isActive).toList();
            final visibleBatches = _showDepleted
                ? [...activeBatches, ...depletedBatches]
                : activeBatches;
            final String? oldestActiveId =
                activeBatches.isNotEmpty ? activeBatches.first.batchId : null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.history_outlined,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Audit & FIFO Batches',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (depletedBatches.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            setState(() => _showDepleted = !_showDepleted),
                        child: Text(
                          _showDepleted
                              ? 'Hide Depleted'
                              : 'Depleted (${depletedBatches.length})',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // Product Meta Audit Grid
                _DetailRow(
                  label: 'Supplier',
                  value: supplier?.name ??
                      (product.supplierId != null &&
                              product.supplierId!.isNotEmpty
                          ? 'ID: ${product.supplierId}'
                          : 'Unassigned / Direct'),
                  isBoldValue: supplier != null,
                ),

                _DetailRow(
                  label: 'Shelf Life',
                  value: product.shelfDays != null
                      ? '${product.shelfDays} Days'
                      : 'Non-Perishable / Unset',
                ),

                _DetailRow(
                  label: 'Pickup Window',
                  value: product.pickupWindowHours != null
                      ? '${product.pickupWindowHours} Hours'
                      : 'Standard',
                ),

                if (product.expiryDate != null)
                  _DetailRow(
                    label: 'Primary Product Expiry',
                    value: formatDate(product.expiryDate!),
                    isBoldValue: true,
                    valueColor: product.expiryDate!.isBefore(DateTime.now())
                        ? colorScheme.error
                        : null,
                  ),

                const Divider(height: 20),

                // Batches Sub-header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Active FIFO Batches (${activeBatches.length})',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                    if (allBatches.isNotEmpty)
                      Text(
                        'Sorted by Date Arrived (Oldest First)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                if (visibleBatches.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inventory_outlined,
                          size: 36,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          activeBatches.isEmpty && depletedBatches.isNotEmpty
                              ? 'All Batches Depleted'
                              : 'No Active FIFO Batches Registered',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activeBatches.isEmpty && depletedBatches.isNotEmpty
                              ? 'Tap "Depleted" above to inspect historical batches.'
                              : 'Receive stock to create tracked FIFO batches.',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visibleBatches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final batch = visibleBatches[index];
                      return _BatchTile(
                        batch: batch,
                        productUnit: product.unit,
                        isOldestActive:
                            batch.isActive && batch.batchId == oldestActiveId,
                        resolvedPoNumber:
                            procurement.resolvePoNumberForBatch(batch),
                        resolvedSupplierName:
                            procurement.resolveSupplierNameForBatch(
                          batch,
                          suppliers: inventory.suppliers,
                          fallbackProductSupplierId: product.supplierId,
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  final ProductBatch batch;
  final String productUnit;
  final bool isOldestActive;
  final String? resolvedPoNumber;
  final String? resolvedSupplierName;

  const _BatchTile({
    required this.batch,
    required this.productUnit,
    this.isOldestActive = false,
    this.resolvedPoNumber,
    this.resolvedSupplierName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = theme.semantic;

    final bool isDepleted = !batch.isActive;
    final days = batch.daysUntilExpiration;
    final isExpired = batch.isExpired;
    final isNearExpiry = batch.isNearExpiration;

    final Color fifoColor = isDepleted
        ? Colors.grey.shade600
        : (isOldestActive ? Colors.green.shade700 : Colors.blue.shade700);
    final String fifoBadge = isDepleted
        ? 'DEPLETED'
        : (isOldestActive ? 'SELLING NOW (OLDEST)' : 'QUEUED (NEWER)');

    final String? formattedPo =
        (resolvedPoNumber != null && resolvedPoNumber!.trim().isNotEmpty)
            ? ProductBatch.formatPoNumber(resolvedPoNumber!)
            : null;
    final String primaryRef =
        batch.primaryReference(resolvedPoNumber: resolvedPoNumber);
    final String displayCode = batch.displayBatchId;
    final bool hasSeparateBatchCode =
        formattedPo != null && displayCode != formattedPo;
    final String supplierLabel = (resolvedSupplierName != null &&
            resolvedSupplierName!.trim().isNotEmpty)
        ? resolvedSupplierName!.trim()
        : 'Direct';

    final int denomInitial = batch.initialQty >= batch.remainingQty
        ? batch.initialQty
        : batch.remainingQty;

    final (expiryText, expiryBg, expiryFg) = batch.expirationDate == null
        ? (
            'No Expiry',
            theme.disabledColor.withValues(alpha: 0.1),
            theme.disabledColor,
          )
        : isExpired
            ? (
                'EXPIRED (${days!.abs()}d ago)',
                colorScheme.errorContainer.withValues(alpha: 0.2),
                colorScheme.error,
              )
            : isNearExpiry
                ? (
                    'Exp ${days}d',
                    semantic.warning.withValues(alpha: 0.15),
                    semantic.warning,
                  )
                : (
                    '${days}d left',
                    semantic.success.withValues(alpha: 0.12),
                    semantic.success,
                  );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOldestActive
            ? Colors.green.withValues(alpha: 0.05)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOldestActive
              ? Colors.green.shade600.withValues(alpha: 0.5)
              : (isExpired
                  ? colorScheme.error.withValues(alpha: 0.4)
                  : colorScheme.outline.withValues(alpha: 0.25)),
          width: isOldestActive ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (formattedPo != null) ...[
                          Icon(
                            Icons.receipt_long_rounded,
                            size: 13,
                            color: isDepleted
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          primaryRef,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: isDepleted
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: fifoColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        fifoBadge,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: fifoColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: expiryBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  expiryText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: expiryFg,
                  ),
                ),
              ),
            ],
          ),
          if (hasSeparateBatchCode || formattedPo == null) ...[
            const SizedBox(height: 3),
            Text(
              hasSeparateBatchCode
                  ? 'Batch ID: $displayCode'
                  : (batch.isLegacyUuidId
                      ? 'Legacy Initial / Direct Stock (No PO)'
                      : 'Direct / Manual Stock (No PO)'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Qty: ${batch.remainingQty} / $denomInitial $productUnit',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isDepleted ? Colors.grey : colorScheme.primary,
                ),
              ),
              Text(
                'Cost: ${formatPeso(batch.costPrice)} / $productUnit',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(
                'Supplier: $supplierLabel',
                style: TextStyle(
                  fontSize: 10.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Purchased: ${formatDate(batch.datePurchased)}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Arrived: ${formatDate(batch.dateArrived)}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight:
                      isOldestActive ? FontWeight.w700 : FontWeight.normal,
                  color: isOldestActive
                      ? Colors.green.shade800
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBoldValue;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isBoldValue = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBoldValue ? FontWeight.w800 : FontWeight.w600,
                color: valueColor ?? colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onReceive;
  final VoidCallback onAudit;

  const _QuickActionsRow({
    required this.product,
    required this.onEdit,
    required this.onReceive,
    required this.onAudit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit Product'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onReceive,
          icon: const Icon(Icons.move_to_inbox_rounded, size: 18),
          label: const Text('Receive Stock'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            side: BorderSide(color: colorScheme.primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onAudit,
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: const Text('Audit FIFO Batches'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            side: BorderSide(color: colorScheme.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => BarcodePrintDialog.show(context, product),
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: const Text('Print Barcode Label'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            side: const BorderSide(color: GdcColors.emeraldPrimary),
            foregroundColor: GdcColors.emeraldPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PARENT GROUP VARIANTS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ParentGroupVariantsCard extends StatelessWidget {
  final Product currentProduct;

  const _ParentGroupVariantsCard({required this.currentProduct});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final siblings = inventory.products
        .where((item) =>
            item.parentId != null &&
            item.parentId!.trim().toLowerCase() ==
                currentProduct.parentId!.trim().toLowerCase())
        .toList();

    if (siblings.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.account_tree_rounded,
                      size: 18, color: Colors.purple.shade900),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Parent Group Variants (${siblings.length} Child SKUs)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Parent Group ID: ${currentProduct.parentId}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: siblings.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final childP = siblings[index];
                final isCurrent = childP.id == currentProduct.id;

                return InkWell(
                  onTap: isCurrent
                      ? null
                      : () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductDetailScreen(product: childP),
                            ),
                          );
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Colors.purple.shade50.withValues(alpha: 0.5)
                          : colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: isCurrent
                          ? Border.all(color: Colors.purple.shade300)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      childP.name,
                                      style: TextStyle(
                                        fontWeight: isCurrent
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (isCurrent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('VIEWING NOW',
                                          style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple)),
                                    ),
                                ],
                              ),
                              if (childP.barcode != null)
                                Text('Barcode: ${childP.barcode}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatPeso(childP.price),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(
                              '${childP.totalStock} ${childP.unit}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: childP.isPhysicalThresholdHit
                                    ? Colors.red
                                    : Colors.green.shade800,
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
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INVENTORY ALLOCATION CARD (FIXED 100% POS / 75% ONLINE / 25% RESERVE)
// ─────────────────────────────────────────────────────────────────────────────

class _InventoryAllocationCard extends StatelessWidget {
  final Product product;

  const _InventoryAllocationCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final semantic = theme.semantic;

    final int totalStock = product.totalStock;
    final int posAvailable = product.totalAvailableStock;
    final int onlineAvailable = product.onlineAvailableStock;
    final int physicalReserve = product.effectivePhysicalReserve;
    final bool isOos = totalStock <= 0;
    final bool isOnlineOos = product.isOnlineOutOfStock;
    final bool isPhysicalLow = !isOos && product.isPhysicalThresholdHit;

    final Color accentColor = (isOos || isOnlineOos)
        ? cs.error
        : (isPhysicalLow ? semantic.warning : cs.primary);

    final int reserveInStock =
        totalStock < physicalReserve ? totalStock : physicalReserve;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.inventory_2_rounded,
                    size: 18,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inventory Allocation (100% POS / 75% Online)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '25% physical-only walk-in reserve automatically calculated on restock',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    (isOos || isOnlineOos)
                        ? Icons.warning_amber_rounded
                        : (isPhysicalLow
                            ? Icons.shield_rounded
                            : Icons.verified_rounded),
                    size: 16,
                    color: accentColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOos
                          ? 'Out of Stock — Restock to replenish POS and reopen Online availability.'
                          : (isOnlineOos
                              ? 'Online Out of Stock — Remaining $posAvailable ${product.unit} protected in the Walk-In Reserve for POS sales.'
                              : 'Online capped at $onlineAvailable ${product.unit} • $physicalReserve ${product.unit} strictly reserved for walk-in POS.'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Visual Stock Bar (Walk-In Reserve vs Online Available)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    Expanded(
                      flex:
                          isOos ? 1 : (reserveInStock > 0 ? reserveInStock : 1),
                      child: Container(
                        color: isOos ? cs.error : semantic.warning,
                      ),
                    ),
                    if (!isOos && onlineAvailable > 0)
                      Expanded(
                        flex: onlineAvailable,
                        child: Container(color: cs.primary),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Read-Only Allocation Visibility Tiles
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (isOos ? cs.error : semantic.success)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Physical Stock (POS)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isOos ? cs.error : semantic.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$totalStock ${product.unit}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Sellable now: $posAvailable ${product.unit}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (isOnlineOos ? cs.error : cs.primary)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Online Available (75% cap)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isOnlineOos ? cs.error : cs.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isOnlineOos
                              ? 'Out of Stock'
                              : '$onlineAvailable ${product.unit}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: isOnlineOos ? cs.error : cs.onSurface,
                          ),
                        ),
                        Text(
                          isOnlineOos
                              ? '0 ${product.unit} online'
                              : 'Customer App catalog',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: semantic.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Walk-In Reserve (25%)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: semantic.warning,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$physicalReserve ${product.unit}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'POS-only protected',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (product.hasVariants) ...[
              const Divider(height: 20),
              Text(
                'Per-Variant Stock Breakdown',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ...product.variants.map((v) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          v.name,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        'POS: ${v.stock} • Online: ${v.isOnlineOutOfStock ? 'OOS' : v.onlineAvailableStock} • Reserve: ${v.effectivePhysicalReserve}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
