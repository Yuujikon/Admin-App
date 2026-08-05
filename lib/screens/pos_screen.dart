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
import '../providers/order_provider.dart';
import '../providers/printer_provider.dart';
import '../utils/pricing_engine.dart';
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
  bool   _redeemPoints = false; 
  bool   _isSeniorPWD = false; 
  bool   _done = false;
  Customer? _selectedCustomer;
  
  List<CartItem> _lastItems = [];
  double _lastTotal = 0, _lastCash = 0, _lastChange = 0;

  @override
  void dispose() {
    _barcodeFocus.dispose();
    _barcodeCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
  }

  PricingBreakdown get _breakdown {
    final products = context.read<InventoryProvider>().products;
    final orderProvider = context.read<OrderProvider>();
    
    // Apply wholesale prices to items before calculating
    final itemsWithWholesale = _cart.map((item) {
      try {
        final p = products.firstWhere((p) => p.id == item.productId);
        final bool isWholesale = p.wholesalePrice != null && item.qty >= (p.wholesaleThreshold ?? 999);
        return item.copyWith(price: isWholesale ? p.wholesalePrice! : p.price);
      } catch (_) {
        return item;
      }
    }).toList();

    return PricingEngine.calculate(
      items: itemsWithWholesale, 
      allProducts: products, 
      activePromos: orderProvider.promotions,
      pointsToRedeem: (_redeemPoints && _selectedCustomer != null) ? _selectedCustomer!.loyaltyPoints : 0,
      isSeniorOrPWD: _isSeniorPWD,
    );
  }

  double get _total => _breakdown.total;
  
  double get _cashNum => double.tryParse(_cash) ?? 0;
  double get _change  => (_cashNum - _total).clamp(0, double.infinity);

  void _toggle(Product p) => setState(() {
    final idx = _cart.indexWhere((c) => c.productId == p.id);
    if (idx >= 0) {
      _cart.removeAt(idx);
    } else {
      _cart.insert(0, CartItem(productId: p.id, name: p.name, price: p.price, qty: 1, isPerishable: p.isPerishable));
    }
  });

  void _onBarcodeSubmit(String code, List<Product> products) {
    if (code.isEmpty) return;
    final matches = products.where((p) => p.barcode == code).toList();
    if (matches.isNotEmpty) {
      final p = matches.first;
      setState(() {
        final idx = _cart.indexWhere((c) => c.productId == p.id);
        if (idx >= 0) {
          if (_cart[idx].qty < p.stock) {
            _cart[idx] = _cart[idx].copyWith(qty: _cart[idx].qty + 1);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max stock reached.')));
          }
        } else {
          _cart.insert(0, CartItem(productId: p.id, name: p.name, price: p.price, qty: 1, isPerishable: p.isPerishable));
        }
      });
      _barcodeCtrl.clear();
      _barcodeFocus.requestFocus(); 
    } else {
      _barcodeFocus.unfocus();
    }
  }

  void _adjustQty(String id, int delta) => setState(() {
    final idx = _cart.indexWhere((c) => c.productId == id);
    if (idx < 0) return;
    final products = context.read<InventoryProvider>().products;
    final stock = products.firstWhere((p) => p.id == id).stock;
    _cart[idx] = _cart[idx].copyWith(qty: (_cart[idx].qty + delta).clamp(1, stock));
  });

  Future<void> _completeSale() async {
    final inventory = context.read<InventoryProvider>();
    if (_cart.isEmpty || _cashNum < _total) return;
    try {
      final products = inventory.products;
      final breakdown = _breakdown;
      
      // Items for the transaction (with wholesale prices)
      final items = _cart.map((item) {
        final p = products.firstWhere((p) => p.id == item.productId);
        final bool isWholesale = p.wholesalePrice != null && item.qty >= (p.wholesaleThreshold ?? 999);
        return item.copyWith(price: isWholesale ? p.wholesalePrice! : p.price);
      }).toList();

      final total = breakdown.total; 
      final cash = _cashNum; 
      final change = _change;
      final pointsRedeemed = (_redeemPoints && _selectedCustomer != null) ? _selectedCustomer!.loyaltyPoints : 0;
      
      await inventory.completeSale(
        items, 
        cash, 
        totalOverride: total,
        customerId: _selectedCustomer?.id, 
        customerEmail: _selectedCustomer?.email, 
        pointsRedeemed: pointsRedeemed
      );

      final printer = context.read<PrinterProvider>();
      if (printer.connected) printer.printReceipt(items: items, total: total, cash: cash, change: change);
      
      setState(() { 
        _lastItems = items; _lastTotal = total; _lastCash = cash; _lastChange = change;
        _cart.clear(); _cash = ''; _cashCtrl.clear(); _selectedCustomer = null; _done = true; _redeemPoints = false; _isSeniorPWD = false;
      });
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _ReceiptScreen(items: _lastItems, total: _lastTotal, cash: _lastCash, change: _lastChange, onNewSale: () => setState(() => _done = false));

    final inventory = context.watch<InventoryProvider>();
    final products  = inventory.sortedProducts;
    final isTablet  = MediaQuery.of(context).size.width >= 600;

    final query = _barcodeCtrl.text.toLowerCase();
    final filtered = products
        .where((p) => p.stock > 0 && p.status == ProductStatus.published)
        .where((p) => p.name.toLowerCase().contains(query) || (p.barcode?.contains(query) ?? false))
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
            controller: _barcodeCtrl, focusNode: _barcodeFocus, onSubmitted: (v) => _onBarcodeSubmit(v, products),
            onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'Scan or search...', prefixIcon: const Icon(Icons.qr_code_scanner), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(icon: const Icon(Icons.camera_alt_outlined), onPressed: () async {
                  final code = await showDialog<String>(context: context, builder: (_) => const ScannerDialog());
                  if (code != null) _onBarcodeSubmit(code, products);
                })))),

        Expanded(child: isTablet 
            ? Row(children: [
                Expanded(child: _ProductGrid(products: filtered, cart: _cart, onToggle: _toggle)),
                SizedBox(width: 340, child: _CartPanel(cart: _cart, cash: _cash, cashCtrl: _cashCtrl, breakdown: _breakdown, cashNum: _cashNum, change: _change, products: products, selectedCustomer: _selectedCustomer, redeemPoints: _redeemPoints, isSeniorPWD: _isSeniorPWD, onCash: (v) => setState(() => _cash = v), onAdjust: _adjustQty, onRemove: (id) => setState(() => _cart.removeWhere((c) => c.productId == id)), onComplete: _completeSale, onSelectCustomer: (c) => setState(() => _selectedCustomer = c), onRedeemPoints: (v) => setState(() => _redeemPoints = v), onSeniorToggle: (v) => setState(() => _isSeniorPWD = v), onClear: () => setState(() => _cart.clear()))),
              ])
            : Stack(children: [
                Positioned.fill(child: _ProductGrid(products: filtered, cart: _cart, onToggle: _toggle)),
                if (_cart.isNotEmpty)
                  DraggableScrollableSheet(
                    initialChildSize: 0.6,
                    minChildSize: 0.18,
                    maxChildSize: 0.95,
                    snap: true,
                    builder: (ctx, sc) => _CartPanel(
                      cart: _cart, cash: _cash, cashCtrl: _cashCtrl, breakdown: _breakdown, cashNum: _cashNum, change: _change,
                      products: products, selectedCustomer: _selectedCustomer, redeemPoints: _redeemPoints, isSeniorPWD: _isSeniorPWD,
                      onCash: (v) => setState(() => _cash = v), onAdjust: _adjustQty, onRemove: (id) => setState(() => _cart.removeWhere((c) => c.productId == id)),
                      onComplete: _completeSale, onSelectCustomer: (c) => setState(() => _selectedCustomer = c),
                      onRedeemPoints: (v) => setState(() => _redeemPoints = v), onSeniorToggle: (v) => setState(() => _isSeniorPWD = v),
                      onClear: () => setState(() => _cart.clear()),
                      scrollController: sc,
                    ),
                  ),
              ])),
      ]),
    );
  }
}

