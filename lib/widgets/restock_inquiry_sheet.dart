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
                      const Text('INQUIRY ITEMS',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.grey,
                              fontSize: 11,
                              letterSpacing: 1)),
                      TextButton.icon(
                        onPressed: () =>
                            _showAddProductPicker(supplierProducts),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('ADD ITEM',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit Restock Inquiry',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text(widget.inquiry.inquiryNumber,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerLow),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(int index) {
    final item = _items[index];
    final inventory = context.read<InventoryProvider>();
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.productName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(
                        'SKU: ${item.sku} • Stock: ${item.currentStock} ${item.unit}',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _removeItem(index),
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.red, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (hasBulk) ...[
            SegmentedButton<bool>(
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Single (${prod!.unit})',
                      style: const TextStyle(fontSize: 11)),
                  icon: const Icon(Icons.inventory_2_outlined, size: 14),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text(
                    'Bulk (${prod.bulkUnit.toUpperCase()} of ${prod.piecesPerPack})',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.all_inbox_rounded, size: 14),
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
            const SizedBox(height: 10),
          ],

          if (hasBulk && isBulk) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Bulk Qty (${prod!.bulkUnit.toUpperCase()})',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey),
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
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Extra Loose (${prod.unit.toUpperCase()})',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey),
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
                  const SizedBox(height: 8),
                  Builder(
                    builder: (_) {
                      final bQty = _itemBulkQty[item.productId] ?? 1;
                      final extra = _itemExtraQty[item.productId] ?? 0;
                      final total = (bQty * prod!.piecesPerPack) + extra;
                      return Text(
                        'Total Request: $bQty ${prod.bulkUnit}(s)${extra > 0 ? " + $extra loose" : ""} = $total ${prod.unit}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('REQUESTED QUANTITY',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(item.unit.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                QtyControl(
                  key: ValueKey('qty_${item.productId}_$index'),
                  qty: item.requestedQty,
                  onChanged: (v) => _updateQty(index, v),
                ),
              ],
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
