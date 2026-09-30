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
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/barcode_routing.dart';
import '../utils/format.dart';
import '../utils/image_utils.dart';
import 'scanner_dialog.dart';
import 'full_product_scanner_dialog.dart';
import '../config/theme.dart';
import '../services/external_barcode_service.dart';
import '../utils/barcode_generator.dart';
import '../utils/pricing_engine.dart';

class ProductEditSheet extends StatefulWidget {
  final Product? product;
  const ProductEditSheet({super.key, this.product});

  @override
  State<ProductEditSheet> createState() => _ProductEditSheetState();
}

class _ProductEditSheetState extends State<ProductEditSheet> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _price;
  late final TextEditingController _costPrice;
  late final TextEditingController _stock;
  late final TextEditingController _unit;
  late final TextEditingController _shelf;
  late final TextEditingController _barcode;
  late final TextEditingController _itemsPerCase;
  late final TextEditingController _pickupWindow;
  late final TextEditingController _lowStockT;
  late final TextEditingController _boxPriceCtrl;
  late final TextEditingController _itemsPerBoxCtrl;
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _notesCtrl = TextEditingController();

  // Focus Nodes
  late final FocusNode _fName;
  late final FocusNode _fBrand;
  late final FocusNode _fPrice;
  late final FocusNode _fCostPrice;
  late final FocusNode _fStock;
  late final FocusNode _fUnit;
  late final FocusNode _fShelf;
  late final FocusNode _fBarcode;
  late final FocusNode _fItemsPerCase;
  late final FocusNode _fPickupWindow;
  late final FocusNode _fLowStockT;
  late final FocusNode _fBoxPrice;
  late final FocusNode _fItemsPerBox;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  Map<FocusNode, TextEditingController> _focusMap = {};

  late String _category;
  late ProductStatus _status;
  String? _supplierId;
  bool _perishable = false;
  bool _taxable = true;
  bool _saving = false;
  bool _processingImage = false;

  // Smart Pricing Engine & Bulk Cost Calculator Flags
  bool _isManualPriceOverride = false;
  bool _isCalculatingBulk = false;
  bool _isCalculatingPrice = false;

  File? _localPhoto;
  String? _photoBase64;
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

    final allCats = {..._defaultCategories, ...products.map((e) => e.category)};

    _name = TextEditingController(text: p?.name ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _price = TextEditingController(text: p?.price.toString() ?? '');
    _costPrice = TextEditingController(text: p?.costPrice.toString() ?? '0');
    _stock = TextEditingController(text: p?.stock.toString() ?? '');
    _unit = TextEditingController(text: p?.unit ?? 'pcs');
    _shelf = TextEditingController(text: p?.shelfDays?.toString() ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _itemsPerCase = TextEditingController(text: p?.itemsPerCase?.toString() ?? '');
    _pickupWindow = TextEditingController(text: p?.pickupWindowHours?.toString() ?? '');
    _lowStockT = TextEditingController(text: p?.lowStockThreshold.toString() ?? '5');
    _boxPriceCtrl = TextEditingController();
    _itemsPerBoxCtrl = TextEditingController(text: p?.itemsPerCase?.toString() ?? '');

    _fName = FocusNode();
    _fBrand = FocusNode();
    _fPrice = FocusNode();
    _fCostPrice = FocusNode();
    _fStock = FocusNode();
    _fUnit = FocusNode();
    _fShelf = FocusNode();
    _fBarcode = FocusNode();
    _fItemsPerCase = FocusNode();
    _fPickupWindow = FocusNode();
    _fLowStockT = FocusNode();
    _fBoxPrice = FocusNode();
    _fItemsPerBox = FocusNode();

    _controllers = [
      _name, _brand, _price, _costPrice, _stock, _unit,
      _shelf, _barcode, _itemsPerCase, _pickupWindow, _lowStockT,
      _boxPriceCtrl, _itemsPerBoxCtrl, _qtyCtrl, _notesCtrl,
    ];

    _focusNodes = [
      _fName, _fBrand, _fPrice, _fCostPrice, _fStock, _fUnit,
      _fShelf, _fBarcode, _fItemsPerCase, _fPickupWindow, _fLowStockT,
      _fBoxPrice, _fItemsPerBox,
    ];

    _focusMap = {
      _fName: _name, _fBrand: _brand, _fPrice: _price, _fCostPrice: _costPrice, _fStock: _stock,
      _fUnit: _unit, _fShelf: _shelf, _fBarcode: _barcode, _fItemsPerCase: _itemsPerCase,
      _fPickupWindow: _pickupWindow, _fLowStockT: _lowStockT,
      _fBoxPrice: _boxPriceCtrl, _fItemsPerBox: _itemsPerBoxCtrl,
    };

    _category = (p != null && allCats.contains(p.category)) ? p.category : settings.masterCategories.first;
    _perishable = p?.isPerishable ?? false;
    _taxable = p?.isTaxable ?? true;
    _status = p?.status ?? ProductStatus.published;
    _photoBase64 = p?.photoBase64;
    _supplierId = p?.supplierId;
    _expiryDate = p?.expiryDate;
    _variants = p?.variants != null ? List.from(p!.variants) : [];

    if (p != null && p.price > 0 && p.costPrice > 0) {
      _isManualPriceOverride = true;
    }

    _barcode.addListener(_onBarcodeChanged);
    _costPrice.addListener(_onUnitCostChanged);
    _boxPriceCtrl.addListener(_onBulkCostCalculatorChanged);
    _itemsPerBoxCtrl.addListener(_onBulkCostCalculatorChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fBarcode.requestFocus();
    });
  }

  void _onBarcodeChanged() {
    if (_barcode.text.isEmpty && !_saving && mounted) {
      if (!_fBarcode.hasFocus) {
        _fBarcode.requestFocus();
      }
    }
  }

  void _onBulkCostCalculatorChanged() {
    if (_isCalculatingBulk) return;
    final boxPrice = double.tryParse(_boxPriceCtrl.text) ?? 0;
    final itemsCount = int.tryParse(_itemsPerBoxCtrl.text) ?? 0;

    if (boxPrice > 0 && itemsCount > 0) {
      _isCalculatingBulk = true;
      final unitCost = boxPrice / itemsCount;
      _costPrice.text = unitCost.toStringAsFixed(2);
      _itemsPerCase.text = itemsCount.toString();
      _isCalculatingBulk = false;
      _autoCalculateSellingPrice();
    }
  }

  void _onUnitCostChanged() {
    if (_isCalculatingBulk) return;
    _autoCalculateSellingPrice();
  }

  void _autoCalculateSellingPrice() {
    if (_isCalculatingPrice || _isManualPriceOverride) return;
    final unitCost = double.tryParse(_costPrice.text) ?? 0;
    if (unitCost > 0) {
      _isCalculatingPrice = true;
      final suggested = CategoryMarkupRules.calculateSellingPrice(
        unitCost: unitCost,
        category: _category,
      );
      _price.text = suggested.toStringAsFixed(2);
      _isCalculatingPrice = false;
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() => _processingImage = true);

      try {
        final bytes = await image.readAsBytes();
        final processedBytes = await compute(_processBackgroundRemoval, bytes);

        if (processedBytes != null) {
          setState(() {
            _localPhoto = File(image.path);
            _photoBase64 = base64Encode(processedBytes);
          });
        } else {
          setState(() {
            _localPhoto = File(image.path);
            _photoBase64 = base64Encode(bytes);
          });
        }
      } catch (e) {
        debugPrint('Image Processing Error: $e');
        setState(() {
          _localPhoto = File(image.path);
        });
      } finally {
        if (mounted) setState(() => _processingImage = false);
      }
    }
  }

  static Uint8List? _processBackgroundRemoval(Uint8List bytes) {
    return ImageUtils.removeWhiteBackground(bytes);
  }

  @override
  void dispose() {
    _barcode.removeListener(_onBarcodeChanged);
    _costPrice.removeListener(_onUnitCostChanged);
    _boxPriceCtrl.removeListener(_onBulkCostCalculatorChanged);
    _itemsPerBoxCtrl.removeListener(_onBulkCostCalculatorChanged);
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
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
      onBarcodeDetected: (code) async {
        setState(() => _barcode.text = code);
        await _handleBarcodeScan(code);
      },
      onTextDetected: (text) {
        setState(() => _name.text = text);
      },
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16, right: 16, top: 24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.product == null ? 'Add New Product' : 'Edit Product',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (widget.product == null)
                      TextButton.icon(
                        onPressed: _fullScan,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Catalog Scan'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── SECTION 1: PRODUCT IDENTITY (CATALOG PROFILE) ─────────────
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.badge_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'SECTION 1: PRODUCT IDENTITY (CATALOG PROFILE)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Image Picker Avatar
                        Center(
                          child: Stack(
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _processingImage
                                    ? const Center(child: CircularProgressIndicator())
                                    : (_localPhoto != null
                                        ? Image.file(_localPhoto!, fit: BoxFit.contain)
                                        : (_photoBase64 != null
                                            ? Image.memory(base64Decode(_photoBase64!), fit: BoxFit.contain)
                                            : const Icon(Icons.add_a_photo_outlined, size: 36, color: Colors.grey))),
                              ),
                              if (!_processingImage)
                                Positioned(
                                  bottom: -6,
                                  right: -6,
                                  child: IconButton.filledTonal(
                                    onPressed: _pickImage,
                                    icon: const Icon(Icons.edit, size: 16),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Barcode Input
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _barcode,
                                focusNode: _fBarcode,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
                                  LengthLimitingTextInputFormatter(50),
                                ],
                                onFieldSubmitted: (v) async {
                                  if (v.trim().isNotEmpty) {
                                    await _handleBarcodeScan(v);
                                  }
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Barcode (Leave blank to auto-generate PLU 200)',
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
                        const SizedBox(height: 12),

                        // Product Name Input (Required)
                        TextFormField(
                          controller: _name,
                          focusNode: _fName,
                          inputFormatters: [LengthLimitingTextInputFormatter(100)],
                          decoration: const InputDecoration(labelText: 'Product Name *', hintText: 'e.g. Coca-Cola 1.5L'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Product Name is required.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Brand & Category Dropdown
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _brand,
                                focusNode: _fBrand,
                                style: brandStyle.copyWith(fontSize: 16),
                                decoration: const InputDecoration(labelText: 'Brand', hintText: 'e.g. Coca-Cola'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _category,
                                decoration: const InputDecoration(labelText: 'Category *'),
                                items: allCats
                                    .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      _category = v;
                                      _autoCalculateSellingPrice();
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Selling Price Input (Smart Pricing Engine Auto-Calculate)
                        TextFormField(
                          controller: _price,
                          focusNode: _fPrice,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          onChanged: (_) {
                            if (!_isCalculatingPrice) {
                              setState(() => _isManualPriceOverride = true);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Selling Price *',
                            prefixText: '₱ ',
                            suffixIcon: Tooltip(
                              message: 'Auto-calculate based on ${(CategoryMarkupRules.getMarginForCategory(_category) * 100).toInt()}% category margin',
                              child: IconButton(
                                icon: Icon(
                                  _isManualPriceOverride ? Icons.lock_outline_rounded : Icons.auto_awesome_rounded,
                                  size: 18,
                                  color: _isManualPriceOverride ? Colors.orange : Theme.of(context).colorScheme.primary,
                                ),
                                onPressed: () {
                                  setState(() => _isManualPriceOverride = false);
                                  _autoCalculateSellingPrice();
                                },
                              ),
                            ),
                          ),
                          validator: (v) {
                            final p = double.tryParse(v ?? '');
                            if (p == null || p <= 0) {
                              return 'Valid Selling Price required.';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── SECTION 2: FIRST DELIVERY DETAILS (INITIAL INVENTORY) ────
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 20, color: Colors.green.shade800),
                            const SizedBox(width: 8),
                            Text(
                              'SECTION 2: FIRST DELIVERY DETAILS (INITIAL INVENTORY)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Bulk Cost Calculator (Expandable)
                        if (context.watch<AppAuthProvider>().role == UserRole.admin) ...[
                          Card(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.15),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
                            ),
                            child: Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                leading: Icon(Icons.calculate_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
                                title: const Text('Calculate Unit Cost from Box/Bulk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _boxPriceCtrl,
                                            focusNode: _fBoxPrice,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                                            decoration: const InputDecoration(labelText: 'Total Box Price', prefixText: '₱ ', hintText: '720.00'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _itemsPerBoxCtrl,
                                            focusNode: _fItemsPerBox,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                            decoration: const InputDecoration(labelText: 'Items per Box', hintText: '24'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Initial Quantity & Unit Cost Inputs
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _stock,
                                focusNode: _fStock,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  labelText: 'Initial Quantity *',
                                  hintText: 'e.g. 48 pcs',
                                ),
                                validator: (v) {
                                  final q = int.tryParse(v ?? '');
                                  if (q == null || q < 0) return 'Enter quantity';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (context.watch<AppAuthProvider>().role == UserRole.admin) ...[
                              Expanded(
                                child: TextFormField(
                                  controller: _costPrice,
                                  focusNode: _fCostPrice,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                                  decoration: const InputDecoration(
                                    labelText: 'Unit Cost *',
                                    prefixText: '₱ ',
                                    hintText: 'e.g. 30.00',
                                  ),
                                  validator: (v) {
                                    final c = double.tryParse(v ?? '');
                                    if (c == null || c <= 0) return 'Enter unit cost';
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Batch Expiry Date Selector
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_available_outlined),
                          title: const Text('Batch Expiry Date'),
                          subtitle: Text(_expiryDate == null ? 'Not set (Optional)' : DateFormat('MMMM dd, yyyy').format(_expiryDate!)),
                          trailing: _expiryDate != null
                              ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _expiryDate = null))
                              : const Icon(Icons.chevron_right),
                          onTap: _pickExpiryDate,
                        ),
                        const SizedBox(height: 12),

                        // Safety Stock Warning & Supplier Dropdown
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _lowStockT,
                                focusNode: _fLowStockT,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  labelText: 'Safety Stock Warning',
                                  hintText: 'Alert level e.g. 5',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                isExpanded: true,
                                initialValue: _supplierId,
                                decoration: const InputDecoration(labelText: 'Supplier'),
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('None / Direct')),
                                  ...suppliers.map((s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))),
                                ],
                                onChanged: (v) => setState(() => _supplierId = v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Submit Button: Executes WriteBatch
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveProductForm,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Saving Profile & Batch...' : 'SAVE PRODUCT & RECEIVE INITIAL STOCK'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GdcColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),

                if (widget.product != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text('DELETE PRODUCT', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _fullScan() async {
    final result = await showDialog<FullProductScannerResult>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => const FullProductScannerDialog(),
    );

    if (result != null && mounted) {
      setState(() {
        if (result.name != null && result.name!.isNotEmpty) _name.text = result.name!;
        if (result.brand != null && result.brand!.isNotEmpty) _brand.text = result.brand!;
        if (result.category != null && result.category!.isNotEmpty) _category = result.category!;
        if (result.barcode != null && result.barcode!.isNotEmpty) _barcode.text = result.barcode!;
      });
      _autoCalculateSellingPrice();
    }
  }

  Future<void> _scanBarcode() async {
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => const ScannerDialog(),
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        _barcode.text = result;
      });
      await _handleBarcodeScan(result);
    }
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return;

    final inventory = context.read<InventoryProvider>();

    // 1. Search Local Store Products
    final localMatch = inventory.products.where((p) => p.barcode == cleanBarcode).toList();
    if (localMatch.isNotEmpty) {
      final product = localMatch.first;
      setState(() {
        _name.text = product.name;
        final b = product.brand;
        if (b != null && b.isNotEmpty) {
          _brand.text = b;
        }
        _price.text = product.price.toString();
        _costPrice.text = product.costPrice.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-filled "${product.name}" from store database! ✅'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // 2. Search Local Catalog
    final catalogMatch = inventory.catalog.where((cp) => cp.barcode == cleanBarcode).toList();
    if (catalogMatch.isNotEmpty) {
      final cp = catalogMatch.first;
      setState(() {
        _name.text = cp.name;
        final cpb = cp.brand;
        if (cpb != null && cpb.isNotEmpty) {
          _brand.text = cpb;
        }
        if (cp.category.isNotEmpty) {
          _category = cp.category;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-filled "${cp.name}" from store catalog! ✅'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // 3. Search Global Barcode Database (Open Food Facts & UPCitemdb)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 12),
              Text('Searching global barcode database... 🌐'),
            ],
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final extInfo = await ExternalBarcodeService.fetchProductInfo(cleanBarcode);

    if (extInfo != null && mounted) {
      setState(() {
        _name.text = extInfo.name;
        final extBrand = extInfo.brand;
        if (extBrand != null && extBrand.isNotEmpty) {
          _brand.text = extBrand;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-filled "${extInfo.name}" from ${extInfo.source}! 🌐'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New barcode ($cleanBarcode)! Please enter product details manually.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickExpiryDate() async {
    final res = await showDatePicker(
      context: context,
      useRootNavigator: true,
      initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (res != null) {
      setState(() => _expiryDate = res);
    }
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

  // Refactored Form Save Method: Executes simultaneous Firestore WriteBatch
  Future<void> _saveProductForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _name.text.trim().capitalize();
    String barcode = _barcode.text.trim();
    final price = double.tryParse(_price.text) ?? 0;
    final costPrice = double.tryParse(_costPrice.text) ?? 0;
    final initialQty = int.tryParse(_stock.text) ?? 0;
    final category = _category;
    final unit = _unit.text.trim();

    // Auto-generate internal 12-digit PLU barcode starting with '200' if left empty
    if (barcode.isEmpty) {
      barcode = BarcodeGenerator.generateInternalBarcode();
    } else {
      // Duplicate Barcode Check (Only if user manually entered a barcode)
      final products = context.read<InventoryProvider>().products;
      final exists = products.any((p) => p.barcode == barcode && p.id != widget.product?.id);
      if (exists) {
        showDialog(
          context: context,
          useRootNavigator: true,
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

    try {
      final inventoryProvider = context.read<InventoryProvider>();

      // 1. Save or Update Catalog Entry
      final catalogMatch = inventoryProvider.catalog.where((cp) => cp.barcode == barcode).toList();
      if (catalogMatch.isEmpty) {
        await inventoryProvider.saveCatalogProduct(CatalogProduct(
          id: '',
          name: name,
          brand: _brand.text.trim().isEmpty ? null : _brand.text.trim().capitalize(),
          category: category,
          barcode: barcode,
          photoBase64: _photoBase64,
        ));
      }

      final int? prevInitial = widget.product?.initialStock;
      final int calculatedInitial = (widget.product == null)
          ? initialQty
          : (initialQty > (prevInitial ?? widget.product?.stock ?? 0)
              ? initialQty
              : (prevInitial ?? initialQty));

      // Construct Main Product Model
      final p = Product(
        id: widget.product?.id ?? '',
        name: name,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim().capitalize(),
        category: category,
        price: price,
        costPrice: costPrice,
        stock: initialQty,
        initialStock: calculatedInitial,
        unit: unit,
        barcode: barcode,
        shelfDays: _perishable ? int.tryParse(_shelf.text) : null,
        pickupWindowHours: _perishable ? int.tryParse(_pickupWindow.text) : null,
        lowStockThreshold: int.tryParse(_lowStockT.text) ?? 5,
        isTaxable: _taxable,
        status: _status,
        photoBase64: _photoBase64,
        supplierId: _supplierId,
        expiryDate: _expiryDate,
        itemsPerCase: int.tryParse(_itemsPerCase.text),
        variants: _variants,
        batches: widget.product?.batches ?? const [],
      );

      // Construct First ProductBatch Model
      final initialBatch = ProductBatch(
        id: const Uuid().v4(),
        productId: p.id,
        quantity: initialQty,
        unitCost: costPrice,
        expiryDate: _expiryDate,
        createdAt: DateTime.now(),
        invoiceNumber: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      await inventoryProvider.saveProductWithBatch(
        product: p,
        initialBatch: initialBatch,
      );

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Saved product profile & initial batch of $initialQty pcs for "$name"! ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving product profile & batch: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
