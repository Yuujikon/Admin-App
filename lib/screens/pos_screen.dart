import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../models/bundle.dart';
import '../models/order.dart';
import '../providers/inventory_provider.dart';
import '../widgets/qty_control.dart';
import '../widgets/scanner_dialog.dart';
import '../utils/barcode_routing.dart';
import '../utils/format.dart';
import '../models/customer.dart';
import '../providers/order_provider.dart';
import '../providers/printer_provider.dart';
import '../utils/pricing_engine.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final List<CartItem> _cart = [];
  final _barcodeFocus = FocusNode();
  final _cashFocus = FocusNode();
  final _barcodeCtrl  = TextEditingController();
  final _cashCtrl     = TextEditingController();
  Map<FocusNode, TextEditingController> _focusMap = {};
  bool   _done = false;
  bool   _saving = false;
  Customer? _selectedCustomer;
  
  String? _lastTxId;
  String? _lastCustomerName;
  List<CartItem> _lastItems = [];
  double _lastTotal = 0, _lastCash = 0, _lastChange = 0;
  PricingBreakdown? _lastBreakdown;

  @override
  void initState() {
    super.initState();
    _focusMap = {
      _barcodeFocus: _barcodeCtrl,
      _cashFocus: _cashCtrl,
    };
    _cashCtrl.addListener(() => setState(() {}));
    // Auto-focus barcode search on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeFocus.dispose();
    _cashFocus.dispose();
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
    );
  }

  double get _total => _breakdown.total;
  
  double get _cashNum => double.tryParse(_cashCtrl.text) ?? 0;
  double get _change  => (_cashNum - _total).clamp(0, double.infinity);

  void _toggle(Product p) async {
    if (p.hasVariants) {
      final v = await _showVariantPicker(p);
      if (v != null) {
        _addToCart(p, variant: v);
      }
      return;
    }
    _addToCart(p);
  }

  void _addToCart(Product p, {ProductVariant? variant}) {
    setState(() {
      final String? vid = variant?.id;
      final idx = _cart.indexWhere((c) => c.productId == p.id && c.variantId == vid);
      
      final stock = variant?.stock ?? p.stock;
      final price = variant?.price ?? p.price;
      final cost  = variant?.costPrice ?? p.costPrice;
      final name  = variant != null ? '${p.name} (${variant.name})' : p.name;

      if (idx >= 0) {
        if (_cart[idx].qty < stock) {
          _cart[idx] = _cart[idx].copyWith(qty: _cart[idx].qty + 1);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max stock reached.')));
        }
      } else {
        if (stock <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item out of stock.')));
          return;
        }
        _cart.insert(0, CartItem(
          productId: p.id, 
          variantId: vid,
          name: name, 
          variantName: variant?.name,
          price: price, 
          costPrice: cost, 
          qty: 1, 
          isPerishable: p.isPerishable
        ));
      }
    });
  }

  Future<ProductVariant?> _showVariantPicker(Product p) {
    return showDialog<ProductVariant>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select Variant: ${p.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: p.variants.length,
            itemBuilder: (ctx, i) {
              final v = p.variants[i];
              return ListTile(
                title: Text(v.name),
                subtitle: Text('${formatPeso(v.price)} • Stock: ${v.stock}'),
                enabled: v.stock > 0,
                onTap: () => Navigator.pop(ctx, v),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
  }

  void _toggleBundle(ProductBundle b) => setState(() {
    final products = context.read<InventoryProvider>().products;
    for (final pid in b.productIds) {
      try {
        final p = products.firstWhere((p) => p.id == pid);
        final idx = _cart.indexWhere((c) => c.productId == p.id);
        if (idx < 0) {
          _cart.insert(0, CartItem(productId: p.id, name: p.name, price: p.price, costPrice: p.costPrice, qty: 1, isPerishable: p.isPerishable));
        } else {
          // If already in cart, maybe just increment? Or leave as is. 
          // Requirements usually suggest adding the missing parts of the bundle.
          // Let's increment qty by 1 for items already in cart.
          if (_cart[idx].qty < p.stock) {
            _cart[idx] = _cart[idx].copyWith(qty: _cart[idx].qty + 1);
          }
        }
      } catch (_) {}
    }
  });

  void _onBarcodeSubmit(String code, List<Product> products) {
    if (code.isEmpty) return;
    
    // 1. Search for products where base barcode matches OR a variant barcode matches
    for (final p in products) {
      if (p.status != ProductStatus.published) continue;

      // Check base product
      if (p.barcode == code) {
        _toggle(p);
        _barcodeCtrl.clear();
        _barcodeFocus.requestFocus();
        return;
      }

      // Check variants
      if (p.hasVariants) {
        try {
          final v = p.variants.firstWhere((v) => v.barcode == code);
          _addToCart(p, variant: v);
          _barcodeCtrl.clear();
          _barcodeFocus.requestFocus();
          return;
        } catch (_) {}
      }
    }

    // Not found
    _barcodeCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Barcode not found.')));
    _barcodeFocus.requestFocus();
  }

  void _adjustQty(String id, String? variantId, int delta) => setState(() {
    final idx = _cart.indexWhere((c) => c.productId == id && c.variantId == variantId);
    if (idx < 0) return;
    final products = context.read<InventoryProvider>().products;
    final p = products.firstWhere((p) => p.id == id);

    final int stock = variantId != null
        ? p.variants.firstWhere((v) => v.id == variantId).stock
        : p.stock;

    _cart[idx] = _cart[idx].copyWith(qty: (_cart[idx].qty + delta).clamp(1, stock));
  });

  Future<void> _completeSale() async {
    final inventory = context.read<InventoryProvider>();
    final printer = context.read<PrinterProvider>();
    
    if (_cart.isEmpty || _cashNum < _total || _saving || inventory.isProcessingSale) return;

    // Pre-flight check: Ensure no items in cart exceed available stock
    final products = inventory.products;
    for (var item in _cart) {
      try {
        final p = products.firstWhere((p) => p.id == item.productId);
        final int currentStock = item.variantId != null 
            ? p.variants.firstWhere((v) => v.id == item.variantId).stock 
            : p.stock;
            
        if (currentStock < item.qty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot complete sale: ${item.name} has only $currentStock units left.'))
          );
          return;
        }
      } catch (_) {
         ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot complete sale: ${item.name} is no longer in the inventory.'))
          );
          return;
      }
    }
    
    setState(() => _saving = true);
    
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
      
      final tx = await inventory.completeSale(
        items, 
        cash, 
        totalOverride: total,
        customerId: _selectedCustomer?.id, 
        customerEmail: _selectedCustomer?.email, 
      );

      if (printer.connected) {
        try {
          final success = await printer.printReceipt(
            items: items, 
            total: total, 
            cash: cash, 
            change: change,
            orderId: tx.id,
            customerName: _selectedCustomer?.name,
            orderType: "In-store",
            breakdown: breakdown,
          );
          if (!success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Failed to print receipt. Check printer connection.")),
            );
          }
        } catch (e) {
          debugPrint("Printing error: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Failed to print receipt. Check printer connection.")),
            );
          }
        }
      }
      
      if (mounted) {
        setState(() { 
          _lastItems = items; _lastTotal = total; _lastCash = cash; _lastChange = change;
          _lastTxId = tx.id;
          _lastCustomerName = _selectedCustomer?.name;
          _lastBreakdown = breakdown;
          _cart.clear(); _cashCtrl.clear(); _selectedCustomer = null; _done = true; _saving = false;
        });
      }
    } catch (e) { 
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return _SuccessView(
        total: _lastTotal, 
        change: _lastChange, 
        onNewSale: () => setState(() => _done = false)
      );
    }

    final inventory = context.watch<InventoryProvider>();
    final products  = inventory.sortedProducts;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final isTablet  = mediaQuery.size.width >= 600 || isLandscape;

    final query = _barcodeCtrl.text.toLowerCase();
    final filtered = products
        .where((p) => p.totalStock > 0 && p.status == ProductStatus.published)
        .where((p) => p.name.toLowerCase().contains(query) || (p.barcode?.contains(query) ?? false))
        .toList();

    return BarcodeInterceptor(
      controllers: _focusMap,
      barcodeFocus: _barcodeFocus,
      onBarcodeDetected: (code) => _onBarcodeSubmit(code, products),
      onTextDetected: (text) {
        _barcodeCtrl.text = text;
        setState(() {});
        _barcodeFocus.requestFocus();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: TextField(
              controller: _barcodeCtrl, focusNode: _barcodeFocus, onSubmitted: (v) => _onBarcodeSubmit(v, products),
              onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'Scan or search...', prefixIcon: const Icon(Icons.qr_code_scanner), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(icon: const Icon(Icons.camera_alt_outlined), onPressed: () async {
                    final code = await showDialog<String>(context: context, useRootNavigator: true, builder: (_) => const ScannerDialog());
                    if (code != null) _onBarcodeSubmit(code, products);
                  })))),
  
          Expanded(child: isTablet 
              ? Row(children: [
                  Expanded(child: _ProductGrid(products: filtered, cart: _cart, onToggle: _toggle, onBundleToggle: _toggleBundle)),
                  SizedBox(width: 340, child: _CartPanel(
                    cart: _cart, cashCtrl: _cashCtrl, breakdown: _breakdown, cashNum: _cashNum, change: _change, 
                    products: products, selectedCustomer: _selectedCustomer, 
                    saving: _saving, cashFocus: _cashFocus,
                    onAdjust: _adjustQty, 
                    onRemove: (id, vid) => setState(() => _cart.removeWhere((c) => c.productId == id && c.variantId == vid)), 
                    onComplete: _completeSale, 
                    onSelectCustomer: (c) => setState(() => _selectedCustomer = c), 
                    onClear: () => setState(() => _cart.clear()))),
                ])
              : Stack(children: [
                  Positioned.fill(child: _ProductGrid(products: filtered, cart: _cart, onToggle: _toggle, onBundleToggle: _toggleBundle)),
                  if (_cart.isNotEmpty)
                    DraggableScrollableSheet(
                      initialChildSize: 0.5,
                      minChildSize: 0.18,
                      maxChildSize: 0.95,
                      snap: true,
                      snapSizes: const [0.18, 0.5, 0.95],
                      builder: (ctx, sc) => SafeArea(
                        bottom: false,
                        child: _CartPanel(
                          cart: _cart, cashCtrl: _cashCtrl, breakdown: _breakdown, cashNum: _cashNum, change: _change,
                          products: products, selectedCustomer: _selectedCustomer,
                          saving: _saving, cashFocus: _cashFocus,
                          onAdjust: _adjustQty, 
                          onRemove: (id, vid) => setState(() => _cart.removeWhere((c) => c.productId == id && c.variantId == vid)),
                          onComplete: _completeSale, 
                          onSelectCustomer: (c) => setState(() => _selectedCustomer = c),
                          onClear: () => setState(() => _cart.clear()),
                          scrollController: sc,
                        ),
                      ),
                    ),
                ])),
        ]),
      ),
    );
  }
}

