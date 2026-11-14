import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import '../providers/inventory_provider.dart';
import '../services/firestore_service.dart';
import '../utils/format.dart';

enum ItemCondition { unopenedSealed, openedBroken }

enum ReturnActionType { cashRefund, itemSwap }

/// Counter Dual-Scan Verification & Physical Seal Gate for Returns / Swaps.
class ReturnSwapDialog extends StatefulWidget {
  final StoreTransaction transaction;
  final String? orderId;

  const ReturnSwapDialog({
    super.key,
    required this.transaction,
    this.orderId,
  });

  static Future<void> show(BuildContext context, StoreTransaction tx,
      {String? orderId}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReturnSwapDialog(transaction: tx, orderId: orderId),
    );
  }

  @override
  State<ReturnSwapDialog> createState() => _ReturnSwapDialogState();
}

class _ReturnSwapDialogState extends State<ReturnSwapDialog> {
  final MobileScannerController _scannerController = MobileScannerController();

  CartItem? _matchedItem;
  String? _errorMessage;
  bool _hasScanned = false;
  bool _isProcessing = false;

  // Inspection Gate State
  ItemCondition? _selectedCondition;
  ReturnActionType _actionType = ReturnActionType.cashRefund;
  bool _isDamagedSwap = false;
  int _returnQty = 1;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _processScannedBarcode(String rawBarcode) {
    if (_hasScanned) return;
    final cleanBarcode = rawBarcode.trim();
    if (cleanBarcode.isEmpty) return;

    setState(() {
      _hasScanned = true;
      _errorMessage = null;
    });

    // Check receipt saved items array for barcode match
    final items = widget.transaction.items;
    final matchingIndex = items.indexWhere((i) => i.barcode == cleanBarcode);

    if (matchingIndex < 0) {
      setState(() {
        _hasScanned = false;
        _errorMessage =
            'Item Mismatch: Barcode [$cleanBarcode] was not part of this receipt.';
      });
      return;
    }

    final matched = items[matchingIndex];
    if (matched.returnedQty >= matched.qty) {
      setState(() {
        _hasScanned = false;
        _errorMessage =
            'All units of "${matched.name}" on this receipt have already been returned.';
      });
      return;
    }

    setState(() {
      _matchedItem = matched;
      _returnQty = 1;
      _selectedCondition = null;
      _errorMessage = null;
    });
  }

  void _showUnbarcodedPicker() {
    final unbarcodedItems = widget.transaction.items
        .where((i) => i.barcode.isEmpty && i.returnedQty < i.qty)
        .toList();

    if (unbarcodedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No unbarcoded items available for return on this receipt.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog<CartItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Unbarcoded Item',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: unbarcodedItems.length,
            itemBuilder: (ctx, i) {
              final item = unbarcodedItems[i];
              final availableQty = item.qty - item.returnedQty;
              return ListTile(
                title: Text(item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'Qty bought: ${item.qty} • Returned: ${item.returnedQty} (Available: $availableQty)'),
                trailing: Text(formatPeso(item.price)),
                onTap: () => Navigator.pop(ctx, item),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
        ],
      ),
    ).then((selected) {
      if (selected != null) {
        setState(() {
          _matchedItem = selected;
          _returnQty = 1;
          _selectedCondition = null;
          _errorMessage = null;
        });
      }
    });
  }

