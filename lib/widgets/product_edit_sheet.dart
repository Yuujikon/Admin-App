import 'dart:ui';
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
import 'receive_delivery_sheet.dart';
import 'barcode_print_dialog.dart';
import 'premium_components.dart';
import '../config/theme.dart';
import '../services/external_barcode_service.dart';
import '../utils/barcode_generator.dart';
import '../utils/pricing_engine.dart';

class ProductEditSheet extends StatefulWidget {
  final Product? product;
  final String? initialBarcode;
  final String? initialSupplierId;

  const ProductEditSheet({
    super.key,
    this.product,
    this.initialBarcode,
    this.initialSupplierId,
  });

  @override
  State<ProductEditSheet> createState() => _ProductEditSheetState();
}

class _ProductEditSheetState extends State<ProductEditSheet> {
  final _formKey = GlobalKey<FormState>();

  Product? _activeProduct;

  // Text Controllers
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _parentIdCtrl;
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
  late final TextEditingController _boxesReceivedCtrl;
  late final TextEditingController _extraItemsCtrl;
  late final TextEditingController _bulkUnitCtrl;
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _notesCtrl = TextEditingController();

  // Focus Nodes
  late final FocusNode _fName;
  late final FocusNode _fBrand;
  late final FocusNode _fParentId;
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
  late final FocusNode _fBoxesReceived;
  late final FocusNode _fExtraItems;

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
  bool _isCalculatingPrice = false;
  bool _isCalculatingUom = false;

  File? _localPhoto;
  String? _photoBase64;
  DateTime? _expiryDate;
  List<ProductVariant> _variants = [];

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
    _activeProduct = widget.product;
    final p = _activeProduct;
    final inventory = context.read<InventoryProvider>();
    final settings = inventory.settings;
    final products = inventory.products;

    final allCats = {..._defaultCategories, ...products.map((e) => e.category)};

    int? initBoxes;
    int? initExtra;
    if (p != null && p.stock > 0 && p.hasBulkPacking) {
      initBoxes = p.stock ~/ p.piecesPerPack;
      initExtra = p.stock % p.piecesPerPack;
    }

