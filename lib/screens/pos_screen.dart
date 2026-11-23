import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../models/bundle.dart';
import '../models/order.dart';
import '../models/transaction.dart';
import '../providers/inventory_provider.dart';
import '../widgets/qty_control.dart';
import '../widgets/scanner_dialog.dart';
import '../utils/barcode_routing.dart';
import '../utils/format.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../models/customer.dart';
import '../providers/printer_provider.dart';
import '../providers/order_provider.dart';
import '../providers/shift_provider.dart';
import '../config/theme.dart';
import '../utils/pricing_engine.dart';
import '../utils/barcode_generator.dart';
import '../widgets/order_qr_scanner.dart';
import '../widgets/action_warning_dialog.dart';

/// Point of Sale (POS) screen for barcode scanning, cart management, and cash checkout processing.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final List<CartItem> _cart = [];
  final _barcodeFocus = FocusNode();
  final _cashFocus = FocusNode();
  final _barcodeCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();
  Map<FocusNode, TextEditingController> _focusMap = {};
  bool _done = false;
  bool _saving = false;
  Customer? _selectedCustomer;

  double _lastTotal = 0, _lastChange = 0;
  StoreTransaction? _lastTransaction;
  bool _showCart = true;

  @override
  void initState() {
    super.initState();
    _focusMap = {
      _barcodeFocus: _barcodeCtrl,
      _cashFocus: _cashCtrl,
    };
    _cashCtrl.addListener(() => setState(() {}));
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

    // Apply wholesale prices to non-variant items and preserve variant prices
    final itemsWithWholesale = _cart.map((item) {
      try {
        final p = products.firstWhere((p) => p.id == item.productId);
        if (item.variantId != null && item.variantId!.isNotEmpty) {
          final v = p.variants.firstWhere(
            (v) => v.id == item.variantId,
            orElse: () => ProductVariant(
                id: item.variantId!, name: item.variantName ?? '', price: item.price, stock: 0),
          );
          return item.copyWith(price: v.price);
        }
        final bool isWholesale = p.wholesalePrice != null &&
            item.qty >= (p.wholesaleThreshold ?? 999);
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
  double get _change => (_cashNum - _total).clamp(0, double.infinity);

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
      final idx =
          _cart.indexWhere((c) => c.productId == p.id && c.variantId == vid);

      final stock = variant?.availableStock ?? p.availableStock;
      final price = variant?.price ?? p.price;
      final cost = variant?.costPrice ?? p.costPrice;
      final name = variant != null ? '${p.name} (${variant.name})' : p.name;
      final reservedCount = variant?.reservedStock ?? p.reservedStock;

      if (idx >= 0) {
        if (_cart[idx].qty < stock) {
          _cart[idx] = _cart[idx].copyWith(qty: _cart[idx].qty + 1);
        } else {
          final msg = reservedCount > 0
              ? 'Max available stock reached ($reservedCount units reserved for pre-orders).'
              : 'Max available stock reached.';
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      } else {
        if (stock <= 0) {
          final msg = reservedCount > 0
              ? 'Item unavailable for walk-in sale ($reservedCount units reserved for pre-orders).'
              : 'Item out of stock.';
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
          return;
        }
        _cart.insert(
            0,
            CartItem(
                productId: p.id,
                variantId: vid,
                name: name,
                variantName: variant?.name,
                barcode: variant?.barcode ?? p.barcode ?? '',
                price: price,
                costPrice: cost,
                qty: 1,
                isPerishable: p.isPerishable));
      }
    });
  }

  Future<ProductVariant?> _showVariantPicker(Product p) {
    return showDialog<ProductVariant>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select Variant: ${p.name}'),
        content: Container(
          width: 440,
          constraints: const BoxConstraints(maxWidth: 440),
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
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))
        ],
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
              _cart.insert(
                  0,
                  CartItem(
                      productId: p.id,
                      name: p.name,
                      barcode: p.barcode ?? '',
                      price: p.price,
                      costPrice: p.costPrice,
                      qty: 1,
                      isPerishable: p.isPerishable));
            } else {
              if (_cart[idx].qty < p.stock) {
                _cart[idx] = _cart[idx].copyWith(qty: _cart[idx].qty + 1);
              }
            }
          } catch (_) {}
        }
      });

  void _onBarcodeSubmit(String code, List<Product> products) {
    if (code.isEmpty) return;

    // Check if scanned barcode is a Click & Collect Order QR Code
    final orderProvider = context.read<OrderProvider>();
    final cleanCode = code.trim().replaceAll('#', '');
    if (cleanCode.startsWith('GDC-') ||
        orderProvider.orders.any((o) =>
            o.orderId.toLowerCase().replaceAll('#', '') ==
                cleanCode.toLowerCase() ||
            o.id.toLowerCase() == cleanCode.toLowerCase())) {
      _barcodeCtrl.clear();
      processScannedOrderCode(context, code);
      return;
    }

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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Barcode not found.')));
    _barcodeFocus.requestFocus();
  }

  void _setCartQty(String id, String? variantId, int targetQty) => setState(() {
        final idx = _cart
            .indexWhere((c) => c.productId == id && c.variantId == variantId);
        if (idx < 0) return;

        int stock = 9999;
        final products = context.read<InventoryProvider>().products;
        try {
          final p = products.firstWhere((p) => p.id == id);
          stock = variantId != null
              ? p.variants.firstWhere((v) => v.id == variantId).availableStock
              : p.availableStock;
        } catch (_) {}

        final int maxStock = stock < 1 ? 1 : stock;
        _cart[idx] = _cart[idx].copyWith(qty: targetQty.clamp(1, maxStock));
      });

  void _adjustQty(String id, String? variantId, int delta) => setState(() {
        final idx = _cart
            .indexWhere((c) => c.productId == id && c.variantId == variantId);
        if (idx < 0) return;
        _setCartQty(id, variantId, _cart[idx].qty + delta);
      });

  Future<void> _completeSale() async {
    final inventory = context.read<InventoryProvider>();
    final printer = context.read<PrinterProvider>();

    if (_cart.isEmpty ||
        _cashNum < _total ||
        _saving ||
        inventory.isProcessingSale) return;

    // Pre-flight check: Ensure no items in cart exceed available stock
    final products = inventory.products;
    for (var item in _cart) {
      try {
        final p = products.firstWhere((p) => p.id == item.productId);
        final int currentAvailable = item.variantId != null
            ? p.variants
                .firstWhere((v) => v.id == item.variantId)
                .availableStock
            : p.availableStock;

        if (currentAvailable < item.qty) {
          final reservedNote = p.reservedStock > 0
              ? ' (${p.reservedStock} reserved for pre-orders)'
              : '';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Cannot complete sale: ${item.name} has only $currentAvailable available units left$reservedNote.')));
          return;
        }
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Cannot complete sale: ${item.name} is no longer in the inventory.')));
        return;
      }
    }

    // Pre-flight check: Notify and confirm if any items are being sold below calculated cost
    final List<String> itemsBelowCostDetails = [];
    double totalTransactionLoss = 0.0;

    for (var item in _cart) {
      Product? p;
      try {
        p = products.firstWhere((prod) => prod.id == item.productId);
      } catch (_) {}

      double cost = item.costPrice;
      if (cost <= 0 && p != null) {
        if (item.variantId != null) {
          try {
            final v = p.variants.firstWhere((v) => v.id == item.variantId);
            cost = v.costPrice > 0 ? v.costPrice : p.effectiveUnitCost;
          } catch (_) {
            cost = p.effectiveUnitCost;
          }
        } else {
          cost = p.effectiveUnitCost;
        }
      }

      final bool isWholesale = p != null &&
          p.wholesalePrice != null &&
          item.qty >= (p.wholesaleThreshold ?? 999);
      final double effectiveSellingPrice =
          isWholesale ? p!.wholesalePrice! : item.price;

      if (effectiveSellingPrice > 0 &&
          cost > 0 &&
          effectiveSellingPrice < cost) {
        final double lossPerPc = cost - effectiveSellingPrice;
        final double totalItemLoss = lossPerPc * item.qty;
        totalTransactionLoss += totalItemLoss;

        itemsBelowCostDetails.add(
          '${item.name}: Selling ${formatPeso(effectiveSellingPrice)} vs Cost ${formatPeso(cost)} (Loss: ${formatPeso(lossPerPc)}/pc × ${item.qty} = ${formatPeso(totalItemLoss)})',
        );
      }
    }

    if (itemsBelowCostDetails.isNotEmpty) {
      itemsBelowCostDetails.add(
        'Total Estimated Sale Loss: ${formatPeso(totalTransactionLoss)}',
      );

      final confirm = await ActionWarningDialog.show(
        context,
        title: 'Item(s) Sold Below Calculated Cost',
        message:
            'One or more items in this transaction are being sold below their calculated cost price. Are you sure you want to proceed with this sale?',
        confirmLabel: 'Proceed with Sale',
        cancelLabel: 'Review Cart',
        severity: ActionWarningSeverity.warning,
        icon: Icons.trending_down_rounded,
        details: itemsBelowCostDetails,
      );
      if (!confirm) return;
    }

    setState(() => _saving = true);

    try {
      final products = inventory.products;
      final breakdown = _breakdown;

      // Items for the transaction (preserve variant prices; apply wholesale to non-variants)
      final items = _cart.map((item) {
        final p = products.firstWhere((p) => p.id == item.productId);
        if (item.variantId != null && item.variantId!.isNotEmpty) {
          final v = p.variants.firstWhere(
            (v) => v.id == item.variantId,
            orElse: () => ProductVariant(
                id: item.variantId!,
                name: item.variantName ?? '',
                price: item.price,
                stock: 0),
          );
          return item.copyWith(price: v.price);
        }
        final bool isWholesale = p.wholesalePrice != null &&
            item.qty >= (p.wholesaleThreshold ?? 999);
        return item.copyWith(price: isWholesale ? p.wholesalePrice! : p.price);
      }).toList();

      final total = breakdown.total;
      final cash = _cashNum;
      final change = _change;
      final itemsCount = items.fold<int>(0, (sum, i) => sum + i.qty);
      final selectedCustomerId = _selectedCustomer?.id;
      final selectedCustomerEmail = _selectedCustomer?.email;
      final selectedCustomerName = _selectedCustomer?.name;

      final tx = await inventory.completeSale(
        items,
        cash,
        totalOverride: total,
        customerId: selectedCustomerId,
        customerEmail: selectedCustomerEmail,
      );

      // Automatically record sale metrics into active register shift session
      final shiftProvider = context.read<ShiftProvider>();
      if (shiftProvider.hasActiveShift) {
        await shiftProvider.updateShiftSales(
          cashAmount: total,
          gcashAmount: 0.0,
          itemsSold: itemsCount,
          cashReceived: cash,
          changeGiven: change,
        );
      }

      // 1. Immediately transition POS UI to completed success state
      if (mounted) {
        setState(() {
          _lastTotal = total;
          _lastChange = change;
          _lastTransaction = tx;
          _cart.clear();
          _cashCtrl.clear();
          _selectedCustomer = null;
          _done = true;
          _saving = false;
          _showCart = true;
        });

        if (itemsBelowCostDetails.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ Sale completed with item(s) sold below calculated cost (Total Loss: ${formatPeso(totalTransactionLoss)}).',
              ),
              backgroundColor: Colors.amber.shade900,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

      // 2. Asynchronously trigger Bluetooth thermal printing in background
      if (printer.connected || printer.device != null) {
        printer.printReceipt(
          items: items,
          total: total,
          cash: cash,
          change: change,
          orderId: tx.id,
          customerName: selectedCustomerName,
          orderType: "In-store",
          breakdown: breakdown,
        ).catchError((e) {
          debugPrint("Background thermal printing error: $e");
          return false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return _SuccessView(
        total: _lastTotal,
        change: _lastChange,
        transaction: _lastTransaction,
        onNewSale: () => setState(() {
          _done = false;
          _lastTransaction = null;
        }),
      );
    }

    final inventory = context.watch<InventoryProvider>();
    final products = inventory.sortedProducts;

    final query = _barcodeCtrl.text.toLowerCase();
    final filtered = products
        .where((p) => p.status == ProductStatus.published)
        .where((p) =>
            p.name.toLowerCase().contains(query) ||
            (p.barcode?.contains(query) ?? false))
        .toList();

    // Automatically push out-of-stock / zero available stock items to the end (last) of the POS list
    filtered.sort((a, b) {
      final aHasStock = a.totalAvailableStock > 0;
      final bHasStock = b.totalAvailableStock > 0;
      if (aHasStock && !bHasStock) return -1;
      if (!aHasStock && bHasStock) return 1;
      return 0;
    });

    return BarcodeInterceptor(
      controllers: _focusMap,
      barcodeFocus: _barcodeFocus,
      onBarcodeDetected: (code) {
        _barcodeCtrl.text = code;
        setState(() {});
        _barcodeFocus.requestFocus();
        _onBarcodeSubmit(code, products);
      },
      onTextDetected: (text) {
        _barcodeCtrl.text = text;
        setState(() {});
        _barcodeFocus.requestFocus();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Column(
          children: [
            const _OfflineStatusBanner(),
            // Top Bar with Search Field + Products/Basket View Switcher
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _barcodeCtrl,
                      focusNode: _barcodeFocus,
                      onSubmitted: (v) => _onBarcodeSubmit(v, products),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Scan or search products...',
                        prefixIcon: const Icon(Icons.qr_code_scanner),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.camera_alt_outlined),
                          onPressed: () async {
                            final code = await showDialog<String>(
                              context: context,
                              useRootNavigator: true,
                              builder: (_) => const ScannerDialog(),
                            );
                            if (code != null && code.isNotEmpty) {
                              _barcodeCtrl.text = code;
                              setState(() {});
                              _barcodeFocus.requestFocus();
                              _onBarcodeSubmit(code, products);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _PosViewSwitcher(
                    showCart: _showCart,
                    totalCartItems:
                        _cart.fold<int>(0, (sum, item) => sum + item.qty),
                    onViewChanged: (showCart) =>
                        setState(() => _showCart = showCart),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _showCart
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: _CartPanel(
                          cart: _cart,
                          cashCtrl: _cashCtrl,
                          breakdown: _breakdown,
                          cashNum: _cashNum,
                          change: _change,
                          products: products,
                          selectedCustomer: _selectedCustomer,
                          saving: _saving,
                          cashFocus: _cashFocus,
                          onAdjust: _adjustQty,
                          onSetQty: _setCartQty,
                          onRemove: (id, vid) => setState(() {
                            _cart.removeWhere(
                                (c) => c.productId == id && c.variantId == vid);
                          }),
                          onComplete: _completeSale,
                          onSelectCustomer: (c) =>
                              setState(() => _selectedCustomer = c),
                          onClear: () async {
                            if (_cart.isEmpty) return;
                            final confirm = await ActionWarningDialog.show(
                              context,
                              title: 'Clear Cart?',
                              message:
                                  'Are you sure you want to remove all ${_cart.length} item(s) from the cart?',
                              confirmLabel: 'Clear Cart',
                              cancelLabel: 'Keep Items',
                              severity: ActionWarningSeverity.danger,
                              icon: Icons.remove_shopping_cart_rounded,
                            );
                            if (confirm) {
                              setState(() => _cart.clear());
                            }
                          },
                          onBackToProducts: () =>
                              setState(() => _showCart = false),
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        _ProductGrid(
                          products: filtered,
                          cart: _cart,
                          onToggle: _toggle,
                          onBundleToggle: _toggleBundle,
                        ),
                        if (_cart.isNotEmpty)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: SafeArea(
                              child: _FloatingCartButton(
                                totalQty: _cart.fold<int>(
                                    0, (sum, item) => sum + item.qty),
                                totalPrice: _total,
                                onPressed: () =>
                                    setState(() => _showCart = true),
                              ),
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
}

class _ProductGrid extends StatefulWidget {
  final List<Product> products;
  final List<CartItem> cart;
  final ValueChanged<Product> onToggle;
  final ValueChanged<ProductBundle> onBundleToggle;
  const _ProductGrid(
      {required this.products,
      required this.cart,
      required this.onToggle,
      required this.onBundleToggle});
  @override
  State<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<_ProductGrid> {
  String _cat = 'All';
  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final cats = [
      'All',
      'Quick Items (PLU)',
      'Bundles',
      ...inventory.settings.masterCategories
    ];

    if (_cat == 'Quick Items (PLU)') {
      final pluProducts = widget.products
          .where((p) => BarcodeGenerator.isInternalPluBarcode(p.barcode))
          .toList();
      return Column(children: [
        SizedBox(
            height: 52,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: cats.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => FilterChip(
                    label: Text(cats[i], style: const TextStyle(fontSize: 12)),
                    selected: _cat == cats[i],
                    onSelected: (_) => setState(() => _cat = cats[i])))),
        Expanded(
          child: pluProducts.isEmpty
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No Quick Items (PLU) available',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.6),
                              fontSize: 13))))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8),
                  itemCount: pluProducts.length,
                  itemBuilder: (_, i) {
                    final p = pluProducts[i];
                    final cartQty = widget.cart
                        .where((c) => c.productId == p.id)
                        .fold<int>(0, (sum, c) => sum + c.qty);
                    return _PosProductTile(
                        p: p,
                        cartQty: cartQty,
                        onToggle: () => widget.onToggle(p));
                  }),
        ),
      ]);
    }

    final matchingBundles = _cat == 'Bundles'
        ? inventory.bundles.where((b) => b.isActive).toList()
        : _cat == 'All'
            ? []
            : inventory.bundles
                .where((b) => b.isActive && b.category == _cat)
                .toList();

    final filteredProducts = _cat == 'Bundles'
        ? <Product>[]
        : widget.products
            .where((p) => _cat == 'All' || p.category == _cat)
            .toList();

    final totalCount = matchingBundles.length + filteredProducts.length;

    return Column(children: [
      SizedBox(
          height: 52,
          child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => FilterChip(
                  label: Text(cats[i], style: const TextStyle(fontSize: 12)),
                  selected: _cat == cats[i],
                  onSelected: (_) => setState(() => _cat = cats[i])))),
      Expanded(
        child: totalCount == 0
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 36,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Text('No items available in this category',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.6),
                              fontSize: 13,
                              fontWeight: FontWeight.bold))
                    ])))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8),
                itemCount: totalCount,
                itemBuilder: (_, i) {
                  if (i < matchingBundles.length) {
                    final bundle = matchingBundles[i];
                    return _BundleTile(
                        bundle: bundle,
                        onToggle: () => widget.onBundleToggle(bundle));
                  }
                  final p = filteredProducts[i - matchingBundles.length];
                  final cartQty = widget.cart
                      .where((c) => c.productId == p.id)
                      .fold<int>(0, (sum, c) => sum + c.qty);
                  return _PosProductTile(
                      p: p,
                      cartQty: cartQty,
                      onToggle: () => widget.onToggle(p));
                }),
      ),
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
          color: Theme.of(context)
              .colorScheme
              .secondaryContainer
              .withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .secondary
                  .withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: bundle.imageBytes != null
                    ? Image.memory(bundle.imageBytes!,
                        fit: BoxFit.cover, gaplessPlayback: true)
                    : const Icon(Icons.auto_awesome_motion_rounded,
                        size: 32, color: Colors.grey),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bundle.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('${bundle.productIds.length} items',
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
  final Product p;
  final int cartQty;
  final VoidCallback onToggle;
  const _PosProductTile({
    required this.p,
    required this.cartQty,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bool inCart = cartQty > 0;
    final int available = p.availableStock;
    final bool isOutOfStock = available <= 0;
    final bool isMaxStock = available > 0 && cartQty >= available;
    final bool isLow = available > 0 && available <= p.lowStockThreshold;

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        decoration: BoxDecoration(
          color: inCart
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMaxStock || isOutOfStock
                ? Colors.red.withValues(alpha: 0.5)
                : (inCart
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.2)),
            width: inCart ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Colors.white,
                    child: p.imageBytes != null
                        ? Image.memory(p.imageBytes!,
                            fit: BoxFit.cover, gaplessPlayback: true)
                        : const Icon(Icons.inventory_2_outlined, size: 32),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              formatPeso(p.price),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isOutOfStock
                                ? 'Out of Stock'
                                : isMaxStock
                                    ? 'Max Stock'
                                    : p.reservedStock > 0
                                        ? '$available (${p.reservedStock} res)'
                                        : 'Stock: $available',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: (isMaxStock || isOutOfStock)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isOutOfStock || isMaxStock
                                  ? Colors.red
                                  : (isLow
                                      ? Colors.orange
                                      : Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Cart Quantity Badge on top corner
            if (inCart)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    'x$cartQty',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  final List<CartItem> cart;
  final TextEditingController cashCtrl;
  final PricingBreakdown breakdown;
  final double cashNum, change;
  final List<Product> products;
  final Customer? selectedCustomer;
  final void Function(String, String?, int) onAdjust;
  final void Function(String, String?, int) onSetQty;
  final void Function(String, String?) onRemove;
  final VoidCallback onComplete, onClear;
  final ValueChanged<Customer?> onSelectCustomer;
  final ScrollController? scrollController;
  final bool saving;
  final FocusNode cashFocus;
  final VoidCallback? onBackToProducts;

  const _CartPanel({
    required this.cart,
    required this.cashCtrl,
    required this.breakdown,
    required this.cashNum,
    required this.change,
    required this.products,
    required this.selectedCustomer,
    required this.onAdjust,
    required this.onSetQty,
    required this.onRemove,
    required this.onComplete,
    required this.onClear,
    required this.onSelectCustomer,
    required this.saving,
    required this.cashFocus,
    this.scrollController,
    this.onBackToProducts,
  });

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final int totalUnits = cart.fold<int>(0, (sum, item) => sum + item.qty);
    final double? nextBill = _getNextBill(breakdown.total);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        children: [
          // 1. Header Section
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (onBackToProducts != null) ...[
                      IconButton.filledTonal(
                        onPressed: onBackToProducts,
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back to Products',
                      ),
                      const SizedBox(width: 12),
                    ],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Cart',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${cart.length} item${cart.length != 1 ? 's' : ''} • $totalUnits unit${totalUnits != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (cart.isNotEmpty)
                      TextButton.icon(
                        onPressed: onClear,
                        icon: const Icon(Icons.remove_shopping_cart_outlined,
                            size: 16, color: Colors.red),
                        label: const Text('Clear Cart',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      formatPeso(breakdown.total),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Scrollable Cart Items Section
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                if (cart.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 40,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your cart is empty',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  ...List.generate(cart.length, (i) {
                    final item = cart[i];
                    Product? product;
                    try {
                      product =
                          products.firstWhere((p) => p.id == item.productId);
                    } catch (_) {}

                    final double currentPrice = item.price;
                    final bool isWholesale = product != null &&
                        product.wholesalePrice != null &&
                        item.qty >= (product.wholesaleThreshold ?? 999);

                    int stock = 0;
                    int reserved = 0;
                    if (product != null) {
                      if (item.variantId != null) {
                        try {
                          final v = product.variants
                              .firstWhere((v) => v.id == item.variantId);
                          stock = v.availableStock;
                          reserved = v.reservedStock;
                        } catch (_) {}
                      } else {
                        stock = product.availableStock;
                        reserved = product.reservedStock;
                      }
                    }

                    final bool isOutOfStock = product == null || stock <= 0;
                    final bool isOverQty = product != null && item.qty > stock;

                    double effectiveCost = item.costPrice;
                    if (effectiveCost <= 0 && product != null) {
                      if (item.variantId != null) {
                        try {
                          final v = product.variants
                              .firstWhere((v) => v.id == item.variantId);
                          effectiveCost = v.costPrice > 0
                              ? v.costPrice
                              : product.effectiveUnitCost;
                        } catch (_) {
                          effectiveCost = product.effectiveUnitCost;
                        }
                      } else {
                        effectiveCost = product.effectiveUnitCost;
                      }
                    }
                    final bool isBelowCost = effectiveCost > 0 &&
                        currentPrice > 0 &&
                        currentPrice < effectiveCost;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isOutOfStock)
                            Padding(
                                padding:
                                    const EdgeInsets.only(left: 4, bottom: 4),
                                child: Text(
                                    reserved > 0
                                        ? '⚠️ ALL $reserved UNITS RESERVED FOR ONLINE ORDERS'
                                        : '⚠️ THIS ITEM IS NOW SOLD OUT',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold)))
                          else if (isOverQty)
                            Padding(
                                padding:
                                    const EdgeInsets.only(left: 4, bottom: 4),
                                child: Text(
                                    '⚠️ ONLY $stock AVAILABLE FOR SALE${reserved > 0 ? " ($reserved reserved)" : ""}',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold))),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        decoration: isOutOfStock
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: isOutOfStock
                                            ? Colors.grey
                                            : null,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '@ ${formatPeso(currentPrice)} / pc',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              QtyControl(
                                key: ValueKey(
                                    'qty_${item.productId}_${item.variantId ?? 'base'}'),
                                qty: item.qty,
                                max: stock,
                                onChanged: (n) => onSetQty(
                                    item.productId, item.variantId, n),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  formatPeso(currentPrice * item.qty),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: isOutOfStock
                                        ? Colors.grey
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    onRemove(item.productId, item.variantId),
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 20, color: Colors.red),
                                tooltip: 'Remove Item',
                              ),
                            ],
                          ),
                          if (isBelowCost)
                            Padding(
                                padding: const EdgeInsets.only(left: 4, top: 2),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        size: 11, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                        '⚠️ Below Cost: Sold @ ${formatPeso(currentPrice)} (Cost: ${formatPeso(effectiveCost)})',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.amber.shade900,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                )),
                          if (isWholesale)
                            const Padding(
                                padding: EdgeInsets.only(left: 4, top: 2),
                                child: Text('Wholesale pricing applied',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold))),
                          if (i < cart.length - 1) const Divider(height: 16),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),

          // 3. Footer / Checkout & Payment Section
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
              border: Border(
                top: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Totals Breakdown
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Subtotal:',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade700)),
                          Text(formatPeso(breakdown.subtotal),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (breakdown.savings > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Wholesale Discount:',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold)),
                            Text('- ${formatPeso(breakdown.savings)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                      const Divider(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Grand Total:',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w900)),
                          Text(
                            formatPeso(breakdown.total),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Cash Input & Payment Section
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: cashCtrl,
                            focusNode: cashFocus,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: false),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}')),
                            ],
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Cash Received',
                              prefixText: '₱ ',
                              prefixStyle: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                              isDense: true,
                              suffixIcon: cashCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () => cashCtrl.clear(),
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Quick Cash Chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ActionChip(
                                  label: const Text('Exact',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11)),
                                  avatar: const Icon(Icons.check, size: 14),
                                  backgroundColor: Colors.green.shade50,
                                  side: BorderSide(color: Colors.green.shade300),
                                  onPressed: () {
                                    cashCtrl.text = breakdown.total % 1 == 0
                                        ? breakdown.total.toStringAsFixed(0)
                                        : breakdown.total.toStringAsFixed(2);
                                  },
                                ),
                                const SizedBox(width: 6),
                                ...[50.0, 100.0, 200.0, 500.0, 1000.0].map((bill) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      label: Text('₱${bill.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: cashNum == bill
                                                ? Colors.white
                                                : Colors.black87,
                                          )),
                                      selected: cashNum == bill,
                                      selectedColor:
                                          Theme.of(context).colorScheme.primary,
                                      onSelected: (_) {
                                        cashCtrl.text = bill.toStringAsFixed(0);
                                      },
                                    ),
                                  );
                                }),
                                if (nextBill != null &&
                                    ![50.0, 100.0, 200.0, 500.0, 1000.0]
                                        .contains(nextBill))
                                  ActionChip(
                                    label: Text(
                                        'Next ₱${nextBill.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11)),
                                    backgroundColor: Colors.blue.shade50,
                                    side: BorderSide(color: Colors.blue.shade300),
                                    onPressed: () {
                                      cashCtrl.text =
                                          nextBill.toStringAsFixed(0);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Complete Sale / PAY Button
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: (cart.isNotEmpty &&
                                  cashNum >= breakdown.total &&
                                  breakdown.total > 0 &&
                                  !saving &&
                                  !inventory.isProcessingSale)
                              ? onComplete
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 2,
                          ),
                          child: (saving || inventory.isProcessingSale)
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white))
                              : const Text(
                                  'COMPLETE\nSALE',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    height: 1.1,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (cart.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // Live Change Due vs Insufficient Cash Banner
                  if (cashNum >= breakdown.total && breakdown.total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.payments_rounded,
                                  size: 20, color: Colors.green.shade800),
                              const SizedBox(width: 8),
                              Text('CHANGE DUE:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.green.shade900)),
                            ],
                          ),
                          Text(formatPeso(change),
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: Colors.green.shade900)),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 18, color: Colors.red.shade800),
                              const SizedBox(width: 6),
                              Text('INSUFFICIENT CASH',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.red.shade900)),
                            ],
                          ),
                          Text('Short: ${formatPeso(breakdown.total - cashNum)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.red.shade900)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  double? _getNextBill(double total) {
    if (total <= 0) return null;
    final standardBills = [50.0, 100.0, 200.0, 500.0, 1000.0];
    for (final bill in standardBills) {
      if (bill > total) return bill;
    }
    final nextMultiple = (total / 500.0).ceil() * 500.0;
    return nextMultiple > total ? nextMultiple : null;
  }
}

