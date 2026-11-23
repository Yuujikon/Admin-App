import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/rfq.dart';
import '../providers/procurement_provider.dart';
import '../utils/format.dart';
import 'premium_components.dart';

class RfqDetailDialog extends StatefulWidget {
  final Rfq rfq;

  const RfqDetailDialog({
    super.key,
    required this.rfq,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required Rfq rfq,
  }) {
    return showDialog<T>(
      context: context,
      builder: (_) => RfqDetailDialog(rfq: rfq),
    );
  }

  @override
  State<RfqDetailDialog> createState() => _RfqDetailDialogState();
}

class _RfqDetailDialogState extends State<RfqDetailDialog> {
  late List<RfqItem> _items;
  DateTime? _expectedDeliveryDate;
  final Map<String, TextEditingController> _priceControllers = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.rfq.items);
    _expectedDeliveryDate = widget.rfq.expectedDeliveryDate;

    for (var item in _items) {
      _priceControllers[item.productId] = TextEditingController(
        text: item.quotedUnitPrice != null && item.quotedUnitPrice! > 0
            ? item.quotedUnitPrice.toString()
            : '',
      );
    }
  }

  @override
  void dispose() {
    for (var ctrl in _priceControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  bool get _isFullyQuoted {
    for (var item in _items) {
      final text = _priceControllers[item.productId]?.text ?? '';
      final val = double.tryParse(text);
      if (val == null || val <= 0) return false;
    }
    return _items.isNotEmpty;
  }

  double get _calculatedTotal {
    double total = 0.0;
    for (var item in _items) {
      final text = _priceControllers[item.productId]?.text ?? '';
      final price = double.tryParse(text) ?? 0.0;
      total += (item.requestedQty * price);
    }
    return total;
  }

  List<RfqItem> _getUpdatedItems() {
    return _items.map((item) {
      final text = _priceControllers[item.productId]?.text ?? '';
      final price = double.tryParse(text);
      return item.copyWith(quotedUnitPrice: price);
    }).toList();
  }

  Future<void> _saveQuotedPrices() async {
    setState(() => _saving = true);
    try {
      final updatedItems = _getUpdatedItems();
      final bool fullyQuoted = updatedItems.every(
          (i) => i.quotedUnitPrice != null && i.quotedUnitPrice! > 0);

      final updatedRfq = widget.rfq.copyWith(
        items: updatedItems,
        expectedDeliveryDate: _expectedDeliveryDate,
        status: fullyQuoted ? RfqStatus.quoted : widget.rfq.status,
      );

      await context.read<ProcurementProvider>().updateRfq(updatedRfq);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quoted unit prices updated successfully.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating RFQ quotes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _convertToPurchaseOrder() async {
    if (!_isFullyQuoted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('All items must have a valid unit price before converting to PO.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shopping_cart_checkout_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Text('Confirm PO Conversion'),
          ],
        ),
        content: Text(
          'Convert RFQ #${widget.rfq.rfqNumber} into a binding Purchase Order?\n\nThis will lock the RFQ and automatically add the Purchase Order to the active FIFO Receiving Queue for ${widget.rfq.supplierName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CONVERT TO PO'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _saving = true);

    try {
      final updatedItems = _getUpdatedItems();
      final updatedRfq = widget.rfq.copyWith(
        items: updatedItems,
        expectedDeliveryDate: _expectedDeliveryDate,
        status: RfqStatus.quoted,
      );

      final String dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final String suppCode = widget.rfq.supplierId.length >= 4
          ? widget.rfq.supplierId.substring(0, 4).toUpperCase()
          : widget.rfq.supplierId.toUpperCase().padRight(4, 'X');
      final String poNumber =
          'PO-$dateStr-$suppCode-${DateTime.now().millisecondsSinceEpoch % 1000}';

      final procurement = context.read<ProcurementProvider>();
      await procurement.updateRfq(updatedRfq);
      await procurement.convertRfqToPurchaseOrder(updatedRfq, poNumber);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully created Purchase Order #$poNumber!'),
            backgroundColor: Colors.teal.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error converting RFQ to PO: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isConverted = widget.rfq.status == RfqStatus.converted;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 750),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'RFQ #${widget.rfq.rfqNumber}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _getStatusColor(widget.rfq.status)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _getStatusColor(widget.rfq.status)),
                            ),
                            child: Text(
                              widget.rfq.status.displayName.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: _getStatusColor(widget.rfq.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Supplier: ${widget.rfq.supplierName} • Created ${DateFormat('MMM d, yyyy').format(widget.rfq.createdAt)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const Divider(height: 20),

            // Delivery Date Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 18, color: Colors.teal),
                    const SizedBox(width: 6),
                    Text(
                      _expectedDeliveryDate != null
                          ? 'ETA: ${DateFormat('MMM d, yyyy').format(_expectedDeliveryDate!)}'
                          : 'ETA: Not set',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (!isConverted)
                  TextButton.icon(
                    icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                    label: const Text('Change Delivery Date'),
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
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Item Quotes Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text('Product / SKU',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text('Req Qty',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Quoted Unit Cost (₱)',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Line Total',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Items List
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final ctrl = _priceControllers[item.productId];
                  final double price =
                      double.tryParse(ctrl?.text ?? '') ?? 0.0;
                  final double lineTotal = item.requestedQty * price;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.productName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              Text('SKU: ${item.sku}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${item.requestedQty}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: isConverted
                              ? Text(
                                  formatPeso(item.quotedUnitPrice ?? 0.0),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                )
                              : Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: TextFormField(
                                    controller: ctrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d+\.?\d{0,2}')),
                                    ],
                                    textAlign: TextAlign.right,
                                    decoration: InputDecoration(
                                      hintText: '0.00',
                                      isDense: true,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                    ),
                                    onChanged: (_) {
                                      setState(() {});
                                    },
                                  ),
                                ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            formatPeso(lineTotal),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: lineTotal > 0
                                  ? Colors.green.shade800
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Live Grand Total Card
            PremiumCard(
              padding: const EdgeInsets.all(14),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL ESTIMATED COST',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5),
                      ),
                      Text(
                        '${widget.rfq.totalRequestedQty} total items requested',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ],
                  ),
                  Text(
                    formatPeso(_calculatedTotal),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.green.shade900,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Footer Action Buttons
            if (_saving)
              const Center(child: CircularProgressIndicator())
            else if (!isConverted)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('SAVE QUOTES'),
                      onPressed: _saveQuotedPrices,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.shopping_cart_checkout_rounded,
                          size: 18),
                      label: const Text('CONVERT TO PO'),
                      onPressed: _isFullyQuoted ? _convertToPurchaseOrder : null,
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
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_rounded, color: Colors.blue.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This RFQ has been converted into a Purchase Order and locked.',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(RfqStatus status) {
    switch (status) {
      case RfqStatus.draft:
        return Colors.grey.shade700;
      case RfqStatus.sent:
        return Colors.blue.shade700;
      case RfqStatus.quoted:
        return Colors.orange.shade800;
      case RfqStatus.converted:
        return Colors.teal.shade800;
      case RfqStatus.rejected:
      case RfqStatus.cancelled:
        return Colors.red.shade700;
    }
  }
}