class _ProductGrid extends StatefulWidget {
  final List<Product> products;
  final List<CartItem> cart;
  final ValueChanged<Product> onToggle;
  const _ProductGrid({required this.products, required this.cart, required this.onToggle});
  @override State<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<_ProductGrid> {
  String _cat = 'All';
  @override
  Widget build(BuildContext context) {
    final cats = ['All', ...context.watch<InventoryProvider>().settings.masterCategories];
    final filtered = widget.products.where((p) => _cat == 'All' || p.category == _cat).toList();
    return Column(children: [
      SizedBox(height: 52, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), itemCount: cats.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) => FilterChip(label: Text(cats[i], style: const TextStyle(fontSize: 12)), selected: _cat == cats[i], onSelected: (_) => setState(() => _cat = cats[i])))),
      Expanded(child: GridView.builder(padding: const EdgeInsets.fromLTRB(12, 12, 12, 160), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, childAspectRatio: 0.8, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: filtered.length, itemBuilder: (_, i) {
                final p = filtered[i]; final inCart = widget.cart.any((c) => c.productId == p.id);
                return _PosProductTile(p: p, inCart: inCart, onToggle: () => widget.onToggle(p));
              })),
    ]);
  }
}

class _PosProductTile extends StatelessWidget {
  final Product p; final bool inCart; final VoidCallback onToggle;
  const _PosProductTile({required this.p, required this.inCart, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    final isLow = p.stock <= p.lowStockThreshold;
    return GestureDetector(onTap: onToggle, child: Container(decoration: BoxDecoration(color: inCart ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3) : Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16), border: Border.all(color: inCart ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline.withOpacity(0.2))), clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Container(width: double.infinity, color: Colors.white, child: p.photoBase64 != null ? Image.memory(base64Decode(p.photoBase64!), fit: BoxFit.cover) : const Icon(Icons.inventory_2_outlined, size: 32))),
          Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text(formatPeso(p.price), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 12)), Text('${p.stock}', style: TextStyle(fontSize: 10, color: isLow ? Colors.red : Colors.grey))]),
          ])),
        ])));
  }
}

