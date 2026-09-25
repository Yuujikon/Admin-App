import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/restock_inquiry.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../providers/restock_provider.dart';
import '../utils/format.dart';
import 'qty_control.dart';

class RestockInquirySheet extends StatefulWidget {
  final RestockInquiry inquiry;
  const RestockInquirySheet({super.key, required this.inquiry});

  @override
  State<RestockInquirySheet> createState() => _RestockInquirySheetState();
}

class _RestockInquirySheetState extends State<RestockInquirySheet> {
  late List<RestockInquiryItem> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.inquiry.items);
  }

  void _addItem(Product p) {
    if (_items.any((i) => i.productId == p.id)) return;
    
    final suggested = p.calculateSuggestedRestock();

    setState(() {
      _items.add(RestockInquiryItem(
        productId: p.id,
        productName: p.name,
        sku: p.barcode ?? p.id,
        currentStock: p.stock,
        lowStockThreshold: p.lowStockThreshold,
        unit: p.unit,
        suggestedQty: suggested,
        requestedQty: suggested,
      ));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot save empty inquiry.')));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final supplierProducts = inventory.products.where((p) => p.supplierId == widget.inquiry.supplierId).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('INQUIRY ITEMS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey, fontSize: 11, letterSpacing: 1)),
                    TextButton.icon(
                      onPressed: () => _showAddProductPicker(supplierProducts),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('ADD ITEM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No items in this inquiry', style: TextStyle(color: Colors.grey))),
                  )
                else
                  ...List.generate(_items.length, (index) => _itemRow(index)),
                
                const SizedBox(height: 32),
              ],
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
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit Restock Inquiry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text(widget.inquiry.inquiryNumber, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(int index) {
    final item = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
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
                    Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text('SKU: ${item.sku}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _removeItem(index),
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('REQUESTED QUANTITY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text('${item.unit.toUpperCase()}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              QtyControl(
                qty: item.requestedQty,
                onChanged: (v) => _updateQty(index, v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _saving 
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold)),
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
                child: Text('Add Item to Inquiry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.builder(
                  controller: sc,
                  itemCount: products.length,
                  itemBuilder: (c, i) {
                    final p = products[i];
                    final bool isAdded = _items.any((item) => item.productId == p.id);
                    return ListTile(
                      title: Text(p.name, style: TextStyle(fontWeight: isAdded ? FontWeight.normal : FontWeight.bold)),
                      subtitle: Text('Stock: ${p.stock} ${p.unit}'),
                      trailing: isAdded 
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.add_circle_outline, color: Colors.blue),
                      onTap: isAdded ? null : () {
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
