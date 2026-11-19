import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/restock_inquiry.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../providers/restock_provider.dart';
import 'qty_control.dart';
import 'premium_components.dart';

class RestockInquirySheet extends StatefulWidget {
  final RestockInquiry inquiry;
  const RestockInquirySheet({super.key, required this.inquiry});

  @override
  State<RestockInquirySheet> createState() => _RestockInquirySheetState();
}

class _RestockInquirySheetState extends State<RestockInquirySheet> {
  late List<RestockInquiryItem> _items;
  bool _saving = false;

  final Map<String, bool> _itemBulkModes = {};
  final Map<String, int> _itemBulkQty = {};
  final Map<String, int> _itemExtraQty = {};

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.inquiry.items);
    final inventory = context.read<InventoryProvider>();

    for (final item in _items) {
      try {
        final prod = inventory.products.firstWhere(
          (p) =>
              p.id == item.productId ||
              p.name.trim().toLowerCase() ==
                  item.productName.trim().toLowerCase(),
        );
        if (prod.hasBulkPacking) {
          _itemBulkModes[item.productId] = true;
          if (item.requestedQty >= prod.piecesPerPack) {
            _itemBulkQty[item.productId] =
                item.requestedQty ~/ prod.piecesPerPack;
            _itemExtraQty[item.productId] =
                item.requestedQty % prod.piecesPerPack;
          } else {
            _itemBulkQty[item.productId] = 1;
            _itemExtraQty[item.productId] = 0;
          }
        }
      } catch (_) {}
    }
  }

  void _addItem(Product p) {
    if (_items.any((i) => i.productId == p.id)) return;

    final suggested = p.calculateSuggestedRestock();

    setState(() {
      _items.add(RestockInquiryItem(
        productId: p.id,
        productName: p.name,
        sku: p.barcode ?? p.id,
        currentStock: p.totalStock,
        lowStockThreshold: p.lowStockThreshold,
        unit: p.unit,
        suggestedQty: suggested,
        requestedQty: suggested,
        costPrice: p.costPrice,
      ));

      if (p.hasBulkPacking) {
        _itemBulkModes[p.id] = true;
        if (suggested >= p.piecesPerPack) {
          _itemBulkQty[p.id] = suggested ~/ p.piecesPerPack;
          _itemExtraQty[p.id] = suggested % p.piecesPerPack;
        } else {
          _itemBulkQty[p.id] = 1;
          _itemExtraQty[p.id] = 0;
        }
      }
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  void _updateQty(int index, int newQty) {
    setState(() {
      _items[index] = _items[index].copyWith(requestedQty: newQty);
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot save empty inquiry.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = widget.inquiry.copyWith(items: _items);
      final restockProvider = context.read<RestockProvider>();
      final navigator = Navigator.of(context);

      await restockProvider.updateInquiry(updated);

      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final supplierProducts = inventory.products
        .where((p) => p.supplierId == widget.inquiry.supplierId)
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: MaxWidthContainer(
              maxWidth: MaxWidthContainer.formMaxWidth,
              alignment: Alignment.topCenter,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'INQUIRY ITEMS',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_items.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showAddProductPicker(supplierProducts),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('ADD ITEM'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                          child: Text('No items in this inquiry',
                              style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ...List.generate(_items.length, (index) => _itemRow(index)),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit Restock Inquiry',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 13,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.inquiry.inquiryNumber,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Close',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemRow(int index) {
    final item = _items[index];
    final inventory = context.read<InventoryProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    Product? prod;
    try {
      prod = inventory.products.firstWhere(
        (p) =>
            p.id == item.productId ||
            p.name.trim().toLowerCase() ==
                item.productName.trim().toLowerCase(),
      );
    } catch (_) {}

    final bool hasBulk = prod != null && prod.hasBulkPacking;
    final bool isBulk = _itemBulkModes[item.productId] ?? hasBulk;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SKU: ${item.sku}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Stock: ${item.currentStock} ${item.unit}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => _removeItem(index),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: colorScheme.error,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (hasBulk) ...[
            SegmentedButton<bool>(
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                selectedBackgroundColor: colorScheme.primaryContainer,
                selectedForegroundColor: colorScheme.primary,
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  label: Text(
                    'Single (${prod.unit})',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 15),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text(
                    'Bulk (${prod.bulkUnit.toUpperCase()} of ${prod.piecesPerPack})',
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.all_inbox_rounded, size: 15),
                ),
              ],
              selected: {isBulk},
              onSelectionChanged: (Set<bool> selection) {
                setState(() {
                  final newIsBulk = selection.first;
                  _itemBulkModes[item.productId] = newIsBulk;
                  if (newIsBulk) {
                    final int req = item.requestedQty;
                    final int bQty = req >= prod!.piecesPerPack
                        ? req ~/ prod.piecesPerPack
                        : 1;
                    final int extra = req >= prod.piecesPerPack
                        ? req % prod.piecesPerPack
                        : 0;
                    _itemBulkQty[item.productId] = bQty;
                    _itemExtraQty[item.productId] = extra;
                    _updateQty(index, (bQty * prod.piecesPerPack) + extra);
                  }
                });
              },
            ),
            const SizedBox(height: 12),
          ],

          if (hasBulk && isBulk) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.all_inbox_rounded,
                            size: 15,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Bulk Qty (${prod.bulkUnit.toUpperCase()})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      QtyControl(
                        key: ValueKey('bulk_qty_${item.productId}_$index'),
                        qty: _itemBulkQty[item.productId] ?? 1,
                        onChanged: (v) {
                          setState(() {
                            _itemBulkQty[item.productId] = v;
                            final extra = _itemExtraQty[item.productId] ?? 0;
                            final total = (v * prod!.piecesPerPack) + extra;
                            _updateQty(index, total);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.widgets_outlined,
                            size: 15,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Extra Loose (${prod.unit.toUpperCase()})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      QtyControl(
                        key: ValueKey('extra_qty_${item.productId}_$index'),
                        qty: _itemExtraQty[item.productId] ?? 0,
                        min: 0,
                        onChanged: (v) {
                          setState(() {
                            _itemExtraQty[item.productId] = v;
                            final bQty = _itemBulkQty[item.productId] ?? 1;
                            final total = (bQty * prod!.piecesPerPack) + v;
                            _updateQty(index, total);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (_) {
                      final bQty = _itemBulkQty[item.productId] ?? 1;
                      final extra = _itemExtraQty[item.productId] ?? 0;
                      final total = (bQty * prod!.piecesPerPack) + extra;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calculate_outlined,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.primary,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Total Request: '),
                                    TextSpan(
                                      text: '$bQty ${prod.bulkUnit}(s)',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    if (extra > 0)
                                      TextSpan(
                                        text: ' + $extra loose',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    const TextSpan(text: ' = '),
                                    TextSpan(
                                      text: '$total ${prod.unit}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REQUESTED QUANTITY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.unit.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  QtyControl(
                    key: ValueKey('qty_${item.productId}_$index'),
                    qty: item.requestedQty,
                    onChanged: (v) => _updateQty(index, v),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5))
        ],
      ),
      child: MaxWidthContainer(
        maxWidth: MaxWidthContainer.formMaxWidth,
        alignment: Alignment.center,
        child: PrimaryButton(
          onPressed: _saving ? null : _save,
          isLoading: _saving,
          minWidth: 200,
          maxWidth: 350,
          child: const Text('SAVE CHANGES',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _showAddProductPicker(List<Product> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Add Item to Inquiry',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.builder(
                  controller: sc,
                  itemCount: products.length,
                  itemBuilder: (c, i) {
                    final p = products[i];
                    final bool isAdded =
                        _items.any((item) => item.productId == p.id);
                    return ListTile(
                      title: Text(p.name,
                          style: TextStyle(
                              fontWeight: isAdded
                                  ? FontWeight.normal
                                  : FontWeight.bold)),
                      subtitle: Text('Stock: ${p.stock} ${p.unit}'),
                      trailing: isAdded
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.add_circle_outline,
                              color: Colors.blue),
                      onTap: isAdded
                          ? null
                          : () {
                              _addItem(p);
                              Navigator.pop(ctx);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
