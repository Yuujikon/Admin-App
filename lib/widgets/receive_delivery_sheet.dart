import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/restock_inquiry.dart';
import '../providers/inventory_provider.dart';
import '../providers/restock_provider.dart';
import '../utils/format.dart';
import 'scanner_dialog.dart';
import 'premium_components.dart';

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
  late final TextEditingController _extraItemsCtrl;
  late final TextEditingController _invoiceCtrl;
  late final TextEditingController _notesCtrl;

  // State variable for Bulk UOM mode toggle
  bool _isBulkMode = false;

  // Inquiry Pre-fill Controllers
  final Map<String, TextEditingController> _inquiryQtyControllers = {};
  final Map<String, TextEditingController> _inquiryCostControllers = {};
  final Map<String, TextEditingController> _inquiryNoteControllers = {};
  final Map<String, DateTime?> _inquiryExpiryDates = {};

  DateTime? _batchExpiry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
    _qtyCtrl = TextEditingController();
    _extraItemsCtrl = TextEditingController();
    _invoiceCtrl = TextEditingController();
    _notesCtrl = TextEditingController();

    if (_selectedProduct != null) {
      if (_selectedProduct!.hasBulkPacking) {
        _isBulkMode = true;
        _costCtrl = TextEditingController(
          text: (_selectedProduct!.packCost != null &&
                  _selectedProduct!.packCost! > 0)
              ? _selectedProduct!.packCost.toString()
              : (_selectedProduct!.costPrice * _selectedProduct!.piecesPerPack)
                  .toStringAsFixed(2),
        );
      } else {
        _costCtrl =
            TextEditingController(text: _selectedProduct!.costPrice.toString());
      }
      if (_selectedProduct!.shelfDays != null) {
        _batchExpiry =
            DateTime.now().add(Duration(days: _selectedProduct!.shelfDays!));
      }
    } else {
      _costCtrl = TextEditingController();
    }

    if (widget.inquiry != null) {
      final inventory = context.read<InventoryProvider>();
      for (var item in widget.inquiry!.items) {
        _inquiryQtyControllers[item.productId] =
            TextEditingController(text: item.requestedQty.toString());
        _inquiryCostControllers[item.productId] = TextEditingController(
            text: item.costPrice > 0 ? item.costPrice.toString() : '');
        _inquiryNoteControllers[item.productId] =
            TextEditingController(text: item.discrepancyNote ?? '');

        DateTime? defaultExp;
        try {
          final prod =
              inventory.products.firstWhere((p) => p.id == item.productId);
          if (prod.shelfDays != null && prod.shelfDays! > 0) {
            defaultExp = DateTime.now().add(Duration(days: prod.shelfDays!));
          } else if (prod.expiryDate != null) {
            defaultExp = prod.expiryDate;
          }
        } catch (_) {}

        _inquiryExpiryDates[item.productId] = defaultExp;
      }
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _extraItemsCtrl.dispose();
    _invoiceCtrl.dispose();
    _notesCtrl.dispose();
    for (var c in _inquiryQtyControllers.values) {
      c.dispose();
    }
    for (var c in _inquiryCostControllers.values) {
      c.dispose();
    }
    for (var c in _inquiryNoteControllers.values) {
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

  void _acceptAllInquiryQty(RestockInquiry inquiry) {
    setState(() {
      for (var item in inquiry.items) {
        _inquiryQtyControllers[item.productId]?.text =
            item.requestedQty.toString();
        if (item.costPrice > 0) {
          _inquiryCostControllers[item.productId]?.text =
              item.costPrice.toString();
        }
      }
    });
  }

  void _setAllInquiryExpiry(Duration duration) {
    final expDate = DateTime.now().add(duration);
    setState(() {
      for (var key in List.from(_inquiryExpiryDates.keys)) {
        _inquiryExpiryDates[key] = expDate;
      }
    });
  }

  Widget _buildInquiryReceivingForm(
      BuildContext context, RestockInquiry inquiry) {
    double calcTotalReceived() {
      double sum = 0.0;
      for (var item in inquiry.items) {
        final q =
            int.tryParse(_inquiryQtyControllers[item.productId]?.text ?? '') ??
                item.requestedQty;
        final c = double.tryParse(
                _inquiryCostControllers[item.productId]?.text ?? '') ??
            item.costPrice;
        sum += (q * c);
      }
      return sum;
    }

    final double totalReceivedValue = calcTotalReceived();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainer
                .withValues(alpha: 0.90),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: MaxWidthContainer(
              maxWidth: MaxWidthContainer.formMaxWidth,
              alignment: Alignment.topCenter,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(3),
                        ),
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
                          'Verify Delivery #${inquiry.inquiryNumber}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        Text(
                          'Supplier: ${inquiry.supplierName}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold),
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

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Items to Verify (${inquiry.items.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _acceptAllInquiryQty(inquiry),
                        icon: const Icon(Icons.done_all_rounded, size: 14),
                        label: const Text('Accept All Qty',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                        ),
                      ),
                      PopupMenuButton<int>(
                        tooltip: 'Set Expiry Date for All Items',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_available_rounded,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                'Set All Expiry',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onSelected: (days) =>
                            _setAllInquiryExpiry(Duration(days: days)),
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                              value: 90, child: Text('Set All: +90 Days')),
                          const PopupMenuItem(
                              value: 180, child: Text('Set All: +180 Days')),
                          const PopupMenuItem(
                              value: 365, child: Text('Set All: +1 Year')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: inquiry.items.length,
                itemBuilder: (context, index) {
                  final item = inquiry.items[index];
                  final qtyCtrl = _inquiryQtyControllers[item.productId] ??=
                      TextEditingController(text: item.requestedQty.toString());
                  final costCtrl = _inquiryCostControllers[item.productId] ??=
                      TextEditingController(
                          text: item.costPrice > 0
                              ? item.costPrice.toString()
                              : '');
                  final noteCtrl = _inquiryNoteControllers[item.productId] ??=
                      TextEditingController(text: item.discrepancyNote ?? '');
                  final expiryDate = _inquiryExpiryDates[item.productId];

                  final int actualQty = int.tryParse(qtyCtrl.text) ?? 0;
                  final int diff = actualQty - item.requestedQty;

                  Color badgeBg;
                  Color badgeText;
                  String badgeLabel;

                  if (diff == 0) {
                    badgeBg = Colors.green.shade50;
                    badgeText = Colors.green.shade800;
                    badgeLabel = 'Match ✅';
                  } else if (diff < 0) {
                    badgeBg = Colors.orange.shade50;
                    badgeText = Colors.orange.shade900;
                    badgeLabel = '${diff.abs()} Short ⚠️';
                  } else {
                    badgeBg = Colors.blue.shade50;
                    badgeText = Colors.blue.shade900;
                    badgeLabel = '+$diff Surplus 📦';
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.productName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  badgeLabel,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: badgeText),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Ordered: ${item.requestedQty} ${item.unit} @ ${formatPeso(item.costPrice)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  onChanged: (_) => setState(() {}),
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d*'))
                                  ],
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Actual Unit Cost',
                                    isDense: true,
                                    prefixText: 'P ',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Batch Expiration Date & Quick Preset Chips
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.event_available_outlined,
                                    size: 16,
                                    color: expiryDate == null
                                        ? Colors.red
                                        : Colors.green.shade800,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text('Batch Expiry Date ',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const Text('*',
                                      style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                  const SizedBox(width: 8),
                                  Text(
                                    expiryDate == null
                                        ? 'Required'
                                        : DateFormat('MMM dd, yyyy')
                                            .format(expiryDate),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: expiryDate == null
                                          ? Colors.red
                                          : Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  ActionChip(
                                    avatar: const Icon(Icons.add, size: 14),
                                    label: const Text('+90 Days',
                                        style: TextStyle(fontSize: 11)),
                                    onPressed: () => setState(() =>
                                        _inquiryExpiryDates[item.productId] =
                                            DateTime.now()
                                                .add(const Duration(days: 90))),
                                  ),
                                  ActionChip(
                                    avatar: const Icon(Icons.add, size: 14),
                                    label: const Text('+180 Days',
                                        style: TextStyle(fontSize: 11)),
                                    onPressed: () => setState(() =>
                                        _inquiryExpiryDates[item.productId] =
                                            DateTime.now().add(
                                                const Duration(days: 180))),
                                  ),
                                  ActionChip(
                                    avatar: const Icon(Icons.add, size: 14),
                                    label: const Text('+1 Year',
                                        style: TextStyle(fontSize: 11)),
                                    onPressed: () => setState(() =>
                                        _inquiryExpiryDates[item.productId] =
                                            DateTime.now().add(
                                                const Duration(days: 365))),
                                  ),
                                  ActionChip(
                                    avatar: const Icon(
                                        Icons.calendar_month_outlined,
                                        size: 14),
                                    label: const Text('Pick Date',
                                        style: TextStyle(fontSize: 11)),
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        useRootNavigator: true,
                                        initialDate: expiryDate ??
                                            DateTime.now()
                                                .add(const Duration(days: 90)),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now()
                                            .add(const Duration(days: 365 * 5)),
                                      );
                                      if (picked != null) {
                                        setState(() => _inquiryExpiryDates[
                                            item.productId] = picked);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),

                          if (diff != 0) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: noteCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Discrepancy Note (Optional)',
                                hintText:
                                    'e.g. 2 pcs damaged / short delivered',
                                isDense: true,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              // Total Financial Summary Box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Ordered Value',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(formatPeso(inquiry.totalOrderedValue),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 18, color: Colors.grey),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Total Delivery Value',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(
                          formatPeso(totalReceivedValue),
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Colors.green.shade900),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              PrimaryButton(
                onPressed: _saving ? null : () => _saveInquiryDelivery(inquiry),
                isLoading: _saving,
                icon: Icons.check_circle_rounded,
                backgroundColor: Colors.green.shade800,
                foregroundColor: Colors.white,
                minWidth: 200,
                maxWidth: 350,
                child: Text(_saving
                    ? 'Processing Delivery...'
                    : 'CONFIRM & RECEIVE DELIVERY'),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
        ),
      ),
    );
  }

  Widget _buildSingleProductReceivingForm(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inventory = context.watch<InventoryProvider>();
    final products = inventory.products;

    final int inputQty = int.tryParse(_qtyCtrl.text) ?? 0;
    final double inputCost = double.tryParse(_costCtrl.text) ?? 0;
    final int extraItems = int.tryParse(_extraItemsCtrl.text) ?? 0;

    final int addedBaseUnits = (_isBulkMode && _selectedProduct != null)
        ? (_selectedProduct!.convertBulkToUnits(inputQty) + extraItems)
        : inputQty;

    final double unitCostPerPiece = (_isBulkMode && _selectedProduct != null)
        ? (addedBaseUnits > 0
            ? ((inputQty * inputCost) / addedBaseUnits)
            : _selectedProduct!.calculateUnitCostFromPack(inputCost))
        : inputCost;

    final double totalBatchCost = inputQty * inputCost;
    final int currentStock = _selectedProduct?.totalStock ?? 0;
    final int newCalculatedStock = currentStock + addedBaseUnits;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainer
                .withValues(alpha: 0.90),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: MaxWidthContainer(
              maxWidth: MaxWidthContainer.formMaxWidth,
              alignment: Alignment.topCenter,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Receive Stock Delivery',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
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
                value: products.any((p) => p.id == _selectedProduct?.id)
                    ? _selectedProduct?.id
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Delivered Product *',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                items: products.map((p) {
                  final brandPrefix = (p.brand != null && p.brand!.isNotEmpty)
                      ? '[${p.brand}] '
                      : '';
                  final parentSuffix =
                      p.hasParentGroup ? ' (${p.parentId})' : '';
                  return DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      '$brandPrefix${p.name}$parentSuffix — ${p.totalStock} ${p.unit}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (id) {
                  if (id != null) {
                    final p = products.firstWhere((prod) => prod.id == id);
                    setState(() {
                      _selectedProduct = p;
                      if (p.hasBulkPacking) {
                        _isBulkMode = true;
                        _costCtrl.text = (p.packCost != null && p.packCost! > 0)
                            ? p.packCost.toString()
                            : (p.costPrice * p.piecesPerPack)
                                .toStringAsFixed(2);
                      } else {
                        _isBulkMode = false;
                        _costCtrl.text = p.costPrice.toString();
                      }
                      if (p.shelfDays != null) {
                        _batchExpiry =
                            DateTime.now().add(Duration(days: p.shelfDays!));
                      }
                    });
                  }
                },
                validator: (v) =>
                    v == null ? 'Please select a delivered product' : null,
              ),

              if (_selectedProduct != null) ...[
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  String supplierName = 'Unassigned Supplier';
                  if (_selectedProduct!.supplierId != null &&
                      _selectedProduct!.supplierId!.isNotEmpty) {
                    try {
                      final supp = inventory.suppliers.firstWhere(
                          (s) => s.id == _selectedProduct!.supplierId);
                      supplierName = supp.name;
                    } catch (_) {}
                  }

                  RestockInquiry? activeInquiry;
                  if (_selectedProduct!.supplierId != null &&
                      _selectedProduct!.supplierId!.isNotEmpty) {
                    final restockProvider = context.watch<RestockProvider>();
                    try {
                      activeInquiry = restockProvider.inquiries.firstWhere(
                        (ri) =>
                            ri.supplierId == _selectedProduct!.supplierId &&
                            (ri.status == RestockInquiryStatus.pending ||
                                ri.status == RestockInquiryStatus.sent ||
                                ri.status ==
                                    RestockInquiryStatus.acknowledged ||
                                ri.status ==
                                    RestockInquiryStatus.partiallyFulfilled),
                      );
                    } catch (_) {}
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_shipping_outlined,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 4),
                          const Text('Supplier: ',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            supplierName,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                        ],
                      ),
                      if (activeInquiry != null) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) =>
                                  ReceiveDeliverySheet(inquiry: activeInquiry),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 16, color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Active restock order #${activeInquiry.inquiryNumber} found for $supplierName. Tap to verify full order.',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900),
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded,
                                    size: 12, color: Colors.blue),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                }),
              ],

              if (_selectedProduct != null &&
                  _selectedProduct!.hasParentGroup) ...[
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  final siblings = inventory
                      .getProductsByParentId(_selectedProduct!.parentId!);
                  if (siblings.length <= 1) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_tree_outlined,
                              size: 14, color: Colors.purple),
                          const SizedBox(width: 4),
                          Text(
                            'Variants in Parent Group "${_selectedProduct!.parentId}":',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: siblings.map((sib) {
                          final isCurrent = sib.id == _selectedProduct!.id;
                          return InkWell(
                            onTap: isCurrent
                                ? null
                                : () {
                                    setState(() {
                                      _selectedProduct = sib;
                                      if (sib.hasBulkPacking) {
                                        _isBulkMode = true;
                                        _costCtrl.text =
                                            (sib.packCost != null &&
                                                    sib.packCost! > 0)
                                                ? sib.packCost.toString()
                                                : (sib.costPrice *
                                                        sib.piecesPerPack)
                                                    .toStringAsFixed(2);
                                      } else {
                                        _isBulkMode = false;
                                        _costCtrl.text =
                                            sib.costPrice.toString();
                                      }
                                      if (sib.shelfDays != null) {
                                        _batchExpiry = DateTime.now().add(
                                            Duration(days: sib.shelfDays!));
                                      }
                                    });
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? Colors.purple.shade100
                                    : Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: isCurrent
                                        ? Colors.purple.shade400
                                        : Colors.purple.shade200),
                              ),
                              child: Text(
                                '${sib.name} (${sib.totalStock} ${sib.unit})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isCurrent
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  color: Colors.purple.shade900,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                }),
              ],

              if (_selectedProduct != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedProduct!.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    if (_selectedProduct!.brand != null &&
                                        _selectedProduct!.brand!.isNotEmpty)
                                      Text('Brand: ${_selectedProduct!.brand}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey)),
                                    if (_selectedProduct!.hasParentGroup)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                            color: Colors.purple.shade50,
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: Text(
                                            'Parent: ${_selectedProduct!.parentId}',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.purple.shade900,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    if (_selectedProduct!.hasBulkPacking)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: Text(
                                            '1 ${_selectedProduct!.bulkUnit} = ${_selectedProduct!.piecesPerPack} ${_selectedProduct!.unit}',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.teal.shade900,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Current Stock',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              Text(_selectedProduct!.formattedBulkStock,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ],
                          ),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 20, color: Colors.grey),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('New Total Stock',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              Text(
                                '$newCalculatedStock ${_selectedProduct!.unit}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Colors.green),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Segmented Button Toggle for Bulk vs Single UOM
              if (_selectedProduct != null && _selectedProduct!.hasBulkPacking)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Single (${_selectedProduct!.unit})'),
                        icon: const Icon(Icons.inventory_2_outlined),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text(
                            'Bulk (${_selectedProduct!.bulkUnit.toUpperCase()} of ${_selectedProduct!.piecesPerPack})'),
                        icon: const Icon(Icons.all_inbox_rounded),
                      ),
                    ],
                    selected: {_isBulkMode},
                    onSelectionChanged: (Set<bool> selection) {
                      setState(() {
                        _isBulkMode = selection.first;
                        // Auto-fill the cost field based on the selected mode
                        if (_isBulkMode && _selectedProduct!.packCost != null) {
                          _costCtrl.text =
                              _selectedProduct!.packCost.toString();
                        } else if (!_isBulkMode) {
                          _costCtrl.text =
                              _selectedProduct!.costPrice.toString();
                        }
                      });
                    },
                  ),
                ),

              if (_isBulkMode && _selectedProduct != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.green.shade900.withValues(alpha: 0.25)
                        : Colors.green.shade50.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isDark
                            ? Colors.green.shade800
                            : Colors.green.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.inventory_2_rounded,
                              size: 18,
                              color: isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade900),
                          const SizedBox(width: 8),
                          Text(
                            'UoM Package & Cost Breakdown',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Row 1: Bulk Qty & Bulk Pack Cost
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _qtyCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText:
                                    'Bulk Qty (${_selectedProduct!.bulkUnit.toUpperCase()}) *',
                                hintText: 'e.g. 2',
                                isDense: true,
                                fillColor:
                                    Theme.of(context).colorScheme.surface,
                                filled: true,
                              ),
                              validator: (v) {
                                final q = int.tryParse(v ?? '');
                                if (q == null || q <= 0)
                                  return 'Enter delivered qty';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _costCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d*'))
                              ],
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText:
                                    'Bulk Cost (per ${_selectedProduct!.bulkUnit}) *',
                                prefixText: 'P ',
                                hintText: 'e.g. 720.00',
                                isDense: true,
                                fillColor:
                                    Theme.of(context).colorScheme.surface,
                                filled: true,
                              ),
                              validator: (v) {
                                final c = double.tryParse(v ?? '');
                                if (c == null || c <= 0)
                                  return 'Enter unit cost';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Row 2: Items per Box & Extra Loose Items
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue:
                                  '${_selectedProduct!.piecesPerPack}',
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText:
                                    'Items per ${_selectedProduct!.bulkUnit}',
                                isDense: true,
                                fillColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                filled: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _extraItemsCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Extra Loose Items',
                                hintText: 'e.g. 2',
                                isDense: true,
                                fillColor:
                                    Theme.of(context).colorScheme.surface,
                                filled: true,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Calculated Breakdown Badge
                      if (inputQty > 0 ||
                          (int.tryParse(_extraItemsCtrl.text) ?? 0) > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.green.shade900.withValues(alpha: 0.4)
                                : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: isDark
                                    ? Colors.green.shade800
                                    : Colors.green.shade400),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 16,
                                  color: isDark
                                      ? Colors.green.shade200
                                      : Colors.green.shade900),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$inputQty ${_selectedProduct!.bulkUnit}(s) @ ${formatPeso(inputCost)} × ${_selectedProduct!.piecesPerPack} ${_selectedProduct!.unit}/${_selectedProduct!.bulkUnit}${(int.tryParse(_extraItemsCtrl.text) ?? 0) > 0 ? ' + ${int.tryParse(_extraItemsCtrl.text)} loose' : ''} = $addedBaseUnits ${_selectedProduct!.unit} total (${formatPeso(unitCostPerPiece)}/${_selectedProduct!.unit})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.green.shade200
                                        : Colors.green.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Initial Quantity (Base Units) & Unit Cost Side-by-Side Row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('uom_qty_$addedBaseUnits'),
                              initialValue: '$addedBaseUnits',
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText:
                                    'Initial Quantity (${_selectedProduct!.unit}) *',
                                isDense: true,
                                fillColor:
                                    Theme.of(context).colorScheme.surface,
                                filled: true,
                                suffixIcon: const Tooltip(
                                  message:
                                      'Auto-calculated from UoM, but editable if extra items exist',
                                  child: Icon(Icons.edit_note, size: 20),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              key: ValueKey(
                                  'uom_cost_${unitCostPerPiece.toStringAsFixed(2)}'),
                              initialValue: unitCostPerPiece > 0
                                  ? unitCostPerPiece.toStringAsFixed(2)
                                  : '0.00',
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Unit Cost *',
                                prefixText: 'P ',
                                isDense: true,
                                fillColor:
                                    Theme.of(context).colorScheme.surface,
                                filled: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText:
                              'Quantity Received (${_selectedProduct?.unit ?? 'pcs'}) *',
                          hintText: 'e.g. 48',
                          prefixIcon:
                              const Icon(Icons.add_shopping_cart_rounded),
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
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'))
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Batch Unit Cost *',
                          prefixText: 'P ',
                          hintText: 'e.g. 20.00',
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

              if (inputQty > 0 && inputCost > 0) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Batch Total Value: ${formatPeso(totalBatchCost)}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue),
                    ),
                    if (_isBulkMode && unitCostPerPiece > 0)
                      Text(
                        '(${formatPeso(unitCostPerPiece)} / ${_selectedProduct?.unit ?? 'pc'})',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800),
                      ),
                  ],
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

              const SizedBox(height: 16),

              // Required Batch Expiry DatePicker Component with Preset Chips
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _batchExpiry == null
                      ? (isDark
                          ? Colors.red.shade900.withValues(alpha: 0.25)
                          : Colors.red.shade50)
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _batchExpiry == null
                        ? (isDark ? Colors.red.shade700 : Colors.red.shade400)
                        : Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.5),
                    width: _batchExpiry == null ? 1.5 : 1.0,
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
                              Icons.event_available_rounded,
                              size: 18,
                              color: _batchExpiry == null
                                  ? (isDark ? Colors.red.shade300 : Colors.red)
                                  : (isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade800),
                            ),
                            const SizedBox(width: 8),
                            Text('Batch Expiry Date ',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: _batchExpiry == null
                                        ? (isDark
                                            ? Colors.red.shade200
                                            : Colors.red.shade900)
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface)),
                            Text('*',
                                style: TextStyle(
                                    color: isDark
                                        ? Colors.red.shade300
                                        : Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          ],
                        ),
                        if (_batchExpiry != null)
                          InkWell(
                            onTap: () => setState(() => _batchExpiry = null),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.clear,
                                      size: 14,
                                      color: isDark
                                          ? Colors.red.shade300
                                          : Colors.red),
                                  const SizedBox(width: 2),
                                  Text('Clear',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.red.shade300
                                              : Colors.red,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickExpiryDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _batchExpiry == null
                                ? (isDark
                                    ? Colors.red.shade700
                                    : Colors.red.shade300)
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              color: _batchExpiry == null
                                  ? (isDark ? Colors.red.shade300 : Colors.red)
                                  : Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _batchExpiry == null
                                    ? 'Select Batch Expiry Date (REQUIRED)'
                                    : DateFormat('MMMM dd, yyyy')
                                        .format(_batchExpiry!),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _batchExpiry == null
                                      ? (isDark
                                          ? Colors.red.shade300
                                          : Colors.red.shade900)
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 14),
                          label: const Text('+90 Days',
                              style: TextStyle(fontSize: 11)),
                          onPressed: () => setState(() => _batchExpiry =
                              DateTime.now().add(const Duration(days: 90))),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 14),
                          label: const Text('+180 Days',
                              style: TextStyle(fontSize: 11)),
                          onPressed: () => setState(() => _batchExpiry =
                              DateTime.now().add(const Duration(days: 180))),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 14),
                          label: const Text('+1 Year',
                              style: TextStyle(fontSize: 11)),
                          onPressed: () => setState(() => _batchExpiry =
                              DateTime.now().add(const Duration(days: 365))),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.calendar_month_outlined,
                              size: 14),
                          label: const Text('Pick Date',
                              style: TextStyle(fontSize: 11)),
                          onPressed: _pickExpiryDate,
                        ),
                      ],
                    ),
                    if (_batchExpiry == null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '⚠️ Mandatory: Every received batch requires an expiration date for FEFO compliance.',
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.red.shade300
                                : Colors.red.shade900,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              PrimaryButton(
                onPressed: _saving ? null : _saveDelivery,
                isLoading: _saving,
                icon: Icons.check_circle_rounded,
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                minWidth: 200,
                maxWidth: 350,
                child: Text(_saving
                    ? 'Updating Stock...'
                    : 'SAVE DELIVERY & UPDATE STOCK'),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
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
        final p = inventory.products
            .firstWhere((prod) => prod.barcode == result.trim());
        setState(() {
          _selectedProduct = p;
          if (_isBulkMode && p.packCost != null) {
            _costCtrl.text = p.packCost.toString();
          } else {
            _costCtrl.text = p.costPrice.toString();
          }
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

    if (_batchExpiry == null) {
      showDialog(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text('Expiration Date Required',
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: const Text(
            'To prevent inventory chaos, an Expiration Date is mandatory for all received delivery batches.\n\nPlease select an expiration date before saving.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _pickExpiryDate();
              },
              child: const Text('Select Date'),
            ),
          ],
        ),
      );
      return;
    }

    final qty = (int.tryParse(_qtyCtrl.text) ?? 0).clamp(0, 999999);
    final cost = (double.tryParse(_costCtrl.text) ?? 0.0).clamp(0.0, 999999.0);
    final extra = (int.tryParse(_extraItemsCtrl.text) ?? 0).clamp(0, 999999);

    final int addedBaseUnits = (_isBulkMode && _selectedProduct != null)
        ? (_selectedProduct!.convertBulkToUnits(qty) + extra)
        : qty;

    final double calculatedPieceCost = (_isBulkMode && _selectedProduct != null)
        ? (addedBaseUnits > 0
            ? ((qty * cost) / addedBaseUnits)
            : _selectedProduct!.calculateUnitCostFromPack(cost))
        : cost;

    setState(() => _saving = true);

    try {
      final inventory = context.read<InventoryProvider>();
      final messenger = ScaffoldMessenger.of(context);

      final String defaultNotes = _isBulkMode
          ? 'Bulk Box Delivery: $qty ${_selectedProduct!.bulkUnit}(s)${extra > 0 ? " + $extra loose" : ""} ($addedBaseUnits ${_selectedProduct!.unit} total) @ ${formatPeso(cost)}/${_selectedProduct!.bulkUnit}'
          : 'Single Delivery: $qty ${_selectedProduct!.unit} @ ${formatPeso(cost)}/${_selectedProduct!.unit}';

      await inventory.receiveDeliveryWithUom(
        product: _selectedProduct!,
        inputQuantity: _isBulkMode ? qty : addedBaseUnits,
        inputCost: _isBulkMode ? cost : calculatedPieceCost,
        isBulkDelivery: _isBulkMode,
        batchExpiryDate: _batchExpiry,
        invoiceNumber:
            _invoiceCtrl.text.trim().isEmpty ? null : _invoiceCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty
            ? defaultNotes
            : _notesCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        final String msg = _isBulkMode
            ? 'Received $qty ${_selectedProduct!.bulkUnit}s${extra > 0 ? ' + $extra loose' : ''} ($addedBaseUnits ${_selectedProduct!.unit}) for ${_selectedProduct!.name}! New Stock: ${_selectedProduct!.totalStock + addedBaseUnits} ${_selectedProduct!.unit} ✅'
            : 'Received $qty ${_selectedProduct!.unit} for ${_selectedProduct!.name}! New Stock: ${_selectedProduct!.totalStock + qty} ${_selectedProduct!.unit} ✅';

        messenger.showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error receiving delivery: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveInquiryDelivery(RestockInquiry inquiry) async {
    final List<String> missingExpiryItems = [];
    for (var item in inquiry.items) {
      final qtyCtrl = _inquiryQtyControllers[item.productId];
      final int recQty = int.tryParse(qtyCtrl?.text ?? '') ?? item.requestedQty;
      if (recQty > 0) {
        final expDate = _inquiryExpiryDates[item.productId];
        if (expDate == null) {
          missingExpiryItems.add(item.productName);
        }
      }
    }

    if (missingExpiryItems.isNotEmpty) {
      showDialog(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text('Expiration Date Required',
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: Text(
            'Expiration date is mandatory for all received delivery items to avoid untracked stock.\n\nPlease select an expiration date for:\n• ${missingExpiryItems.join("\n• ")}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final inventory = context.read<InventoryProvider>();
      final messenger = ScaffoldMessenger.of(context);

      final List<Map<String, dynamic>> receivedItemData = [];

      for (var item in inquiry.items) {
        final qtyCtrl = _inquiryQtyControllers[item.productId];
        final costCtrl = _inquiryCostControllers[item.productId];
        final noteCtrl = _inquiryNoteControllers[item.productId];
        final expDate = _inquiryExpiryDates[item.productId];

        final int recQty =
            int.tryParse(qtyCtrl?.text ?? '') ?? item.requestedQty;
        final double cost =
            double.tryParse(costCtrl?.text ?? '') ?? item.costPrice;
        final String? note = noteCtrl?.text.trim().isNotEmpty == true
            ? noteCtrl!.text.trim()
            : null;

        receivedItemData.add({
          'productId': item.productId,
          'receivedQty': recQty,
          'costPrice': cost,
          'expiryDate': expDate,
          'discrepancyNote': note,
        });
      }

      await inventory.processInquiryDelivery(
        inquiry: inquiry,
        receivedItemData: receivedItemData,
        invoiceNumber:
            _invoiceCtrl.text.trim().isEmpty ? null : _invoiceCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'Delivery for Order #${inquiry.inquiryNumber} Received & Reconciled ✅'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error processing delivery: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
