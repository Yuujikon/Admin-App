import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ExternalProductInfo {
  final String name;
  final String? brand;
  final String? imageUrl;
  final String source;

  ExternalProductInfo({
    required this.name,
    this.brand,
    this.imageUrl,
    required this.source,
  });
}

class ExternalBarcodeService {
  /// Fetches product details from Open Food Facts API, falling back to UPCitemdb.
  static Future<ExternalProductInfo?> fetchProductInfo(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;

    // 1. Try Open Food Facts API (Free, No API key required, excellent global/PH coverage)
    final offResult = await _fetchFromOpenFoodFacts(cleanBarcode);
    if (offResult != null) return offResult;

    // 2. Fallback to UPCitemdb Free Trial API
    final upcResult = await _fetchFromUpcItemDb(cleanBarcode);
    if (upcResult != null) return upcResult;

    return null;
  }

  static Future<ExternalProductInfo?> _fetchFromOpenFoodFacts(String barcode) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$barcode.json');
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'GDC_SariSariStore/1.0 (Android; markjeo.hinampas@gmail.com)');

      final response = await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);

        if (json['status'] == 1 && json['product'] != null) {
          final p = json['product'] as Map<String, dynamic>;

          String? name;
          final possibleNameKeys = [
            'product_name', 'product_name_en', 'product_name_ph',
            'generic_name', 'generic_name_en', 'abbreviated_product_name'
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
            return ExternalProductInfo(
              name: name,
              brand: brand,
              imageUrl: p['image_front_url']?.toString() ?? p['image_url']?.toString(),
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

  static Future<ExternalProductInfo?> _fetchFromUpcItemDb(String barcode) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$barcode');
      final request = await client.getUrl(uri);

      final response = await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);

        if (json['code'] == 'OK' && json['items'] is List && (json['items'] as List).isNotEmpty) {
          final item = json['items'][0];
          final title = item['title']?.toString().trim();
          final brand = item['brand']?.toString().trim();

          if (title != null && title.isNotEmpty) {
            return ExternalProductInfo(
              name: title,
              brand: brand,
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
