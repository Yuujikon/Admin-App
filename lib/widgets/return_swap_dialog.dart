import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../models/batch.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import '../providers/inventory_provider.dart';
import '../services/firestore_service.dart';
import '../utils/format.dart';

enum ItemCondition { goodRestock, damagedWriteOff }

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
  final TextEditingController _manualBarcodeCtrl = TextEditingController();

  CartItem? _matchedItem;
  String? _errorMessage;
  bool _isProcessing = false;

  // Inspection Gate State
  ItemCondition? _selectedCondition = ItemCondition.goodRestock;
  ReturnActionType _actionType = ReturnActionType.cashRefund;
  String? _preferredBatchId;
  int _returnQty = 1;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualBarcodeCtrl.dispose();
    super.dispose();
  }

  void _processScannedBarcode(String rawBarcode) {
    final cleanInput = rawBarcode.trim();
    if (cleanInput.isEmpty) return;

    final String normalized =
        cleanInput.replaceAll('#', '').toLowerCase().trim();

    setState(() {
      _errorMessage = null;
    });

    final items = widget.transaction.items;

    // 1. Check if input matches Receipt # / Order ID / Transaction ID
    final String txId = widget.transaction.id.replaceAll('#', '').toLowerCase();
    final String? orderId = widget.orderId?.replaceAll('#', '').toLowerCase();

    final bool isReceiptMatch = normalized.isNotEmpty &&
        (txId == normalized ||
            txId.contains(normalized) ||
            normalized.contains(txId) ||
            (orderId != null &&
                (orderId == normalized ||
                    orderId.contains(normalized) ||
                    normalized.contains(orderId))));

    if (isReceiptMatch) {
      final returnableItems =
          items.where((i) => i.returnedQty < i.qty).toList();
      _showItemPickerForReceipt(returnableItems);
      return;
    }

    // 2. Match by Item Barcode
    int matchingIndex = items.indexWhere((i) {
      final b = i.barcode.replaceAll('#', '').toLowerCase();
      return b.isNotEmpty && (b == normalized || b.contains(normalized));
    });

    // 3. Match by Product Name
    if (matchingIndex < 0) {
      matchingIndex =
          items.indexWhere((i) => i.name.toLowerCase().contains(normalized));
    }

    if (matchingIndex < 0) {
      // Fallback: If receipt has available returnable items, open item selection dialog
      final returnableItems =
          items.where((i) => i.returnedQty < i.qty).toList();
      if (returnableItems.isNotEmpty) {
        _showItemPickerForReceipt(returnableItems);
        return;
      }

      setState(() {
        _errorMessage =
            'Mismatch: Barcode/Number "$cleanInput" was not found on this receipt.';
      });
      return;
    }

    final matched = items[matchingIndex];
    if (matched.returnedQty >= matched.qty) {
      setState(() {
        _errorMessage =
            'All units of "${matched.name}" on this receipt have already been returned.';
      });
      return;
    }

    setState(() {
      _matchedItem = matched;
      _returnQty = 1;
      _selectedCondition = ItemCondition.goodRestock;
      _preferredBatchId = null;
      _errorMessage = null;
    });
  }

  void _showItemPickerForReceipt([List<CartItem>? customItems]) {
    final availableItems = customItems ??
        widget.transaction.items.where((i) => i.returnedQty < i.qty).toList();

    if (availableItems.isEmpty) {
      setState(() {
        _errorMessage = 'All items on this receipt have already been returned.';
      });
      return;
    }

    if (availableItems.length == 1) {
      setState(() {
        _matchedItem = availableItems.first;
        _returnQty = 1;
        _selectedCondition = null;
        _errorMessage = null;
      });
      return;
    }

    showDialog<CartItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Item to Return / Swap',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableItems.length,
            itemBuilder: (ctx, i) {
              final item = availableItems[i];
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

  void _showUnbarcodedPicker() => _showItemPickerForReceipt();

  Future<void> _confirmReturn() async {
    if (_matchedItem == null || _selectedCondition == null || _isProcessing) {
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final fs = FirestoreService();
      final isCash = _actionType == ReturnActionType.cashRefund;
      final isGood = _selectedCondition == ItemCondition.goodRestock;
      final inventory = context.read<InventoryProvider>();

      final result = await fs.processItemReturn(
        transactionId: widget.transaction.id,
        orderId: widget.orderId ?? widget.transaction.orderId,
        productId: _matchedItem!.productId,
        variantId: _matchedItem!.variantId,
        barcode: _matchedItem!.barcode,
        returnQty: _returnQty,
        isCashRefund: isCash,
        isDamagedSwap: !isGood,
        condition: isGood ? 'SELLABLE' : 'DAMAGED',
        preferredBatchId: _preferredBatchId,
        productName: _matchedItem!.name,
        unitPrice: _matchedItem!.unitPriceAtSale,
        settings: inventory.settings,
      );

      if (mounted) {
        inventory.initialize();

        final batchSummary = isGood
            ? result.restoredAllocations
                .map((a) => '${a.batchId} (+${a.qtyReturned})')
                .join(', ')
            : result.writtenOffAllocations
                .map((a) => '${a.batchId} (${a.qtyReturned} write-off)')
                .join(', ');

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCash
                  ? (isGood
                      ? 'Refund Processed! $_returnQty unit(s) restored to original batch${batchSummary.isNotEmpty ? " ($batchSummary)" : ""}.'
                      : 'Refund Processed! $_returnQty damaged unit(s) written off${batchSummary.isNotEmpty ? " ($batchSummary)" : ""} (not restocked).')
                  : '1-to-1 Item Swap Processed for "${_matchedItem!.name}"${batchSummary.isNotEmpty ? " ($batchSummary)" : ""}.',
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
                const Text(
                  'OR ENTER ITEM / RECEIPT BARCODE NUMBER:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualBarcodeCtrl,
                        decoration: InputDecoration(
                          hintText: 'Type item or receipt barcode number...',
                          isDense: true,
                          prefixIcon:
                              const Icon(Icons.qr_code_rounded, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        onSubmitted: (val) => _processScannedBarcode(val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () =>
                          _processScannedBarcode(_manualBarcodeCtrl.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Verify'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                // STEP 3: Batch Backtracking, Condition Choice & Action
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                                Text(
                                  'Original Sale: ${DateFormat('MMM d, yyyy h:mm a').format(widget.transaction.createdAt)}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.teal.shade800),
                                ),
                                Text(
                                  'Price: ${formatPeso(_matchedItem!.price)} • Bought: ${_matchedItem!.qty} • Returned: ${_matchedItem!.returnedQty}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _matchedItem = null;
                              _preferredBatchId = null;
                            }),
                            child: const Text('Rescan'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(builder: (context) {
                        final allocs = _matchedItem!.batchAllocations
                            .where((a) =>
                                a.batchId.isNotEmpty &&
                                !a.batchId.startsWith('fallback-') &&
                                !a.batchId.startsWith('variant-'))
                            .toList();
                        if (allocs.isEmpty) {
                          return Text(
                            'Legacy Receipt: Restocking will restore to oldest active batch or create a RETURN-RESTORE batch.',
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.amber.shade900),
                          );
                        }
                        return Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: allocs.map((a) {
                            final refLabel = (a.poNumber != null &&
                                    a.poNumber!.trim().isNotEmpty)
                                ? ProductBatch.formatPoNumber(a.poNumber!)
                                : ProductBatch.formatBatchIdForDisplay(
                                    a.batchId);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.teal.shade300),
                              ),
                              child: Text(
                                'Source: $refLabel (${a.qtyDeducted}x @ ${formatPeso(a.costPrice)})',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.teal.shade900,
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                const Text(
                  'RETURN CONDITION & BATCH DISPOSITION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),

                RadioGroup<ItemCondition>(
                  groupValue: _selectedCondition,
                  onChanged: (v) => setState(() => _selectedCondition = v),
                  child: const Column(
                    children: [
                      RadioListTile<ItemCondition>(
                        title: Text(
                          'Option A — Good Condition (Restock to Original Batch)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.green),
                        ),
                        subtitle: Text(
                          'Restores qty back to original FIFO batch (reactivates DEPLETED batches to front of queue).',
                        ),
                        value: ItemCondition.goodRestock,
                        activeColor: Colors.green,
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<ItemCondition>(
                        title: Text(
                          'Option B — Damaged / Defective (Write-Off)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.red),
                        ),
                        subtitle: Text(
                          'Does NOT restore stock or batch qty; logs permanent write-off against exact original batch.',
                        ),
                        value: ItemCondition.damagedWriteOff,
                        activeColor: Colors.red,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
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
                      label:
                          Text('Cash Refund', style: TextStyle(fontSize: 12)),
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

                if (_matchedItem!.batchAllocations.length > 1) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _preferredBatchId,
                    decoration: const InputDecoration(
                      labelText: 'Target Original Batch (Multi-Batch Sale)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Auto (Reverse FIFO Allocation Order)'),
                      ),
                      ..._matchedItem!.batchAllocations.map(
                        (a) => DropdownMenuItem<String?>(
                          value: a.batchId,
                          child: Text('${a.batchId} (${a.qtyDeducted} sold)'),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _preferredBatchId = v),
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_selectedCondition != null && !_isProcessing)
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