class _CartPanel extends StatelessWidget {
  final List<CartItem> cart; final String cash; final TextEditingController cashCtrl; final PricingBreakdown breakdown; final double cashNum, change; final List<Product> products; final Customer? selectedCustomer; final ValueChanged<String> onCash; final void Function(String, int) onAdjust; final ValueChanged<String> onRemove; final VoidCallback onComplete, onClear; final ValueChanged<Customer?> onSelectCustomer; final ScrollController? scrollController; final bool redeemPoints, isSeniorPWD; final ValueChanged<bool> onRedeemPoints, onSeniorToggle;

  const _CartPanel({required this.cart, required this.cash, required this.cashCtrl, required this.breakdown, required this.cashNum, required this.change, required this.products, required this.selectedCustomer, required this.redeemPoints, required this.isSeniorPWD, required this.onCash, required this.onAdjust, required this.onRemove, required this.onComplete, required this.onClear, required this.onSelectCustomer, required this.onRedeemPoints, required this.onSeniorToggle, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final isPeek = constraints.maxHeight < 150;
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
        ),
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 12),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Cart', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                Text('${cart.length} items', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ])),
              Text(formatPeso(breakdown.total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Theme.of(context).colorScheme.primary)),
            ]),
            if (!isPeek) ...[
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // Cart Items
                    ...List.generate(cart.length, (i) {
                      final item = cart[i];
                      Product? product;
                      try { product = products.firstWhere((p) => p.id == item.productId); } catch (_) {}
                      final bool isWholesale = product != null && product.wholesalePrice != null && item.qty >= (product.wholesaleThreshold ?? 999);
                      final double currentPrice = isWholesale ? product!.wholesalePrice! : item.price;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              QtyControl(qty: item.qty, max: product?.stock ?? 999, onChanged: (n) => onAdjust(item.productId, n - item.qty)),
                              const SizedBox(width: 8),
                              Text(formatPeso(currentPrice * item.qty), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              IconButton(onPressed: () => onRemove(item.productId), icon: const Icon(Icons.close, size: 18, color: Colors.red)),
                            ]),
                            if (isWholesale) Padding(padding: const EdgeInsets.only(left: 4), child: Text('Wholesale pricing applied', style: TextStyle(fontSize: 9, color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.bold))),
                            if (i < cart.length - 1) const Divider(height: 12),
                          ],
                        ),
                      );
                    }),
                    
                    const Divider(height: 24),
                    
                    // Actions Row
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(onPressed: () => _showCustomerPicker(context), icon: const Icon(Icons.person, size: 14), label: Text(selectedCustomer?.name ?? 'Customer', style: const TextStyle(fontSize: 10)))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(onPressed: () => onSeniorToggle(!isSeniorPWD), icon: const Icon(Icons.badge, size: 14), label: Text(isSeniorPWD ? 'Senior ON' : 'Discount', style: const TextStyle(fontSize: 10)))),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(onPressed: onClear, icon: const Icon(Icons.delete_outline, size: 18), color: Colors.red),
                    ]),
                    
                    if (selectedCustomer != null) Padding(padding: const EdgeInsets.only(top: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Loyalty Points: ${selectedCustomer!.loyaltyPoints}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      if (selectedCustomer!.loyaltyPoints > 0) Row(children: [
                        const Text('Redeem?', style: TextStyle(fontSize: 10)),
                        Switch.adaptive(value: redeemPoints, onChanged: onRedeemPoints, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      ]),
                    ])),

                    const SizedBox(height: 12),

                    // Pricing Breakdown
                    if (breakdown.promoDiscount > 0 || breakdown.seniorDiscount > 0 || breakdown.pointsDiscount > 0) ...[
                      _BreakdownRow('Subtotal', breakdown.subtotal),
                      if (breakdown.promoDiscount > 0) _BreakdownRow('Promo Discount', -breakdown.promoDiscount),
                      if (breakdown.seniorDiscount > 0) _BreakdownRow('Senior/PWD Disc', -breakdown.seniorDiscount),
                      if (breakdown.pointsDiscount > 0) _BreakdownRow('Points Redeemed', -breakdown.pointsDiscount),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              
              // Sticky Footer
              const Divider(height: 16),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(flex: 3, child: TextField(controller: cashCtrl, keyboardType: TextInputType.number, onChanged: onCash, decoration: const InputDecoration(labelText: 'Cash Received', prefixText: '₱ ', isDense: true))),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: ElevatedButton(onPressed: (cart.isNotEmpty && cashNum >= breakdown.total) ? onComplete : null, style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)), child: const Text('PAY'))),
                ]),
                const SizedBox(height: 8),
                if (cashNum >= breakdown.total) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Change Due:', style: TextStyle(fontSize: 11)), Text(formatPeso(change), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green))])
                else if (cart.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Short:', style: TextStyle(fontSize: 11)), Text(formatPeso(breakdown.total - cashNum), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red))]),
                const SizedBox(height: 4),
              ]),
            ],
          ]),
        ),
      );
    });
  }

  Widget _BreakdownRow(String label, double value) => Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(formatPeso(value), style: TextStyle(fontSize: 10, color: value < 0 ? Colors.green : Colors.grey, fontWeight: value < 0 ? FontWeight.bold : FontWeight.normal))]));

  void _showCustomerPicker(BuildContext context) async {
    final customers = context.read<InventoryProvider>().customers;
    final res = await showDialog<Customer>(context: context, builder: (ctx) => AlertDialog(title: const Text('Select Customer'), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: customers.length, itemBuilder: (_, i) => ListTile(title: Text(customers[i].name), subtitle: Text('${customers[i].loyaltyPoints} pts'), onTap: () => Navigator.pop(ctx, customers[i])))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))]));
    if (res != null) onSelectCustomer(res);
  }
}

class _ReceiptScreen extends StatelessWidget {
  final List<CartItem> items; final double total, cash, change; final VoidCallback onNewSale;
  const _ReceiptScreen({required this.items, required this.total, required this.cash, required this.change, required this.onNewSale});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.check_circle, color: Colors.green, size: 64),
    const Text('Sale Complete!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20),
    Container(constraints: const BoxConstraints(maxHeight: 400), decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(12)), child: ListView.builder(shrinkWrap: true, itemCount: items.length, itemBuilder: (_, i) => ListTile(dense: true, title: Text(items[i].name), trailing: Text(formatPeso(items[i].price * items[i].qty))))),
    const SizedBox(height: 20),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total Paid'), Text(formatPeso(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
    const SizedBox(height: 32),
    ElevatedButton(onPressed: onNewSale, style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)), child: const Text('NEW SALE')),
  ]))));
}