    _name = TextEditingController(text: p?.name ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _parentIdCtrl = TextEditingController(text: p?.parentId ?? '');
    _price = TextEditingController(text: p?.price.toString() ?? '');
    _costPrice = TextEditingController(text: p?.costPrice.toString() ?? '0');
    _stock = TextEditingController(text: p?.stock.toString() ?? '');
    _unit = TextEditingController(text: p?.unit ?? 'pcs');
    _shelf = TextEditingController(text: p?.shelfDays?.toString() ?? '');
    _barcode = TextEditingController(
        text: p?.barcode ?? widget.initialBarcode ?? '');
    _itemsPerCase =
        TextEditingController(text: p?.itemsPerCase?.toString() ?? '');
    _pickupWindow =
        TextEditingController(text: p?.pickupWindowHours?.toString() ?? '');
    _lowStockT =
        TextEditingController(text: p?.lowStockThreshold.toString() ?? '5');
    _boxPriceCtrl = TextEditingController(text: p?.packCost?.toString() ?? '');
    _itemsPerBoxCtrl =
        TextEditingController(text: p?.itemsPerCase?.toString() ?? '');
    _boxesReceivedCtrl = TextEditingController(
        text: initBoxes != null && initBoxes > 0 ? initBoxes.toString() : '');
    _extraItemsCtrl = TextEditingController(
        text: initExtra != null && initExtra > 0 ? initExtra.toString() : '');
    _bulkUnitCtrl = TextEditingController(text: p?.bulkUnit ?? 'box');

    _fName = FocusNode();
    _fBrand = FocusNode();
    _fParentId = FocusNode();
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
    _fBoxesReceived = FocusNode();
    _fExtraItems = FocusNode();

    _controllers = [
      _name,
      _brand,
      _parentIdCtrl,
      _price,
      _costPrice,
      _stock,
      _unit,
      _shelf,
      _barcode,
      _itemsPerCase,
      _pickupWindow,
      _lowStockT,
      _boxPriceCtrl,
      _itemsPerBoxCtrl,
      _boxesReceivedCtrl,
      _extraItemsCtrl,
      _bulkUnitCtrl,
      _qtyCtrl,
      _notesCtrl,
    ];

    _focusNodes = [
      _fName,
      _fBrand,
      _fParentId,
      _fPrice,
      _fCostPrice,
      _fStock,
      _fUnit,
      _fShelf,
      _fBarcode,
      _fItemsPerCase,
      _fPickupWindow,
      _fLowStockT,
      _fBoxPrice,
      _fItemsPerBox,
      _fBoxesReceived,
      _fExtraItems,
    ];

    _focusMap = {
      _fName: _name,
      _fBrand: _brand,
      _fParentId: _parentIdCtrl,
      _fPrice: _price,
      _fCostPrice: _costPrice,
      _fStock: _stock,
      _fUnit: _unit,
      _fShelf: _shelf,
      _fBarcode: _barcode,
      _fItemsPerCase: _itemsPerCase,
      _fPickupWindow: _pickupWindow,
      _fLowStockT: _lowStockT,
      _fBoxPrice: _boxPriceCtrl,
      _fItemsPerBox: _itemsPerBoxCtrl,
      _fBoxesReceived: _boxesReceivedCtrl,
      _fExtraItems: _extraItemsCtrl,
    };

    _category = (p != null && allCats.contains(p.category))
        ? p.category
        : settings.masterCategories.first;
    _perishable = p?.isPerishable ?? false;
    _taxable = p?.isTaxable ?? true;
    _status = p?.status ?? ProductStatus.published;
    _photoBase64 = p?.photoBase64;
    _supplierId = p?.supplierId ?? widget.initialSupplierId;
    _expiryDate = p?.expiryDate;
    _variants = p?.variants != null ? List.from(p!.variants) : [];

    if (p != null && p.price > 0 && p.costPrice > 0) {
      _isManualPriceOverride = true;
    }

    _barcode.addListener(_onBarcodeChanged);
    _costPrice.addListener(_onUnitCostChanged);
    _boxPriceCtrl.addListener(_onUomCalculationChanged);
    _boxesReceivedCtrl.addListener(_onUomCalculationChanged);
    _itemsPerBoxCtrl.addListener(_onUomCalculationChanged);
    _extraItemsCtrl.addListener(_onUomCalculationChanged);
    _name.addListener(_onNameOrBrandChanged);
    _brand.addListener(_onNameOrBrandChanged);

    _fName.addListener(() {
      if (!_fName.hasFocus &&
          _name.text.trim().isNotEmpty &&
          _activeProduct == null) {
        _checkExistingProductByName(_name.text);
      }
    });

    _fBarcode.addListener(() {
      if (!_fBarcode.hasFocus && _barcode.text.trim().isNotEmpty) {
        _checkExistingProductByBarcode(_barcode.text);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fBarcode.requestFocus();
    });
  }

  void _checkExistingProductByBarcode(String barcode) {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return;

    final inventory = context.read<InventoryProvider>();
    final localMatch = inventory.products
        .where(
          (p) => p.barcode == cleanBarcode && p.id != _activeProduct?.id,
        )
        .toList();

    if (localMatch.isNotEmpty) {
      _showProductAlreadyExistsDialog(localMatch.first);
    }
  }

  void _checkExistingProductByName(String name) {
    final cleanName = name.trim();
    if (cleanName.length < 2) return;

    final inventory = context.read<InventoryProvider>();
    final localMatch = inventory.products
        .where(
          (p) =>
              p.name.trim().toLowerCase() == cleanName.toLowerCase() &&
              p.id != _activeProduct?.id,
        )
        .toList();

    if (localMatch.isNotEmpty) {
      _showProductAlreadyExistsDialog(localMatch.first);
    }
  }

  void _showProductAlreadyExistsDialog(Product existingProduct) {
    if (!mounted) return;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.inventory_2_rounded,
                  color: Theme.of(context).colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Product Already in System',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Container(
          width: 440,
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            existingProduct.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('ALREADY IN STORE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.brown)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (existingProduct.barcode != null &&
                        existingProduct.barcode!.isNotEmpty)
                      Text('Barcode: ${existingProduct.barcode}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    Text(
                        'Category: ${existingProduct.category} • Brand: ${existingProduct.brand ?? 'N/A'}',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant)),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            'Current Stock: ${existingProduct.totalStock} ${existingProduct.unit}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('Price: ${formatPeso(existingProduct.price)}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.primary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'This product is already registered in your store inventory.\n\nWhat would you like to do?',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  final parentCtx = context;
                  Navigator.pop(ctx);
                  Navigator.pop(parentCtx);
                  showModalBottomSheet(
                    context: parentCtx,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) =>
                        ReceiveDeliverySheet(initialProduct: existingProduct),
                  );
                },
                icon: const Icon(Icons.add_business_rounded, size: 20),
                label: const Text('Receive Delivery / Restock Batch'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _loadExistingProduct(existingProduct);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Switched to editing existing product "${existingProduct.name}"'),
                      backgroundColor: Colors.blue.shade700,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.edit_note_rounded, size: 20),
                label: const Text('Edit Existing Product Profile'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _barcode.clear();
                    _name.clear();
                  });
                },
                child: const Text('Cancel & Clear Input',
                    style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _loadExistingProduct(Product p) {
    setState(() {
      _activeProduct = p;
      _name.text = p.name;
      _brand.text = p.brand ?? '';
      _parentIdCtrl.text = p.parentId ?? '';
      _price.text = p.price.toString();
      _costPrice.text = p.costPrice.toString();
      _stock.text = p.stock.toString();
      _unit.text = p.unit;
      _shelf.text = p.shelfDays?.toString() ?? '';
      _barcode.text = p.barcode ?? '';
      _itemsPerCase.text = p.itemsPerCase?.toString() ?? '';
      _pickupWindow.text = p.pickupWindowHours?.toString() ?? '';
      _lowStockT.text = p.lowStockThreshold.toString();
      _boxPriceCtrl.text = p.packCost?.toString() ?? '';
      _itemsPerBoxCtrl.text = p.itemsPerCase?.toString() ?? '';
      _bulkUnitCtrl.text = p.bulkUnit;

      if (p.hasBulkPacking && p.stock > 0) {
        final b = p.stock ~/ p.piecesPerPack;
        final r = p.stock % p.piecesPerPack;
        _boxesReceivedCtrl.text = b > 0 ? b.toString() : '';
        _extraItemsCtrl.text = r > 0 ? r.toString() : '';
      } else {
        _boxesReceivedCtrl.clear();
        _extraItemsCtrl.clear();
      }

      _category = p.category;
      _perishable = p.isPerishable;
      _taxable = p.isTaxable;
      _status = p.status;
      _photoBase64 = p.photoBase64;
      _supplierId = p.supplierId;
      _expiryDate = p.expiryDate;
      _variants = List.from(p.variants);
    });
  }

  void _onBarcodeChanged() {
    if (_barcode.text.isEmpty && !_saving && mounted) {
      if (!_fBarcode.hasFocus) {
        _fBarcode.requestFocus();
      }
    }
  }

  void _onUomCalculationChanged() {
    if (_isCalculatingUom) return;
    _isCalculatingUom = true;

    final boxes = int.tryParse(_boxesReceivedCtrl.text) ?? 0;
    final itemsPerBox = int.tryParse(_itemsPerBoxCtrl.text) ?? 0;
    final extraItems = int.tryParse(_extraItemsCtrl.text) ?? 0;
    final boxPrice = double.tryParse(_boxPriceCtrl.text) ?? 0.0;

    if (itemsPerBox > 0) {
      _itemsPerCase.text = itemsPerBox.toString();
    }

    // 1. Calculate Initial Stock Quantity
    if (boxes > 0 && itemsPerBox > 0) {
      final calculatedStock = (boxes * itemsPerBox) + extraItems;
      _stock.text = calculatedStock.toString();
    } else if (extraItems > 0 && boxes == 0 && itemsPerBox == 0) {
      _stock.text = extraItems.toString();
    }

    // 2. Calculate Base Unit Cost (COGS) from Bulk Box Cost
    if (boxPrice > 0 && itemsPerBox > 0) {
      final unitCost = boxPrice / itemsPerBox;
      _costPrice.text = unitCost.toStringAsFixed(2);
      _autoCalculateSellingPrice();
    }

    _isCalculatingUom = false;
    if (mounted) setState(() {});
  }

  void _onUnitCostChanged() {
    if (_isCalculatingUom) return;
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

  void _onNameOrBrandChanged() {
    if (_parentIdCtrl.text.trim().isEmpty) {
      _autoGenerateParentGroupId();
    }
  }

  void _autoGenerateParentGroupId({bool force = false}) {
    if (_parentIdCtrl.text.trim().isNotEmpty && !force) return;

    final inventory = context.read<InventoryProvider>();
    final name = _name.text.trim();
    final brand = _brand.text.trim();

    if (name.isEmpty && brand.isEmpty) return;

    // 1. Check if an existing product in store shares the same brand
    if (brand.isNotEmpty) {
      try {
        final match = inventory.products.firstWhere(
          (p) =>
              p.brand?.toLowerCase() == brand.toLowerCase() &&
              p.parentId != null &&
              p.parentId!.trim().isNotEmpty,
        );
        if (match.parentId != null && match.parentId!.isNotEmpty) {
          _parentIdCtrl.text = match.parentId!;
          return;
        }
      } catch (_) {}
    }

    // 2. Derive a clean slugified group ID from Brand + Name Base
    final rawText = brand.isNotEmpty
        ? '$brand ${name.split(" ").take(2).join(" ")}'
        : name.split(" ").take(2).join(" ");

    final cleanSlug = rawText
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');

    if (cleanSlug.isNotEmpty) {
      _parentIdCtrl.text = 'GRP-$cleanSlug';
    }
  }

  String _getUomBreakdownText() {
    final boxes = int.tryParse(_boxesReceivedCtrl.text) ?? 0;
    final itemsBox = int.tryParse(_itemsPerBoxCtrl.text) ?? 0;
    final extra = int.tryParse(_extraItemsCtrl.text) ?? 0;
    final boxPrice = double.tryParse(_boxPriceCtrl.text) ?? 0.0;
    final bulkName =
        _bulkUnitCtrl.text.trim().isEmpty ? 'box' : _bulkUnitCtrl.text.trim();
    final unitName = _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim();

    if (boxes <= 0 && itemsBox <= 0 && extra <= 0 && boxPrice <= 0) return '';

    final total = (boxes * itemsBox) + extra;
    final unitCost =
        (boxPrice > 0 && itemsBox > 0) ? (boxPrice / itemsBox) : 0.0;

    if (boxes > 0 && itemsBox > 0) {
      final extraStr = extra > 0 ? ' + $extra extra $unitName' : '';
      final priceStr =
          boxPrice > 0 ? ' @ ${formatPeso(boxPrice)}/$bulkName' : '';
      final unitCostStr =
          unitCost > 0 ? ' (Unit Cost: ${formatPeso(unitCost)}/$unitName)' : '';
      return '$boxes $bulkName(s)$priceStr × $itemsBox $unitName/$bulkName$extraStr = $total $unitName total$unitCostStr';
    } else if (extra > 0) {
      return '$extra loose $unitName';
    }
    return '';
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
    _boxPriceCtrl.removeListener(_onUomCalculationChanged);
    _boxesReceivedCtrl.removeListener(_onUomCalculationChanged);
    _itemsPerBoxCtrl.removeListener(_onUomCalculationChanged);
    _extraItemsCtrl.removeListener(_onUomCalculationChanged);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inventory = context.watch<InventoryProvider>();
    final suppliers = inventory.suppliers;
    final allCats = {
      ..._defaultCategories,
      ...inventory.products.map((e) => e.category),
      if (_category.isNotEmpty) _category,
    }.toList()
      ..sort();

    final brandStyle = BrandStyling.getStyle(_brand.text, fontSize: 16);

    return BarcodeInterceptor(
      controllers: _focusMap,
      barcodeFocus: _fBarcode,
      nameFocus: _fName,
      onBarcodeDetected: (code) async {
        setState(() => _barcode.text = code);
        _fBarcode.requestFocus();
        await _handleBarcodeScan(code);
      },
      onTextDetected: (text) {
        setState(() => _name.text = text);
        if (_activeProduct == null && text.trim().isNotEmpty) {
          _checkExistingProductByName(text);
        }
      },
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: SingleChildScrollView(
            child: MaxWidthContainer(
              maxWidth: 620,
              alignment: Alignment.topCenter,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Drag Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Sheet Header
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _activeProduct == null
                                    ? 'Add New Product'
                                    : 'Edit Product',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                              ),
                              Text(
                                _activeProduct == null
                                    ? 'Create catalog entry and log initial stock'
                                    : 'Update product details, pricing, and UoM',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (_activeProduct == null) ...[
                          IconButton.filledTonal(
                            onPressed: _fullScan,
                            icon: const Icon(Icons.qr_code_scanner_rounded,
                                size: 18),
                            tooltip: 'Catalog Scan',
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 4),
                        ],
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: 'Close',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Photo & Barcode Header Card
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _pickImage,
                            child: Stack(
                              children: [
                                Container(
                                  width: 62,
                                  height: 62,
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _processingImage
                                      ? const Center(
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : (_localPhoto != null
                                          ? Image.file(_localPhoto!,
                                              fit: BoxFit.cover)
                                          : (_photoBase64 != null
                                              ? Image.memory(
                                                  base64Decode(_photoBase64!),
                                                  fit: BoxFit.cover)
                                              : Icon(
                                                  Icons.add_a_photo_outlined,
                                                  size: 24,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline,
                                                ))),
                                ),
                                if (!_processingImage)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.edit_rounded,
                                          size: 10, color: Colors.white),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _barcode,
                                    focusNode: _fBarcode,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[a-zA-Z0-9\-]')),
                                      LengthLimitingTextInputFormatter(50),
                                    ],
                                    onFieldSubmitted: (v) async {
                                      if (v.trim().isNotEmpty) {
                                        await _handleBarcodeScan(v);
                                      }
                                    },
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Barcode / PLU',
                                      hintText: 'Auto-generates if blank',
                                      prefixIcon: Icon(
                                          Icons.qr_code_scanner,
                                          size: 18),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton.filledTonal(
                                  onPressed: _scanBarcode,
                                  icon: const Icon(Icons.camera_alt_outlined,
                                      size: 18),
                                  tooltip: 'Scan Camera',
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton.filledTonal(
                                  onPressed: () {
                                    String code = _barcode.text.trim();
                                    if (code.isEmpty) {
                                      code =
                                          BarcodeGenerator.generateInternalBarcode();
                                      _barcode.text = code;
                                    }
                                    BarcodePrintDialog.showCustom(
                                      context,
                                      productName: _name.text,
                                      price:
                                          double.tryParse(_price.text) ?? 0,
                                      barcode: code,
                                    );
                                  },
                                  icon: const Icon(Icons.print_rounded,
                                      size: 18),
                                  tooltip: 'Print Label',
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── SECTION 1: PRODUCT IDENTITY ─────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.badge_outlined,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary),
                              const SizedBox(width: 8),
                              Text(
                                'PRODUCT IDENTITY',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Product Name
                          TextFormField(
                            controller: _name,
                            focusNode: _fName,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(100)
                            ],
                            onFieldSubmitted: (v) {
                              if (v.trim().isNotEmpty &&
                                  _activeProduct == null) {
                                _checkExistingProductByName(v);
                              }
                            },
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Product Name *',
                              hintText: 'e.g. Coca-Cola 1.5L',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Product Name is required.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),

                          // Brand & Category
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _brand,
                                  focusNode: _fBrand,
                                  style: brandStyle.copyWith(fontSize: 14),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Brand',
                                    hintText: 'e.g. Nestlé',
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: allCats.contains(_category)
                                      ? _category
                                      : (allCats.isNotEmpty
                                          ? allCats.first
                                          : null),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Category *',
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                  items: allCats
                                      .map((c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(c,
                                              overflow:
                                                  TextOverflow.ellipsis)))
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
                          const SizedBox(height: 10),

                          // Parent Group ID Dropdown Selector & Auto-Generation
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: inventory.uniqueParentIds
                                          .contains(_parentIdCtrl.text.trim())
                                      ? _parentIdCtrl.text.trim()
                                      : (_parentIdCtrl.text.trim().isNotEmpty
                                          ? _parentIdCtrl.text.trim()
                                          : null),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Parent Group ID (Variant Family)',
                                    prefixIcon: const Icon(
                                        Icons.account_tree_outlined,
                                        size: 18),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    suffixIcon: Tooltip(
                                      message: 'Auto-generate Group ID from Brand/Name',
                                      child: IconButton(
                                        icon: const Icon(Icons.auto_awesome_rounded,
                                            size: 16, color: Colors.purple),
                                        onPressed: () {
                                          setState(() {
                                            _autoGenerateParentGroupId(force: true);
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  hint: Text(
                                    _parentIdCtrl.text.isNotEmpty
                                        ? _parentIdCtrl.text
                                        : 'Select existing or auto-generate...',
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  items: [
                                    if (_parentIdCtrl.text.trim().isNotEmpty &&
                                        !inventory.uniqueParentIds
                                            .contains(_parentIdCtrl.text.trim()))
                                      DropdownMenuItem<String>(
                                        value: _parentIdCtrl.text.trim(),
                                        child: Text(
                                          '✨ Auto/Current: ${_parentIdCtrl.text.trim()}',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple),
                                        ),
                                      ),
                                    ...inventory.uniqueParentIds.map(
                                      (pId) => DropdownMenuItem<String>(
                                        value: pId,
                                        child: Text(
                                          '📦 $pId',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _parentIdCtrl.text = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _parentIdCtrl,
                            focusNode: _fParentId,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-zA-Z0-9\-_]')),
                              LengthLimitingTextInputFormatter(60),
                            ],
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Custom Group ID Slug (Optional)',
                              hintText: 'e.g. GRP-PALMOLIVE-SHAMPOO',
                              prefixIcon:
                                  Icon(Icons.edit_outlined, size: 16),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── SECTION 2: UOM & INVENTORY ──────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.widgets_outlined,
                                  size: 18,
                                  color: isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade800),
                              const SizedBox(width: 8),
                              Text(
                                'UOM & INVENTORY LOG',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                  color: isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // UoM Units
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _bulkUnitCtrl,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Bulk Unit Name',
                                    hintText: 'e.g. box, tie, case',
                                    prefixIcon: Icon(
                                        Icons.inventory_2_outlined,
                                        size: 18),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _unit,
                                  focusNode: _fUnit,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Base Unit Name *',
                                    hintText: 'e.g. pcs, bottle',
                                    prefixIcon: Icon(Icons.label_outlined,
                                        size: 18),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Enter base unit';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Bulk Presets
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                const Text('Presets: ',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold)),
                                ...[
                                  'box',
                                  'case',
                                  'bundle',
                                  'tie',
                                  'pack',
                                  'sack',
                                  'tray'
                                ].map((preset) => Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: InkWell(
                                        onTap: () => setState(
                                            () => _bulkUnitCtrl.text = preset),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                                color: Colors.teal.shade200),
                                          ),
                                          child: Text(preset,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.teal.shade900,
                                                  fontWeight:
                                                      FontWeight.bold)),
                                        ),
                                      ),
                                    )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // UoM Breakdown Calculator Card
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.green.shade900
                                      .withValues(alpha: 0.25)
                                  : Colors.green.shade50
                                      .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isDark
                                      ? Colors.green.shade800
                                      : Colors.green.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.auto_awesome_rounded,
                                        size: 16,
                                        color: isDark
                                            ? Colors.green.shade300
                                            : Colors.green.shade900),
                                    const SizedBox(width: 6),
                                    Text(
                                      'UoM Package Breakdown',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.green.shade300
                                            : Colors.green.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                // Row 1: Cost per Box & Boxes Received
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _boxPriceCtrl,
                                        focusNode: _fBoxPrice,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(r'^\d*\.?\d*'))
                                        ],
                                        decoration: InputDecoration(
                                          isDense: true,
                                          labelText: 'Cost per Box',
                                          prefixText: '₱ ',
                                          hintText: 'e.g. 720.00',
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .surface,
                                          filled: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _boxesReceivedCtrl,
                                        focusNode: _fBoxesReceived,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly
                                        ],
                                        decoration: InputDecoration(
                                          isDense: true,
                                          labelText: 'Boxes Received',
                                          hintText: 'e.g. 2',
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .surface,
                                          filled: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Row 2: Items per Box & Extra Loose Items
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _itemsPerBoxCtrl,
                                        focusNode: _fItemsPerBox,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly
                                        ],
                                        decoration: InputDecoration(
                                          isDense: true,
                                          labelText: 'Items per Box',
                                          hintText: 'e.g. 24',
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .surface,
                                          filled: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _extraItemsCtrl,
                                        focusNode: _fExtraItems,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly
                                        ],
                                        decoration: InputDecoration(
                                          isDense: true,
                                          labelText: 'Extra Loose Items',
                                          hintText: 'e.g. 2',
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .surface,
                                          filled: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                if (_getUomBreakdownText().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.green.shade900
                                              .withValues(alpha: 0.4)
                                          : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _getUomBreakdownText(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.green.shade200
                                            : Colors.green.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Selling Price & Unit Cost (Auto-populated from UoM)
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _price,
                                  focusNode: _fPrice,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d*'))
                                  ],
                                  onChanged: (_) {
                                    if (!_isCalculatingPrice) {
                                      setState(
                                          () => _isManualPriceOverride = true);
                                    }
                                  },
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Selling Price *',
                                    prefixText: '₱ ',
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                    suffixIcon: Tooltip(
                                      message:
                                          'Auto-calculate from ${(CategoryMarkupRules.getMarginForCategory(_category) * 100).toInt()}% margin',
                                      child: IconButton(
                                        icon: Icon(
                                          _isManualPriceOverride
                                              ? Icons.lock_outline_rounded
                                              : Icons.auto_awesome_rounded,
                                          size: 16,
                                          color: _isManualPriceOverride
                                              ? Colors.orange
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                        ),
                                        onPressed: () {
                                          setState(() =>
                                              _isManualPriceOverride = false);
                                          _autoCalculateSellingPrice();
                                        },
                                      ),
                                    ),
                                  ),
                                  validator: (v) {
                                    final p = double.tryParse(v ?? '');
                                    if (p == null || p <= 0) {
                                      return 'Required.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (context.watch<AppAuthProvider>().role ==
                                  UserRole.admin)
                                Expanded(
                                  child: TextFormField(
                                    controller: _costPrice,
                                    focusNode: _fCostPrice,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*'))
                                    ],
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Unit Cost *',
                                      prefixText: '₱ ',
                                      hintText: 'e.g. 30.00',
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                    ),
                                    validator: (v) {
                                      final c = double.tryParse(v ?? '');
                                      if (c == null || c <= 0) {
                                        return 'Required';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Initial Quantity (Base Units)
                          TextFormField(
                            controller: _stock,
                            focusNode: _fStock,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: InputDecoration(
                              isDense: true,
                              labelText:
                                  'Total Initial Quantity (${_unit.text.isEmpty ? 'pcs' : _unit.text}) *',
                              hintText: 'e.g. 50',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            validator: (v) {
                              final q = int.tryParse(v ?? '');
                              if (q == null || q < 0) {
                                return 'Enter valid quantity';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),

                          // Batch Expiry Date Selector
                          InkWell(
                            onTap: _pickExpiryDate,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _expiryDate == null
                                      ? (isDark
                                          ? Colors.red.shade700
                                          : Colors.red.shade300)
                                      : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.event_available_outlined,
                                    size: 18,
                                    color: _expiryDate == null
                                        ? (isDark
                                            ? Colors.red.shade300
                                            : Colors.red)
                                        : Theme.of(context)
                                            .colorScheme
                                            .primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _expiryDate == null
                                          ? 'Batch Expiry Date * (Mandatory)'
                                          : 'Expiry: ${DateFormat('MMMM dd, yyyy').format(_expiryDate!)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: _expiryDate == null
                                            ? FontWeight.w600
                                            : FontWeight.bold,
                                        color: _expiryDate == null
                                            ? (isDark
                                                ? Colors.red.shade300
                                                : Colors.red)
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                      ),
                                    ),
                                  ),
                                  if (_expiryDate != null)
                                    GestureDetector(
                                      onTap: () => setState(
                                          () => _expiryDate = null),
                                      child: const Icon(Icons.clear, size: 16),
                                    )
                                  else
                                    const Icon(Icons.chevron_right, size: 18),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Safety Stock & Supplier
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _lowStockT,
                                  focusNode: _fLowStockT,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Safety Stock',
                                    hintText: 'e.g. 5',
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  isExpanded: true,
                                  value: suppliers.any((s) => s.id == _supplierId)
                                      ? _supplierId
                                      : null,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Supplier',
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('None / Direct')),
                                    ...suppliers.map((s) =>
                                        DropdownMenuItem<String?>(
                                            value: s.id,
                                            child: Text(s.name,
                                                overflow:
                                                    TextOverflow.ellipsis))),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _supplierId = v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Invoice Notes
                          TextFormField(
                            controller: _notesCtrl,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Invoice / Delivery Notes (Optional)',
                              hintText: 'e.g. Inv #10492 — Direct Delivery',
                              prefixIcon: Icon(
                                  Icons.receipt_long_outlined,
                                  size: 18),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Submit & Action Buttons
                    Row(
                      children: [
                        if (_activeProduct != null) ...[
                          IconButton.outlined(
                            onPressed: () => _confirmDelete(context),
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            tooltip: 'Delete Product',
                            style: IconButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _saveProductForm,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded, size: 20),
                              label: Text(
                                _saving
                                    ? 'Saving Profile...'
                                    : (_activeProduct == null
                                        ? 'SAVE & LOG STOCK'
                                        : 'SAVE CHANGES'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: GdcColors.primaryGreen,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
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
      final inventory = context.read<InventoryProvider>();

      if (result.barcode != null && result.barcode!.isNotEmpty) {
        final match = inventory.products
            .where((p) => p.barcode == result.barcode!.trim())
            .firstOrNull;
        if (match != null && match.id != _activeProduct?.id) {
          _showProductAlreadyExistsDialog(match);
          return;
        }
      }

      if (result.name != null && result.name!.isNotEmpty) {
        final match = inventory.products
            .where((p) =>
                p.name.trim().toLowerCase() ==
                result.name!.trim().toLowerCase())
            .firstOrNull;
        if (match != null && match.id != _activeProduct?.id) {
          _showProductAlreadyExistsDialog(match);
          return;
        }
      }

      setState(() {
        if (result.name != null && result.name!.isNotEmpty)
          _name.text = result.name!;
        if (result.brand != null && result.brand!.isNotEmpty)
          _brand.text = result.brand!;
        if (result.category != null && result.category!.isNotEmpty)
          _category = result.category!;
        if (result.barcode != null && result.barcode!.isNotEmpty)
          _barcode.text = result.barcode!;
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
      _fBarcode.requestFocus();
      await _handleBarcodeScan(result);
    }
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return;

    final inventory = context.read<InventoryProvider>();

    // 1. Search Local Store Products
    final localMatch =
        inventory.products.where((p) => p.barcode == cleanBarcode).toList();
    if (localMatch.isNotEmpty) {
      final existingProduct = localMatch.first;
      if (_activeProduct?.id != existingProduct.id) {
        _showProductAlreadyExistsDialog(existingProduct);
        return;
      }
    }

    // 2. Search Local Catalog
    final catalogMatch =
        inventory.catalog.where((cp) => cp.barcode == cleanBarcode).toList();
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
        _autoGenerateParentGroupId();
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
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
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
        _autoGenerateParentGroupId();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Auto-filled "${extInfo.name}" from ${extInfo.source}! 🌐'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'New barcode ($cleanBarcode)! Please enter product details manually.'),
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
        content: Text(
            'Are you sure you want to remove "${_activeProduct?.name}" from your inventory? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (_activeProduct != null) {
                await context
                    .read<InventoryProvider>()
                    .deleteProduct(_activeProduct!.id);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProductForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Mandatory Expiration Date Check to prevent chaotic inventory tracking
    if (_expiryDate == null) {
      showDialog(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text('Expiration Date Required',
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: const Text(
            'To prevent inventory chaos and ensure accurate stock tracking, an Expiration Date is mandatory for all products and batches.\n\nPlease select a batch expiration date.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _pickExpiryDate();
              },
              child: const Text('Select Date'),
            ),
          ],
        ),
      );
      return;
    }

    final name = _name.text.trim().capitalize();
    String barcode = _barcode.text.trim();
    final price = double.tryParse(_price.text) ?? 0;
    final costPrice = double.tryParse(_costPrice.text) ?? 0;
    final initialQty = int.tryParse(_stock.text) ?? 0;
    final category = _category;
    final unit = _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim();
    final bulkUnit =
        _bulkUnitCtrl.text.trim().isEmpty ? 'box' : _bulkUnitCtrl.text.trim();

    final inventoryProvider = context.read<InventoryProvider>();
    final authProvider = context.read<AppAuthProvider>();

    // Safety check for existing product detection when adding a new product
    if (_activeProduct == null) {
      if (barcode.isNotEmpty) {
        final existingByBarcode = inventoryProvider.products
            .where((p) => p.barcode == barcode)
            .firstOrNull;
        if (existingByBarcode != null) {
          _showProductAlreadyExistsDialog(existingByBarcode);
          return;
        }
      }
      final existingByName = inventoryProvider.products
          .where(
              (p) => p.name.trim().toLowerCase() == name.trim().toLowerCase())
          .firstOrNull;
      if (existingByName != null) {
        _showProductAlreadyExistsDialog(existingByName);
        return;
      }
    } else {
      // Duplicate Barcode Check for existing product edit
      if (barcode.isNotEmpty) {
        final exists = inventoryProvider.products
            .any((p) => p.barcode == barcode && p.id != _activeProduct?.id);
        if (exists) {
          showDialog(
            context: context,
            useRootNavigator: true,
            builder: (ctx) => AlertDialog(
              title: const Text('Duplicate Barcode'),
              content: const Text(
                  'This barcode is already assigned to another item. Please use a unique barcode.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'))
              ],
            ),
          );
          return;
        }
      }
    }

    // Auto-generate internal 12-digit PLU barcode starting with '200' if left empty
    if (barcode.isEmpty) {
      barcode = BarcodeGenerator.generateInternalBarcode();
    }

    setState(() => _saving = true);

    try {
      // 1. Save or Update Catalog Entry
      final catalogMatch = inventoryProvider.catalog
          .where((cp) => cp.barcode == barcode)
          .toList();
      if (catalogMatch.isEmpty) {
        await inventoryProvider.saveCatalogProduct(CatalogProduct(
          id: '',
          name: name,
          brand: _brand.text.trim().isEmpty
              ? null
              : _brand.text.trim().capitalize(),
          category: category,
          barcode: barcode,
          photoBase64: _photoBase64,
        ));
      }

      final int? prevInitial = _activeProduct?.initialStock;
      final int calculatedInitial = (_activeProduct == null)
          ? initialQty
          : (initialQty > (prevInitial ?? _activeProduct?.stock ?? 0)
              ? initialQty
              : (prevInitial ?? initialQty));

      final itemsPerCaseVal = int.tryParse(_itemsPerBoxCtrl.text) ??
          int.tryParse(_itemsPerCase.text);
      final packCostVal = double.tryParse(_boxPriceCtrl.text);

      // Construct Main Product Model
      final p = Product(
        id: _activeProduct?.id ?? '',
        name: name,
        brand:
            _brand.text.trim().isEmpty ? null : _brand.text.trim().capitalize(),
        parentId: _parentIdCtrl.text.trim().isEmpty
            ? null
            : _parentIdCtrl.text.trim(),
        category: category,
        price: price,
        costPrice: costPrice,
        stock: initialQty,
        initialStock: calculatedInitial,
        unit: unit,
        bulkUnit: bulkUnit,
        packCost: packCostVal,
        itemsPerCase: itemsPerCaseVal,
        barcode: barcode,
        shelfDays: _perishable ? int.tryParse(_shelf.text) : null,
        pickupWindowHours:
            _perishable ? int.tryParse(_pickupWindow.text) : null,
        lowStockThreshold: int.tryParse(_lowStockT.text) ?? 5,
        isTaxable: _taxable,
        status: _status,
        photoBase64: _photoBase64,
        supplierId: _supplierId,
        expiryDate: _expiryDate,
        variants: _variants,
        batches: _activeProduct?.batches ?? const [],
      );

      // Construct ProductBatch Model
      final initialBatch = ProductBatch(
        id: const Uuid().v4(),
        productId: p.id,
        quantity: initialQty,
        unitCost: costPrice,
        expiryDate: _expiryDate,
        createdAt: DateTime.now(),
        invoiceNumber:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      // Build detailed inventory history log notes
      final boxes = int.tryParse(_boxesReceivedCtrl.text) ?? 0;
      final itemsBox = int.tryParse(_itemsPerBoxCtrl.text) ?? 0;
      final extra = int.tryParse(_extraItemsCtrl.text) ?? 0;
      final boxPrice = double.tryParse(_boxPriceCtrl.text) ?? 0.0;

      String historyNotes;
      if (boxes > 0 && itemsBox > 0) {
        final extraStr = extra > 0 ? ' + $extra extra $unit' : '';
        final costStr =
            boxPrice > 0 ? ' @ ${formatPeso(boxPrice)}/$bulkUnit' : '';
        historyNotes =
            'Initial UoM Received: $boxes $bulkUnit(s)$costStr ($itemsBox $unit/$bulkUnit)$extraStr = $initialQty $unit total (Unit Cost: ${formatPeso(costPrice)}/$unit).';
      } else {
        historyNotes =
            'Initial Stock Entry: $initialQty $unit @ ${formatPeso(costPrice)}/$unit.';
      }

      if (_notesCtrl.text.trim().isNotEmpty) {
        historyNotes += ' Invoice/Notes: ${_notesCtrl.text.trim()}';
      }

      final currentUser = authProvider.currentUser;
      final receivedBy =
          currentUser?.email ?? currentUser?.displayName ?? 'Admin';

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      // Save product & write straight to inventory history (delivery_logs)
      await inventoryProvider.saveProductWithBatch(
        product: p,
        initialBatch: initialBatch,
        receivedBy: receivedBy,
        notes: historyNotes,
      );

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'Saved "$name" ($initialQty $unit) straight to Inventory History! ✅'),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Error saving product profile & inventory history: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
