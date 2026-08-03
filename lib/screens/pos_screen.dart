import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import '../providers/inventory_provider.dart';
import '../widgets/qty_control.dart';
import '../widgets/scanner_dialog.dart';
import '../utils/format.dart';
import '../models/customer.dart';
import '../providers/printer_provider.dart';
import '../config/theme.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final List<CartItem> _cart = [];
  final _barcodeFocus = FocusNode();
  final _barcodeCtrl  = TextEditingController();
  final _cashCtrl     = TextEditingController();
  String _cash = '';
  bool   _done = false;
  Customer? _selectedCustomer;
  
  // Store data for the receipt
  List<CartItem> _lastItems = [];
  double _lastTotal = 0, _lastCash = 0, _lastChange = 0;

  @override
  void dispose() {
    _barcodeFocus.dispose();
    _barcodeCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
  }

  double get _total => _cart.fold(0, (s, item) {
    final products = context.read<InventoryProvider>().products;
    try {
      final p = products.firstWhere((p) => p.id == item.productId);
      final price = (p.wholesalePrice != null && p.wholesaleThreshold != null && item.qty >= p.wholesaleThreshold!)
          ? p.wholesalePrice!
          : p.price;
      return s + price * item.qty;
    } catch (_) {
      return s + item.price * item.qty;
    }
  });
  
  double get _cashNum => double.tryParse(_cash) ?? 0;
  double get _change  => (_cashNum - _total).clamp(0, double.infinity);

  void _toggle(Product p) => setState(() {
    final idx = _cart.indexWhere((c) => c.productId == p.id);
    if (idx >= 0) {
      _cart.removeAt(idx);
    } else {
      _cart.add(CartItem(
        productId: p.id, 
        name: p.name, 
        price: p.price, 
        qty: 1, 
        isPerishable: p.isPerishable
      ));
    }
  });

  void _onBarcodeSubmit(String code, List<Product> products) {
    if (code.isEmpty) return;
    
    // Search for an exact barcode match
    final matches = products.where((p) => p.barcode == code).toList();
    
    if (matches.isNotEmpty) {
      final p = matches.first;
      setState(() {
        final idx = _cart.indexWhere((c) => c.productId == p.id);
        if (idx >= 0) {
          // Increment if within stock
          if (_cart[idx].qty < p.stock) {
            _cart[idx] = _cart[idx].copyWith(qty: _cart[idx].qty + 1);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cannot add more. Only ${p.stock} in stock.'))
            );
          }
        } else {
          _cart.add(CartItem(
            productId: p.id, 
            name: p.name, 
            price: p.price, 
            qty: 1, 
            isPerishable: p.isPerishable
          ));
        }
      });
      _barcodeCtrl.clear();
      _barcodeFocus.requestFocus(); 
    } else {
      // It's likely a search query. The list is already filtered via the TextField's onChanged.
      // Just hide the keyboard so they can see the results.
      _barcodeFocus.unfocus();
    }
  }

  void _adjustQty(String id, int delta) => setState(() {
    final idx = _cart.indexWhere((c) => c.productId == id);
    if (idx < 0) return;
    
    final products = context.read<InventoryProvider>().products;
    final stock = products.firstWhere((p) => p.id == id, orElse: () => throw 'Product not found').stock;

    _cart[idx] = _cart[idx].copyWith(qty: (_cart[idx].qty + delta).clamp(1, stock));
  });

  Future<void> _completeSale() async {
    final inventory = context.read<InventoryProvider>();
    
    // Check if store is closed
    if (inventory.settings.effectivelyClosed) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Store is CLOSED'),
          content: const Text('The store is currently marked as CLOSED or scheduled to be closed. Do you still want to process this walk-in sale?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Proceed Anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (_cart.isEmpty) return;
    if (_cashNum < _total) return;

    // Safety Warning for important action
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Transaction?'),
        content: Text(
          'Total: ${formatPeso(_total)}\n'
          'Cash: ${formatPeso(_cashNum)}\n'
          'Change: ${formatPeso(_change)}'
          '${_selectedCustomer != null ? "\nCustomer: ${_selectedCustomer?.name}" : ""}'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go Back')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm Sale')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final inventory = context.read<InventoryProvider>();
      final products = inventory.products;
      
      // Map cart items to their effective prices (handling wholesale)
      final items = _cart.map((item) {
        final p = products.firstWhere((p) => p.id == item.productId);
        final bool isWholesale = p.wholesalePrice != null && 
                               p.wholesaleThreshold != null && 
                               item.qty >= p.wholesaleThreshold!;
        return item.copyWith(price: isWholesale ? p.wholesalePrice! : p.price);
      }).toList();

      final total = _total;
      final cash = _cashNum;
      final change = _change;

      final printer = context.read<PrinterProvider>();

      await inventory.completeSale(
        items, 
        cash,
        customerId: _selectedCustomer?.id,
        paymentMethod: PaymentMethod.cash,
      );
      
      if (!mounted) return;

      // Auto-print if printer is connected
      if (printer.connected) {
        printer.printReceipt(
          items: items,
          total: total,
          cash: cash,
          change: change,
        );
      }

      setState(() { 
        _lastItems = items;
        _lastTotal = total;
        _lastCash = cash;
        _lastChange = change;
        _cart.clear(); 
        _cash = ''; 
        _cashCtrl.clear();
        _selectedCustomer = null;
        _done = true; 
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error completing sale: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return _ReceiptScreen(
        items: _lastItems,
        total: _lastTotal,
        cash: _lastCash,
        change: _lastChange,
        onNewSale: () => setState(() => _done = false),
      );
    }

    final inventory = context.watch<InventoryProvider>();
    final products  = inventory.sortedProducts;
    final isTablet  = MediaQuery.of(context).size.width >= 600;

    return Column(
      children: [
        // ── Unified Search & Scan Header ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcodeCtrl,
                  focusNode: _barcodeFocus,
                  onSubmitted: (v) => _onBarcodeSubmit(v, products),
                  onChanged: (_) => setState(() {}), // Trigger real-time filtering
                  decoration: InputDecoration(
                    hintText: 'Scan or search products…',
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_barcodeCtrl.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() {
                              _barcodeCtrl.clear();
                              _barcodeFocus.requestFocus();
                            }),
                          ),
                        IconButton(
                          icon: const Icon(Icons.camera_alt_outlined),
                          onPressed: () => _scanCamera(products),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(child: _buildSaleBody(isTablet, products)),
      ],
    );
  }

  Future<void> _scanCamera(List<Product> products) async {
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => const ScannerDialog(),
    );
    if (code != null) {
      _onBarcodeSubmit(code, products);
    }
  }

  Widget _buildSaleBody(bool isTablet, List<Product> products) {
    // Filter products based on the search/barcode text if it's not a direct match
    final query = _barcodeCtrl.text.toLowerCase();
    final filtered = products
        .where((p) => p.stock > 0)
        .where((p) => p.name.toLowerCase().contains(query) || 
                      (p.barcode != null && p.barcode!.contains(query)))
        .toList();

    if (isTablet) {
      return Row(children: [
        Expanded(child: _ProductGrid(products: filtered, cart: _cart, onToggle: _toggle)),
        SizedBox(width: 300,
            child: _CartPanel(
              cart: _cart, cash: _cash, cashCtrl: _cashCtrl,
              total: _total, cashNum: _cashNum, change: _change,
              products: products,
              selectedCustomer: _selectedCustomer,
              onCash: (v) => setState(() => _cash = v),
              onAdjust:   _adjustQty,
              onRemove:   (id) => setState(() => _cart.removeWhere((c) => c.productId == id)),
              onComplete: _completeSale,
              onSelectCustomer: (c) => setState(() => _selectedCustomer = c),
            )),
      ]);
    }

    return Column(children: [
      Expanded(child: _ProductGrid(products: filtered, cart: _cart, onToggle: _toggle)),
      if (_cart.isNotEmpty)
        GestureDetector(
          onVerticalDragUpdate: (_) {}, // Prevent accidental swipes
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: _CartPanel(
              cart: _cart, cash: _cash, cashCtrl: _cashCtrl,
              total: _total, cashNum: _cashNum, change: _change,
              products: products,
              selectedCustomer: _selectedCustomer,
              onCash: (v) => setState(() => _cash = v),
              onAdjust:   _adjustQty,
              onRemove:   (id) => setState(() => _cart.removeWhere((c) => c.productId == id)),
              onComplete: _completeSale,
              onSelectCustomer: (c) => setState(() => _selectedCustomer = c),
            ),
          ),
        ),
    ]);
  }
}

