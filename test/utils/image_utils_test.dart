import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/utils/image_utils.dart';
import 'package:image/image.dart' as img;

void main() {
  group('ImageUtils - Whitespace Trimming & Image Processing Tests', () {
    test('trimWhitespace crops surrounding white border from an image', () {
      // Create a 100x100 white image with a 20x20 red square in the center
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      // Draw a red rectangle in the center (40,40) to (60,60)
      img.fillRect(image,
          x1: 40, y1: 40, x2: 60, y2: 60, color: img.ColorRgb8(255, 0, 0));

      final trimmed = ImageUtils.trimWhitespace(image);

      // The trimmed image should be significantly smaller than 100x100
      expect(trimmed.width, lessThan(100));
      expect(trimmed.height, lessThan(100));
      expect(trimmed.width, greaterThanOrEqualTo(20));
      expect(trimmed.height, greaterThanOrEqualTo(20));
    });

    test('compressAndEncode successfully encodes and trims image bytes', () {
      final image = img.Image(width: 50, height: 50);
      img.fill(image, color: img.ColorRgb8(200, 100, 50));
      final bytes = img.encodeJpg(image);

      final encoded = ImageUtils.compressAndEncode(bytes);
      expect(encoded, isNotEmpty);
    });
  });
}