class _ProductGrid extends StatefulWidget {
  final List<Product> products;
  final List<CartItem> cart;
  final ValueChanged<Product> onToggle;
  final ValueChanged<ProductBundle> onBundleToggle;
  const _ProductGrid({required this.products, required this.cart, required this.onToggle, required this.onBundleToggle});
  @override State<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<_ProductGrid> {
  String _cat = 'All';
  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final cats = ['All', 'Bundles', ...inventory.settings.masterCategories];
    
    if (_cat == 'Bundles') {
      final bundles = inventory.bundles.where((b) => b.isActive).toList();
      return Column(children: [
        SizedBox(height: 52, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), itemCount: cats.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) => FilterChip(label: Text(cats[i], style: const TextStyle(fontSize: 12)), selected: _cat == cats[i], onSelected: (_) => setState(() => _cat = cats[i])))),
        Expanded(child: GridView.builder(padding: const EdgeInsets.fromLTRB(12, 12, 12, 160), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, childAspectRatio: 0.8, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: bundles.length, itemBuilder: (_, i) {
                  return _BundleTile(bundle: bundles[i], onToggle: () => widget.onBundleToggle(bundles[i]));
                })),
      ]);
    }

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

class _BundleTile extends StatelessWidget {
  final ProductBundle bundle;
  final VoidCallback onToggle;
  const _BundleTile({required this.bundle, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: bundle.photoBase64 != null 
                    ? Image.memory(base64Decode(bundle.photoBase64!), fit: BoxFit.cover)
                    : const Icon(Icons.auto_awesome_motion_rounded, size: 32, color: Colors.grey),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bundle.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${bundle.productIds.length} items', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosProductTile extends StatelessWidget {
  final Product p; final bool inCart; final VoidCallback onToggle;
  const _PosProductTile({required this.p, required this.inCart, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    final isLow = p.stock <= p.lowStockThreshold;
    return GestureDetector(onTap: onToggle, child: Container(decoration: BoxDecoration(color: inCart ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16), border: Border.all(color: inCart ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2))), clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Container(width: double.infinity, color: Colors.white, child: p.photoBase64 != null ? Image.memory(base64Decode(p.photoBase64!), fit: BoxFit.cover) : const Icon(Icons.inventory_2_outlined, size: 32))),
          Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ 
              Expanded(child: Text(formatPeso(p.price), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              Text('${p.stock}', style: TextStyle(fontSize: 10, color: isLow ? Colors.red : Colors.grey)),
            ]),
          ])),
        ])));
  }
}