// ── Product grid ───────────────────────────────────────────────────────────


class _ProductGrid extends StatefulWidget {
  final List<Product> products;
  final List<CartItem> cart;
  final ValueChanged<Product> onToggle;
  const _ProductGrid({required this.products, required this.cart, required this.onToggle});
  @override State<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<_ProductGrid> {
  String _cat    = 'All';

  @override
  Widget build(BuildContext context) {
    final cats = ['All', ...widget.products.map((p) => p.category).toSet().toList()..sort()];
    final filtered = widget.products
        .where((p) => _cat == 'All' || p.category == _cat)
        .toList();

    return Column(children: [
      SizedBox(height: 52, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => FilterChip(
              label: Text(cats[i], style: const TextStyle(fontSize: 12)),
              selected: _cat == cats[i],
              onSelected: (_) => setState(() => _cat = cats[i])))),
      Expanded(child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160, childAspectRatio: 0.85,
              crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final p      = filtered[i];
            final inCart = widget.cart.any((c) => c.productId == p.id);
            return GestureDetector(
              onTap: () => widget.onToggle(p),
              child: Container(
                decoration: BoxDecoration(
                  color: inCart ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05) : Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: inCart ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                    width: inCart ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: Colors.grey.shade50,
                      child: p.photoBase64 != null
                        ? Image.memory(base64Decode(p.photoBase64!), fit: BoxFit.cover)
                        : Icon(Icons.inventory_2_outlined, color: Colors.grey.shade200, size: 32),
                    ),
                  ),
                  Padding(padding: const EdgeInsets.all(10), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.category.toUpperCase(),
                        style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(p.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.1),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatPeso(p.price),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w900, fontSize: 14)),
                        if (p.stock <= 5)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('${p.stock}',
                                style: TextStyle(fontSize: 10,
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w900)),
                          )
                        else
                          Text('${p.stock} left', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                      ],
                    ),
                  ])),
                ]),
              ),
            );
          })),
    ]);
  }
}

