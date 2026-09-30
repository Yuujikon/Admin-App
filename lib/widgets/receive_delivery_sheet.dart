import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/restock_inquiry.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';
import 'scanner_dialog.dart';

class ReceiveDeliverySheet extends StatefulWidget {
  final Product? initialProduct;
  final RestockInquiry? inquiry;

  const ReceiveDeliverySheet({
    super.key,
    this.initialProduct,
    this.inquiry,
  });

  @override
  State<ReceiveDeliverySheet> createState() => _ReceiveDeliverySheetState();
}

class _ReceiveDeliverySheetState extends State<ReceiveDeliverySheet> {
  final _formKey = GlobalKey<FormState>();

  Product? _selectedProduct;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _invoiceCtrl;
  late final TextEditingController _notesCtrl;

  // Inquiry Pre-fill Controllers
  final Map<String, TextEditingController> _inquiryQtyControllers = {};
  final Map<String, TextEditingController> _inquiryCostControllers = {};
  final Map<String, DateTime?> _inquiryExpiryDates = {};

  DateTime? _batchExpiry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
    _qtyCtrl = TextEditingController();
    _costCtrl = TextEditingController(text: _selectedProduct?.costPrice.toString() ?? '');
    _invoiceCtrl = TextEditingController();
    _notesCtrl = TextEditingController();

    if (widget.inquiry != null) {
      for (var item in widget.inquiry!.items) {
        _inquiryQtyControllers[item.productId] = TextEditingController(text: item.requestedQty.toString());
        _inquiryCostControllers[item.productId] = TextEditingController(text: item.costPrice > 0 ? item.costPrice.toString() : '');
        _inquiryExpiryDates[item.productId] = null;
      }
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _invoiceCtrl.dispose();
    _notesCtrl.dispose();
    for (var c in _inquiryQtyControllers.values) {
      c.dispose();
    }
    for (var c in _inquiryCostControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inquiry != null) {
      return _buildInquiryReceivingForm(context, widget.inquiry!);
    }

    return _buildSingleProductReceivingForm(context);
  }