class _CartPanel extends StatelessWidget {
  final List<CartItem> cart; final TextEditingController cashCtrl; final PricingBreakdown breakdown; final double cashNum, change; final List<Product> products; final Customer? selectedCustomer; final void Function(String, String?, int) onAdjust; final void Function(String, String?) onRemove; final VoidCallback onComplete, onClear; final ValueChanged<Customer?> onSelectCustomer; final ScrollController? scrollController; final bool saving;
  final FocusNode cashFocus;

  const _CartPanel({required this.cart, required this.cashCtrl, required this.breakdown, required this.cashNum, required this.change, required this.products, required this.selectedCustomer, required this.onAdjust, required this.onRemove, required this.onComplete, required this.onClear, required this.onSelectCustomer, required this.saving, required this.cashFocus, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    return LayoutBuilder(builder: (context, constraints) {
      // Logic for hiding overlapping elements when collapsed
      final bool hideCheckout = constraints.maxHeight < 280;

      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: Stack(
            children: [
              // 1. Scrollable List (Using provided sc to handle sheet dragging)
              ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 200),
                children: [
                  const SizedBox(height: 80), // Buffer for sticky header
                  
                  // Cart Items
                  ...List.generate(cart.length, (i) {
                    final item = cart[i];
                    Product? product;
                    try { product = products.firstWhere((p) => p.id == item.productId); } catch (_) {}
                    
                    final double currentPrice = item.price;
                    final bool isWholesale = product != null && product.wholesalePrice != null && item.qty >= (product.wholesaleThreshold ?? 999);
                    
                    int stock = 0;
                    if (product != null) {
                      if (item.variantId != null) {
                        try {
                          stock = product.variants.firstWhere((v) => v.id == item.variantId).stock;
                        } catch (_) {}
                      } else {
                        stock = product.stock;
                      }
                    }

                    final bool isOutOfStock = product == null || stock <= 0;
                    final bool isOverQty = product != null && item.qty > stock;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isOutOfStock)
                            const Padding(padding: EdgeInsets.only(left: 4, bottom: 4), child: Text('⚠️ THIS ITEM IS NOW SOLD OUT', style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)))
                          else if (isOverQty)
                            Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text('⚠️ ONLY ${product.stock} LEFT IN STOCK', style: const TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold))),

                          Row(children: [
                            Expanded(child: Text(item.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, decoration: isOutOfStock ? TextDecoration.lineThrough : null, color: isOutOfStock ? Colors.grey : null), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            QtyControl(
                              qty: item.qty, 
                              max: stock, 
                              onChanged: (n) => onAdjust(item.productId, item.variantId, n - item.qty)
                            ),
                            const SizedBox(width: 8),
                            Text(formatPeso(currentPrice * item.qty), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isOutOfStock ? Colors.grey : null)),
                            IconButton(onPressed: () => onRemove(item.productId, item.variantId), icon: const Icon(Icons.close, size: 18, color: Colors.red)),
                          ]),
                          if (isWholesale) const Padding(padding: EdgeInsets.only(left: 4), child: Text('Wholesale pricing applied', style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold))),
                          if (i < cart.length - 1) const Divider(height: 12),
                        ],
                      ),
                    );
                  }),
                  
                  const Divider(height: 24),
                  
                  // Actions Row
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    IconButton.filledTonal(onPressed: onClear, icon: const Icon(Icons.delete_outline, size: 18), color: Colors.red),
                  ]),
                  
                  const SizedBox(height: 12),
                ],
              ),

              // 2. Sticky Header (Always visible at the top of the sheet)
              Positioned(
                top: 0, left: 0, right: 0,
                child: IgnorePointer(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 40, height: 4, 
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Your Cart', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                            Text('${cart.length} items', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ])),
                          Text(formatPeso(breakdown.total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Theme.of(context).colorScheme.primary)),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Sticky Footer (Only shown when expanded enough)
              if (!hideCheckout)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(flex: 3, child: TextField(
                            controller: cashCtrl, 
                            focusNode: cashFocus,
                            keyboardType: TextInputType.number, 
                            decoration: const InputDecoration(labelText: 'Cash Received', prefixText: '₱ ', isDense: true))),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: ElevatedButton(
                            onPressed: (cart.isNotEmpty && cashNum >= breakdown.total && !saving && !inventory.isProcessingSale) ? onComplete : null, 
                            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 64)), 
                            child: (saving || inventory.isProcessingSale) 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('PAY')
                          )),
                        ]),
                        const SizedBox(height: 8),
                        if (cashNum >= breakdown.total) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Change Due:', style: TextStyle(fontSize: 11)), Text(formatPeso(change), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green))])
                        else if (cart.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Short:', style: TextStyle(fontSize: 11)), Text(formatPeso(breakdown.total - cashNum), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red))]),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _breakdownRow(String label, double value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text(formatPeso(value), style: TextStyle(fontSize: 10, color: value < 0 ? Colors.green : Colors.grey, fontWeight: value < 0 ? FontWeight.bold : FontWeight.normal)),
      ],
    ),
  );

  void _showCustomerPicker(BuildContext context) async {
    final customers = context.read<InventoryProvider>().customers;
    final res = await showDialog<Customer>(
      context: context, 
      useRootNavigator: true,
      builder: (ctx) => _CustomerPickerDialog(customers: customers),
    );
    if (res != null) onSelectCustomer(res);
  }
}

