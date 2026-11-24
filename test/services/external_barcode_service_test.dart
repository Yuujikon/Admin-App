import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/services/external_barcode_service.dart';

void main() {
  group('ExternalBarcodeService - Image URL Resolution Tests', () {
    test('resolves image_front_url when present', () {
      final json = {
        'image_front_url': 'https://images.openfoodfacts.org/front.jpg',
        'selected_images': {
          'front': {
            'display': {'en': 'https://images.openfoodfacts.org/display_en.jpg'}
          }
        }
      };

      final url = ExternalBarcodeService.resolveImageUrl(json);
      expect(url, equals('https://images.openfoodfacts.org/front.jpg'));
    });

    test(
        'falls back to selected_images.front.display["en"] when image_front_url is missing',
        () {
      final json = {
        'image_front_url': '',
        'selected_images': {
          'front': {
            'display': {
              'en': 'https://images.openfoodfacts.org/display_en.jpg',
              'fr': 'https://images.openfoodfacts.org/display_fr.jpg',
            }
          }
        }
      };

      final url = ExternalBarcodeService.resolveImageUrl(json);
      expect(url, equals('https://images.openfoodfacts.org/display_en.jpg'));
    });

    test(
        'falls back to first available language in selected_images when "en" is missing',
        () {
      final json = {
        'selected_images': {
          'front': {
            'display': {
              'fr': 'https://images.openfoodfacts.org/display_fr.jpg',
              'es': 'https://images.openfoodfacts.org/display_es.jpg',
            }
          }
        }
      };

      final url = ExternalBarcodeService.resolveImageUrl(json);
      expect(url, equals('https://images.openfoodfacts.org/display_fr.jpg'));
    });

    test('returns null when no image fields or selected_images are found', () {
      final json = <String, dynamic>{
        'product_name': 'Sample Product',
      };

      final url = ExternalBarcodeService.resolveImageUrl(json);
      expect(url, isNull);
    });
  });

  group('ExternalBarcodeService - Base Unit Mapping Tests', () {
    test('maps raw product_quantity_unit "g" to standard "g" and "kg" to "kg"',
        () {
      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: 'g',
          rawQuantity: '155 g',
          productName: 'Ligo Sardines in Tomato Sauce 155g',
        ),
        equals('g'),
      );

      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: 'kg',
          rawQuantity: '1 kg',
          productName: 'Jasmine Rice',
        ),
        equals('kg'),
      );
    });

    test('maps liquid unit "ml" to "ml" and "l" to "l"', () {
      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: 'ml',
          rawQuantity: '330 ml',
          productName: 'San Miguel Pale Pilsen 330ml',
        ),
        equals('ml'),
      );

      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: 'l',
          rawQuantity: '1.5 L',
          productName: 'Coca-Cola Zero Sugar',
        ),
        equals('l'),
      );
    });

    test('maps container units "can", "bottle", "sachet", "pack" to "pcs"',
        () {
      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: 'can',
          rawQuantity: '155g',
          productName: 'Ligo Sardines',
        ),
        equals('pcs'),
      );

      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: 'sachet',
          rawQuantity: '33g',
          productName: 'Nescafe 3in1 Twin Pack Sachet',
        ),
        equals('pcs'),
      );

      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: 'pack',
          rawQuantity: '55g',
          productName: 'Lucky Me Instant Pancit Canton',
        ),
        equals('pcs'),
      );

      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: 'pcs',
          rawQuantity: '12 pcs',
          productName: 'Fresh Farm Eggs',
        ),
        equals('pcs'),
      );

      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: 'box',
          rawQuantity: '1 box',
          productName: 'Cereal Box',
        ),
        equals('box'),
      );
    });

    test('parses unit from rawQuantity when product_quantity_unit is empty',
        () {
      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: '',
          rawQuantity: '330 ml',
          productName: 'Soda',
        ),
        equals('ml'),
      );

      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: null,
          rawQuantity: '500 g',
          productName: 'Refined Sugar',
        ),
        equals('g'),
      );

      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: null,
          rawQuantity: '6 pack',
          productName: 'Juice Drink',
        ),
        equals('pcs'),
      );
    });

    test('auto-maps rice to kg based on product name fallback', () {
      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: null,
          rawQuantity: null,
          productName: 'Premium Dinorado Rice',
        ),
        equals('kg'),
      );
    });

    test('returns null when no unit can be parsed or matched', () {
      expect(
        ExternalBarcodeService.mapToBaseUnit(
          rawUnit: null,
          rawQuantity: null,
          productName: 'Generic Unknown Item',
        ),
        isNull,
      );
    });
  });
}
