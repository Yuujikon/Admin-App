import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';
import '../models/shift_session.dart';
import '../services/receipt_printer_service.dart';
import '../utils/format.dart';
import '../utils/pricing_engine.dart';

/// Provider for managing Bluetooth thermal receipt printer connectivity and ESC/POS print jobs.
class PrinterProvider extends ChangeNotifier {
  BluetoothInfo? _device;
  bool _connected = false;
  bool _isConnecting = false;

  /// Connected Bluetooth device info.
  BluetoothInfo? get device => _device;

  /// True if thermal printer is currently connected.
  bool get connected => _connected;

  /// True if Bluetooth connection attempt is in progress.
  bool get isConnecting => _isConnecting;

  PrinterProvider() {
    Future.delayed(const Duration(seconds: 2), _init);
  }

  Future<void> _init() async {
    final bool isBluetoothEnabled =
        await PrintBluetoothThermal.bluetoothEnabled;
    if (!isBluetoothEnabled) {
      _connected = false;
      notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedMac = prefs.getString('last_printer_mac');

    if (savedMac != null) {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      try {
        final d = devices.firstWhere((d) => d.macAdress == savedMac);
        await connect(d);
      } catch (e) {
        _isConnecting = false;
        _connected = await PrintBluetoothThermal.connectionStatus;
        notifyListeners();
      }
    } else {
      _connected = await PrintBluetoothThermal.connectionStatus;
      notifyListeners();
    }
  }

  Future<List<BluetoothInfo>> getDevices() async {
    return await PrintBluetoothThermal.pairedBluetooths;
  }

  Future<void> connect(BluetoothInfo device) async {
    if (_isConnecting) return;
    _isConnecting = true;
    notifyListeners();

    try {
      final bool result = await PrintBluetoothThermal.connect(
              macPrinterAddress: device.macAdress)
          .timeout(const Duration(seconds: 10), onTimeout: () => false);

      if (result) {
        _device = device;
        _connected = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_printer_mac', device.macAdress);
      } else {
        _connected = false;
      }
    } catch (e) {
      _connected = false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
    _connected = false;
    _device = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_printer_mac');
    notifyListeners();
  }

  String _cleanPeso(String text) =>
      text.replaceAll('₱', 'P').replaceAll('\u20b1', 'P');

  // Helper to pad strings for manual left-right alignment (32 chars wide for 58mm)
  String _formatRow(String left, String right) {
    int space = 32 - (left.length + right.length);
    if (space < 1) space = 1;
    return left + (" " * space) + right;
  }

  Future<bool> printReceipt({
    required List<CartItem> items,
    required double total,
    required double cash,
    required double change,
    String? orderId,
    String? customerName,
    String orderType = "In-store",
    PricingBreakdown? breakdown,
  }) async {
    try {
      final bool isBluetoothEnabled =
          await PrintBluetoothThermal.bluetoothEnabled;
      if (!isBluetoothEnabled) {
        debugPrint("Bluetooth is disabled");
        return false;
      }

      bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) {
        debugPrint("Printer not connected, attempting to reconnect...");
        if (_device != null) {
          await PrintBluetoothThermal.connect(
                  macPrinterAddress: _device!.macAdress)
              .timeout(const Duration(seconds: 5), onTimeout: () => false);
          isConnected = await PrintBluetoothThermal.connectionStatus;
        }

        if (!isConnected) {
          final prefs = await SharedPreferences.getInstance();
          final savedMac = prefs.getString('last_printer_mac');
          if (savedMac != null) {
            await PrintBluetoothThermal.connect(macPrinterAddress: savedMac)
                .timeout(const Duration(seconds: 5), onTimeout: () => false);
            isConnected = await PrintBluetoothThermal.connectionStatus;
          }
        }

        if (!isConnected) {
          _connected = false;
          notifyListeners();
          return false;
        } else {
          _connected = true;
          notifyListeners();
        }
      }

      final bytes = await ReceiptPrinterService.generateReceiptBytes(
        items: items,
        total: total,
        cash: cash,
        change: change,
        invoiceId: orderId,
        cashierName: customerName ?? 'Cashier',
        paperWidthMm: 58,
        breakdown: breakdown,
      );

      final bool result = await PrintBluetoothThermal.writeBytes(bytes);
      debugPrint("Print result: $result");
      return result;
    } catch (e) {
      debugPrint("Error in printReceipt: $e");
      return false;
    }
  }

  Future<bool> printTest() async {
    try {
      bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) return false;
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      bytes += generator.reset();
      bytes += generator.text("PRINTER TEST OK",
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(3);
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      debugPrint("Error in printTest: $e");
      return false;
    }
  }

  Future<bool> printZReading({
    required ShiftSession shift,
    int totalTransactions = 0,
    int itemsSold = 0,
    int spoilageUnits = 0,
    bool isXReading = false,
  }) async {
    try {
      final bool isBluetoothEnabled =
          await PrintBluetoothThermal.bluetoothEnabled;
      if (!isBluetoothEnabled) return false;

      final bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) return false;

      final bytes = await ReceiptPrinterService.generateZReadingBytes(
        shift: shift,
        totalTransactions: totalTransactions,
        itemsSold: itemsSold,
        spoilageUnits: spoilageUnits,
        isXReading: isXReading,
      );

      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      debugPrint('Error printing Z-Reading: $e');
      return false;
    }
  }

