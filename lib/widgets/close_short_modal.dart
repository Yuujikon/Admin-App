import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/purchase_order.dart';
import '../providers/procurement_provider.dart';

/// Modal dialog for force-closing unfulfilled remaining balances on a Purchase Order.
class CloseShortModal extends StatefulWidget {
  final PurchaseOrder purchaseOrder;

  const CloseShortModal({
    super.key,
    required this.purchaseOrder,
  });

  static Future<bool?> show(BuildContext context, PurchaseOrder purchaseOrder) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CloseShortModal(purchaseOrder: purchaseOrder),
    );
  }

  @override
  State<CloseShortModal> createState() => _CloseShortModalState();
}

class _CloseShortModalState extends State<CloseShortModal> {
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController(text: 'Supplier out of stock');
  bool _submitting = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmCloseShort() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _submitting = true);

    try {
      final procurement = context.read<ProcurementProvider>();
      final unfulfilledItems =
          widget.purchaseOrder.items.where((i) => i.remainingQty > 0).toList();

      final String cancelReason = _reasonCtrl.text.trim();

      await procurement.shortClosePurchaseOrder(
        widget.purchaseOrder.id,
        widget.purchaseOrder.items,
        reason: cancelReason,
        closedBy: 'Admin',
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'PO #${widget.purchaseOrder.poNumber} closed short (${unfulfilledItems.length} items cancelled).'),
            backgroundColor: Colors.teal.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to close PO short: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remainingItems =
        widget.purchaseOrder.items.where((i) => i.remainingQty > 0).toList();
    final int totalRemainingUnits = widget.purchaseOrder.totalRemainingQty;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.close_fullscreen_rounded,
                color: Colors.red.shade800, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Force-Close PO (Close Short)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to cancel the remaining unfulfilled balance on PO #${widget.purchaseOrder.poNumber}?',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),

              // Summary Box of items being cancelled
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Unfulfilled Remainder:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        Text(
                          '$totalRemainingUnits units (${remainingItems.length} items)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    ...remainingItems.take(5).map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.productName,
                                  style: const TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${item.remainingQty} units cancelled',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.red.shade800),
                              ),
                            ],
                          ),
                        )),
                    if (remainingItems.length > 5)
                      Text(
                        '+ ${remainingItems.length - 5} more items...',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Safe Notice Banner
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 18, color: Colors.blue.shade800),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Previously accepted stock and recorded delivery costs will remain intact and unaffected.',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Cancellation Reason Field
              TextFormField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Cancellation Reason *',
                  hintText: 'e.g. Supplier out of stock / Discontinued',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Reason required'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Keep in Backorder'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade800,
            foregroundColor: Colors.white,
          ),
          onPressed: _submitting ? null : _confirmCloseShort,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_rounded, size: 16),
          label: Text(_submitting ? 'Closing...' : 'Confirm Close Short'),
        ),
      ],
    );
  }
}
