import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../models/product.dart';
import '../../models/loss_record.dart';
import '../../widgets/scanner_dialog.dart';
import '../../widgets/brand_scanner_dialog.dart';
import '../../providers/inventory_provider.dart';
import '../config/theme.dart';
import '../../utils/format.dart';

class InventoryScreen extends StatefulWidget {
  final String? initialCategory;
  const InventoryScreen({super.key, this.initialCategory});
  @override State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  late String _cat;

  @override
  void initState() {
    super.initState();
    _cat = widget.initialCategory ?? 'All';
  }

  @override
  void didUpdateWidget(InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategory != oldWidget.initialCategory && widget.initialCategory != null) {
      _cat = widget.initialCategory!;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final products  = inventory.sortedProducts;
    final cats      = ['All', 'Low Stock', ...products.map((p) => p.category).toSet().toList()..sort()];
    final filtered = products
        .where((p) {
          if (_cat == 'Low Stock') return p.stock <= 5;
          return _cat == 'All' || p.category == _cat;
        })
        .where((p) {
          final query = _search.toLowerCase();
          return query.isEmpty ||
                 p.name.toLowerCase().contains(query) ||
                 (p.barcode != null && p.barcode!.toLowerCase().contains(query));
        })
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: GdcColors.sageGreen,
        foregroundColor: Colors.white,
        heroTag: 'inventory_fab',
        onPressed: () => _showSheet(context, null),
        icon:  const Icon(Icons.add_rounded),
        label: const Text('New Product'),
      ),
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text('Inventory',
                style: Theme.of(context).textTheme.headlineMedium)),

        // Search
        Padding(padding: const EdgeInsets.all(12),
            child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search), 
                    hintText: 'Search products…',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_search.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _search = '';
                            }),
                          ),
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () async {
                            final res = await showDialog<String>(context: context, builder: (_) => const ScannerDialog());
                            if (res != null) {
                              // If it's a barcode we know, show the name in the search bar
                              String searchText = res;
                              try {
                                final p = products.firstWhere((p) => p.barcode == res);
                                searchText = p.name;
                              } catch (_) {}
                              
                              _searchCtrl.text = searchText;
                              setState(() => _search = searchText);
                            }
                          },
                        ),
                      ],
                    )))),

        // Category filter
        SizedBox(height: 48, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => FilterChip(
                label: Text(cats[i], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                selected: _cat == cats[i],
                onSelected: (_) => setState(() {
                  _cat = cats[i];
                  if (_cat == 'All') {
                    _searchCtrl.clear();
                    _search = '';
                  }
                })))),

        const SizedBox(height: 8),

        // Product list
        Expanded(child: products.isEmpty 
            ? const Center(child: CircularProgressIndicator())
            : (filtered.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade200),
                    const SizedBox(height: 16),
                    const Text('No products matching filters', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                    TextButton(onPressed: () => setState(() { _search = ''; _cat = 'All'; }), child: const Text('Clear all filters')),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _ProductRow(
                      product: filtered[i],
                      onEdit:  () => _showSheet(context, filtered[i]),
                    )))),
      ])),
    );
  }

  void _showSheet(BuildContext context, Product? product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProductSheet(product: product),
    );
  }
}

// ── Product row ────────────────────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  const _ProductRow({required this.product, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final isLow = product.stock <= 5;
    final now = DateTime.now();
    final isExpired = product.expiryDate != null && product.expiryDate!.isBefore(now);
    final isNearExpiry = product.expiryDate != null && 
                        !isExpired && 
                        product.expiryDate!.isBefore(now.add(const Duration(days: 7)));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.light 
                ? Colors.black.withValues(alpha: 0.02) 
                : Colors.transparent,
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isLow || isExpired
                ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1)
                : isNearExpiry ? Theme.of(context).semantic.warning.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: product.photoBase64 != null
              ? Image.memory(base64Decode(product.photoBase64!), fit: BoxFit.cover)
              : Icon(
                  isExpired ? Icons.event_busy_rounded : (isLow ? Icons.warning_amber_rounded : Icons.inventory_2_rounded),
                  color: isExpired || isLow
                      ? Theme.of(context).colorScheme.error
                      : isNearExpiry ? Theme.of(context).semantic.warning : Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
        ),
        title: Text(product.name,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.2)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(6)),
              child: Text(product.category, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ),
            if (product.isPerishable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Theme.of(context).semantic.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('Shelf: ${product.shelfDays}d', style: TextStyle(fontSize: 10, color: Theme.of(context).semantic.warning, fontWeight: FontWeight.w800)),
              ),
            if (product.expiryDate != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: isExpired ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1) : (isNearExpiry ? Theme.of(context).semantic.warning.withValues(alpha: 0.1) : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1)),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(
                    isExpired ? 'EXPIRED' : 'Exp: ${DateFormat('MM/dd/yy').format(product.expiryDate!)}',
                    style: TextStyle(
                        fontSize: 10, 
                        color: isExpired ? Theme.of(context).colorScheme.error : (isNearExpiry ? Theme.of(context).semantic.warning : Theme.of(context).colorScheme.primary),
                        fontWeight: FontWeight.w900)),
              ),
          ]),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min, children: [
                Text(formatPeso(product.price),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLow ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1) : Theme.of(context).semantic.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('${product.stock} ${product.unit}',
                      style: TextStyle(
                          fontSize: 10,
                          color: isLow ? Theme.of(context).colorScheme.error : Theme.of(context).semantic.success,
                          fontWeight: FontWeight.w900)),
                ),
              ]),
          const SizedBox(width: 8),
          IconButton(
              icon: Icon(Icons.edit_note_rounded, color: Colors.grey.shade400),
              onPressed: onEdit),
        ]),
      ),
    );
  }
}

