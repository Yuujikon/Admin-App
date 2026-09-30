import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../providers/inventory_provider.dart';
import '../providers/order_provider.dart';
import '../providers/printer_provider.dart';
import '../utils/format.dart';

/// Modal triggered when an order is ready for Click & Collect cash payment.
/// Features order summary, walk-in item merging, cash calculator, change display,
/// and strict validation.
class PosCheckoutModal extends StatefulWidget {
  final PreOrder order;

  const PosCheckoutModal({
    super.key,
    required this.order,
  });

  static Future<StoreTransaction?> show(BuildContext context, PreOrder order) {
    return showModalBottomSheet<StoreTransaction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PosCheckoutModal(order: order),
    );
  }

  @override
  State<PosCheckoutModal> createState() => _PosCheckoutModalState();
}

class _PosCheckoutModalState extends State<PosCheckoutModal> {
  final TextEditingController _cashController = TextEditingController();
  final FocusNode _cashFocusNode = FocusNode();

  final List<CartItem> _walkInItems = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cashController.addListener(() => setState(() {}));
    // Request focus on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _cashFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _cashController.dispose();
    _cashFocusNode.dispose();
    super.dispose();
  }

  double get _digitalOrderTotal => widget.order.total;

  double get _walkInTotal => _walkInItems.fold(
        0.0,
        (sum, item) => sum + (item.price * item.qty),
      );

  double get _grandTotal => _digitalOrderTotal + _walkInTotal;

  double get _cashTendered => double.tryParse(_cashController.text.replaceAll(',', '')) ?? 0.0;

  double get _changeDue => (_cashTendered - _grandTotal) > 0 ? (_cashTendered - _grandTotal) : 0.0;

  bool get _isCashValid => _cashTendered >= _grandTotal && _grandTotal > 0;

  void _addQuickDenomination(double amount) {
    setState(() {
      _cashController.text = amount.toStringAsFixed(0);
      _cashController.selection = TextSelection.fromPosition(
        TextPosition(offset: _cashController.text.length),
      );
    });
  }

  void _setExactAmount() {
    setState(() {
      _cashController.text = _grandTotal.toStringAsFixed(2);
      _cashController.selection = TextSelection.fromPosition(
        TextPosition(offset: _cashController.text.length),
      );
    });
  }

  void _clearCash() {
    setState(() {
      _cashController.clear();
    });
  }

  void _openAddWalkInItemSheet() async {
    final Product? selectedProduct = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _WalkInItemPickerSheet(),
    );

    if (selectedProduct != null) {
      setState(() {
        final existingIdx = _walkInItems.indexWhere(
          (item) => item.productId == selectedProduct.id && item.variantId == null,
        );

        if (existingIdx >= 0) {
          final existing = _walkInItems[existingIdx];
          _walkInItems[existingIdx] = existing.copyWith(qty: existing.qty + 1);
        } else {
          _walkInItems.add(CartItem(
            productId: selectedProduct.id,
            name: selectedProduct.name,
            price: selectedProduct.price,
            costPrice: selectedProduct.costPrice,
            qty: 1,
            isPerishable: selectedProduct.isPerishable,
          ));
        }
      });
    }
  }

  Future<void> _completeCheckout() async {
    if (!_isCashValid || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final orderProvider = context.read<OrderProvider>();
      final printerProvider = context.read<PrinterProvider>();

      final tx = await orderProvider.completePickupWithCash(
        orderId: widget.order.id,
        cashTendered: _cashTendered,
        changeGiven: _changeDue,
        walkInItems: _walkInItems,
      );

      // Attempt printing receipt if configured
      try {
        await printerProvider.printReceipt(
          items: tx.items,
          total: tx.total,
          cash: tx.cashTendered,
          change: tx.changeGiven,
          orderId: widget.order.orderId,
          customerName: widget.order.customerName,
          orderType: "Click & Collect",
        );
      } catch (e) {
        debugPrint('Printer error during checkout: $e');
      }

      if (mounted) {
        Navigator.pop(context, tx);
        _showSuccessDialog(context, tx);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete sale: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSuccessDialog(BuildContext context, StoreTransaction tx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 56),
        title: const Text('Sale Completed!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Order #${widget.order.orderId} successfully collected.',
                style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Amount:'),
                      Text(formatPeso(tx.total),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cash Received:'),
                      Text(formatPeso(tx.cashTendered),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Change Returned:'),
                      Text(formatPeso(tx.changeGiven),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag Handle & Title
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.point_of_sale,
                        color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Checkout #${widget.order.orderId}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Customer: ${widget.order.customerName}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Order Summary Section
                    _buildOrderSummarySection(theme),

                    const SizedBox(height: 20),

                    // Tender Input Section (Cash Calculator)
                    _buildTenderInputSection(theme),

                    const SizedBox(height: 20),

                    // Change Display Section
                    _buildChangeDisplaySection(),

                    const SizedBox(height: 24),

                    // Action Button: Complete Sale
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: (_isCashValid && !_isProcessing)
                            ? _completeCheckout
                            : null,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_outline, size: 24),
                        label: Text(
                          _isProcessing
                              ? 'Processing...'
                              : 'Complete Sale (${formatPeso(_grandTotal)})',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummarySection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ORDER SUMMARY',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Colors.grey)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('READY FOR PICKUP',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Digital pre-order items list
          ...widget.order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text('${item.qty}x',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.name + (item.variantName != null ? ' (${item.variantName})' : ''),
                        style: const TextStyle(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(formatPeso(item.price * item.qty),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              )),

          // Walk-In additional items list
          if (_walkInItems.isNotEmpty) ...[
            const Divider(height: 16),
            const Text('WALK-IN ADDED ITEMS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange)),
            const SizedBox(height: 6),
            ..._walkInItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text('${item.qty}x',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(formatPeso(item.price * item.qty),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (item.qty > 1) {
                            _walkInItems[idx] =
                                item.copyWith(qty: item.qty - 1);
                          } else {
                            _walkInItems.removeAt(idx);
                          }
                        });
                      },
                      child: const Icon(Icons.remove_circle_outline,
                          size: 18, color: Colors.red),
                    ),
                  ],
                ),
              );
            }),
          ],

          const SizedBox(height: 8),

          // Button to merge physical store items into order
          OutlinedButton.icon(
            onPressed: _openAddWalkInItemSheet,
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Add Walk-In Item'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const Divider(height: 20),

          // Total Summary Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL AMOUNT DUE',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text(
                formatPeso(_grandTotal),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTenderInputSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CASH RECEIVED (₱)',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _cashController,
          focusNode: _cashFocusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.payments, size: 28),
            suffixIcon: _cashController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearCash,
                  )
                : null,
            hintText: '0.00',
            filled: true,
            fillColor: Colors.grey.shade100,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Quick Denomination Buttons Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildDenominationChip(50),
              const SizedBox(width: 8),
              _buildDenominationChip(100),
              const SizedBox(width: 8),
              _buildDenominationChip(500),
              const SizedBox(width: 8),
              _buildDenominationChip(1000),
              const SizedBox(width: 8),
              ActionChip(
                label: const Text('Exact',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                avatar: const Icon(Icons.check, size: 16),
                backgroundColor: Colors.green.shade50,
                side: BorderSide(color: Colors.green.shade300),
                onPressed: _setExactAmount,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDenominationChip(double amount) {
    final bool isSelected = _cashTendered == amount;
    return ChoiceChip(
      label: Text('₱${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.black87,
          )),
      selected: isSelected,
      selectedColor: Theme.of(context).colorScheme.primary,
      backgroundColor: Colors.grey.shade200,
      onSelected: (_) => _addQuickDenomination(amount),
    );
  }

  Widget _buildChangeDisplaySection() {
    final bool isValid = _isCashValid;
    final double shortfall = _grandTotal - _cashTendered;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isValid ? Colors.green.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isValid ? Colors.green.shade300 : Colors.amber.shade300,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.account_balance_wallet : Icons.error_outline,
            color: isValid ? Colors.green.shade700 : Colors.amber.shade900,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isValid ? 'CHANGE DUE' : 'SHORTFALL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: isValid ? Colors.green.shade800 : Colors.amber.shade900,
                  ),
                ),
                Text(
                  isValid
                      ? formatPeso(_changeDue)
                      : 'Need ${formatPeso(shortfall)} more',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isValid ? Colors.green.shade800 : Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yellow Warning Modal shown when scanning an order that is not bagged/ready yet.
class OrderNotBaggedDialog extends StatelessWidget {
  final PreOrder order;

  const OrderNotBaggedDialog({
    super.key,
    required this.order,
  });

  static Future<void> show(BuildContext context, PreOrder order) {
    return showDialog(
      context: context,
      builder: (ctx) => OrderNotBaggedDialog(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.amber.shade50,
      icon: Icon(Icons.warning_amber_rounded, size: 56, color: Colors.amber.shade900),
      title: Text(
        'Order is not bagged yet.',
        style: TextStyle(
          color: Colors.amber.shade900,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Order #${order.orderId} (${order.customerName}) is currently in "${order.status.name.toUpperCase()}" status.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${order.items.length} items waiting to be packed.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.amber.shade800,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Acknowledge'),
        ),
      ],
    );
  }
}

/// Sheet to pick store products to merge as walk-in items
class _WalkInItemPickerSheet extends StatefulWidget {
  const _WalkInItemPickerSheet();

  @override
  State<_WalkInItemPickerSheet> createState() => _WalkInItemPickerSheetState();
}

class _WalkInItemPickerSheetState extends State<_WalkInItemPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final products = inventory.products.where((p) {
      if (_search.isEmpty) return true;
      return p.name.toLowerCase().contains(_search.toLowerCase()) ||
          (p.barcode != null && p.barcode!.contains(_search));
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Add Walk-In Store Item',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search product or scan barcode...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: products.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final p = products[idx];
                return ListTile(
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Stock: ${p.stock} | ₱${p.price.toStringAsFixed(2)}'),
                  trailing: ElevatedButton(
                    onPressed: p.stock > 0 ? () => Navigator.pop(context, p) : null,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Add'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
