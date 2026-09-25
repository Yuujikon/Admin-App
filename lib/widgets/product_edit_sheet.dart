import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/catalog_product.dart';
import '../models/loss_record.dart';
import '../providers/inventory_provider.dart';
import '../utils/barcode_routing.dart';
import '../utils/format.dart';
import '../utils/image_utils.dart';
import 'scanner_dialog.dart';
import 'full_product_scanner_dialog.dart';
import '../config/theme.dart';

class ProductEditSheet extends StatefulWidget {
  final Product? product;
  const ProductEditSheet({super.key, this.product});
  @override State<ProductEditSheet> createState() => _ProductEditSheetState();
}

class _ProductEditSheetState extends State<ProductEditSheet> {
  late TextEditingController _name, _brand, _price, _costPrice, _stock, _unit, _shelf, _barcode, _wPrice, _wThreshold, _pickupWindow, _lowStockT;
  late FocusNode _fName, _fBrand, _fPrice, _fCostPrice, _fStock, _fUnit, _fShelf, _fBarcode, _fWPrice, _fWThreshold, _fPickupWindow, _fLowStockT;
  Map<FocusNode, TextEditingController> _focusMap = {};

  late String _category;
  late ProductStatus _status;
  String? _supplierId;
  bool _perishable = false;
  bool _taxable    = true;
  bool _saving     = false;
  bool _processingImage = false;
  String? _photoBase64;
  File? _localPhoto;
  DateTime? _expiryDate;
  List<ProductVariant> _variants = [];