// ── Add / Edit sheet ───────────────────────────────────────────────────────

class _ProductSheet extends StatefulWidget {
  final Product? product;
  const _ProductSheet({this.product});
  @override State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late TextEditingController _name, _price, _stock, _unit, _shelf, _barcode, _wPrice, _wThreshold;
  late String _category;
  String? _supplierId;
  bool _perishable = false;
  bool _saving     = false;
  String? _photoBase64;
  File? _localPhoto;
  DateTime? _expiryDate;

  static const _defaultCategories = [
    'Fresh', 'Grains', 'Snacks', 'Beverages', 
    'Canned Goods', 'Personal Care', 'Condiments', 'Others'
  ];

  @override
  void initState() {
    super.initState();
    final p     = widget.product;
    final products = context.read<InventoryProvider>().products;
    
    // Combine defaults with existing categories from DB
    final allCats = {..._defaultCategories, ...products.map((e) => e.category)};
    
    _name       = TextEditingController(text: p?.name ?? '');
    _price      = TextEditingController(text: p?.price.toString() ?? '');
    _stock      = TextEditingController(text: p?.stock.toString() ?? '');
    _unit       = TextEditingController(text: p?.unit ?? 'pc');
    _shelf      = TextEditingController(text: p?.shelfDays?.toString() ?? '');
    _barcode    = TextEditingController(text: p?.barcode ?? '');
    _wPrice     = TextEditingController(text: p?.wholesalePrice?.toString() ?? '');
    _wThreshold = TextEditingController(text: p?.wholesaleThreshold?.toString() ?? '');
    _category   = (p != null && allCats.contains(p.category)) ? p.category : _defaultCategories.first;
    _perishable = p?.isPerishable ?? false;
    _photoBase64 = p?.photoBase64;
    _supplierId = p?.supplierId;
    _expiryDate = p?.expiryDate;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400, // Reasonable size for 58mm printer and DB storage
      imageQuality: 70,
    );

