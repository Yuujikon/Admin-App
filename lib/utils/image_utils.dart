import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageUtils {
  /// Removes pixels that are "white enough" from the image.
  /// Converts the image to PNG to support transparency.
  static Uint8List? removeWhiteBackground(Uint8List bytes, {int threshold = 240}) {
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

    // Encode as PNG to keep transparency
    return Uint8List.fromList(img.encodePng(rgba8));
  }
}
