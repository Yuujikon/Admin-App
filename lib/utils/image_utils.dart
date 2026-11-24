import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Utility class for image background manipulation and base64 compression.
class ImageUtils {
  /// Trims white and transparent borders around the image subject so the product fills the frame with comfortable padding.
  static img.Image trimWhitespace(img.Image image,
      {int threshold = 240, double paddingRatio = 0.05}) {
    int minX = image.width;
    int minY = image.height;
    int maxX = -1;
    int maxY = -1;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final bool isTransparent = pixel.a < 15;
        final bool isWhite =
            pixel.r > threshold && pixel.g > threshold && pixel.b > threshold;

        if (!isTransparent && !isWhite) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    // If no non-background pixels were found or bounds cover the full image, return original
    if (maxX < minX || maxY < minY) return image;

    final cropW = maxX - minX + 1;
    final cropH = maxY - minY + 1;

    // If cropped area is already 95%+ of original image size, no need to crop
    if (cropW * cropH >= image.width * image.height * 0.95) return image;

    final padX = (cropW * paddingRatio).round().clamp(2, 20);
    final padY = (cropH * paddingRatio).round().clamp(2, 20);

    final x = (minX - padX).clamp(0, image.width - 1);
    final y = (minY - padY).clamp(0, image.height - 1);
    final w = (cropW + padX * 2).clamp(1, image.width - x);
    final h = (cropH + padY * 2).clamp(1, image.height - y);

    return img.copyCrop(image, x: x, y: y, width: w, height: h);
  }

  /// Removes pixels that are "white enough" from the image.
  /// Converts the image to PNG to support transparency and trims empty margins.
  static Uint8List? removeWhiteBackground(Uint8List bytes,
      {int threshold = 240}) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    // Ensure we have an alpha channel
    img.Image rgba8;
    if (image.format != img.Format.uint8 || image.numChannels != 4) {
      rgba8 = image.convert(format: img.Format.uint8, numChannels: 4);
    } else {
      rgba8 = image;
    }

    // Process pixels
    for (final pixel in rgba8) {
      // Check if pixel is white based on RGB values
      if (pixel.r > threshold && pixel.g > threshold && pixel.b > threshold) {
        // Set alpha to 0 (fully transparent)
        pixel.a = 0;
      }
    }

    // Trim transparent/white borders around product subject
    final trimmed = trimWhitespace(rgba8, threshold: threshold);

    // Encode as PNG to keep transparency
    return Uint8List.fromList(img.encodePng(trimmed));
  }

  /// Compresses the given image bytes and returns a base64 encoded string.
  /// Automatically trims excessive white/transparent borders around the subject.
  static String compressAndEncode(Uint8List bytes,
      {int maxWidth = 800, int quality = 80}) {
    final image = img.decodeImage(bytes);
    if (image == null) return base64Encode(bytes);

    // Trim whitespace borders first so product subject is properly framed
    final trimmed = trimWhitespace(image);

    final resized = (trimmed.width > maxWidth)
        ? img.copyResize(trimmed, width: maxWidth)
        : trimmed;
    final compressedBytes = img.encodeJpg(resized, quality: quality);
    return base64Encode(compressedBytes);
  }
}