    if (image != null) {
      final file = File(image.path);
      final bytes = await file.readAsBytes();
      setState(() {
        _localPhoto = file;
        _photoBase64 = base64Encode(bytes);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose(); _price.dispose(); _stock.dispose();
    _unit.dispose(); _shelf.dispose(); _barcode.dispose();
    _wPrice.dispose(); _wThreshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final suppliers = inventory.suppliers;
    final allCats = {..._defaultCategories, ...inventory.products.map((e) => e.category)}.toList()..sort();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16, right: 16, top: 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle bar
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(widget.product == null ? 'Add Product' : 'Edit Product',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),

          // ── Photo Picker ──────────────────────────────────────────────────
          Center(
            child: Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _localPhoto != null
                      ? Image.file(_localPhoto!, fit: BoxFit.cover)
                      : (_photoBase64 != null
                          ? Image.memory(base64Decode(_photoBase64!), fit: BoxFit.cover)
                          : const Icon(Icons.add_a_photo_outlined, size: 40, color: Colors.grey)),
                ),
                Positioned(
                  bottom: -8,
                  right: -8,
                  child: IconButton.filledTonal(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.edit, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: TextField(controller: _name,
                    decoration: const InputDecoration(labelText: 'Product Name')),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _scanBrand,
                icon: const Icon(Icons.text_fields_rounded),
                tooltip: 'Scan Brand Name',
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Barcode Field
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcode,
                  decoration: const InputDecoration(
                    labelText: 'Barcode',
                    prefixIcon: Icon(Icons.qr_code_scanner),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _scanBarcode,
                icon: const Icon(Icons.camera_alt_outlined),
                tooltip: 'Scan Barcode',
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(child: TextField(controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price', prefixText: '₱ '))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _stock,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Stock'))),
          ]),
          const SizedBox(height: 10),

          // Wholesale pricing
          Row(children: [
            Expanded(child: TextField(controller: _wPrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Wholesale Price', prefixText: '₱ ', hintText: 'Optional'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _wThreshold,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Threshold Qty', hintText: 'e.g. 12'))),
          ]),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(child: TextField(controller: _unit,
                decoration: const InputDecoration(labelText: 'Unit (pc, kg…)'))),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: allCats.map((c) =>
                    DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _category = v!))),
          ]),

          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _supplierId,
            decoration: const InputDecoration(labelText: 'Supplier (for low stock alerts)', prefixIcon: Icon(Icons.business_outlined)),
            items: [
              const DropdownMenuItem(value: null, child: Text('No Supplier Assigned')),
              ...suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
            ],
            onChanged: (v) => setState(() => _supplierId = v),
          ),
          const SizedBox(height: 10),

          // Expiry Date Picker
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('Expiry Date'),
            subtitle: Text(_expiryDate == null ? 'Not Set (Optional)' : DateFormat('MMMM dd, yyyy').format(_expiryDate!)),
            trailing: _expiryDate != null 
              ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _expiryDate = null))
              : const Icon(Icons.chevron_right),
            onTap: _pickExpiryDate,
          ),
          const SizedBox(height: 4),

          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Perishable item'),
              subtitle: const Text('Auto-cancels if not picked up within 2 hours'),
              value: _perishable,
              onChanged: (v) => setState(() => _perishable = v)),

          if (_perishable) ...[
            TextField(controller: _shelf,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Shelf life (days)',
                    prefixIcon: Icon(Icons.timer_outlined))),
            const SizedBox(height: 8),
          ],

          if (widget.product != null) ...[
            const Divider(height: 32),
              OutlinedButton.icon(
                onPressed: () => _showLossDialog(context),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Record Loss / Expired / Damaged'),
                style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).semantic.warning),
              ),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.product != null)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                    onPressed: () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ),
              if (widget.product != null) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                    onPressed: _saving ? null : () async {
                      if (_name.text.trim().isEmpty) return;

                      final barcode = _barcode.text.trim();
                      if (barcode.isNotEmpty) {
                        final products = context.read<InventoryProvider>().products;
                        final exists = products.any((p) => 
                          p.barcode == barcode && p.id != widget.product?.id
                        );
                        if (exists) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Error: This barcode is already assigned to another item.'), backgroundColor: Colors.red)
                          );
                          return;
                        }
                      }

                      setState(() => _saving = true);
                      final p = Product(
                        id:        widget.product?.id ?? '',
                        name:      _name.text.trim(),
                        category:  _category,
                        price:     double.tryParse(_price.text) ?? 0,
                        stock:     int.tryParse(_stock.text) ?? 0,
                        unit:      _unit.text.trim(),
                        barcode:   _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
                        shelfDays: _perishable ? int.tryParse(_shelf.text) : null,
                        photoBase64: _photoBase64,
                        supplierId: _supplierId,
                        expiryDate: _expiryDate,
                        wholesalePrice: double.tryParse(_wPrice.text),
                        wholesaleThreshold: int.tryParse(_wThreshold.text),
                      );
                      await context.read<InventoryProvider>().saveProduct(p);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: _saving
                        ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Product')),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  void _showLossDialog(BuildContext context) {
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();
    LossType type = LossType.expired;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Text('Record Loss/Waste'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Product: ${widget.product!.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<LossType>(
                value: type,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: LossType.values.map((t) => DropdownMenuItem(
                  value: t, 
                  child: Text(t.name.toUpperCase().replaceAll('_', ' '))
                )).toList(),
                onChanged: (v) => setSt(() => type = v!),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity to Remove'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final q = int.tryParse(qtyCtrl.text) ?? 0;
                if (q <= 0 || q > widget.product!.stock) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid quantity.')));
                  return;
                }
                
                final record = LossRecord(
                  id: '',
                  productId: widget.product!.id,
                  productName: widget.product!.name,
                  qty: q,
                  unitPrice: widget.product!.price,
                  type: type,
                  notes: notesCtrl.text.trim(),
                  createdAt: DateTime.now(),
                );

                await context.read<InventoryProvider>().logLoss(record);
                if (ctx.mounted) {
                  Navigator.pop(ctx); // Close dialog
                  Navigator.pop(context); // Close bottom sheet
                }
              },
              child: const Text('Confirm Deduction'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text('Are you sure you want to remove "${widget.product?.name}" from your inventory? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await context.read<InventoryProvider>().deleteProduct(widget.product!.id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }


  Future<void> _scanBarcode() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => const ScannerDialog(),
    );
    if (result != null) {
      setState(() => _barcode.text = result);
    }
  }

  Future<void> _scanBrand() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => const BrandScannerDialog(),
    );
    if (result != null) {
      // Prepend brand name if there's already a name, otherwise set it
      final current = _name.text.trim();
      if (current.isEmpty) {
        setState(() => _name.text = result);
      } else {
        setState(() => _name.text = '$result $current');
      }
    }
  }

  Future<void> _pickExpiryDate() async {
    final res = await showDatePicker(
      context: context, 
      initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 30)), 
      firstDate: DateTime.now().subtract(const Duration(days: 365)), 
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (res != null) {
      setState(() => _expiryDate = res);
    }
  }
}