// ── Cart panel ─────────────────────────────────────────────────────────────

class _CartPanel extends StatelessWidget {
  final List<CartItem> cart;
  final String cash;
  final TextEditingController cashCtrl;
  final double total, cashNum, change;
  final List<Product> products;
  final Customer? selectedCustomer;
  final ValueChanged<String> onCash;
  final void Function(String, int) onAdjust;
  final ValueChanged<String> onRemove;
  final VoidCallback onComplete;
  final ValueChanged<Customer?> onSelectCustomer;

  const _CartPanel({
    required this.cart, required this.cash, required this.cashCtrl,
    required this.total, required this.cashNum, required this.change,
    required this.products,
    required this.selectedCustomer,
    required this.onCash, required this.onAdjust,
    required this.onRemove, required this.onComplete,
    required this.onSelectCustomer,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 20,
          offset: const Offset(0, -5),
        )
      ],
    ),
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 40, height: 4,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2)),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Your Cart', style: Theme.of(context).textTheme.titleLarge),
          if (cart.isNotEmpty)
            Text('${cart.length} items', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
      const SizedBox(height: 16),
      if (cart.isEmpty)
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shopping_bag_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1), size: 80),
              const SizedBox(height: 12),
              Text('Cart is empty', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3), fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        )
      else
        Flexible(child: ListView.separated(
          shrinkWrap: true,
          itemCount: cart.length,
          separatorBuilder: (_, __) => Divider(height: 24, color: Colors.grey.shade50),
          itemBuilder: (_, i) {
            final item = cart[i];
            final products = context.read<InventoryProvider>().products;
            final product = products.firstWhere((p) => p.id == item.productId, orElse: () => throw 'Product not found');
            final stock = product.stock;
            
            final bool isWholesale = product.wholesalePrice != null && 
                                   product.wholesaleThreshold != null && 
                                   item.qty >= product.wholesaleThreshold!;
            
            final effectivePrice = isWholesale ? product.wholesalePrice! : item.price;

            return Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(formatPeso(effectivePrice),
                            style: TextStyle(fontSize: 12, color: isWholesale ? Colors.blue.shade700 : Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                        if (isWholesale) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                            child: const Text('WHOLESALE', style: TextStyle(fontSize: 8, color: Colors.blue, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              QtyControl(
                  qty: item.qty,
                  max: stock,
                  onChanged: (n) => onAdjust(item.productId, n - item.qty)),
              const SizedBox(width: 8),
              Text(formatPeso(effectivePrice * item.qty),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(width: 4),
              IconButton(
                  onPressed: () => onRemove(item.productId),
                  icon: Icon(Icons.remove_circle_outline, size: 18, color: Colors.red.shade300),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ]);
          },
        )),
      const Divider(height: 32),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Total Amount', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(formatPeso(total),
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Theme.of(context).colorScheme.primary)),
      ]),
      const SizedBox(height: 20),
      
      if (cart.isNotEmpty) ...[
        // Cash Input
        TextField(
          controller: cashCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onCash,
          decoration: InputDecoration(
            labelText: 'Cash Received',
            prefixText: '₱ ',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: cash.isNotEmpty ? IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                cashCtrl.clear();
                onCash('');
              },
            ) : null,
          ),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        
        // Quick Cash Buttons
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [20, 50, 100, 200, 500, 1000].map((amt) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  onPressed: () {
                    final current = double.tryParse(cash) ?? 0;
                    final newVal = current + amt;
                    cashCtrl.text = newVal.toStringAsFixed(0);
                    onCash(cashCtrl.text);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('+$amt', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
      ],
      
      // Customer / Rewards Selection
      if (cart.isNotEmpty)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          tileColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
          leading: Icon(Icons.stars_rounded, color: Theme.of(context).colorScheme.primary),
          title: Text(selectedCustomer?.name ?? 'Select Customer for Rewards',
              style: TextStyle(color: selectedCustomer == null ? Colors.grey : Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: selectedCustomer != null ? Text('Earns ${(total / 100).floor()} points', style: const TextStyle(fontSize: 10)) : null,
          trailing: const Icon(Icons.expand_more_rounded),
          onTap: () => _showCustomerPicker(context),
        ),

      if (cashNum >= total && cart.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Change Due:', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(formatPeso(change), style: TextStyle(color: Theme.of(context).semantic.success, fontWeight: FontWeight.w900, fontSize: 18)),
              ],
            )),
      const SizedBox(height: 20),
      ElevatedButton(
          onPressed: cart.isNotEmpty && cashNum >= total ? onComplete : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            elevation: 8,
            shadowColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded),
              SizedBox(width: 10),
              Text('COMPLETE SALE'),
            ],
          )),
    ]),
  );

  void _showCustomerPicker(BuildContext context) async {
    final inventory = context.read<InventoryProvider>();
    final customers = inventory.customers;

    final res = await showDialog<Customer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Customer'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: customers.length,
            itemBuilder: (context, i) => ListTile(
              leading: Icon(Icons.stars_rounded, color: Theme.of(context).colorScheme.primary),
              title: Text(customers[i].name),
              subtitle: Text('Points: ${customers[i].loyaltyPoints}'),
              onTap: () => Navigator.pop(ctx, customers[i]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (res != null) {
      onSelectCustomer(res);
    }
  }
}

// ── Receipt / done screen ──────────────────────────────────────────────────

class _ReceiptScreen extends StatelessWidget {
  final List<CartItem> items;
  final double total, cash, change;
  final VoidCallback onNewSale;
  
  const _ReceiptScreen({
    required this.items,
    required this.total,
    required this.cash,
    required this.change,
    required this.onNewSale
  });

  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterProvider>();
    
    return Center(child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, color: GdcColors.successLight, size: 72),
        const SizedBox(height: 16),
        Text('Sale Complete!',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Transaction saved to Firebase',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        
        // Item Summary in Receipt
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 12),
            itemBuilder: (_, i) => Row(
              children: [
                Expanded(child: Text(items[i].name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                Text('x${items[i].qty}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 12),
                Text(formatPeso(items[i].price * items[i].qty), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TOTAL PAID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text(formatPeso(total), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
          ],
        ),
        
        if (total >= 100) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Text('+${(total / 100).floor()} Loyalty Points Earned', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 32),
        
        if (printer.connected)
          ElevatedButton.icon(
            onPressed: () => printer.printReceipt(
              items: items, 
              total: total, 
              cash: cash, 
              change: change
            ), 
            icon: const Icon(Icons.print),
            label: const Text('PRINT RECEIPT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 12),
                Expanded(child: Text('Printer not connected. Connect in the top menu to print receipts.', style: TextStyle(fontSize: 12))),
              ],
            ),
          ),
          
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: onNewSale, 
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('NEW TRANSACTION'),
        ),
      ],
      ),
    ));
  }
}
