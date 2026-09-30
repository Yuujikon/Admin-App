import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../models/catalog_product.dart';
import '../providers/auth_provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/barcode_routing.dart';
import '../utils/format.dart';
import '../utils/image_utils.dart';
import '../utils/barcode_generator.dart';
import 'scanner_dialog.dart';
import 'full_product_scanner_dialog.dart';
import 'barcode_print_dialog.dart';
import 'premium_components.dart';
import '../config/theme.dart';

class AddProductSheet extends StatefulWidget {
  final String? initialBarcode;
  final String? initialSupplierId;
  const AddProductSheet(
      {super.key, this.initialBarcode, this.initialSupplierId});

  @override
  State<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<AddProductSheet> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
  final _lowStockCtrl = TextEditingController(text: '5');
  final _unitCtrl = TextEditingController(text: 'pcs');
  final _notesCtrl = TextEditingController();

  // Bulk / Wholesale Controllers
  bool _enableBulkPacking = false;
  final _bulkUnitCtrl = TextEditingController(text: 'box');
  final _itemsPerBoxCtrl = TextEditingController();
  final _boxPriceCtrl = TextEditingController();
  bool _isCalculatingUom = false;

  // Focus Nodes
  final _nameFocus = FocusNode();
  final _brandFocus = FocusNode();
  final _barcodeFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _costPriceFocus = FocusNode();
  final _lowStockFocus = FocusNode();
  final _unitFocus = FocusNode();

  late Map<FocusNode, TextEditingController> _focusMap;

  // Form State
  String _category = 'Snacks';
  ProductStatus _status = ProductStatus.published;
  String? _supplierId;
  bool _perishable = false;
  bool _saving = false;
  bool _processingImage = false;

  File? _localPhoto;
  String? _photoBase64;
  DateTime? _expiryDate;

  // Real-time duplication warning
  Product? _existingDuplicate;

  static const _defaultCategories = [
    'Fresh',
    'Grains',
    'Snacks',
    'Beverages',
    'Canned Goods',
    'Personal Care',
    'Condiments',
    'Others'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialBarcode != null && widget.initialBarcode!.isNotEmpty) {
      _barcodeCtrl.text = widget.initialBarcode!;
    }
    if (widget.initialSupplierId != null &&
        widget.initialSupplierId!.isNotEmpty) {
      _supplierId = widget.initialSupplierId;
    }

    _focusMap = {
      _nameFocus: _nameCtrl,
      _brandFocus: _brandCtrl,
      _barcodeFocus: _barcodeCtrl,
      _priceFocus: _priceCtrl,
      _costPriceFocus: _costPriceCtrl,
      _lowStockFocus: _lowStockCtrl,
      _unitFocus: _unitCtrl,
    };

    _nameFocus.addListener(_checkDuplicateByName);
    _barcodeFocus.addListener(_checkDuplicateByBarcode);

