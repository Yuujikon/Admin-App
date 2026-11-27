import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
import '../utils/inventory_allocation.dart';
import 'scanner_dialog.dart';
import 'full_product_scanner_dialog.dart';
import 'receive_delivery_sheet.dart';
import 'barcode_print_dialog.dart';
import 'premium_components.dart';
import '../config/theme.dart';
import '../services/external_barcode_service.dart';
import '../services/inventory_batch_service.dart';
import '../utils/barcode_generator.dart';
import 'action_warning_dialog.dart';
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

  /// Standard launcher for [ProductEditSheet] as a bottom sheet with gesture safety & scroll control.
  static Future<T?> show<T>({
    required BuildContext context,
    Product? product,
    String? initialBarcode,
    String? initialSupplierId,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductEditSheet(
        product: product,
        initialBarcode: initialBarcode,
        initialSupplierId: initialSupplierId,
      ),
    );
  }

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
  late final TextEditingController _boxPriceCtrl;
  late final TextEditingController _itemsPerBoxCtrl;
  late final TextEditingController _boxesReceivedCtrl;
  late final TextEditingController _extraItemsCtrl;
  late final TextEditingController _bulkUnitCtrl;
  late final TextEditingController _manualMarkupCtrl;
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
  late final FocusNode _fBoxPrice;
  late final FocusNode _fItemsPerBox;
  late final FocusNode _fBoxesReceived;
  late final FocusNode _fExtraItems;
  late final FocusNode _fManualMarkup;

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

  // Section Expansion States for Progressive Disclosure
  bool _showBulkUom = false;
  bool _showVariantFamily = false;
  bool _showSupplierAlerts = false;
  bool _showPerishableDetails = false;

  // Dynamic Velocity-Based Markup & Bulk Cost Calculator State
  String _pricingMode = Product.pricingModeAuto;
  double _salesVelocityScore = 0.5;
  bool _isCalculatingPrice = false;
  bool _isCalculatingUom = false;

  File? _localPhoto;
  String? _photoBase64;
  DateTime? _expiryDate;
  DateTime _datePurchased = DateTime.now();
  DateTime _dateArrived = DateTime.now();
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
    final int initialDisplayStock = p?.totalStock ?? 0;
    if (p != null && initialDisplayStock > 0 && p.hasBulkPacking) {
      initBoxes = initialDisplayStock ~/ p.piecesPerPack;
      initExtra = initialDisplayStock % p.piecesPerPack;
    }

    _name = TextEditingController(text: p?.name ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _parentIdCtrl = TextEditingController(text: p?.parentId ?? '');
    _price = TextEditingController(text: p?.price.toString() ?? '');
    _costPrice = TextEditingController(text: p?.costPrice.toString() ?? '0');
    _stock =
        TextEditingController(text: p != null ? p.totalStock.toString() : '');
    _unit = TextEditingController(text: p?.unit ?? 'pcs');
    _shelf = TextEditingController(text: p?.shelfDays?.toString() ?? '');
    _barcode =
        TextEditingController(text: p?.barcode ?? widget.initialBarcode ?? '');
    _itemsPerCase =
        TextEditingController(text: p?.itemsPerCase?.toString() ?? '');
    _pickupWindow =
        TextEditingController(text: p?.pickupWindowHours?.toString() ?? '');
    _boxPriceCtrl = TextEditingController(text: p?.packCost?.toString() ?? '');
    _itemsPerBoxCtrl =
        TextEditingController(text: p?.itemsPerCase?.toString() ?? '');
    _boxesReceivedCtrl = TextEditingController(
        text: initBoxes != null && initBoxes > 0 ? initBoxes.toString() : '');
    _extraItemsCtrl = TextEditingController(
        text: initExtra != null && initExtra > 0 ? initExtra.toString() : '');
    _bulkUnitCtrl = TextEditingController(text: p?.bulkUnit ?? 'box');
    _manualMarkupCtrl = TextEditingController(
        text: p?.manualMarkupPercent != null
            ? p!.manualMarkupPercent!.toStringAsFixed(2)
            : '');

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
    _fBoxPrice = FocusNode();
    _fItemsPerBox = FocusNode();
    _fBoxesReceived = FocusNode();
    _fExtraItems = FocusNode();
    _fManualMarkup = FocusNode();

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
      _boxPriceCtrl,
      _itemsPerBoxCtrl,
      _boxesReceivedCtrl,
      _extraItemsCtrl,
      _bulkUnitCtrl,
      _manualMarkupCtrl,
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
      _fBoxPrice,
      _fItemsPerBox,
      _fBoxesReceived,
      _fExtraItems,
      _fManualMarkup,
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
      _fBoxPrice: _boxPriceCtrl,
      _fItemsPerBox: _itemsPerBoxCtrl,
      _fBoxesReceived: _boxesReceivedCtrl,
      _fExtraItems: _extraItemsCtrl,
      _fManualMarkup: _manualMarkupCtrl,
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

    // Initialize Dynamic Velocity-Based Markup state
    _pricingMode = p?.pricingMode ?? Product.pricingModeAuto;
    _salesVelocityScore = p != null ? inventory.getLiveVelocityScore(p) : 0.5;
    if (p != null &&
        _pricingMode == Product.pricingModeManual &&
        _manualMarkupCtrl.text.isEmpty &&
        p.price > 0 &&
        p.activeFifoUnitCost > 0) {
      final rev = PricingEngine.reverseCalculateMarkupPercent(
        sellingPrice: p.price,
        unitCost: p.activeFifoUnitCost,
      );
      if (rev != null) {
        _manualMarkupCtrl.text = rev.toStringAsFixed(2);
      }
    }

    // Auto-expand optional panels if product already has bulk data, parent ID, or supplier info
    _showBulkUom = p?.hasBulkPacking == true ||
        (initBoxes != null && initBoxes > 0) ||
        (p?.packCost != null && p!.packCost! > 0);
    _showVariantFamily = p?.parentId != null && p!.parentId!.isNotEmpty;
    _showSupplierAlerts = p?.supplierId != null && p!.supplierId!.isNotEmpty;
    _showPerishableDetails = _perishable || p?.shelfDays != null;

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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
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
                  ReceiveDeliverySheet.show(
                    context: parentCtx,
                    initialProduct: existingProduct,
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
      final int liveStock = p.totalStock;
      _stock.text = liveStock.toString();
      _unit.text = p.unit;
      _shelf.text = p.shelfDays?.toString() ?? '';
      _barcode.text = p.barcode ?? '';
      _itemsPerCase.text = p.itemsPerCase?.toString() ?? '';
      _pickupWindow.text = p.pickupWindowHours?.toString() ?? '';
      _boxPriceCtrl.text = p.packCost?.toString() ?? '';
      _itemsPerBoxCtrl.text = p.itemsPerCase?.toString() ?? '';
      _bulkUnitCtrl.text = p.bulkUnit;

      if (p.hasBulkPacking && liveStock > 0) {
        final b = liveStock ~/ p.piecesPerPack;
        final r = liveStock % p.piecesPerPack;
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

      _pricingMode = p.pricingMode;
      _salesVelocityScore =
          context.read<InventoryProvider>().getLiveVelocityScore(p);
      if (p.manualMarkupPercent != null) {
        _manualMarkupCtrl.text = p.manualMarkupPercent!.toStringAsFixed(2);
      } else if (p.isManualPricing && p.price > 0 && p.activeFifoUnitCost > 0) {
        final rev = PricingEngine.reverseCalculateMarkupPercent(
          sellingPrice: p.price,
          unitCost: p.activeFifoUnitCost,
        );
        _manualMarkupCtrl.text = rev != null ? rev.toStringAsFixed(2) : '';
      } else {
        _manualMarkupCtrl.clear();
      }

      _showBulkUom =
          p.hasBulkPacking || (p.packCost != null && p.packCost! > 0);
      _showVariantFamily = p.parentId != null && p.parentId!.isNotEmpty;
      _showSupplierAlerts = p.supplierId != null && p.supplierId!.isNotEmpty;
      _showPerishableDetails = p.isPerishable || p.shelfDays != null;
    });
  }

  void _onBarcodeChanged() {
    if (_barcode.text.isEmpty && !_saving && mounted) {
      if (!_fBarcode.hasFocus) {
        _fBarcode.requestFocus();
      }
    }
  }

  double _resolveActiveUnitCost() {
    final boxPrice = double.tryParse(_boxPriceCtrl.text) ?? 0.0;
    final itemsPerBox = int.tryParse(_itemsPerBoxCtrl.text) ?? 0;
    if (boxPrice > 0 && itemsPerBox > 0) {
      return double.parse((boxPrice / itemsPerBox).toStringAsFixed(2));
    }
    final enteredCost = double.tryParse(_costPrice.text) ?? 0.0;
    if (enteredCost > 0 && enteredCost.isFinite) {
      return enteredCost;
    }
    final activeBatchCost = _activeProduct?.activeFifoUnitCost ?? 0.0;
    return activeBatchCost > 0 ? activeBatchCost : 0.0;
  }

  ItemPricingResult _evaluateCurrentPricing() {
    final settings = context.read<InventoryProvider>().settings;
    final double unitCost = _resolveActiveUnitCost();
    final double? manualPct = double.tryParse(_manualMarkupCtrl.text.trim());
    final candidate = Product(
      id: _activeProduct?.id ?? '',
      name: _name.text.trim(),
      category: _category,
      price: double.tryParse(_price.text) ?? 0.0,
      costPrice: unitCost,
      stock: int.tryParse(_stock.text) ?? 0,
      pricingMode: _pricingMode,
      manualMarkupPercent:
          _pricingMode == Product.pricingModeManual ? manualPct : null,
      salesVelocityScore: _salesVelocityScore,
      batches: _activeProduct?.batches ?? const [],
    );
    return PricingEngine.evaluateProductPricing(
      candidate,
      unitCostOverride: unitCost,
      settings: settings,
    );
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

    // 1. Calculate Initial Stock Quantity (only for newly created products;
    // existing non-variant product stock is managed via atomic FIFO batches).
    if (_activeProduct == null) {
      if (boxes > 0 && itemsPerBox > 0) {
        final calculatedStock = (boxes * itemsPerBox) + extraItems;
        _stock.text = calculatedStock.toString();
      } else if (extraItems > 0 && boxes == 0 && itemsPerBox == 0) {
        _stock.text = extraItems.toString();
      }
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
    if (_pricingMode == Product.pricingModeAuto) {
      _autoCalculateSellingPrice();
    } else {
      final manualPct = double.tryParse(_manualMarkupCtrl.text.trim());
      final unitCost = _resolveActiveUnitCost();
      if (manualPct != null && manualPct.isFinite && unitCost > 0) {
        _isCalculatingPrice = true;
        final settings = context.read<InventoryProvider>().settings;
        final computed = PricingEngine.calculateFinalSellingPrice(
          unitCost: unitCost,
          markupPercent: manualPct,
          roundingStep: settings.priceRoundingStep,
        );
        _price.text = computed.toStringAsFixed(2);
        _isCalculatingPrice = false;
      }
    }
    if (mounted) setState(() {});
  }

  void _autoCalculateSellingPrice() {
    if (_isCalculatingPrice || _pricingMode != Product.pricingModeAuto) return;
    final eval = _evaluateCurrentPricing();
    if (!eval.hasInvalidCost && eval.finalSellingPrice > 0) {
      _isCalculatingPrice = true;
      _price.text = eval.finalSellingPrice.toStringAsFixed(2);
      _isCalculatingPrice = false;
    }
  }

  void _setPricingMode(String mode) {
    if (_pricingMode == mode) return;
    setState(() {
      _pricingMode = mode;
      if (mode == Product.pricingModeManual) {
        if (_manualMarkupCtrl.text.trim().isEmpty) {
          final unitCost = _resolveActiveUnitCost();
          final currentPrice = double.tryParse(_price.text.trim()) ?? 0.0;
          final reversed = (currentPrice > 0 && unitCost > 0)
              ? PricingEngine.reverseCalculateMarkupPercent(
                  sellingPrice: currentPrice,
                  unitCost: unitCost,
                )
              : null;
          if (reversed != null) {
            _manualMarkupCtrl.text = reversed.toStringAsFixed(2);
          } else {
            final eval = _evaluateCurrentPricing();
            _manualMarkupCtrl.text =
                eval.computedMarkupPercent.toStringAsFixed(2);
          }
        }
      } else {
        _autoCalculateSellingPrice();
      }
    });
  }

  void _onManualMarkupChanged(String value) {
    if (_isCalculatingPrice) return;
    final markupPct = double.tryParse(value.trim());
    final unitCost = _resolveActiveUnitCost();
    if (markupPct != null && markupPct.isFinite && unitCost > 0) {
      final settings = context.read<InventoryProvider>().settings;
      final newPrice = PricingEngine.calculateFinalSellingPrice(
        unitCost: unitCost,
        markupPercent: markupPct,
        roundingStep: settings.priceRoundingStep,
      );
      _isCalculatingPrice = true;
      _price.text = newPrice.toStringAsFixed(2);
      _isCalculatingPrice = false;
    }
    if (mounted) setState(() {});
  }

  void _onDirectSellingPriceChanged(String value) {
    if (_isCalculatingPrice) return;
    final sellingPrice = double.tryParse(value.trim());
    final unitCost = _resolveActiveUnitCost();
    setState(() {
      _pricingMode = Product.pricingModeManual;
      if (sellingPrice != null && sellingPrice.isFinite && unitCost > 0) {
        final reversed = PricingEngine.reverseCalculateMarkupPercent(
          sellingPrice: sellingPrice,
          unitCost: unitCost,
        );
        if (reversed != null) {
          _isCalculatingPrice = true;
          _manualMarkupCtrl.text = reversed.toStringAsFixed(2);
          _isCalculatingPrice = false;
        }
      }
    });
  }

  Widget _buildDynamicMarkupSection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final eval = _evaluateCurrentPricing();
    final bool isAuto = _pricingMode == Product.pricingModeAuto;
    final ProductBatch? activeBatch = _activeProduct?.activeFifoBatch;

    final Color speedColor = switch (eval.speedTag) {
      'Fast Moving' => Colors.green.shade700,
      'Slow Moving' => Colors.orange.shade800,
      _ => Colors.blue.shade700,
    };

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isAuto ? Icons.auto_awesome_rounded : Icons.tune_rounded,
                size: 16,
                color: isAuto ? cs.primary : Colors.deepOrange.shade700,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Dynamic Markup & Pricing Mode',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isAuto ? cs.primary : Colors.deepOrange)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAuto ? 'AUTO' : 'ADMIN OVERRIDE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isAuto ? cs.primary : Colors.deepOrange.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Mode Toggle: Auto-Scale Markup vs Custom Admin Markup
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: Product.pricingModeAuto,
                icon: Icon(Icons.auto_graph_rounded, size: 15),
                label: Text(
                  'Auto-Scale Markup\n(Category & Speed)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, height: 1.15),
                ),
              ),
              ButtonSegment<String>(
                value: Product.pricingModeManual,
                icon: Icon(Icons.lock_outline_rounded, size: 15),
                label: Text(
                  'Custom Admin\nMarkup',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, height: 1.15),
                ),
              ),
            ],
            selected: {_pricingMode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                _setPricingMode(selection.first);
              }
            },
          ),

          // Zero-Cost / Missing-Cost Warning Banner
          if (eval.hasInvalidCost) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade500.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade600, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      eval.warningMessage ??
                          'Missing or zero unit cost. Markup calculation skipped to prevent invalid pricing.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade800,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (isAuto) ...[
            const SizedBox(height: 10),
            // Read-Only Auto-Scale Preview Badge
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: speedColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.speed_rounded,
                                size: 13, color: speedColor),
                            const SizedBox(width: 4),
                            Text(
                              '${eval.speedTag} (${eval.velocityScore.toStringAsFixed(2)})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: speedColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          eval.usedGlobalBenchmarkOnly
                              ? 'Global Benchmark: 15.0% – 25.0%'
                              : '${eval.categoryRange.canonicalCategory}: ${eval.categoryRange.formattedRange}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _pricingPreviewMetric(
                          context,
                          label: 'Computed Markup',
                          value:
                              '${eval.computedMarkupPercent.toStringAsFixed(1)}%',
                          valueColor: cs.primary,
                        ),
                      ),
                      Expanded(
                        child: _pricingPreviewMetric(
                          context,
                          label: activeBatch != null
                              ? 'Active FIFO Cost'
                              : 'Unit Cost',
                          value: eval.hasInvalidCost
                              ? 'Missing'
                              : formatPeso(eval.unitCost),
                          valueColor: eval.hasInvalidCost
                              ? Colors.red.shade700
                              : cs.onSurface,
                        ),
                      ),
                      Expanded(
                        child: _pricingPreviewMetric(
                          context,
                          label: 'Final Selling Price',
                          value: eval.hasInvalidCost
                              ? '—'
                              : formatPeso(eval.finalSellingPrice),
                          valueColor: Colors.green.shade700,
                          sublabel: eval.hasInvalidCost
                              ? null
                              : 'Step ${formatPeso(eval.roundingStep)}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manualMarkupCtrl,
                    focusNode: _fManualMarkup,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))
                    ],
                    onChanged: _onManualMarkupChanged,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Custom Markup %',
                      suffixText: '%',
                      hintText: 'e.g. 18.5',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    validator: (v) {
                      if (_pricingMode != Product.pricingModeManual) {
                        return null;
                      }
                      final m = double.tryParse(v?.trim() ?? '');
                      if (m == null || !m.isFinite) {
                        return 'Enter valid %';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    focusNode: _fPrice,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                    ],
                    onChanged: _onDirectSellingPriceChanged,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Selling Price Override *',
                      prefixText: '₱ ',
                      hintText: 'e.g. 35.00',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    validator: (v) {
                      if (_pricingMode != Product.pricingModeManual) {
                        return null;
                      }
                      final p = double.tryParse(v?.trim() ?? '');
                      if (p == null || p <= 0) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Locked manual override: background sales-speed syncs will not alter this markup. If a new FIFO batch activates with a different unit cost, selling price scales from this locked markup %.',
              style: TextStyle(
                fontSize: 10.5,
                color: cs.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pricingPreviewMetric(
    BuildContext context, {
    required String label,
    required String value,
    required Color valueColor,
    String? sublabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
        if (sublabel != null)
          Text(
            sublabel,
            style: TextStyle(
              fontSize: 9.5,
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildBelowCostWarningBanner() {
    final boxPrice = double.tryParse(_boxPriceCtrl.text) ?? 0.0;
    final itemsPerBox = int.tryParse(_itemsPerBoxCtrl.text) ?? 0;
    final costPrice = double.tryParse(_costPrice.text) ?? 0.0;
    final double calculatedUnitCost = (boxPrice > 0 && itemsPerBox > 0)
        ? (boxPrice / itemsPerBox)
        : costPrice;
    final double sellingPrice = double.tryParse(_price.text) ?? 0.0;

    if (sellingPrice <= 0 ||
        calculatedUnitCost <= 0 ||
        sellingPrice >= calculatedUnitCost) {
      return const SizedBox.shrink();
    }

    final double unitLoss = calculatedUnitCost - sellingPrice;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade500.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade700, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selling Price Below Calculated Cost',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Selling price (${formatPeso(sellingPrice)}) is below calculated unit cost (${formatPeso(calculatedUnitCost)}). Every unit sold will incur a loss of ${formatPeso(unitLoss)}.',
                  style: TextStyle(
                    color: Colors.amber.shade900,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  bool _hasUnsavedChanges() {
    if (_saving) return false;
    final p = _activeProduct;
    if (p == null) {
      return _name.text.trim().isNotEmpty ||
          _brand.text.trim().isNotEmpty ||
          _price.text.trim().isNotEmpty ||
          (_costPrice.text.trim().isNotEmpty &&
              _costPrice.text.trim() != '0') ||
          _stock.text.trim().isNotEmpty ||
          (_barcode.text.trim().isNotEmpty &&
              _barcode.text.trim() != (widget.initialBarcode ?? '')) ||
          _shelf.text.trim().isNotEmpty ||
          _itemsPerCase.text.trim().isNotEmpty ||
          _boxPriceCtrl.text.trim().isNotEmpty ||
          _boxesReceivedCtrl.text.trim().isNotEmpty ||
          _notesCtrl.text.trim().isNotEmpty ||
          _localPhoto != null;
    } else {
      return _name.text.trim() != p.name ||
          _brand.text.trim() != (p.brand ?? '') ||
          _price.text.trim() != p.price.toString() ||
          _costPrice.text.trim() != p.costPrice.toString() ||
          _stock.text.trim() != p.stock.toString() ||
          _unit.text.trim() != p.unit ||
          _barcode.text.trim() != (p.barcode ?? '') ||
          _notesCtrl.text.trim().isNotEmpty ||
          _localPhoto != null;
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasUnsavedChanges()) return true;

    final theme = Theme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.all(20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                color: theme.colorScheme.error,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Discard Unsaved Changes?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'You have unsaved information in this form. Are you sure you want to discard your changes and close?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        ),
        actions: [
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              foregroundColor: theme.colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard Changes',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _handleClose() async {
    final shouldPop = await _confirmDiscardChanges();
    if (shouldPop && mounted) {
      Navigator.of(context).pop();
    }
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
    final maxHeight = MediaQuery.of(context).size.height * 0.90;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscardChanges();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: BarcodeInterceptor(
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
            constraints: BoxConstraints(
              maxHeight: maxHeight,
            ),
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
                                      : 'Edit Product Profile',
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
                                      ? 'Fast product creation & initial stock logging'
                                      : 'Update pricing, UoM, and product info',
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
                              tooltip: 'Scan Catalog Barcode',
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 4),
                          ],
                          IconButton(
                            onPressed: _handleClose,
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
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLow,
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
                                            ? Padding(
                                                padding:
                                                    const EdgeInsets.all(2),
                                                child: Image.file(_localPhoto!,
                                                    fit: BoxFit.contain),
                                              )
                                            : (_photoBase64 != null
                                                ? Padding(
                                                    padding:
                                                        const EdgeInsets.all(2),
                                                    child: Image.memory(
                                                        base64Decode(
                                                            _photoBase64!),
                                                        fit: BoxFit.contain),
                                                  )
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
                                        prefixIcon: Icon(Icons.qr_code_scanner,
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
                                        code = BarcodeGenerator
                                            .generateInternalBarcode();
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

                      // ── ESSENTIAL SECTION 1: CORE PRODUCT DETAILS ──────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLow,
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
                                Icon(Icons.stars_rounded,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'ESSENTIAL PRODUCT DETAILS',
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
                                    initialValue: allCats.contains(_category)
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

                            // Unit & Stock Display (Read-Only)
                            Row(
                              children: [
                                Expanded(
                                  child:
                                      ValueListenableBuilder<TextEditingValue>(
                                    valueListenable: _stock,
                                    builder: (context, stockValue, _) {
                                      return ValueListenableBuilder<
                                          TextEditingValue>(
                                        valueListenable: _unit,
                                        builder: (context, unitValue, _) {
                                          final stockText =
                                              stockValue.text.isNotEmpty
                                                  ? stockValue.text
                                                  : "0";
                                          final unitText =
                                              unitValue.text.isNotEmpty
                                                  ? unitValue.text
                                                  : "pcs";
                                          return TextFormField(
                                            key: ValueKey(
                                                'stock_display_${stockText}_$unitText'),
                                            initialValue:
                                                '$stockText $unitText',
                                            readOnly: true,
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              labelText: 'Base Unit',
                                              prefixIcon: Icon(
                                                  Icons.inventory_2_outlined,
                                                  size: 18),
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _unit,
                                    focusNode: _fUnit,
                                    readOnly: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Net Content',
                                      prefixIcon:
                                          Icon(Icons.label_outlined, size: 18),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Required';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Unit Cost & Dynamic Velocity-Based Markup Controls
                            if (context.watch<AppAuthProvider>().role ==
                                UserRole.admin) ...[
                              TextFormField(
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
                                  labelText: 'Unit Cost (Base COGS) *',
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
                              _buildDynamicMarkupSection(context),
                            ] else if (_activeProduct != null) ...[
                              TextFormField(
                                controller: _price,
                                focusNode: _fPrice,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Selling Price',
                                  prefixText: '₱ ',
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                              ),
                            ],
                            _buildBelowCostWarningBanner(),
                            const SizedBox(height: 10),

                            // Initial Quantity (Base Units) — read-only on existing non-variant
                            // products because FIFO batches are the single source of truth for stock.
                            TextFormField(
                              controller: _stock,
                              focusNode: _fStock,
                              readOnly:
                                  _activeProduct != null && _variants.isEmpty,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: _activeProduct == null
                                    ? 'Initial Quantity (${_unit.text.isEmpty ? 'pcs' : _unit.text}) *'
                                    : 'Current Synced Stock (${_unit.text.isEmpty ? 'pcs' : _unit.text})',
                                hintText: 'e.g. 50',
                                helperText: _activeProduct != null &&
                                        _variants.isEmpty
                                    ? 'Derived from active FIFO batches. Use Receive Delivery or Shelf Audit to change stock.'
                                    : null,
                                helperMaxLines: 2,
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

                            if (_activeProduct == null) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: _datePurchased,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now()
                                              .add(const Duration(days: 365)),
                                        );
                                        if (picked != null && mounted) {
                                          setState(
                                              () => _datePurchased = picked);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surface,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outlineVariant,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Date Purchased',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              DateFormat('MMM dd, yyyy')
                                                  .format(_datePurchased),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: _dateArrived,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now()
                                              .add(const Duration(days: 365)),
                                        );
                                        if (picked != null && mounted) {
                                          setState(() => _dateArrived = picked);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.teal
                                              .withValues(alpha: 0.06),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: Colors.teal
                                                .withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Date Arrived (FIFO)',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.teal.shade800,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              DateFormat('MMM dd, yyyy')
                                                  .format(_dateArrived),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],

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
                                            ? 'Batch Expiry Date * (Tap to Set)'
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
                                        onTap: () =>
                                            setState(() => _expiryDate = null),
                                        child:
                                            const Icon(Icons.clear, size: 16),
                                      )
                                    else
                                      const Icon(Icons.chevron_right, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── COLLAPSIBLE SECTION A: BULK & UOM CALCULATOR ─────────
                      _buildCollapsibleCard(
                        title: 'Bulk & UoM Package Breakdown',
                        subtitle: _getUomBreakdownText().isNotEmpty
                            ? _getUomBreakdownText()
                            : 'Cost per box, boxes received, & items per box calculator',
                        icon: Icons.inventory_2_outlined,
                        isExpanded: _showBulkUom,
                        onToggle: () =>
                            setState(() => _showBulkUom = !_showBulkUom),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                              ],
                            ),
                            const SizedBox(height: 6),
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
                                        padding:
                                            const EdgeInsets.only(right: 4),
                                        child: InkWell(
                                          onTap: () => setState(() =>
                                              _bulkUnitCtrl.text = preset),
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

                            // UoM Breakdown Calculator Fields
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
                                        'UoM Automatic Calculator',
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
                                                    horizontal: 10,
                                                    vertical: 8),
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
                                            FilteringTextInputFormatter
                                                .digitsOnly
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
                                                    horizontal: 10,
                                                    vertical: 8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _itemsPerBoxCtrl,
                                          focusNode: _fItemsPerBox,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly
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
                                                    horizontal: 10,
                                                    vertical: 8),
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
                                            FilteringTextInputFormatter
                                                .digitsOnly
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
                                                    horizontal: 10,
                                                    vertical: 8),
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // ── COLLAPSIBLE SECTION B: VARIANT FAMILY & GROUPING ─────
                      _buildCollapsibleCard(
                        title: 'Variant Family & Parent Group ID',
                        subtitle: _parentIdCtrl.text.isNotEmpty
                            ? 'Group: ${_parentIdCtrl.text}'
                            : 'Link related flavor/size variants under one product family',
                        icon: Icons.account_tree_outlined,
                        isExpanded: _showVariantFamily,
                        onToggle: () => setState(
                            () => _showVariantFamily = !_showVariantFamily),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: inventory.uniqueParentIds
                                            .contains(_parentIdCtrl.text.trim())
                                        ? _parentIdCtrl.text.trim()
                                        : (_parentIdCtrl.text.trim().isNotEmpty
                                            ? _parentIdCtrl.text.trim()
                                            : null),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: 'Parent Group ID',
                                      prefixIcon: const Icon(
                                          Icons.account_tree_outlined,
                                          size: 18),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                      suffixIcon: Tooltip(
                                        message:
                                            'Auto-generate Group ID from Brand/Name',
                                        child: IconButton(
                                          icon: const Icon(
                                              Icons.auto_awesome_rounded,
                                              size: 16,
                                              color: Colors.purple),
                                          onPressed: () {
                                            setState(() {
                                              _autoGenerateParentGroupId(
                                                  force: true);
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
                                      if (_parentIdCtrl.text
                                              .trim()
                                              .isNotEmpty &&
                                          !inventory.uniqueParentIds.contains(
                                              _parentIdCtrl.text.trim()))
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
                                labelText: 'Custom Group Slug',
                                hintText: 'e.g. GRP-PALMOLIVE-SHAMPOO',
                                prefixIcon: Icon(Icons.edit_outlined, size: 16),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // ── COLLAPSIBLE SECTION C: SUPPLIER ───
                      _buildCollapsibleCard(
                        title: 'Supplier',
                        subtitle: _supplierId != null
                            ? 'Supplier linked • Auto low-stock alerts at 30% of original stock'
                            : 'Link supplier (alerts trigger automatically at 30% of original stock)',
                        icon: Icons.local_shipping_outlined,
                        isExpanded: _showSupplierAlerts,
                        onToggle: () => setState(
                            () => _showSupplierAlerts = !_showSupplierAlerts),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String?>(
                                    isExpanded: true,
                                    initialValue: suppliers
                                            .any((s) => s.id == _supplierId)
                                        ? _supplierId
                                        : null,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: _activeProduct == null
                                          ? 'Supplier *'
                                          : 'Supplier',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('Select Supplier')),
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
                            TextFormField(
                              controller: _notesCtrl,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText:
                                    'Invoice / Delivery Notes (Optional)',
                                hintText: 'e.g. Inv #10492 — Direct Delivery',
                                prefixIcon:
                                    Icon(Icons.receipt_long_outlined, size: 18),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // ── COLLAPSIBLE SECTION D: PERISHABLE & SHELF LIFE ───────
                      _buildCollapsibleCard(
                        title: 'Perishable & Shelf Life Options',
                        subtitle: _perishable
                            ? 'Marked perishable'
                            : 'Optional shelf days & pickup window hours',
                        icon: Icons.timer_outlined,
                        isExpanded: _showPerishableDetails,
                        onToggle: () => setState(() =>
                            _showPerishableDetails = !_showPerishableDetails),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text('Is Perishable Item?',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              subtitle: const Text(
                                  'Track shelf days and short-life warnings',
                                  style: TextStyle(fontSize: 11)),
                              value: _perishable,
                              onChanged: (v) => setState(() => _perishable = v),
                            ),
                            if (_perishable) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _shelf,
                                      focusNode: _fShelf,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'Shelf Life (Days)',
                                        hintText: 'e.g. 7',
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _pickupWindow,
                                      focusNode: _fPickupWindow,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'Pickup Window (Hours)',
                                        hintText: 'e.g. 24',
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
      ),
    );
  }

  Widget _buildCollapsibleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: child,
            ),
          ],
        ],
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
        if (result.name != null && result.name!.isNotEmpty) {
          _name.text = result.name!;
        }
        if (result.brand != null && result.brand!.isNotEmpty) {
          _brand.text = result.brand!;
        }
        if (result.category != null && result.category!.isNotEmpty) {
          _category = result.category!;
        }
        if (result.barcode != null && result.barcode!.isNotEmpty) {
          _barcode.text = result.barcode!;
        }
        if (result.photoBase64 != null &&
            result.photoBase64!.isNotEmpty &&
            _photoBase64 == null &&
            _localPhoto == null) {
          _photoBase64 = result.photoBase64;
        }
        if (result.unit != null &&
            result.unit!.isNotEmpty &&
            (_unit.text.trim().isEmpty || _unit.text.trim() == 'pcs')) {
          _unit.text = result.unit!;
        }
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
        if (_name.text.trim().isEmpty) {
          _name.text = cp.name;
        }
        final cpb = cp.brand;
        if (cpb != null && cpb.isNotEmpty && _brand.text.trim().isEmpty) {
          _brand.text = cpb;
        }
        if (cp.category.isNotEmpty) {
          _category = cp.category;
        }
        if (_photoBase64 == null &&
            _localPhoto == null &&
            cp.photoBase64 != null &&
            cp.photoBase64!.isNotEmpty) {
          _photoBase64 = cp.photoBase64;
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
        if (_name.text.trim().isEmpty) {
          _name.text = extInfo.name;
        }
        final extBrand = extInfo.brand;
        if (extBrand != null &&
            extBrand.isNotEmpty &&
            _brand.text.trim().isEmpty) {
          _brand.text = extBrand;
        }
        if (_photoBase64 == null &&
            _localPhoto == null &&
            extInfo.photoBase64 != null &&
            extInfo.photoBase64!.isNotEmpty) {
          _photoBase64 = extInfo.photoBase64;
        }
        if ((_unit.text.trim().isEmpty || _unit.text.trim() == 'pcs') &&
            extInfo.unit != null &&
            extInfo.unit!.isNotEmpty) {
          _unit.text = extInfo.unit!;
        }
        if (extInfo.category != null && extInfo.category!.isNotEmpty) {
          _category = extInfo.category!;
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

  void _confirmDelete(BuildContext context) async {
    final productName = _activeProduct?.name ?? 'this product';
    final confirm = await ActionWarningDialog.show(
      context,
      title: 'Delete Product?',
      message:
          'Are you sure you want to permanently remove "$productName" from your inventory database?',
      confirmLabel: 'Delete Product',
      cancelLabel: 'Cancel',
      severity: ActionWarningSeverity.danger,
      icon: Icons.delete_forever_rounded,
      requireCheckbox: true,
      checkboxLabel: 'I understand this action cannot be undone.',
      details: [
        'Product name: $productName',
        'All associated inventory logs and product records will be removed.',
      ],
    );

    if (confirm && context.mounted) {
      if (_activeProduct != null) {
        await context
            .read<InventoryProvider>()
            .deleteProduct(_activeProduct!.id);
      }
      if (context.mounted) Navigator.pop(context);
    }
  }

  Future<void> _saveProductForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

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
    final costPrice = double.tryParse(_costPrice.text) ?? 0;
    final pricingEval = _evaluateCurrentPricing();
    final double parsedManualPrice = double.tryParse(_price.text.trim()) ?? 0.0;
    final double price = _pricingMode == Product.pricingModeManual
        ? (parsedManualPrice > 0
            ? parsedManualPrice
            : pricingEval.finalSellingPrice)
        : (pricingEval.hasInvalidCost
            ? parsedManualPrice
            : pricingEval.finalSellingPrice);
    final initialQty = int.tryParse(_stock.text) ?? 0;
    final category = _category;
    final unit = _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim();
    final bulkUnit =
        _bulkUnitCtrl.text.trim().isEmpty ? 'box' : _bulkUnitCtrl.text.trim();

    final inventoryProvider = context.read<InventoryProvider>();
    final authProvider = context.read<AppAuthProvider>();

    if (_activeProduct == null) {
      // Enforce valid supplier when creating initial stock batch
      if (_variants.isEmpty &&
          initialQty > 0 &&
          (_supplierId == null ||
              _supplierId!.trim().isEmpty ||
              !inventoryProvider.suppliers.any((s) => s.id == _supplierId))) {
        setState(() => _showSupplierAlerts = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please select a valid Supplier under "Supplier & Stock Alerts" before creating an initial stock batch.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
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

    if (barcode.isEmpty) {
      barcode = BarcodeGenerator.generateInternalBarcode();
    }

    final boxPrice = double.tryParse(_boxPriceCtrl.text) ?? 0.0;
    final itemsPerBox = int.tryParse(_itemsPerBoxCtrl.text) ?? 0;
    final double calculatedUnitCost = (boxPrice > 0 && itemsPerBox > 0)
        ? (boxPrice / itemsPerBox)
        : costPrice;

    final double? manualMarkupToSave = _pricingMode == Product.pricingModeManual
        ? (double.tryParse(_manualMarkupCtrl.text.trim()) ??
            PricingEngine.reverseCalculateMarkupPercent(
              sellingPrice: price,
              unitCost: calculatedUnitCost,
            ))
        : null;
    final double computedMarkupToSave =
        _pricingMode == Product.pricingModeManual && manualMarkupToSave != null
            ? manualMarkupToSave
            : pricingEval.computedMarkupPercent;

    final List<String> belowCostDetails = [];
    if (price > 0 && calculatedUnitCost > 0 && price < calculatedUnitCost) {
      final loss = calculatedUnitCost - price;
      belowCostDetails.add(
        'Base Item "$name": Selling ${formatPeso(price)} vs Cost ${formatPeso(calculatedUnitCost)} (Loss: ${formatPeso(loss)}/unit)',
      );
    }
    for (final v in _variants) {
      final vCost = v.costPrice > 0 ? v.costPrice : calculatedUnitCost;
      if (v.price > 0 && vCost > 0 && v.price < vCost) {
        final loss = vCost - v.price;
        belowCostDetails.add(
          'Variant "${v.name}": Selling ${formatPeso(v.price)} vs Cost ${formatPeso(vCost)} (Loss: ${formatPeso(loss)}/unit)',
        );
      }
    }

    if (belowCostDetails.isNotEmpty) {
      final confirm = await ActionWarningDialog.show(
        context,
        title: 'Selling Price Below Calculated Cost',
        message:
            'One or more prices for "$name" are set below their calculated unit cost. Saving these prices will result in financial loss on sales. Are you sure you want to proceed?',
        confirmLabel: 'Save Anyway',
        cancelLabel: 'Edit Price',
        severity: ActionWarningSeverity.warning,
        icon: Icons.trending_down_rounded,
        details: belowCostDetails,
      );
      if (!confirm) return;
    }

    setState(() => _saving = true);

    try {
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

      final int prevOriginal = _activeProduct?.effectiveOriginalStock ?? 0;
      final bool isStockIncrease =
          _activeProduct == null || initialQty > _activeProduct!.totalStock;
      final int calculatedInitial = isStockIncrease
          ? initialQty
          : (prevOriginal > 0 ? prevOriginal : initialQty);

      final itemsPerCaseVal = int.tryParse(_itemsPerBoxCtrl.text) ??
          int.tryParse(_itemsPerCase.text);
      final packCostVal = double.tryParse(_boxPriceCtrl.text);

      final Map<String, ProductVariant> prevVariantsById = {
        for (final v in _activeProduct?.variants ?? const <ProductVariant>[])
          v.id: v,
      };
      final List<ProductVariant> resolvedVariants = _variants.map((v) {
        final prev = prevVariantsById[v.id];
        final bool isRestock = prev == null ||
            v.stock > prev.stock ||
            prev.physicalReserve == null;
        final int prevVarOriginal = prev?.effectiveOriginalStock ?? 0;
        return v.copyWith(
          initialStock: (prev == null || v.stock > prev.stock)
              ? v.stock
              : (prevVarOriginal > 0 ? prevVarOriginal : v.stock),
          physicalReserve: isRestock
              ? InventoryAllocation.calculatePhysicalReserve(v.stock)
              : prev.effectivePhysicalReserve,
        );
      }).toList();

      final int resolvedPhysicalReserve = resolvedVariants.isNotEmpty
          ? resolvedVariants.fold(
              0, (acc, v) => acc + v.effectivePhysicalReserve)
          : (_activeProduct == null ||
                  initialQty > _activeProduct!.totalStock ||
                  _activeProduct!.physicalReserve == null)
              ? InventoryAllocation.calculatePhysicalReserve(initialQty)
              : _activeProduct!.effectivePhysicalReserve;

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
        reservedStock: _activeProduct?.reservedStock ?? 0,
        wholesalePrice: _activeProduct?.wholesalePrice,
        wholesaleThreshold: _activeProduct?.wholesaleThreshold,
        unit: unit,
        bulkUnit: bulkUnit,
        packCost: packCostVal,
        itemsPerCase: itemsPerCaseVal,
        pricingMode: _pricingMode,
        manualMarkupPercent: manualMarkupToSave,
        salesVelocityScore: _salesVelocityScore,
        computedMarkupPercent: computedMarkupToSave,
        physicalReserve: resolvedPhysicalReserve,
        barcode: barcode,
        shelfDays: _perishable ? int.tryParse(_shelf.text) : null,
        pickupWindowHours:
            _perishable ? int.tryParse(_pickupWindow.text) : null,
        isTaxable: _taxable,
        status: _status,
        photoBase64: _photoBase64,
        supplierId: _supplierId,
        expiryDate: _expiryDate,
        variants: resolvedVariants,
        batches: _activeProduct?.batches ?? const [],
      );

      final initialBatch = ProductBatch(
        batchId: InventoryBatchService.generateBatchId(_dateArrived),
        productId: p.id,
        productName: name,
        supplierId: _supplierId,
        datePurchased: _datePurchased,
        dateArrived: _dateArrived,
        expiryDate: _expiryDate,
        costPrice: costPrice,
        initialQty: initialQty,
        remainingQty: initialQty,
        status: initialQty > 0 ? BatchStatus.active : BatchStatus.depleted,
        invoiceNumber:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

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

      if (_activeProduct == null) {
        await inventoryProvider.saveProductWithBatch(
          product: p,
          initialBatch: initialBatch,
          receivedBy: receivedBy,
          notes: historyNotes,
        );
      } else {
        await inventoryProvider.saveProduct(p);
      }

      if (mounted) {
        navigator.pop();
        if (belowCostDetails.isNotEmpty) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                  '⚠️ Saved "$name" with selling price(s) below calculated cost.'),
              backgroundColor: Colors.amber.shade900,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                  'Saved "$name" ($initialQty $unit) straight to Inventory History! ✅'),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
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