  static const _defaultCategories = [
    'Fresh', 'Grains', 'Snacks', 'Beverages', 
    'Canned Goods', 'Personal Care', 'Condiments', 'Others'
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final inventory = context.read<InventoryProvider>();
    final settings = inventory.settings;
    final products = inventory.products;
    
    // Combine defaults with existing categories from DB
    final allCats = {..._defaultCategories, ...products.map((e) => e.category)};
    
    _name       = TextEditingController(text: p?.name ?? '');
    _brand      = TextEditingController(text: p?.brand ?? '');
    _price      = TextEditingController(text: p?.price.toString() ?? '');
    _costPrice  = TextEditingController(text: p?.costPrice.toString() ?? '0');
    _stock      = TextEditingController(text: p?.stock.toString() ?? '');
    _unit       = TextEditingController(text: p?.unit ?? 'pcs');
    _shelf      = TextEditingController(text: p?.shelfDays?.toString() ?? '');
    _barcode    = TextEditingController(text: p?.barcode ?? '');
    _wPrice     = TextEditingController(text: p?.wholesalePrice?.toString() ?? '');
    _wThreshold = TextEditingController(text: p?.wholesaleThreshold?.toString() ?? '');
    _pickupWindow = TextEditingController(text: p?.pickupWindowHours?.toString() ?? '');
    _lowStockT  = TextEditingController(text: p?.lowStockThreshold.toString() ?? '5');
    
    _fName = FocusNode(); _fBrand = FocusNode(); _fPrice = FocusNode(); _fCostPrice = FocusNode(); _fStock = FocusNode();
    _fUnit = FocusNode(); _fShelf = FocusNode(); _fBarcode = FocusNode(); _fWPrice = FocusNode();
    _fWThreshold = FocusNode(); _fPickupWindow = FocusNode(); _fLowStockT = FocusNode();

    _focusMap = {
      _fName: _name, _fBrand: _brand, _fPrice: _price, _fCostPrice: _costPrice, _fStock: _stock,
      _fUnit: _unit, _fShelf: _shelf, _fBarcode: _barcode, _fWPrice: _wPrice,
      _fWThreshold: _wThreshold, _fPickupWindow: _pickupWindow, _fLowStockT: _lowStockT,
    };

    _category   = (p != null && allCats.contains(p.category)) ? p.category : settings.masterCategories.first;
    _perishable = p?.isPerishable ?? false;
    _taxable    = p?.isTaxable ?? true;
    _status     = p?.status ?? ProductStatus.published;
    _photoBase64 = p?.photoBase64;
    _supplierId = p?.supplierId;
    _expiryDate = p?.expiryDate;
    _variants   = p?.variants != null ? List.from(p!.variants) : [];

    _barcode.addListener(_onBarcodeChanged);

    // Auto-focus barcode on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fBarcode.requestFocus();
    });
  }

  void _onBarcodeChanged() {
    // If user clears the barcode, return focus there to scan again
    if (_barcode.text.isEmpty && !_saving && mounted) {
      if (!_fBarcode.hasFocus) {
        _fBarcode.requestFocus();
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 100,
    );

    if (image != null) {
      setState(() => _processingImage = true);
      
      try {
        final bytes = await image.readAsBytes();
        
        // Remove white background in a background isolate
        final processedBytes = await compute(_processBackgroundRemoval, bytes);
        
        if (processedBytes != null) {
          setState(() {
            _photoBase64 = base64Encode(processedBytes);
            _localPhoto = null; // Use base64 to support transparency preview
          });
        }
      } catch (e) {
        debugPrint('Background Removal Error: $e');
        // Fallback to original image if processing fails
        final bytes = await image.readAsBytes();
        setState(() {
          _localPhoto = File(image.path);
          _photoBase64 = base64Encode(bytes);
        });
      } finally {
        setState(() => _processingImage = false);
      }
    }
  }

  static Uint8List? _processBackgroundRemoval(Uint8List bytes) {
    return ImageUtils.removeWhiteBackground(bytes);
  }

  @override
  void dispose() {
    _name.dispose(); _brand.dispose(); _price.dispose(); _costPrice.dispose(); _stock.dispose();
    _unit.dispose(); _shelf.dispose(); _barcode.dispose(); _wPrice.dispose();
    _wThreshold.dispose(); _pickupWindow.dispose(); _lowStockT.dispose();
    
    _fName.dispose(); _fBrand.dispose(); _fPrice.dispose(); _fCostPrice.dispose(); _fStock.dispose();
    _fUnit.dispose(); _fShelf.dispose(); _fBarcode.dispose(); _fWPrice.dispose();
    _fWThreshold.dispose(); _fPickupWindow.dispose(); _fLowStockT.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final suppliers = inventory.suppliers;
    final allCats = {..._defaultCategories, ...inventory.products.map((e) => e.category)}.toList()..sort();

    final brandStyle = BrandStyling.getStyle(_brand.text, fontSize: 18);

    return BarcodeInterceptor(
      controllers: _focusMap,
      barcodeFocus: _fBarcode,
      nameFocus: _fName,
      onBarcodeDetected: (code) {
        setState(() => _barcode.text = code);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Barcode detected: $code'),
            duration: const Duration(milliseconds: 800),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onTextDetected: (text) {
        setState(() => _name.text = text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Name detected: $text'),
            duration: const Duration(milliseconds: 800),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16, right: 16, top: 24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.product == null ? 'Add Product' : 'Edit Product',
                    style: Theme.of(context).textTheme.titleLarge),
                if (widget.product == null)
                  TextButton.icon(
                    onPressed: _fullScan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Catalog Scan'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                      // Use a subtle gradient to hint at transparency
                      gradient: (_photoBase64 != null || _localPhoto != null) 
                        ? LinearGradient(
                            colors: [Colors.grey.shade100, Colors.white],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _processingImage
                        ? const Center(child: CircularProgressIndicator())
                        : (_localPhoto != null
                            ? Image.file(_localPhoto!, fit: BoxFit.contain)
                            : (_photoBase64 != null
                                ? Image.memory(base64Decode(_photoBase64!), fit: BoxFit.contain)
                                : const Icon(Icons.add_a_photo_outlined, size: 40, color: Colors.grey))),
                  ),
                  if (!_processingImage)
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
                  child: TextField(
                    controller: _brand,
                    focusNode: _fBrand,
                    style: brandStyle.copyWith(fontSize: 18),
                    decoration: const InputDecoration(
                      labelText: 'Brand',
                      hintText: 'e.g. Coca-Cola',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _name,
              focusNode: _fName,
              inputFormatters: [
                LengthLimitingTextInputFormatter(100),
              ],
              decoration: const InputDecoration(labelText: 'Product Name')),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _barcode,
                    focusNode: _fBarcode,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
                      LengthLimitingTextInputFormatter(50),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Barcode',
                      prefixIcon: Icon(Icons.qr_code_scanner),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  tooltip: 'Scan Barcode',
                ),
              ],
            ),
            const SizedBox(height: 10),

              Row(children: [
            Expanded(child: TextField(
                controller: _costPrice,
                focusNode: _fCostPrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                decoration: const InputDecoration(labelText: 'Buying Price', prefixText: '₱ ', hintText: 'Capital'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(
                controller: _price,
                focusNode: _fPrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                decoration: const InputDecoration(labelText: 'Selling Price', prefixText: '₱ '))),
          ]),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(child: TextField(
                controller: _stock,
                focusNode: _fStock,
                enabled: _variants.isEmpty,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: _variants.isEmpty ? 'Current Stock' : 'Total Stock (Locked)',
                  hintText: _variants.isNotEmpty ? 'Manage variants below' : null,
                  suffixText: _variants.isNotEmpty ? _variants.fold(0, (sum, v) => sum + v.stock).toString() : null,
                ))),
            if (_variants.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Text('${_variants.fold(0, (sum, v) => sum + v.stock)} items', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
              ),
            ],
          ]),
          const SizedBox(height: 10),

          // ── VARIANTS SECTION ──────────────────────────────────────────────
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PRODUCT VARIANTS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1, color: Colors.grey)),
              TextButton.icon(
                onPressed: _addVariant,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Variant'),
              ),
            ],
          ),
          if (_variants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No variants added. This item uses base price/stock.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
            )
          else
            ..._variants.asMap().entries.map((entry) {
              final i = entry.key;
              final v = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${formatPeso(v.price)} • Stock: ${v.stock}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editVariant(i)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => setState(() => _variants.removeAt(i))),
                    ],
                  ),
                ),
              );
            }),
          const Divider(height: 32),

          Row(children: [
            Expanded(child: TextField(
                controller: _wPrice,
                focusNode: _fWPrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                decoration: const InputDecoration(labelText: 'Wholesale Price', prefixText: '₱ ', hintText: 'Optional'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(
                controller: _wThreshold,
                focusNode: _fWThreshold,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(labelText: 'Threshold Qty', hintText: 'e.g. 12'))),
          ]),
          const SizedBox(height: 10),

            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: ['pcs', 'pack', 'kg', 'g', 'ml', 'L'].contains(_unit.text) ? _unit.text : 'pcs',
                  decoration: const InputDecoration(labelText: 'UOM'),
                  items: ['pcs', 'pack', 'kg', 'g', 'ml', 'L']
                      .map((u) => DropdownMenuItem(value: u, child: Text(u, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => _unit.text = v!))),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: allCats.map((c) =>
                      DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => _category = v!))),
            ]),
            const SizedBox(height: 10),

              Row(children: [
            Expanded(child: DropdownButtonFormField<ProductStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Visibility Status'),
                items: ProductStatus.values.map((s) =>
                    DropdownMenuItem(value: s, child: Text(s.name.toUpperCase()))).toList(),
                onChanged: (v) => setState(() => _status = v!))),
            const SizedBox(width: 10),
            Expanded(child: TextField(
                controller: _lowStockT,
                focusNode: _fLowStockT,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(labelText: 'Low Stock Threshold'))),
          ]),
          const SizedBox(height: 10),

            CheckboxListTile(
              title: const Text('Taxable (Apply VAT)'),
              value: _taxable,
              onChanged: (v) => setState(() => _taxable = v ?? true),
            ),

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
                subtitle: Text(_perishable 
                    ? 'Set shelf life and specific pickup window.' 
                    : 'Auto-cancels if not picked up within store defaults.'),
                value: _perishable,
                onChanged: (v) => setState(() => _perishable = v)),

            if (_perishable) ...[
            Row(children: [
              Expanded(child: TextField(
                  controller: _shelf,
                  focusNode: _fShelf,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                      labelText: 'Shelf life (days)',
                      prefixIcon: Icon(Icons.timer_outlined)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                  controller: _pickupWindow,
                  focusNode: _fPickupWindow,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                      labelText: 'Pickup (hrs)',
                      prefixIcon: Icon(Icons.shopping_basket_outlined)))),
            ]),
            const SizedBox(height: 12),
          ],

            if (widget.product != null) ...[
              const Divider(height: 32),
                OutlinedButton.icon(
                  onPressed: () => _showLossDialog(context),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Record Loss / Expired / Damaged'),
                  style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
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
                        final name = _name.text.trim().capitalize();
                        final barcode = _barcode.text.trim();
                        final price = double.tryParse(_price.text) ?? 0;
                        final category = _category;
                        final unit = _unit.text.trim();

                        // Validation Logic (Flexible)
                        String? error;
                        if (name.isEmpty) {
                          error = 'Product Name is required.';
                        } else if (price <= 0) {
                          error = 'A valid Selling Price is required.';
                        }
                        // Barcode, Category, Unit are now optional to allow items like eggs/rice

                        if (error != null) {
                          showDialog(
                            context: context,
                            useRootNavigator: true, // Always on top
                            builder: (ctx) => AlertDialog(
                              title: const Text('Missing Information'),
                              content: Text(error!),
                              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                            ),
                          );
                          return;
                        }

                        // Duplicate Barcode Check (Only if barcode is provided)
                        if (barcode.isNotEmpty) {
                          final products = context.read<InventoryProvider>().products;
                          final exists = products.any((p) => p.barcode == barcode && p.id != widget.product?.id);
                          if (exists) {
                            showDialog(
                              context: context,
                              useRootNavigator: true, // Always on top
                              builder: (ctx) => AlertDialog(
                                title: const Text('Duplicate Barcode'),
                                content: const Text('This barcode is already assigned to another item. Please use a unique barcode.'),
                                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                              ),
                            );
                            return;
                          }
                        }

                        setState(() => _saving = true);
                        
                        // Ensure Catalog consistency
                        final inventoryProvider = context.read<InventoryProvider>();
                        
                        if (barcode.isNotEmpty) {
                          // If we have a barcode, ensure it's in the catalog
                          final catalogMatch = inventoryProvider.catalog.where((cp) => cp.barcode == barcode).toList();
                          
                          if (catalogMatch.isEmpty) {
                            // Create new catalog entry for this new barcode
                            await inventoryProvider.saveCatalogProduct(CatalogProduct(
                              id: '',
                              name: name,
                              brand: _brand.text.trim().isEmpty ? null : _brand.text.trim().capitalize(),
                              category: category,
                              barcode: barcode,
                              photoBase64: _photoBase64,
                            ));
                          } else if (catalogMatch.first.name != name || catalogMatch.first.brand != _brand.text.trim()) {
                            // Optionally update catalog if name/brand changed? 
                            // For now, let's keep catalog as the source of truth for the barcode.
                          }
                        }

                        final int newStock = int.tryParse(_stock.text) ?? 0;
                        final int? prevInitial = widget.product?.initialStock;
                        final int calculatedInitial = (widget.product == null)
                            ? newStock
                            : (newStock > (prevInitial ?? widget.product?.stock ?? 0)
                                ? newStock
                                : (prevInitial ?? newStock));

                        final p = Product(
                          id:        widget.product?.id ?? '',
                          name:      name,
                          brand:     _brand.text.trim().isEmpty ? null : _brand.text.trim().capitalize(),
                          category:  category,
                          price:     price,
                          costPrice: double.tryParse(_costPrice.text) ?? 0,
                          stock:     newStock,
                          initialStock: calculatedInitial,
                          unit:      unit,
                          barcode:   barcode.isEmpty ? null : barcode,
                          shelfDays: _perishable ? int.tryParse(_shelf.text) : null,
                          pickupWindowHours: _perishable ? int.tryParse(_pickupWindow.text) : null,
                          lowStockThreshold: int.tryParse(_lowStockT.text) ?? 5,
                          isTaxable: _taxable,
                          status: _status,
                          photoBase64: _photoBase64,
                          supplierId: _supplierId,
                          expiryDate: _expiryDate,
                          wholesalePrice: double.tryParse(_wPrice.text),
                          wholesaleThreshold: int.tryParse(_wThreshold.text),
                          variants: _variants,
                        );
                        
                        if (context.mounted) {
                          await context.read<InventoryProvider>().saveProduct(p);
                        }
                        
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
      ),
    );
  }

  void _showLossDialog(BuildContext context) {
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();
    LossType type = LossType.expired;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Text('Record Loss/Waste'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Product: ${widget.product!.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<LossType>(
                initialValue: type,
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
                  Navigator.pop(ctx);
                  Navigator.pop(context);
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
      useRootNavigator: true,
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
      useRootNavigator: true,
      builder: (ctx) => const ScannerDialog(),
    );
    if (result != null) {
      setState(() {
        _barcode.text = result;
        if (result.length >= 10 && result.contains('17')) {
          final idx = result.indexOf('17');
          if (result.length >= idx + 8) {
            final dateStr = result.substring(idx + 2, idx + 8);
            try {
              final yy = int.parse(dateStr.substring(0, 2)) + 2000;
              final mm = int.parse(dateStr.substring(2, 4));
              final dd = int.parse(dateStr.substring(4, 6));
              _expiryDate = DateTime(yy, mm, dd);
            } catch (_) {}
          }
        }
      });
    }
  }

  Future<void> _pickExpiryDate() async {
    final res = await showDatePicker(
      context: context, 
      useRootNavigator: true,
      initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 30)), 
      firstDate: DateTime.now().subtract(const Duration(days: 365)), 
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (res != null) {
      setState(() => _expiryDate = res);
    }
  }

  Future<void> _fullScan() async {
    final result = await Navigator.push<FullProductScannerResult>(
      context,
      MaterialPageRoute(builder: (_) => const FullProductScannerDialog()),
    );

    if (result != null) {
      setState(() {
        if (result.barcode != null) {
          _barcode.text = result.barcode!;
        }
        
        _name.text = result.name ?? _name.text;
        _brand.text = result.brand ?? _brand.text;
        
        if (result.category != null) {
          final cat = result.category!;
          if (_defaultCategories.contains(cat)) {
            _category = cat;
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catalog details applied! Please review inventory values.')),
      );
    }
  }

  void _editVariant(int index) {
    final v = _variants[index];
    _showVariantSheet(variant: v, onSave: (updated) {
      setState(() => _variants[index] = updated);
    });
  }

  void _addVariant() {
    _showVariantSheet(onSave: (v) {
      setState(() => _variants.add(v));
    });
  }

  void _showVariantSheet({ProductVariant? variant, required ValueChanged<ProductVariant> onSave}) {
    final name = TextEditingController(text: variant?.name ?? '');
    final price = TextEditingController(text: variant?.price.toString() ?? '');
    final cost = TextEditingController(text: variant?.costPrice.toString() ?? '');
    final stock = TextEditingController(text: variant?.stock.toString() ?? '');
    final barcode = TextEditingController(text: variant?.barcode ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(variant == null ? 'New Variant' : 'Edit Variant', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  if (variant == null)
                    TextButton.icon(
                      onPressed: () async {
                        final Product? p = await showDialog<Product>(
                          context: context,
                          useRootNavigator: true,
                          builder: (c) => const _ProductSearchDialog(),
                        );
                        if (p != null) {
                          setModalState(() {
                            name.text = p.name;
                            price.text = p.price.toString();
                            cost.text = p.costPrice.toString();
                            stock.text = p.stock.toString();
                            barcode.text = p.barcode ?? '';
                          });
                        }
                      },
                      icon: const Icon(Icons.inventory_2_outlined, size: 16),
                      label: const Text('Import Product', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Variant Name', hintText: 'e.g. Small, Large, Red, etc.')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost Price', prefixText: '₱ '))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price', prefixText: '₱ '))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock')),
              const SizedBox(height: 10),
              TextField(controller: barcode, decoration: const InputDecoration(labelText: 'Barcode (Optional)', prefixIcon: Icon(Icons.qr_code_scanner))),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (name.text.isEmpty) return;
                  final int vStock = int.tryParse(stock.text) ?? 0;
                  final int? prevVarInitial = variant?.initialStock;
                  final int calculatedVarInitial = (variant == null)
                      ? vStock
                      : (vStock > (prevVarInitial ?? variant?.stock ?? 0)
                          ? vStock
                          : (prevVarInitial ?? vStock));

                  onSave(ProductVariant(
                    id: variant?.id ?? const Uuid().v4(),
                    name: name.text.trim(),
                    price: double.tryParse(price.text) ?? 0,
                    costPrice: double.tryParse(cost.text) ?? 0,
                    stock: vStock,
                    initialStock: calculatedVarInitial,
                    barcode: barcode.text.trim().isEmpty ? null : barcode.text.trim(),
                  ));
                  Navigator.pop(ctx);
                },
                child: const Text('SAVE VARIANT'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductSearchDialog extends StatefulWidget {
  const _ProductSearchDialog();

  @override
  State<_ProductSearchDialog> createState() => _ProductSearchDialogState();
}

class _ProductSearchDialogState extends State<_ProductSearchDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final products = context.watch<InventoryProvider>().products;
    final filtered = products.where((p) {
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) || 
             (p.brand?.toLowerCase().contains(q) ?? false) ||
             (p.barcode?.contains(q) ?? false);
    }).toList();

    return AlertDialog(
      title: const Text('Search Inventory'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search products...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No matching products found.', style: TextStyle(color: Colors.grey)),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (ctx, i) {
                    final p = filtered[i];
                    return ListTile(
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${p.brand ?? 'No Brand'} • Stock: ${p.totalStock}'),
                      trailing: Text(formatPeso(p.price)),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