class _CustomerPickerDialog extends StatefulWidget {
  final List<Customer> customers;
  const _CustomerPickerDialog({required this.customers});
  @override State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.customers.where((c) => 
      c.name.toLowerCase().contains(_q.toLowerCase()) || 
      c.phone.contains(_q)
    ).toList();

    return AlertDialog(
      title: const Text('Select Customer'), 
      content: SizedBox(
        width: double.maxFinite, 
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(hintText: 'Search name or phone...', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true, 
                itemCount: filtered.length, 
                itemBuilder: (_, i) => ListTile(
                  title: Text(filtered[i].name), 
                  subtitle: Text(filtered[i].phone), 
                  onTap: () => Navigator.pop(context, filtered[i])
                )
              ),
            ),
          ],
        )
      ), 
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))]
    );
  }
}

class _SuccessView extends StatelessWidget {
  final double total, change;
  final VoidCallback onNewSale;

  const _SuccessView({
    required this.total, 
    required this.change, 
    required this.onNewSale
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 80),
              ),
              const SizedBox(height: 32),
              Text('Purchase Successful!', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text('The transaction has been recorded.', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Paid:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(formatPeso(total), style: TextStyle(fontWeight: FontWeight.w900, color: theme.colorScheme.primary, fontSize: 18)),
                      ],
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Change Given:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(formatPeso(change), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 18)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 64),
              ElevatedButton.icon(
                onPressed: onNewSale,
                icon: const Icon(Icons.add),
                label: const Text('NEW SALE'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.grey)),
            );
          }),
        );
      },
    );
  }
}
