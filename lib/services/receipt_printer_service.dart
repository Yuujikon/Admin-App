import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../models/shift_session.dart';
import '../utils/format.dart';
import '../utils/pricing_engine.dart';

class ReceiptPrinterService {
  static String cleanPeso(String text) => text.replaceAll('₱', 'P').replaceAll('\u20b1', 'P');

  /// Formats a two-column line for 58mm (32 chars) or 80mm (48 chars) thermal paper
  static String formatLine(String left, String right, {int width = 32}) {
    int space = width - (left.length + right.length);
    if (space < 1) space = 1;
    return left + (" " * space) + right;
  }

  /// Generates ESC/POS byte commands for 58mm or 80mm thermal receipt printers,
  /// complete with ESC/POS formatting, cash drawer kick pulse (ESC p), and paper cut (GS V).
  static Future<List<int>> generateReceiptBytes({
    required List<CartItem> items,
    required double total,
    required double cash,
    required double change,
    String? invoiceId,
    String cashierName = 'Cashier',
    String storeName = 'GDC SARI-SARI STORE',
    String storeAddress = 'Angeles City, Pampanga, PH',
    String storePhone = 'Tel: (045) 123-4567',
    int paperWidthMm = 58,
    PricingBreakdown? breakdown,
  }) async {
    final List<int> bytes = [];
    final PaperSize paperSize = paperWidthMm == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final int widthChars = paperWidthMm == 80 ? 48 : 32;

    CapabilityProfile profile;
    try {
      profile = await CapabilityProfile.load();
    } catch (_) {
      final profiles = await CapabilityProfile.getAvailableProfiles();
      profile = await CapabilityProfile.load(name: profiles.first.toString());
    }

    final generator = Generator(paperSize, profile);

    // 1. Hardware Reset
    bytes.addAll(generator.reset());

    // 2. Cash Drawer Kick Pulse (ESC p 0 25 250 - Kick pulse to open cash drawer)
    bytes.addAll([0x1B, 0x70, 0x00, 0x19, 0xFA]);

    // 3. Header Section
    bytes.addAll(generator.text("================================", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text(storeName, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size1, width: PosTextSize.size1)));
    bytes.addAll(generator.text(storeAddress, styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text(storePhone, styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text("================================", styles: const PosStyles(align: PosAlign.center)));

    final now = DateTime.now();
    bytes.addAll(generator.text(formatLine("Date: ${now.toString().substring(0, 10)}", "Time: ${now.toString().substring(11, 16)}", width: widthChars)));
    bytes.addAll(generator.text(formatLine("Invoice:", invoiceId != null ? invoiceId.substring(0, invoiceId.length > 10 ? 10 : invoiceId.length) : 'TX-ONLINE', width: widthChars)));
    bytes.addAll(generator.text(formatLine("Cashier:", cashierName, width: widthChars)));
    bytes.addAll(generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center)));

    // 4. Line Items Table
    bytes.addAll(generator.text(formatLine("ITEM", "QTY   PRICE", width: widthChars), styles: const PosStyles(bold: true)));
    bytes.addAll(generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center)));

    for (final item in items) {
      String name = item.name;
      if (name.length > widthChars) name = '${name.substring(0, widthChars - 3)}...';
      bytes.addAll(generator.text(name));

      final qtyPricePart = "${item.qty} x ${cleanPeso(formatPeso(item.price))}";
      final totalPart = cleanPeso(formatPeso(item.price * item.qty));
      bytes.addAll(generator.text(formatLine(qtyPricePart, totalPart, width: widthChars)));
    }

    bytes.addAll(generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center)));

    // 5. Total & Payment Summary
    final int totalItemsSold = items.fold(0, (sum, i) => sum + i.qty);
    bytes.addAll(generator.text(formatLine("TOTAL ITEMS:", totalItemsSold.toString(), width: widthChars)));
    bytes.addAll(generator.text(formatLine("TOTAL AMOUNT:", cleanPeso(formatPeso(total)), width: widthChars), styles: const PosStyles(bold: true, height: PosTextSize.size2)));
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.text(formatLine("TENDER TYPE:", cash > 0 ? "CASH" : "GCASH/DIGITAL", width: widthChars)));
    bytes.addAll(generator.text(formatLine("AMOUNT TENDERED:", cleanPeso(formatPeso(cash > 0 ? cash : total)), width: widthChars)));
    bytes.addAll(generator.text(formatLine("CHANGE:", cleanPeso(formatPeso(change)), width: widthChars), styles: const PosStyles(bold: true)));
    bytes.addAll(generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center)));

    // 6. Footer & Auto-Cut
    bytes.addAll(generator.text("Salamat sa Pagbili!", styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.text("Please come again.", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text("================================", styles: const PosStyles(align: PosAlign.center)));

    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    return bytes;
  }

  /// Generates ESC/POS byte commands for an Official End-of-Shift Z-Reading or Mid-day X-Reading Report.
  static Future<List<int>> generateZReadingBytes({
    required ShiftSession shift,
    int totalTransactions = 0,
    int itemsSold = 0,
    int spoilageUnits = 0,
    String storeName = 'GDC SARI-SARI STORE',
    int paperWidthMm = 58,
    bool isXReading = false,
  }) async {
    final List<int> bytes = [];
    final PaperSize paperSize = paperWidthMm == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final int widthChars = paperWidthMm == 80 ? 48 : 32;

    CapabilityProfile profile;
    try {
      profile = await CapabilityProfile.load();
    } catch (_) {
      final profiles = await CapabilityProfile.getAvailableProfiles();
      profile = await CapabilityProfile.load(name: profiles.first.toString());
    }

    final generator = Generator(paperSize, profile);

    bytes.addAll(generator.reset());
    bytes.addAll(generator.text("================================", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text(storeName, styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.text(isXReading ? "MID-DAY X-READING REPORT" : "OFFICIAL SHIFT Z-READING", styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.text("================================", styles: const PosStyles(align: PosAlign.center)));

    final shiftIdStr = shift.id.length >= 8 ? shift.id.substring(0, 8).toUpperCase() : shift.id;
    bytes.addAll(generator.text(formatLine("Shift ID:", "SHIFT-$shiftIdStr", width: widthChars)));
    bytes.addAll(generator.text(formatLine("Cashier:", shift.cashierName, width: widthChars)));
    bytes.addAll(generator.text(formatLine("Opened:", DateFormat('MM/dd/yy hh:mm a').format(shift.openedAt), width: widthChars)));
    if (shift.closedAt != null) {
      bytes.addAll(generator.text(formatLine("Closed:", DateFormat('MM/dd/yy hh:mm a').format(shift.closedAt!), width: widthChars)));
    }
    bytes.addAll(generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text("FINANCIAL BREAKDOWN", styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center)));

    bytes.addAll(generator.text(formatLine("Opening Cash Float:", cleanPeso(formatPeso(shift.openingFloat)), width: widthChars)));
    bytes.addAll(generator.text(formatLine("Cash Sales Total:", cleanPeso(formatPeso(shift.cashSales)), width: widthChars)));
    bytes.addAll(generator.text(formatLine("GCash Sales Total:", cleanPeso(formatPeso(shift.gcashSales)), width: widthChars)));
    bytes.addAll(generator.text(formatLine("Mid-Shift Cash Drops:", "-${cleanPeso(formatPeso(shift.totalCashDrops))}", width: widthChars)));
    bytes.addAll(generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center)));

    bytes.addAll(generator.text(formatLine("EXPECTED DRAWER CASH:", cleanPeso(formatPeso(shift.expectedCash)), width: widthChars), styles: const PosStyles(bold: true)));
    if (shift.actualCashCounted != null) {
      bytes.addAll(generator.text(formatLine("ACTUAL CASH COUNTED:", cleanPeso(formatPeso(shift.actualCashCounted!)), width: widthChars), styles: const PosStyles(bold: true)));
      
      final variance = shift.cashDifference;
      String varianceLabel = "P0.00 (BALANCED)";
      if (variance < 0) {
        varianceLabel = "-${cleanPeso(formatPeso(variance.abs()))} (SHORT)";
      } else if (variance > 0) {
        varianceLabel = "+${cleanPeso(formatPeso(variance))} (OVER)";
      }
      bytes.addAll(generator.text(formatLine("CASH VARIANCE:", varianceLabel, width: widthChars), styles: const PosStyles(bold: true)));
    }

    bytes.addAll(generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text("TRANSACTION AUDIT", styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center)));

    bytes.addAll(generator.text(formatLine("Total Transactions:", totalTransactions.toString(), width: widthChars)));
    bytes.addAll(generator.text(formatLine("Items Sold:", itemsSold.toString(), width: widthChars)));
    bytes.addAll(generator.text(formatLine("Spoilage / Loss Units:", spoilageUnits.toString(), width: widthChars)));

    bytes.addAll(generator.text("================================", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.text("Cashier Signature: _____________", styles: const PosStyles(align: PosAlign.left)));
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.text("Manager Signature: _____________", styles: const PosStyles(align: PosAlign.left)));
    bytes.addAll(generator.text("================================", styles: const PosStyles(align: PosAlign.center)));

    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    return bytes;
  }
}
