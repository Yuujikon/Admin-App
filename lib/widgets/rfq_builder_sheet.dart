import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/rfq.dart';
import '../models/supplier.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import 'premium_components.dart';

class RfqBuilderSheet extends StatefulWidget {
  final Rfq? initialRfq;
  final Supplier? initialSupplier;

  const RfqBuilderSheet({
    super.key,
    this.initialRfq,
    this.initialSupplier,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    Rfq? initialRfq,
    Supplier? initialSupplier,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RfqBuilderSheet(
        initialRfq: initialRfq,
        initialSupplier: initialSupplier,
      ),
    );
  }

  @override
  State<RfqBuilderSheet> createState() => _RfqBuilderSheetState();
}

class _RfqBuilderSheetState extends State<RfqBuilderSheet> {
  final _formKey = GlobalKey<FormState>();

  Supplier? _selectedSupplier;
  DateTime? _expectedDeliveryDate;
  final List<RfqItem> _items = [];
  bool _saving = false;

  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialRfq != null) {
      _expectedDeliveryDate = widget.initialRfq!.expectedDeliveryDate;
      for (var item in widget.initialRfq!.items) {
        _items.add(item);
        _qtyControllers[item.productId] =
            TextEditingController(text: item.requestedQty.toString());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final suppliers = context.read<InventoryProvider>().suppliers;
      if (widget.initialRfq != null) {
        final supp = suppliers.firstWhere(
          (s) => s.id == widget.initialRfq!.supplierId,
          orElse: () => Supplier(
            id: widget.initialRfq!.supplierId,
            name: widget.initialRfq!.supplierName,
          ),
        );
        setState(() => _selectedSupplier = supp);
      } else if (widget.initialSupplier != null) {
        setState(() => _selectedSupplier = widget.initialSupplier);
      } else if (suppliers.length == 1) {
        setState(() => _selectedSupplier = suppliers.first);
      }
    });
  }

  @override
  void dispose() {
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addItem(Product product) {
    if (_items.any((i) => i.productId == product.id)) return;
    final suggested = product.calculateSuggestedRestock();
    final qty = suggested > 0 ? suggested : 1;

    setState(() {
      _items.add(RfqItem(
        productId: product.id,
        productName: product.name,
        sku: (product.barcode != null && product.barcode!.isNotEmpty)
            ? product.barcode!
            : product.id,
        requestedQty: qty,
        quotedUnitPrice: product.costPrice > 0 ? product.costPrice : null,
      ));
      _qtyControllers[product.id] =
          TextEditingController(text: qty.toString());
    });
  }

  void _removeItem(String productId) {
    setState(() {
      _items.removeWhere((i) => i.productId == productId);
      _qtyControllers[productId]?.dispose();
      _qtyControllers.remove(productId);
    });
  }

  Future<void> _saveRfq({required bool markAsSent}) async {
    if (_formKey.currentState?.validate() != true) return;
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a supplier first.')),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one product to the RFQ.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final updatedItems = _items.map((item) {
        final qtyStr = _qtyControllers[item.productId]?.text ?? '1';
        final int qty = int.tryParse(qtyStr) ?? item.requestedQty;
        return item.copyWith(requestedQty: qty);
      }).toList();

      final String nowStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final String suppCode = _selectedSupplier!.id.length >= 4
          ? _selectedSupplier!.id.substring(0, 4).toUpperCase()
          : _selectedSupplier!.id.toUpperCase().padRight(4, 'X');
      final String rfqNo = widget.initialRfq?.rfqNumber ??
          'RFQ-$nowStr-$suppCode-${DateTime.now().millisecondsSinceEpoch % 1000}';

      final rfq = Rfq(
        id: widget.initialRfq?.id ?? '',
        rfqNumber: rfqNo,
        supplierId: _selectedSupplier!.id,
        supplierName: _selectedSupplier!.name,
        status: markAsSent ? RfqStatus.sent : RfqStatus.draft,
        createdAt: widget.initialRfq?.createdAt ?? DateTime.now(),
        expectedDeliveryDate: _expectedDeliveryDate,
        items: updatedItems,
      );

      final procurement = context.read<ProcurementProvider>();

      if (widget.initialRfq != null && widget.initialRfq!.id.isNotEmpty) {
        await procurement.updateRfq(rfq);
      } else {
        await procurement.addRfq(rfq);
      }

      if (mounted) {
        Navigator.of(context).pop();

        if (markAsSent) {
          _showShareRfqDialog(context, rfq);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('RFQ #${rfq.rfqNumber} saved as Draft.'),
              backgroundColor: Colors.teal.shade800,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving RFQ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showShareRfqDialog(BuildContext context, Rfq rfq) {
    final buffer = StringBuffer();
    buffer.writeln('REQUEST FOR QUOTATION (RFQ)');
    buffer.writeln('RFQ Number: #${rfq.rfqNumber}');
    buffer.writeln('Supplier: ${rfq.supplierName}');
    buffer.writeln('Date: ${DateFormat('MMM d, yyyy').format(rfq.createdAt)}');
    if (rfq.expectedDeliveryDate != null) {
      buffer.writeln(
          'Target Delivery: ${DateFormat('MMM d, yyyy').format(rfq.expectedDeliveryDate!)}');
    }
    buffer.writeln('-----------------------------------');
    buffer.writeln('Items Requested:');
    for (var i in rfq.items) {
      buffer.writeln('• ${i.productName} (SKU: ${i.sku}): ${i.requestedQty} pcs');
    }
    buffer.writeln('-----------------------------------');
    buffer.writeln('Please provide unit price quote at your earliest convenience.');

    final shareText = buffer.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.send_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Text('RFQ Marked as Sent'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The RFQ has been updated to SENT. You can copy the message payload below to send to your supplier via Email, Messenger, or SMS:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                shareText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('COPY TEXT'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: shareText));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('RFQ payload copied to clipboard!')),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog() {
    final products = context.read<InventoryProvider>().products;
    String filter = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = products.where((p) {
              final query = filter.toLowerCase();
              return p.name.toLowerCase().contains(query) ||
                  (p.barcode != null && p.barcode!.contains(query));
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Product to Request',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search product by name or barcode...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) {
                      setModalState(() => filter = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching products found'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              final isAdded =
                                  _items.any((i) => i.productId == p.id);

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh,
                                  child: Icon(Icons.inventory_2,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                ),
                                title: Text(p.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    'Stock: ${p.stock} ${p.unit} • Threshold: ${p.lowStockThreshold}'),
                                trailing: isAdded
                                    ? const Icon(Icons.check_circle,
                                        color: Colors.green)
                                    : IconButton(
                                        icon: const Icon(
                                            Icons.add_circle_outline,
                                            color: Colors.teal),
                                        onPressed: () {
                                          _addItem(p);
                                          Navigator.of(ctx).pop();
                                        },
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = context.watch<InventoryProvider>().suppliers;
    final isEditing = widget.initialRfq != null;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.request_quote_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit RFQ' : 'Create Request For Quotation',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          Text(
                            'Step 1: Ask supplier for item prices',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const Divider(height: 24),

              // Supplier Picker Dropdown
              const Text(
                'Select Supplier *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<Supplier>(
                value: _selectedSupplier,
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.storefront_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                hint: const Text('Choose a supplier...'),
                items: suppliers.map((s) {
                  return DropdownMenuItem<Supplier>(
                    value: s,
                    child: Text(s.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedSupplier = val);
                },
                validator: (val) =>
                    val == null ? 'Please select a supplier' : null,
              ),

              const SizedBox(height: 16),

              // Target Delivery Date Picker
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(
                        _expectedDeliveryDate == null
                            ? 'Set Target Delivery Date (Optional)'
                            : 'ETA: ${DateFormat('MMM d, yyyy').format(_expectedDeliveryDate!)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _expectedDeliveryDate ??
                              DateTime.now().add(const Duration(days: 3)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 90)),
                        );
                        if (picked != null) {
                          setState(() => _expectedDeliveryDate = picked);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (_expectedDeliveryDate != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setState(() => _expectedDeliveryDate = null);
                      },
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 20),

              // Items Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Requested Items',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showAddProductDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Product'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Items List
              if (_items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.5)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 36, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No products added to RFQ yet',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      Text(
                        'Tap "Add Product" to select items from catalog',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final ctrl = _qtyControllers[item.productId];

                    return PremiumCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                                Text(
                                  'SKU: ${item.sku}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              controller: ctrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: InputDecoration(
                                labelText: 'Req Qty',
                                isDense: true,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                              ),
                              validator: (val) {
                                final n = int.tryParse(val ?? '');
                                if (n == null || n <= 0) return '> 0';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: Colors.red),
                            onPressed: () => _removeItem(item.productId),
                          ),
                        ],
                      ),
                    );
                  },
                ),

              const SizedBox(height: 24),

              // Action Buttons
              if (_saving)
                const Center(child: CircularProgressIndicator())
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.save_as_outlined, size: 18),
                        label: const Text('SAVE DRAFT'),
                        onPressed: () => _saveRfq(markAsSent: false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('MARK AS SENT'),
                        onPressed: () => _saveRfq(markAsSent: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
      ),
    );
  }
}
