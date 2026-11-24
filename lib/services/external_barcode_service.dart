import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/image_utils.dart';

/// Data class representing product details fetched from external barcode lookup APIs.
class ExternalProductInfo {
  /// The product title or commercial name.
  final String name;

  /// The brand or manufacturer of the product.
  final String? brand;

  /// Public URL pointing to the product image asset.
  final String? imageUrl;

  /// Product category from external API.
  final String? category;

  /// Base64 encoded compressed image asset bytes (if successfully fetched).
  final String? photoBase64;

  /// Mapped base unit of measure matching system allowed options (e.g. 'pcs', 'bottle', 'can', 'pack', 'kg', 'sachet').
  final String? unit;

  /// Name of the external data provider (e.g. Open Food Facts, UPCitemdb).
  final String source;

  /// Creates an instance of [ExternalProductInfo].
  ExternalProductInfo({
    required this.name,
    this.brand,
    this.category,
    this.imageUrl,
    this.photoBase64,
    this.unit,
    required this.source,
  });
}

/// Service for looking up product catalog information from global barcode databases.
class ExternalBarcodeService {
  static const List<String> validBaseUnits = [
    'pcs',
    'g',
    'kg',
    'ml',
    'l',
    'can',
    'bottle',
    'pack',
    'sachet',
    'box',
    'bar',
    'pad',
    'roll',
  ];

  /// Fetches product details from Open Food Facts API v3, falling back to UPCitemdb.
  ///
  /// Takes a raw [barcode] string, trims whitespace, and queries global APIs.
  /// Returns [ExternalProductInfo] if found, or `null` if the barcode is not recognized.
  static Future<ExternalProductInfo?> fetchProductInfo(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;

    // 1. Try Open Food Facts API v3 (Free, No API key required, excellent global/PH coverage)
    final offResult = await _fetchFromOpenFoodFacts(cleanBarcode);
    if (offResult != null) return offResult;

    // 2. Fallback to UPCitemdb Free Trial API
    final upcResult = await _fetchFromUpcItemDb(cleanBarcode);
    if (upcResult != null) return upcResult;

    return null;
  }

  /// Internal helper to query the Open Food Facts API v3 endpoint.
  static Future<ExternalProductInfo?> _fetchFromOpenFoodFacts(
      String barcode) async {
    try {
      final client = HttpClient();
      final fields = [
        'product_name',
        'brands',
        'quantity',
        'product_quantity',
        'product_quantity_unit',
        'image_front_url',
        'image_front_small_url',
        'image_url',
        'selected_images',
        'categories'
      ].join(',');

      final uri = Uri.parse(
          'https://world.openfoodfacts.org/api/v3/product/$barcode.json?fields=$fields');
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent',
          'GDC_SariSariStore/1.0 (Android; markjeo.hinampas@gmail.com)');

      final response =
          await request.close().timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);

        final status = json['status']?.toString();
        if (status == 'failure') return null;

        final p = json['product'];
        if (p is Map<String, dynamic>) {
          String? name;
          final possibleNameKeys = [
            'product_name',
            'product_name_en',
            'product_name_ph',
            'generic_name',
            'generic_name_en',
            'abbreviated_product_name'
          ];
          for (final key in possibleNameKeys) {
            final val = p[key]?.toString().trim();
            if (val != null && val.isNotEmpty) {
              name = val;
              break;
            }
          }

          String? brand;
          final possibleBrandKeys = ['brands', 'brand_owner', 'brands_tags'];
          for (final key in possibleBrandKeys) {
            final val = p[key]?.toString().trim();
            if (val != null && val.isNotEmpty) {
              brand = val;
              break;
            }
          }

          if (name != null && name.isNotEmpty) {
            // Product Image Resolution & Download
            final imageUrl = resolveImageUrl(p);
            String? photoBase64;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              photoBase64 = await downloadAndEncodeImage(imageUrl);
            }

            // Extract category
            String? category;
            final categoriesStr = p['categories']?.toString();
            if (categoriesStr != null && categoriesStr.isNotEmpty) {
              final list = categoriesStr
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (list.isNotEmpty) {
                category =
                    list.last; // Most specific category usually at the end
              }
            }

            // Base Unit Mapping
            final rawUnit = p['product_quantity_unit']?.toString().trim();
            final rawQuantity = p['quantity']?.toString().trim();
            final mappedUnit = mapToBaseUnit(
              rawUnit: rawUnit,
              rawQuantity: rawQuantity,
              productName: name,
            );

            return ExternalProductInfo(
              name: name,
              brand: brand,
              category: category,
              imageUrl: imageUrl,
              photoBase64: photoBase64,
              unit: mappedUnit,
              source: 'Open Food Facts',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('OpenFoodFacts API Error: $e');
    }
    return null;
  }