  Future<void> _confirmReturn() async {
    if (_matchedItem == null ||
        _selectedCondition != ItemCondition.unopenedSealed ||
        _isProcessing) {
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final fs = FirestoreService();
      final isCash = _actionType == ReturnActionType.cashRefund;

      await fs.processItemReturn(
        transactionId: widget.transaction.id,
        orderId: widget.orderId,
        productId: _matchedItem!.productId,
        variantId: _matchedItem!.variantId,
        barcode: _matchedItem!.barcode,
        returnQty: _returnQty,
        isCashRefund: isCash,
        isDamagedSwap: !isCash && _isDamagedSwap,
      );

      if (mounted) {
        // Refresh local inventory state
        context.read<InventoryProvider>().initialize();

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCash
                  ? 'Cash Refund Processed! $_returnQty unit(s) of "${_matchedItem!.name}" restocked.'
                  : '1-to-1 Item Swap Processed for "${_matchedItem!.name}".',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing return: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.published_with_changes_rounded,
                          color: Colors.teal, size: 24),
                      SizedBox(width: 10),
                      Text(
                        'Process Return / Swap',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_matchedItem == null) ...[
                // STEP 2: Live Barcode Match
                const Text(
                  'STEP 2: SCAN PHYSICAL ITEM BARCODE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Scan the barcode printed on the item handed over by the customer to verify it against this receipt.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),

                Container(
                  height: 200,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final raw = barcodes.first.rawValue;
                        if (raw != null) {
                          _processScannedBarcode(raw);
                        }
                      }
                    },
                  ),
                ),

                const SizedBox(height: 16),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _showUnbarcodedPicker,
                    icon: const Icon(Icons.touch_app_rounded, size: 18),
                    label: const Text('Manual Select (No Barcode on Item)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ] else ...[
                // STEP 3: Inspection Gate & Action
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.teal, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _matchedItem!.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              'Barcode: ${_matchedItem!.barcode.isNotEmpty ? _matchedItem!.barcode : "N/A"} • Price: ${formatPeso(_matchedItem!.price)}',
                              style: const TextStyle(
                                  fontSize: 11, fontFamily: 'monospace'),
                            ),
                            Text(
                              'Bought: ${_matchedItem!.qty} • Already Returned: ${_matchedItem!.returnedQty}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _matchedItem = null;
                          _hasScanned = false;
                        }),
                        child: const Text('Rescan'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                const Text(
                  'PHYSICAL SEAL & CONDITION CHECK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),

                RadioListTile<ItemCondition>(
                  title: const Text('Unopened & Factory Sealed',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text(
                      'Packaging is intact, unbroken seal. Eligible for return/swap.'),
                  value: ItemCondition.unopenedSealed,
                  groupValue: _selectedCondition,
                  onChanged: (v) => setState(() => _selectedCondition = v),
                  activeColor: Colors.teal,
                  contentPadding: EdgeInsets.zero,
                ),

                RadioListTile<ItemCondition>(
                  title: const Text('Opened / Seal Broken',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.red)),
                  subtitle:
                      const Text('Package has been opened or seal tampered.'),
                  value: ItemCondition.openedBroken,
                  groupValue: _selectedCondition,
                  onChanged: (v) => setState(() => _selectedCondition = v),
                  activeColor: Colors.red,
                  contentPadding: EdgeInsets.zero,
                ),

                if (_selectedCondition == ItemCondition.openedBroken) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.block_rounded, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Refund Blocked: Opened items cannot be refunded or swapped per store policy.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_selectedCondition == ItemCondition.unopenedSealed) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'SELECT RETURN ACTION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ReturnActionType>(
                    segments: const [
                      ButtonSegment(
                        value: ReturnActionType.cashRefund,
                        label: Text('Cash Refund (+Restock)',
                            style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.attach_money_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: ReturnActionType.itemSwap,
                        label: Text('1-to-1 Item Swap',
                            style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.swap_horiz_rounded, size: 16),
                      ),
                    ],
                    selected: {_actionType},
                    onSelectionChanged: (s) =>
                        setState(() => _actionType = s.first),
                  ),
                  if (_actionType == ReturnActionType.itemSwap) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text(
                          'Mark returned unit as Damaged / Expired (-1 sellable stock)',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                          'Check this if returned unit cannot go back to sellable shelf.'),
                      value: _isDamagedSwap,
                      onChanged: (v) =>
                          setState(() => _isDamagedSwap = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Quantity to return:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      DropdownButton<int>(
                        value: _returnQty,
                        items: List.generate(
                          _matchedItem!.qty - _matchedItem!.returnedQty,
                          (i) => DropdownMenuItem(
                              value: i + 1, child: Text('${i + 1}')),
                        ),
                        onChanged: (v) {
                          if (v != null) setState(() => _returnQty = v);
                        },
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        (_selectedCondition == ItemCondition.unopenedSealed &&
                                !_isProcessing)
                            ? _confirmReturn
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Confirm Refund / 1-to-1 Swap',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