class _CustomerPickerDialog extends StatefulWidget {
  final List<Customer> customers;
  const _CustomerPickerDialog({required this.customers});
  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.customers
        .where((c) =>
            c.name.toLowerCase().contains(_q.toLowerCase()) ||
            c.phone.contains(_q))
        .toList();

    return AlertDialog(
        title: const Text('Select Customer'),
        content: Container(
            width: 440,
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                      hintText: 'Search name or phone...',
                      prefixIcon: Icon(Icons.search)),
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
                          onTap: () => Navigator.pop(context, filtered[i]))),
                ),
              ],
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'))
        ]);
  }
}

class _SuccessView extends StatelessWidget {
  final double total, change;
  final StoreTransaction? transaction;
  final VoidCallback onNewSale;

  const _SuccessView({
    required this.total,
    required this.change,
    this.transaction,
    required this.onNewSale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = transaction;
    final int totalUnits =
        tx != null ? tx.items.fold(0, (sum, i) => sum + i.qty) : 0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: Colors.green, size: 72),
                ),
                const SizedBox(height: 20),
                Text(
                  'Purchase Successful!',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                if (tx != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Transaction #${tx.id.length >= 8 ? tx.id.substring(0, 8).toUpperCase() : tx.id}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Post-Checkout Receipt Summary Modal Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tx != null && tx.items.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'ITEMS SOLD',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              '${tx.items.length} item type${tx.items.length != 1 ? 's' : ''} • $totalUnits unit${totalUnits != 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: tx.items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 12),
                            itemBuilder: (_, idx) {
                              final item = tx.items[idx];
                              return Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${item.qty}x',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      item.name +
                                          (item.variantName != null
                                              ? ' (${item.variantName})'
                                              : ''),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    formatPeso(item.price * item.qty),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const Divider(height: 24),
                      ],

                      // Totals & Cash Tendered / Change Breakdown
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Amount:',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(formatPeso(total),
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: theme.colorScheme.primary,
                                  fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Cash Tendered:',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(
                            formatPeso(tx?.cashTendered ?? (total + change)),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.payments_rounded,
                                    color: Colors.green.shade800, size: 24),
                                const SizedBox(width: 10),
                                Text(
                                  'CHANGE DUE:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              formatPeso(change),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.green.shade900,
                                fontSize: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (tx != null) ...[
                      OutlinedButton.icon(
                        onPressed: () {
                          final printer = context.read<PrinterProvider>();
                          printer
                              .printReceipt(
                            items: tx.items,
                            total: tx.total,
                            cash: tx.cashTendered,
                            change: tx.changeGiven,
                            orderId: tx.id,
                            customerName: tx.customerEmail,
                            orderType: "In-store",
                          )
                              .catchError((e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Printer error: $e'),
                                  backgroundColor: Colors.red),
                            );
                            return false;
                          });
                        },
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text('Print Receipt'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    ElevatedButton.icon(
                      onPressed: onNewSale,
                      icon: const Icon(Icons.add_shopping_cart_rounded),
                      label: const Text('NEW SALE',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GdcColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineStatusBanner extends StatelessWidget {
  const _OfflineStatusBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('store_settings')
          .snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        final bool isFromCache =
            snapshot.hasData && snapshot.data!.metadata.isFromCache;
        if (!isFromCache) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          color: Colors.amber.shade900,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ Offline Mode: Sales are saving locally and will auto-sync when online.',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FloatingCartButton extends StatelessWidget {
  final int totalQty;
  final double totalPrice;
  final VoidCallback onPressed;

  const _FloatingCartButton({
    required this.totalQty,
    required this.totalPrice,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final onPrimaryColor = theme.colorScheme.onPrimary;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: primaryColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.shopping_bag_outlined,
                        color: onPrimaryColor, size: 24),
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          '$totalQty',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'View Your Cart',
                        style: TextStyle(
                          color: onPrimaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '$totalQty item${totalQty != 1 ? 's' : ''} added',
                        style: TextStyle(
                          color: onPrimaryColor.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatPeso(totalPrice),
                  style: TextStyle(
                    color: onPrimaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: onPrimaryColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosViewSwitcher extends StatelessWidget {
  final bool showCart;
  final int totalCartItems;
  final ValueChanged<bool> onViewChanged;

  const _PosViewSwitcher({
    required this.showCart,
    required this.totalCartItems,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Basket Tab
          _buildTab(
            context,
            isSelected: showCart,
            icon: Icons.shopping_cart_outlined,
            label: 'Basket',
            badgeCount: totalCartItems > 0 ? totalCartItems : null,
            onTap: () => onViewChanged(true),
          ),
          const SizedBox(width: 4),
          // Products Tab
          _buildTab(
            context,
            isSelected: !showCart,
            icon: Icons.grid_view_rounded,
            label: 'Products',
            badgeCount: null,
            onTap: () => onViewChanged(false),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(
    BuildContext context, {
    required bool isSelected,
    required IconData icon,
    required String label,
    required int? badgeCount,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final activeBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.6);
    final activeBorder = theme.colorScheme.primary;
    final activeTextColor = theme.colorScheme.primary;
    final inactiveTextColor = theme.colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: isSelected
                ? Border.all(color: activeBorder, width: 1.5)
                : Border.all(color: Colors.transparent, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? activeTextColor : inactiveTextColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected ? activeTextColor : inactiveTextColor,
                ),
              ),
              if (badgeCount != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? activeTextColor : inactiveTextColor,
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
