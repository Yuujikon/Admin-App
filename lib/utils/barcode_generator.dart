import 'dart:math';

/// Utility for generating internal retail barcodes for items without manufacturer barcodes (PLU items).
class BarcodeGenerator {
  static final Random _random = Random();

  /// Generates a random 12-digit internal barcode starting with prefix '200'.
  /// Prefix '200' is the standard retail prefix reserved for in-store PLU items (e.g. fresh eggs, rice, produce).
  static String generateInternalBarcode() {
    // Prefix '200' + 9 random digits = 12 digits
    final StringBuffer buffer = StringBuffer('200');
    for (int i = 0; i < 9; i++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }

  /// Checks whether a barcode string is an internal PLU barcode starting with prefix '200'.
  static bool isInternalPluBarcode(String? barcode) {
    if (barcode == null) return false;
    final clean = barcode.trim();
    return clean.startsWith('200') && clean.length >= 12;
  }
}