    _boxPriceCtrl.addListener(_onUomCalculationChanged);
    _itemsPerBoxCtrl.addListener(_onUomCalculationChanged);
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_checkDuplicateByName);
    _barcodeFocus.removeListener(_checkDuplicateByBarcode);

    _boxPriceCtrl.removeListener(_onUomCalculationChanged);
    _itemsPerBoxCtrl.removeListener(_onUomCalculationChanged);

    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _barcodeCtrl.dispose();
    _priceCtrl.dispose();
    _costPriceCtrl.dispose();
    _lowStockCtrl.dispose();
    _unitCtrl.dispose();
    _notesCtrl.dispose();

    _bulkUnitCtrl.dispose();
    _itemsPerBoxCtrl.dispose();
    _boxPriceCtrl.dispose();

    _nameFocus.dispose();
    _brandFocus.dispose();
    _barcodeFocus.dispose();
    _priceFocus.dispose();
    _costPriceFocus.dispose();
    _lowStockFocus.dispose();
    _unitFocus.dispose();

    super.dispose();
  }

  void _checkDuplicateByName() {
    if (!_nameFocus.hasFocus && _nameCtrl.text.trim().isNotEmpty) {
      final inventory = context.read<InventoryProvider>();
      final nameQuery = _nameCtrl.text.trim().toLowerCase();
      final match = inventory.products
          .where((p) => p.name.trim().toLowerCase() == nameQuery)
          .firstOrNull;
      setState(() => _existingDuplicate = match);
    }
  }

  void _checkDuplicateByBarcode() {
    if (!_barcodeFocus.hasFocus && _barcodeCtrl.text.trim().isNotEmpty) {
      final inventory = context.read<InventoryProvider>();
      final code = _barcodeCtrl.text.trim();
      final match =
          inventory.products.where((p) => p.barcode == code).firstOrNull;
      if (match != null) {
        setState(() => _existingDuplicate = match);
      }
    }
  }

  void _onUomCalculationChanged() {
    if (_isCalculatingUom) return;
    _isCalculatingUom = true;

    final itemsPerBox = int.tryParse(_itemsPerBoxCtrl.text) ?? 0;
    final boxPrice = double.tryParse(_boxPriceCtrl.text) ?? 0.0;

    // Calculate Base Unit Cost (COGS) from Bulk Box Cost
    if (boxPrice > 0 && itemsPerBox > 0) {
      final unitCost = boxPrice / itemsPerBox;
      _costPriceCtrl.text = unitCost.toStringAsFixed(2);
    }

    _isCalculatingUom = false;
    if (mounted) setState(() {});
  }

  String _getUomBreakdownText() {
    final itemsBox = int.tryParse(_itemsPerBoxCtrl.text) ?? 0;
    final boxPrice = double.tryParse(_boxPriceCtrl.text) ?? 0.0;
    final bulkName =
        _bulkUnitCtrl.text.trim().isEmpty ? 'box' : _bulkUnitCtrl.text.trim();
    final unitName =
        _unitCtrl.text.trim().isEmpty ? 'pcs' : _unitCtrl.text.trim();

    if (itemsBox <= 0 && boxPrice <= 0) return '';

    final unitCost =
        (boxPrice > 0 && itemsBox > 0) ? (boxPrice / itemsBox) : 0.0;

    if (itemsBox > 0 && boxPrice > 0) {
      return '1 $bulkName @ ${formatPeso(boxPrice)} contains $itemsBox $unitName (Derived Base Cost: ${formatPeso(unitCost)}/$unitName)';
    } else if (itemsBox > 0) {
      return '1 $bulkName = $itemsBox $unitName';
    }
    return '';
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() => _processingImage = true);
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (picked != null) {
        final bytes = await File(picked.path).readAsBytes();
        final compressedBase64 = ImageUtils.compressAndEncode(bytes);
        setState(() {
          _localPhoto = File(picked.path);
          _photoBase64 = compressedBase64;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingImage = false);
    }
  }

  Future<void> _scanBarcode() async {
    final res = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const ScannerDialog(),
    );
    if (res != null && res.isNotEmpty) {
      setState(() {
        _barcodeCtrl.text = res;
      });
      _checkDuplicateByBarcode();
    }
  }

  Future<void> _quickScanAutoFill() async {
    final result = await showDialog<FullProductScannerResult>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const FullProductScannerDialog(),
    );

    if (result != null) {
      setState(() {
        if (result.name != null && result.name!.isNotEmpty) {
          _nameCtrl.text = result.name!;
        }
        if (result.brand != null && result.brand!.isNotEmpty) {
          _brandCtrl.text = result.brand!;
        }
        if (result.barcode != null && result.barcode!.isNotEmpty) {
          _barcodeCtrl.text = result.barcode!;
        }
        if (result.category != null && result.category!.isNotEmpty) {
          _category = result.category!;
        }
      });
      _checkDuplicateByBarcode();
      _checkDuplicateByName();
    }
  }

  void _generateAutoBarcode() {
    final generated = BarcodeGenerator.generateInternalBarcode();
    setState(() {
      _barcodeCtrl.text = generated;
    });
  }

  void _showAddCategoryDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g. Frozen Foods',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newCat = ctrl.text.trim();
              if (newCat.isNotEmpty) {
                final inventory = context.read<InventoryProvider>();
                final settings = inventory.settings;
                final updated = List<String>.from(settings.masterCategories)
                  ..add(newCat)
                  ..sort();
                await inventory.saveStoreSettings(
                  settings.copyWith(masterCategories: updated),
                );
                if (mounted) {
                  setState(() => _category = newCat);
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final inventoryProvider = context.read<InventoryProvider>();

    final name = _nameCtrl.text.trim();
    var barcode = _barcodeCtrl.text.trim();

    // Check existing duplicates
    if (barcode.isNotEmpty) {
      final existingByBarcode = inventoryProvider.products
          .where((p) => p.barcode == barcode)
          .firstOrNull;
      if (existingByBarcode != null) {
        _showDuplicateDialog(existingByBarcode);
        return;
      }
    }

    final existingByName = inventoryProvider.products
        .where((p) => p.name.trim().toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (existingByName != null) {
      _showDuplicateDialog(existingByName);
      return;
    }

    // Auto-generate barcode if blank
    if (barcode.isEmpty) {
      barcode = BarcodeGenerator.generateInternalBarcode();
    }

    final price = double.tryParse(_priceCtrl.text) ?? 0.0;
    final costPrice = double.tryParse(_costPriceCtrl.text) ?? 0.0;
    final lowStockT = int.tryParse(_lowStockCtrl.text) ?? 5;
    final unit = _unitCtrl.text.trim().isEmpty ? 'pcs' : _unitCtrl.text.trim();

    final itemsPerCaseVal =
        _enableBulkPacking ? (int.tryParse(_itemsPerBoxCtrl.text)) : null;
    final packCostVal =
        _enableBulkPacking ? (double.tryParse(_boxPriceCtrl.text)) : null;
    final bulkUnitVal = _enableBulkPacking
        ? (_bulkUnitCtrl.text.trim().isEmpty
            ? 'box'
            : _bulkUnitCtrl.text.trim())
        : 'box';

    setState(() => _saving = true);

    try {
      // 1. Save to master catalog if new
      final catalogMatch = inventoryProvider.catalog
          .where((cp) => cp.barcode == barcode)
          .toList();
      if (catalogMatch.isEmpty) {
        await inventoryProvider.saveCatalogProduct(
          CatalogProduct(
            id: '',
            name: name,
            brand: _brandCtrl.text.trim().isEmpty
                ? null
                : _brandCtrl.text.trim().capitalize(),
            category: _category,
            barcode: barcode,
            photoBase64: _photoBase64,
          ),
        );
      }

      // 2. Construct Master Product Model (Architectural Rule: Initial Stock is 0; seeded via Receive Delivery)
      final product = Product(
        id: '', // Empty ID indicates new creation
        name: name,
        brand: _brandCtrl.text.trim().isEmpty
            ? null
            : _brandCtrl.text.trim().capitalize(),
        category: _category,
        price: price,
        costPrice: costPrice,
        stock: 0,
        initialStock: 0,
        unit: unit,
        bulkUnit: bulkUnitVal,
        packCost: packCostVal,
        itemsPerCase: itemsPerCaseVal,
        barcode: barcode,
        shelfDays: _perishable ? int.tryParse(_notesCtrl.text) : null,
        lowStockThreshold: lowStockT,
        status: _status,
        photoBase64: _photoBase64,
        supplierId: _supplierId,
        expiryDate: _expiryDate,
        variants: const [],
        batches: const [],
      );

      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      await inventoryProvider.saveProduct(product);

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                '🎉 Product "$name" created! Seed stock via "Quick Restock". ✅'),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving product: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showDuplicateDialog(Product existing) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Product Already Exists'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'A product named "${existing.name}" with barcode "${existing.barcode ?? 'N/A'}" already exists in your inventory.'),
            const SizedBox(height: 12),
            Text('Current Stock: ${existing.stock} ${existing.unit}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Price: ${formatPeso(existing.price)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final settings = inventory.settings;
    final suppliers = inventory.suppliers;

    final categories = {
      ..._defaultCategories,
      ...settings.masterCategories,
      ...inventory.products.map((p) => p.category)
    }.toList()
      ..sort();

    final double price = double.tryParse(_priceCtrl.text) ?? 0.0;
    final double cost = double.tryParse(_costPriceCtrl.text) ?? 0.0;
    final double profit = price - cost;
    final double marginPercent = price > 0 ? (profit / price * 100) : 0.0;

    return BarcodeInterceptor(
      controllers: _focusMap,
      barcodeFocus: _barcodeFocus,
      onBarcodeDetected: (code) {
        setState(() => _barcodeCtrl.text = code);
        _checkDuplicateByBarcode();
      },
      onTextDetected: (text) {
        if (_nameFocus.hasFocus) {
          setState(() => _nameCtrl.text = text);
          _checkDuplicateByName();
        }
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top Drag Handle & Title Bar ─────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                GdcColors.primaryGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.add_shopping_cart_rounded,
                            color: GdcColors.primaryGreen,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add New Product',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                'Create a dedicated product profile & initial stock',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _quickScanAutoFill,
                          icon: const Icon(Icons.qr_code_scanner_rounded,
                              size: 16),
                          label: const Text('Auto-Fill',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GdcColors.primaryGreen,
                            side:
                                const BorderSide(color: GdcColors.primaryGreen),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Scrollable Form Body ─────────────────────────────────────────
              Expanded(
                child: Form(
                  key: _formKey,
                  child: MaxWidthContainer(
                    maxWidth: MaxWidthContainer.formMaxWidth,
                    alignment: Alignment.topCenter,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                    children: [
                      // Duplication Alert Banner if detected
                      if (_existingDuplicate != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_rounded,
                                  color: Colors.amber.shade900),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'A matching product "${_existingDuplicate!.name}" already exists in your inventory!',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ── SECTION 1: Product Basic Info ────────────────────────
                      _buildSectionHeader(
                        icon: Icons.inventory_2_outlined,
                        title: 'Product Information',
                      ),

                      const SizedBox(height: 12),

                      // Product Photo Picker
                      Center(
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: () => _pickImage(ImageSource.gallery),
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline
                                        .withValues(alpha: 0.5),
                                  ),
                                  image: _photoBase64 != null
                                      ? DecorationImage(
                                          image: MemoryImage(
                                              base64Decode(_photoBase64!)),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: _photoBase64 == null
                                    ? Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_a_photo_outlined,
                                            size: 28,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Add Photo',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            ),
                            if (_photoBase64 != null)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.red,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                    onPressed: () => setState(() {
                                      _localPhoto = null;
                                      _photoBase64 = null;
                                    }),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Product Name Field
                      TextFormField(
                        controller: _nameCtrl,
                        focusNode: _nameFocus,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Product Name *',
                          hintText: 'e.g. Lucky Me Instant Noodle Beef',
                          prefixIcon: const Icon(Icons.shopping_bag_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Product name is required'
                            : null,
                      ),

                      const SizedBox(height: 12),

                      // Brand & Category Row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _brandCtrl,
                              focusNode: _brandFocus,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                labelText: 'Brand Name',
                                hintText: 'e.g. Lucky Me',
                                prefixIcon: const Icon(
                                    Icons.branding_watermark_outlined),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: categories.contains(_category)
                                  ? _category
                                  : (categories.isNotEmpty ? categories.first : null),
                              decoration: InputDecoration(
                                labelText: 'Category',
                                prefixIcon: const Icon(Icons.category_outlined),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      size: 20),
                                  onPressed: _showAddCategoryDialog,
                                  tooltip: 'Add new category',
                                ),
                              ),
                              items: categories
                                  .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c,
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _category = v);
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Barcode Field with Scan & Auto-Generate
                      TextFormField(
                        controller: _barcodeCtrl,
                        focusNode: _barcodeFocus,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Barcode / PLU',
                          hintText: 'Scan or enter barcode',
                          prefixIcon: const Icon(Icons.qr_code_2_rounded),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.print_rounded),
                                tooltip: 'Print Barcode Label',
                                onPressed: () {
                                  if (_barcodeCtrl.text.isEmpty) {
                                    _generateAutoBarcode();
                                  }
                                  BarcodePrintDialog.showCustom(
                                    context,
                                    productName: _nameCtrl.text,
                                    price:
                                        double.tryParse(_priceCtrl.text) ?? 0,
                                    barcode: _barcodeCtrl.text,
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                                tooltip: 'Scan Barcode',
                                onPressed: _scanBarcode,
                              ),
                              TextButton(
                                onPressed: _generateAutoBarcode,
                                child: const Text('Auto PLU',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Bulk Box / Wholesale Packaging (Optional)
                      Container(
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: 0.3)),
                        ),
                        child: ExpansionTile(
                          shape: const Border(),
                          title: const Text('Bulk Box / Wholesale Packing',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: const Text(
                              'Configure wholesale case/pack cost & units per box',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey)),
                          leading: const Icon(Icons.all_inbox_rounded,
                              color: Colors.teal),
                          initiallyExpanded: _enableBulkPacking,
                          onExpansionChanged: (exp) =>
                              setState(() => _enableBulkPacking = exp),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _bulkUnitCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'Bulk Unit',
                                            hintText: 'e.g. box, case',
                                            border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _itemsPerBoxCtrl,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly
                                          ],
                                          decoration: InputDecoration(
                                            labelText:
                                                'Items / Box (Pack Ratio)',
                                            hintText: 'e.g. 24',
                                            border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _boxPriceCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d{0,2}'))
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Wholesale Box Cost (P)',
                                      prefixText: 'P ',
                                      hintText: 'e.g. 480.00',
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                  ),
                                  if (_getUomBreakdownText().isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.teal.shade300),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.auto_awesome,
                                              size: 18,
                                              color: Colors.teal.shade900),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _getUomBreakdownText(),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── SECTION 2: Pricing & Profit ─────────────────────────
                      _buildSectionHeader(
                        icon: Icons.payments_outlined,
                        title: 'Pricing & Costing',
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _priceCtrl,
                              focusNode: _priceFocus,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}'))
                              ],
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Selling Price (P) *',
                                prefixText: 'P ',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty)
                                  return 'Price required';
                                if ((double.tryParse(v) ?? -1) < 0)
                                  return 'Invalid price';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _costPriceCtrl,
                              focusNode: _costPriceFocus,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}'))
                              ],
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Cost Price / COGS (P)',
                                prefixText: 'P ',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Live Profit Indicator Card
                      if (price > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: profit >= 0
                                ? (marginPercent >= 20
                                    ? Colors.green.shade50
                                    : Colors.orange.shade50)
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: profit >= 0
                                  ? (marginPercent >= 20
                                      ? Colors.green.shade300
                                      : Colors.orange.shade300)
                                  : Colors.red.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    profit >= 0
                                        ? Icons.trending_up_rounded
                                        : Icons.trending_down_rounded,
                                    color: profit >= 0
                                        ? (marginPercent >= 20
                                            ? Colors.green.shade800
                                            : Colors.orange.shade800)
                                        : Colors.red.shade800,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Profit Margin:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: profit >= 0
                                          ? (marginPercent >= 20
                                              ? Colors.green.shade900
                                              : Colors.orange.shade900)
                                          : Colors.red.shade900,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${formatPeso(profit)} (${marginPercent.toStringAsFixed(1)}%)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: profit >= 0
                                      ? (marginPercent >= 20
                                          ? Colors.green.shade900
                                          : Colors.orange.shade900)
                                      : Colors.red.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),

                      // ── SECTION 3: Stock & Inventory Control ──────
                      _buildSectionHeader(
                        icon: Icons.inventory_outlined,
                        title: 'Inventory & Stock Parameters',
                      ),

                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.blue.shade900, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Architectural Rule: Creating a product initializes master schema parameters (Stock: 0). All inventory batches must be seeded via "Receive Delivery" to ensure FEFO compliance and maintain audit trails.',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade900,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _unitCtrl,
                              focusNode: _unitFocus,
                              decoration: InputDecoration(
                                labelText: 'Base Unit *',
                                hintText: 'pcs, bottle, kg',
                                prefixIcon:
                                    const Icon(Icons.straighten_outlined),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _lowStockCtrl,
                              focusNode: _lowStockFocus,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: InputDecoration(
                                labelText: 'Low Stock Alert Level',
                                prefixIcon: const Icon(
                                    Icons.notification_important_outlined),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      DropdownButtonFormField<String?>(
                        value: suppliers.any((s) => s.id == _supplierId)
                            ? _supplierId
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Assigned Supplier',
                          prefixIcon: const Icon(Icons.local_shipping_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('None / Direct')),
                          ...suppliers.map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name,
                                  overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) => setState(() => _supplierId = v),
                      ),

                      const SizedBox(height: 12),

                      // Perishable & Expiry Date Switch
                      SwitchListTile(
                        title: const Text('Perishable / Has Expiry Date',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: const Text(
                            'Enable expiration tracking for FEFO stock management',
                            style: TextStyle(fontSize: 11)),
                        value: _perishable,
                        activeColor: GdcColors.primaryGreen,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setState(() => _perishable = val),
                      ),

                      if (_perishable)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _expiryDate ??
                                          DateTime.now()
                                              .add(const Duration(days: 30)),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now()
                                          .add(const Duration(days: 3650)),
                                    );
                                    if (picked != null) {
                                      setState(() => _expiryDate = picked);
                                    }
                                  },
                                  icon: const Icon(Icons.event_outlined,
                                      size: 18),
                                  label: Text(
                                    _expiryDate == null
                                        ? 'Select Expiry Date'
                                        : 'Expires: ${DateFormat('yyyy-MM-dd').format(_expiryDate!)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              if (_expiryDate != null)
                                IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Colors.red),
                                  onPressed: () =>
                                      setState(() => _expiryDate = null),
                                ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),

                      // ── SECTION 4: Additional Notes / Invoice

                      // ── SECTION 5: Additional Notes / Invoice
                      TextFormField(
                        controller: _notesCtrl,
                        decoration: InputDecoration(
                          labelText: 'Initial Delivery Notes / Invoice Ref',
                          hintText: 'Optional purchase order or batch notes',
                          prefixIcon: const Icon(Icons.note_alt_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),

              // ── Bottom Action Button Bar ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: MaxWidthContainer(
                  maxWidth: MaxWidthContainer.formMaxWidth,
                  alignment: Alignment.center,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _saveProduct,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_circle_rounded, size: 20),
                          label: Text(
                            _saving ? 'Saving...' : 'SAVE NEW PRODUCT',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GdcColors.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
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
      ),
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: GdcColors.primaryGreen),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}