  /// Resolves the front product image URL from Open Food Facts API response.
  /// Checks `image_front_url` first, then `image_url`, and falls back to `selected_images.front.display`.
  @visibleForTesting
  static String? resolveImageUrl(Map<String, dynamic> product) {
    // 1. Check product.image_front_url first
    final frontUrl = product['image_front_url']?.toString().trim();
    if (frontUrl != null && frontUrl.isNotEmpty) {
      return frontUrl;
    }

    // 2. Check product.image_url
    final mainUrl = product['image_url']?.toString().trim();
    if (mainUrl != null && mainUrl.isNotEmpty) {
      return mainUrl;
    }

    // 3. Fallback to product.selected_images.front.display
    final selectedImages = product['selected_images'];
    if (selectedImages is Map<String, dynamic>) {
      final front = selectedImages['front'];
      if (front is Map<String, dynamic>) {
        final display = front['display'];
        if (display is Map<String, dynamic>) {
          final enUrl = display['en']?.toString().trim();
          if (enUrl != null && enUrl.isNotEmpty) {
            return enUrl;
          }

          for (final entry in display.entries) {
            final val = entry.value?.toString().trim();
            if (val != null && val.isNotEmpty) {
              return val;
            }
          }
        }
        final small = front['small'];
        if (small is Map<String, dynamic>) {
          final enUrl = small['en']?.toString().trim();
          if (enUrl != null && enUrl.isNotEmpty) return enUrl;
        }
      }
    }
    return null;
  }

