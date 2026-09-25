import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../models/catalog_product.dart';
import '../utils/format.dart';
import '../config/theme.dart';
import 'catalog_search_dialog.dart';

class FullProductScannerResult {
  final String? name;
  final String? brand;
  final String? category;
  final String? barcode;
  final String? catalogId;

  FullProductScannerResult({
    this.name,
    this.brand,
    this.category,
    this.barcode,
    this.catalogId,
  });
}

class FullProductScannerDialog extends StatefulWidget {
  const FullProductScannerDialog({super.key});

  @override
  State<FullProductScannerDialog> createState() => _FullProductScannerDialogState();
}

class _FullProductScannerDialogState extends State<FullProductScannerDialog> with SingleTickerProviderStateMixin {
  final MobileScannerController _scannerController = MobileScannerController();
  String? _detectedBarcode;
  bool _isTorchOn = false;

  late AnimationController _animationController;
  late Animation<double> _animation;

  // Review State
  bool _showReview = false;
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  String? _selectedCategory;
  String? _selectedCatalogId;
  String _infoSource = 'Catalog'; 

  final List<String> _categories = [
    'Fresh', 'Grains', 'Snacks', 'Beverages',
    'Canned Goods', 'Personal Care', 'Condiments', 'Others'
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scannerController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(String barcode) {
    if (_showReview) return;

    final inventory = context.read<InventoryProvider>();
    final catalog = inventory.catalog;

    // 1. Search Catalog by Barcode
    final match = catalog.where((p) => p.barcode == barcode).toList();

    if (match.isNotEmpty) {
      final p = match.first;
      setState(() {
        _detectedBarcode = barcode;
        _nameController.text = p.name;
        _brandController.text = p.brand ?? '';
        _selectedCategory = p.category;
        _selectedCatalogId = p.id;
        _infoSource = 'Catalog Match';
        _showReview = true;
      });
      HapticFeedback.mediumImpact();
      return;
    }

    // 2. Not found in catalog
    setState(() {
      _detectedBarcode = barcode;
      _nameController.clear();
      _brandController.clear();
      _selectedCategory = null;
      _selectedCatalogId = null;
      _infoSource = 'New Barcode';
      _showReview = true;
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _searchCatalog() async {
    final result = await showDialog<CatalogProduct>(
      context: context,
      builder: (_) => const CatalogSearchDialog(),
    );

    if (result != null) {
      setState(() {
        _nameController.text = result.name;
        _brandController.text = result.brand ?? '';
        _selectedCategory = result.category;
        _selectedCatalogId = result.id;
        _infoSource = 'Catalog Selected';
      });
    }
  }

  void _onConfirm() {
    Navigator.pop(
      context,
      FullProductScannerResult(
        name: _nameController.text.trim().capitalize(),
        brand: _brandController.text.trim().capitalize(),
        category: _selectedCategory,
        barcode: _detectedBarcode,
        catalogId: _selectedCatalogId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Catalog Scanner'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              setState(() => _isTorchOn = !_isTorchOn);
              _scannerController.toggleTorch();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Scanner Overlay
          Positioned.fill(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final code = barcodes.first.rawValue;
                  if (code != null) {
                    _onBarcodeDetected(code);
                  }
                }
              },
            ),
          ),

          // Custom Viewfinder HUD
          _buildViewfinderHUD(),

          if (_showReview) _buildReviewOverlay(),
        ],
      ),
    );
  }

  Widget _buildViewfinderHUD() {
    return Stack(
      children: [
        // Semi-transparent background with a hole in the middle
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.7),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 280,
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Viewfinder lines and animation
        Center(
          child: SizedBox(
            width: 280,
            height: 180,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return CustomPaint(
                  painter: ViewfinderPainter(
                    animationValue: _animation.value,
                    borderColor: GdcColors.primaryGreen,
                  ),
                );
              },
            ),
          ),
        ),

        // Helper Text
        const Positioned(
          top: 100,
          left: 0,
          right: 0,
          child: Center(
            child: Column(
              children: [
                Icon(Icons.qr_code_scanner, color: Colors.white70, size: 32),
                SizedBox(height: 12),
                Text(
                  'Center barcode in frame',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SingleChildScrollView(
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _infoSource == 'Catalog Match' ? Icons.verified : Icons.help_outline,
                        color: _infoSource == 'Catalog Match' ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Catalog Identification',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Source: $_infoSource',
                    style: TextStyle(
                      fontSize: 12,
                      color: _infoSource == 'Catalog Match' ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Divider(height: 32),
                  if (_detectedBarcode != null) ...[
                    Text('Barcode', style: Theme.of(context).textTheme.labelSmall),
                    Text(_detectedBarcode!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                  ],

                  if (_infoSource == 'New Barcode')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ElevatedButton.icon(
                        onPressed: _searchCatalog,
                        icon: const Icon(Icons.search),
                        label: const Text('Search Catalog for this Product'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade50,
                          foregroundColor: Colors.blue.shade900,
                        ),
                      ),
                    ),

                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      hintText: 'e.g. Original Taste',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _brandController,
                    decoration: const InputDecoration(
                      labelText: 'Brand',
                      hintText: 'e.g. Coca-Cola',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _categories.contains(_selectedCategory) ? _selectedCategory : null,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setState(() => _selectedCategory = val),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _showReview = false),
                          child: const Text('Rescan'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _onConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GdcColors.primaryGreen,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Confirm'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ViewfinderPainter extends CustomPainter {
  final double animationValue;
  final Color borderColor;

  ViewfinderPainter({
    required this.animationValue,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const double length = 32;
    const double radius = 24;

    // Top Left
    canvas.drawPath(
      Path()
        ..moveTo(0, length)
        ..lineTo(0, radius)
        ..quadraticBezierTo(0, 0, radius, 0)
        ..lineTo(length, 0),
      paint,
    );

    // Top Right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - length, 0)
        ..lineTo(size.width - radius, 0)
        ..quadraticBezierTo(size.width, 0, size.width, radius)
        ..lineTo(size.width, length),
      paint,
    );

    // Bottom Left
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - length)
        ..lineTo(0, size.height - radius)
        ..quadraticBezierTo(0, size.height, radius, size.height)
        ..lineTo(length, size.height),
      paint,
    );

    // Bottom Right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - length, size.height)
        ..lineTo(size.width - radius, size.height)
        ..quadraticBezierTo(size.width, size.height, size.width, size.height - radius)
        ..lineTo(size.width, size.height - length),
      paint,
    );

    // Scanning Line
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          borderColor.withValues(alpha: 0.0),
          borderColor,
          borderColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, size.height * animationValue, size.width, 2))
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(12, size.height * animationValue),
      Offset(size.width - 12, size.height * animationValue),
      scanPaint..color = borderColor.withValues(alpha: 0.8),
    );
    
    // Add a glowing effect to the line
    canvas.drawLine(
      Offset(12, size.height * animationValue),
      Offset(size.width - 12, size.height * animationValue),
      Paint()
        ..color = borderColor.withValues(alpha: 0.4)
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant ViewfinderPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