  Widget _buildInquiryReceivingForm(BuildContext context, RestockInquiry inquiry) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20, right: 20, top: 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Receive Delivery #${inquiry.inquiryNumber}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        Text(
                          'Supplier: ${inquiry.supplierName}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              TextFormField(
                controller: _invoiceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supplier DR / Invoice Number (Optional)',
                  hintText: 'e.g. DR-2026-8801',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),

              const SizedBox(height: 16),
              Text(
                'Expected Items (${inquiry.items.length} products)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: inquiry.items.length,
                itemBuilder: (context, index) {
                  final item = inquiry.items[index];
                  final qtyCtrl = _inquiryQtyControllers[item.productId] ??= TextEditingController(text: item.requestedQty.toString());
                  final costCtrl = _inquiryCostControllers[item.productId] ??= TextEditingController(text: item.costPrice > 0 ? item.costPrice.toString() : '');
                  final expiryDate = _inquiryExpiryDates[item.productId];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('Ordered: ${item.requestedQty} ${item.unit}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: InputDecoration(
                                    labelText: 'Actual Received Qty',
                                    isDense: true,
                                    suffixText: item.unit,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: costCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                                  decoration: const InputDecoration(
                                    labelText: 'Unit Cost',
                                    isDense: true,
                                    prefixText: '₱ ',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event_available_outlined, size: 20),
                            title: const Text('Batch Expiry Date', style: TextStyle(fontSize: 12)),
                            subtitle: Text(
                              expiryDate == null ? 'Not set (Optional)' : DateFormat('MMM dd, yyyy').format(expiryDate),
                              style: TextStyle(
                                fontSize: 11,
                                color: expiryDate == null ? Colors.grey : Colors.green.shade800,
                                fontWeight: expiryDate == null ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                            trailing: expiryDate != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () => setState(() => _inquiryExpiryDates[item.productId] = null),
                                  )
                                : const Icon(Icons.chevron_right, size: 20),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                useRootNavigator: true,
                                initialDate: expiryDate ?? DateTime.now().add(const Duration(days: 90)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                              );
                              if (picked != null) {
                                setState(() => _inquiryExpiryDates[item.productId] = picked);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : () => _saveInquiryDelivery(inquiry),
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(_saving ? 'Processing Delivery...' : 'CONFIRM & RECEIVE DELIVERY'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSingleProductReceivingForm(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final products = inventory.products;

    final int qtyReceived = int.tryParse(_qtyCtrl.text) ?? 0;
    final double unitCost = double.tryParse(_costCtrl.text) ?? 0;
    final double totalBatchCost = qtyReceived * unitCost;
    final int currentStock = _selectedProduct?.totalStock ?? 0;
    final int newCalculatedStock = currentStock + qtyReceived;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Receive Stock Delivery', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scan Barcode',
                    onPressed: _scanBarcode,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedProduct?.id,
                decoration: const InputDecoration(
                  labelText: 'Delivered Product *',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                items: products.map((p) => DropdownMenuItem(
                  value: p.id,
                  child: Text('${p.name} (Current: ${p.totalStock} ${p.unit})'),
                )).toList(),
                onChanged: (id) {
                  if (id != null) {
                    final p = products.firstWhere((prod) => prod.id == id);
                    setState(() {
                      _selectedProduct = p;
                      if (_costCtrl.text.isEmpty || _costCtrl.text == '0') {
                        _costCtrl.text = p.costPrice.toString();
                      }
                    });
                  }
                },
                validator: (v) => v == null ? 'Please select a delivered product' : null,
              ),

              if (_selectedProduct != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Current Stock', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text('$currentStock ${_selectedProduct!.unit}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.grey),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('New Total Stock', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(
                            '$newCalculatedStock ${_selectedProduct!.unit}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.green),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Quantity Received *',
                        hintText: 'e.g. 48',
                        prefixIcon: Icon(Icons.add_shopping_cart_rounded),
                      ),
                      validator: (v) {
                        final q = int.tryParse(v ?? '');
                        if (q == null || q <= 0) return 'Enter delivered qty';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Batch Unit Cost *',
                        prefixText: '₱ ',
                        hintText: 'e.g. 30.00',
                      ),
                      validator: (v) {
                        final c = double.tryParse(v ?? '');
                        if (c == null || c <= 0) return 'Enter unit cost';
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              if (qtyReceived > 0 && unitCost > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Batch Total Value: ${formatPeso(totalBatchCost)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],

              const SizedBox(height: 16),

              TextFormField(
                controller: _invoiceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supplier Invoice / DR Number (Optional)',
                  hintText: 'e.g. INV-2026-9901',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),

              const SizedBox(height: 12),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Batch Expiry Date'),
                subtitle: Text(_batchExpiry == null ? 'Not set (Optional)' : DateFormat('MMMM dd, yyyy').format(_batchExpiry!)),
                trailing: _batchExpiry != null
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _batchExpiry = null))
                    : const Icon(Icons.chevron_right),
                onTap: _pickExpiryDate,
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveDelivery,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(_saving ? 'Updating Stock...' : 'SAVE DELIVERY & UPDATE STOCK'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scanBarcode() async {
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => const ScannerDialog(),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final inventory = context.read<InventoryProvider>();
      try {
        final p = inventory.products.firstWhere((prod) => prod.barcode == result.trim());
        setState(() {
          _selectedProduct = p;
          _costCtrl.text = p.costPrice.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Matched: ${p.name} ✅')),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Barcode "$result" not found in inventory.')),
        );
      }
    }
  }

  Future<void> _pickExpiryDate() async {
    final res = await showDatePicker(
      context: context,
      useRootNavigator: true,
      initialDate: _batchExpiry ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (res != null) {
      setState(() => _batchExpiry = res);
    }
  }

  Future<void> _saveDelivery() async {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) return;

    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    final cost = double.tryParse(_costCtrl.text) ?? 0;

    setState(() => _saving = true);

    try {
      final inventory = context.read<InventoryProvider>();
      final messenger = ScaffoldMessenger.of(context);

      await inventory.receiveDelivery(
        product: _selectedProduct!,
        qtyReceived: qty,
        unitCost: cost,
        batchExpiryDate: _batchExpiry,
        invoiceNumber: _invoiceCtrl.text.trim().isEmpty ? null : _invoiceCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Received $qty pcs for ${_selectedProduct!.name}! New Stock: ${_selectedProduct!.totalStock + qty} pcs ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error receiving delivery: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveInquiryDelivery(RestockInquiry inquiry) async {
    setState(() => _saving = true);

    try {
      final inventory = context.read<InventoryProvider>();
      final messenger = ScaffoldMessenger.of(context);

      final List<Map<String, dynamic>> receivedItemData = [];

      for (var item in inquiry.items) {
        final qtyCtrl = _inquiryQtyControllers[item.productId];
        final costCtrl = _inquiryCostControllers[item.productId];
        final expDate = _inquiryExpiryDates[item.productId];

        final int recQty = int.tryParse(qtyCtrl?.text ?? '') ?? item.requestedQty;
        final double cost = double.tryParse(costCtrl?.text ?? '') ?? item.costPrice;

        receivedItemData.add({
          'productId': item.productId,
          'receivedQty': recQty,
          'costPrice': cost,
          'expiryDate': expDate,
        });
      }

      await inventory.processInquiryDelivery(
        inquiry: inquiry,
        receivedItemData: receivedItemData,
        invoiceNumber: _invoiceCtrl.text.trim().isEmpty ? null : _invoiceCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Delivery for Order #${inquiry.inquiryNumber} Received & Reconciled ✅'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing delivery: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