  /// Downloads and converts image from [url] into a compressed base64 string.
  /// Non-blocking with 4-second timeout, returns null on network or loading errors.
  @visibleForTesting
  static Future<String?> downloadAndEncodeImage(String url) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent',
          'GDC_SariSariStore/1.0 (Android; markjeo.hinampas@gmail.com)');

      final response =
          await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final bytesList = <int>[];
        await for (final chunk in response) {
          bytesList.addAll(chunk);
        }
        final bytes = Uint8List.fromList(bytesList);
        if (bytes.isNotEmpty) {
          return ImageUtils.compressAndEncode(bytes);
        }
      }
    } catch (e) {
      debugPrint('Error downloading product image from $url: $e');
    }
    return null;
  }

  /// Maps raw Open Food Facts unit or quantity string to a system valid Base Unit option.
  @visibleForTesting
  static String? mapToBaseUnit({
    String? rawUnit,
    String? rawQuantity,
    String? productName,
  }) {
    String candidateUnit = '';

    // 1. Check rawUnit first
    if (rawUnit != null && rawUnit.isNotEmpty) {
      candidateUnit = rawUnit.toLowerCase().trim();
    }

    // 2. Parse unit from rawQuantity if candidateUnit is empty
    if (candidateUnit.isEmpty &&
        rawQuantity != null &&
        rawQuantity.isNotEmpty) {
      final match =
          RegExp(r'(\d+(?:\.\d+)?)\s*([a-zA-Z]+)', caseSensitive: false)
              .firstMatch(rawQuantity);
      if (match != null && match.groupCount >= 2) {
        candidateUnit = match.group(2)!.toLowerCase().trim();
      } else {
        candidateUnit = rawQuantity.toLowerCase().trim();
      }
    }

    // 3. Parse unit from productName if candidateUnit is still empty
    if (candidateUnit.isEmpty &&
        productName != null &&
        productName.isNotEmpty) {
      final match = RegExp(
              r'(\d+(?:\.\d+)?)\s*(g|kg|ml|l|can|bottle|pack|sachet|box|bar|pad|roll|pcs|pc)\b',
              caseSensitive: false)
          .firstMatch(productName);
      if (match != null && match.groupCount >= 2) {
        candidateUnit = match.group(2)!.toLowerCase().trim();
      }
    }

    // Direct unit mapping to standard base units
    if (candidateUnit == 'g' ||
        candidateUnit == 'gram' ||
        candidateUnit == 'grams' ||
        candidateUnit == 'gr') {
      return 'g';
    }

    if (candidateUnit == 'kg' ||
        candidateUnit == 'kilo' ||
        candidateUnit == 'kilogram' ||
        candidateUnit == 'kilograms') {
      return 'kg';
    }

    if (candidateUnit == 'ml' ||
        candidateUnit == 'milliliter' ||
        candidateUnit == 'millilitre' ||
        candidateUnit == 'milliliters' ||
        candidateUnit == 'cl') {
      return 'ml';
    }

    if (candidateUnit == 'l' ||
        candidateUnit == 'liter' ||
        candidateUnit == 'litre' ||
        candidateUnit == 'liters') {
      return 'l';
    }

    if (candidateUnit == 'can' ||
        candidateUnit == 'cans' ||
        candidateUnit == 'tin' ||
        candidateUnit == 'tins') {
      return 'pcs';
    }

    if (candidateUnit == 'bottle' ||
        candidateUnit == 'bottles' ||
        candidateUnit == 'btl') {
      return 'pcs';
    }

    if (candidateUnit == 'sachet' ||
        candidateUnit == 'sachets' ||
        candidateUnit == 'pouch' ||
        candidateUnit == 'pouches') {
      return 'pcs';
    }

    if (candidateUnit == 'pack' ||
        candidateUnit == 'packs' ||
        candidateUnit == 'packet' ||
        candidateUnit == 'packets' ||
        candidateUnit == 'bag') {
      return 'pcs';
    }

    if (candidateUnit == 'box' || candidateUnit == 'boxes') {
      return 'box';
    }

    if (candidateUnit == 'bar' || candidateUnit == 'bars') {
      return 'pcs';
    }

    if (candidateUnit == 'pad' || candidateUnit == 'pads') {
      return 'pcs';
    }

    if (candidateUnit == 'roll' || candidateUnit == 'rolls') {
      return 'pcs';
    }

    if (candidateUnit == 'pcs' ||
        candidateUnit == 'pc' ||
        candidateUnit == 'piece' ||
        candidateUnit == 'pieces' ||
        candidateUnit == 'unit' ||
        candidateUnit == 'units') {
      return 'pcs';
    }

    if (candidateUnit.isNotEmpty && validBaseUnits.contains(candidateUnit)) {
      return candidateUnit;
    }

    // Fallback: Check container keywords in productName as whole words
    final lowerName = productName?.toLowerCase() ?? '';

    // Auto-map based on product type keywords
    if (RegExp(r'\b(rice|sugar|salt|flour)\b').hasMatch(lowerName)) {
      return 'kg';
    }

    if (RegExp(r'\b(can|cans|tin|tins)\b').hasMatch(lowerName)) return 'pcs';
    if (RegExp(r'\b(bottle|bottles|btl)\b').hasMatch(lowerName)) {
      return 'pcs';
    }
    if (RegExp(r'\b(sachet|sachets|pouch|pouches)\b').hasMatch(lowerName)) {
      return 'pcs';
    }
    if (RegExp(r'\b(pack|packs|packet|packets)\b').hasMatch(lowerName)) {
      return 'pcs';
    }
    if (RegExp(r'\b(box|boxes)\b').hasMatch(lowerName)) return 'box';
    if (RegExp(r'\b(bar|bars)\b').hasMatch(lowerName)) return 'pcs';
    if (RegExp(r'\b(pad|pads)\b').hasMatch(lowerName)) return 'pcs';
    if (RegExp(r'\b(roll|rolls)\b').hasMatch(lowerName)) return 'pcs';

    return null;
  }

  /// Internal helper to query the UPCitemdb Trial endpoint.
  static Future<ExternalProductInfo?> _fetchFromUpcItemDb(
      String barcode) async {
    try {
      final client = HttpClient();
      final uri =
          Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$barcode');
      final request = await client.getUrl(uri);

      final response =
          await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);

        if (json['code'] == 'OK' &&
            json['items'] is List &&
            (json['items'] as List).isNotEmpty) {
          final item = json['items'][0];
          final title = item['title']?.toString().trim();
          final brand = item['brand']?.toString().trim();

          if (title != null && title.isNotEmpty) {
            final mappedUnit = mapToBaseUnit(productName: title);
            return ExternalProductInfo(
              name: title,
              brand: brand,
              unit: mappedUnit,
              source: 'UPCitemdb',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('UPCitemdb API Error: $e');
    }
    return null;
  }
}