  Future<bool> printBarcodeLabel({
    required String productName,
    required double price,
    required String barcode,
    int copies = 1,
    String storeName = "GDC SARI-SARI STORE",
    int paperWidthMm = 58,
  }) async {
    try {
      final bool isBluetoothEnabled =
          await PrintBluetoothThermal.bluetoothEnabled;
      if (!isBluetoothEnabled) return false;

      bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected && _device != null) {
        await PrintBluetoothThermal.connect(
                macPrinterAddress: _device!.macAdress)
            .timeout(const Duration(seconds: 5), onTimeout: () => false);
        isConnected = await PrintBluetoothThermal.connectionStatus;
      }

      if (!isConnected) {
        _connected = false;
        notifyListeners();
        return false;
      }

      final cleanBarcode = barcode.trim();
      if (cleanBarcode.isEmpty) return false;

      CapabilityProfile profile;
      try {
        profile = await CapabilityProfile.load();
      } catch (_) {
        final profiles = await CapabilityProfile.getAvailableProfiles();
        profile = await CapabilityProfile.load(name: profiles.first.toString());
      }

      final PaperSize paperSize =
          paperWidthMm == 80 ? PaperSize.mm80 : PaperSize.mm58;
      final int widthChars = paperWidthMm == 80 ? 48 : 32;
      final String sep = '=' * widthChars;

      final generator = Generator(paperSize, profile);
      List<int> bytes = [];

      for (int i = 0; i < copies; i++) {
        bytes.addAll(generator.reset());
        bytes.addAll(generator.text(sep,
            styles: const PosStyles(align: PosAlign.center)));
        bytes.addAll(generator.text(storeName,
            styles: const PosStyles(align: PosAlign.center, bold: true)));
        bytes.addAll(generator.text(productName,
            styles: const PosStyles(
                align: PosAlign.center,
                bold: true,
                height: PosTextSize.size1,
                width: PosTextSize.size1)));
        bytes.addAll(generator.text(_cleanPeso("PRICE: ${formatPeso(price)}"),
            styles: const PosStyles(
                align: PosAlign.center,
                bold: true,
                height: PosTextSize.size2,
                width: PosTextSize.size2)));
        bytes.addAll(generator.feed(1));

        try {
          bytes.addAll(generator.barcode(
            Barcode.code128(cleanBarcode.startsWith('{')
                ? cleanBarcode.split('')
                : "{B$cleanBarcode}".split('')),
            height: 60,
            width: 2,
            textPos: BarcodeText.below,
          ));
        } catch (_) {
          bytes.addAll(generator.text("PLU: $cleanBarcode",
              styles: const PosStyles(
                  align: PosAlign.center,
                  bold: true,
                  height: PosTextSize.size2)));
        }

        bytes.addAll(generator.text(sep,
            styles: const PosStyles(align: PosAlign.center)));
        bytes.addAll(generator.feed(3));
      }

      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      debugPrint("Error printing barcode label: $e");
      return false;
    }
  }
}
