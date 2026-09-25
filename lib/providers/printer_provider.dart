import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../utils/format.dart';
import '../utils/pricing_engine.dart';

class PrinterProvider extends ChangeNotifier {
  BluetoothInfo? _device;
  bool _connected = false;
  bool _isConnecting = false;

  BluetoothInfo? get device => _device;
  bool get connected => _connected;
  bool get isConnecting => _isConnecting;

  PrinterProvider() {
    Future.delayed(const Duration(seconds: 2), _init);
  }

  Future<void> _init() async {
    final bool isBluetoothEnabled = await PrintBluetoothThermal.bluetoothEnabled;
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
      final bool result = await PrintBluetoothThermal.connect(macPrinterAddress: device.macAdress)
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

  String _cleanPeso(String text) => text.replaceAll('₱', 'P').replaceAll('\u20b1', 'P');

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
      final bool isBluetoothEnabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!isBluetoothEnabled) {
        debugPrint("Bluetooth is disabled");
        return false;
      }

      bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) {
        debugPrint("Printer not connected, attempting to reconnect...");
        // If we have a saved device, try one quick reconnect
        if (_device != null) {
          await PrintBluetoothThermal.connect(macPrinterAddress: _device!.macAdress)
              .timeout(const Duration(seconds: 5), onTimeout: () => false);
          isConnected = await PrintBluetoothThermal.connectionStatus;
        }
        
        if (!isConnected) {
          _connected = false;
          notifyListeners();
          return false;
        }
      }

      List<int> bytes = [];
      CapabilityProfile profile;
      try {
        profile = await CapabilityProfile.load();
      } catch (e) {
        debugPrint("Failed to load capability profile: $e");
        // Fallback or rethrow? Let's try to proceed with default if possible
        // Actually ESC/POS often works with a simple generator if profile fails
        return false;
      }
      
      final generator = Generator(PaperSize.mm58, profile);

      bytes += generator.reset();
      
      // ── Header ───────────────────────────────────────────────────────────
      bytes += generator.text("GDC SARI-SARI STORE", styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text("123 Barangay St, City Name", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text("Tel: (02) 888-1234", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center));
      
      if (orderId != null) {
        bytes += generator.text(_formatRow("Receipt #:", orderId.toUpperCase().substring(0, 8)));
      }
      // Only include customer name for Pre-Orders or Pickups, hide for standard In-Store POS sales
      if (customerName != null && orderType != "In-store") {
        bytes += generator.text(_formatRow("Customer:", customerName));
      }
      bytes += generator.text(_formatRow("Order Type:", orderType));
      bytes += generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center));

      // ── Items ────────────────────────────────────────────────────────────
      // Column headers
      bytes += generator.text("ITEM            QTY     TOTAL");
      bytes += generator.text("--------------------------------");

      for (var item in items) {
        // Line 1: Item Name
        String name = item.name;
        if (name.length > 32) name = name.substring(0, 29) + "...";
        bytes += generator.text(name);
        
        // Line 2: Details (Qty @ Price)   Total
        final qtyPart = "${item.qty} x ${_cleanPeso(formatPeso(item.price))}";
        final totalPart = _cleanPeso(formatPeso(item.price * item.qty));
        bytes += generator.text(_formatRow(qtyPart, totalPart));
      }

      bytes += generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center));

      // ── Summary ──────────────────────────────────────────────────────────
      final int totalQty = items.fold(0, (sum, item) => sum + item.qty);
      bytes += generator.text(_formatRow("TOTAL QUANTITY:", totalQty.toString()));
      bytes += generator.text(_formatRow("TOTAL AMOUNT:", _cleanPeso(formatPeso(total))), styles: const PosStyles(bold: true, height: PosTextSize.size2));
      bytes += generator.feed(1);
      bytes += generator.text(_formatRow("CASH TENDERED:", _cleanPeso(formatPeso(cash))));
      bytes += generator.text(_formatRow("CHANGE DUE:", _cleanPeso(formatPeso(change))), styles: const PosStyles(bold: true));
      bytes += generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center));
      
      // ── Footer ───────────────────────────────────────────────────────────
      bytes += generator.text("THANK YOU FOR SHOPPING!", styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.feed(1);
      bytes += generator.text("Please keep this receipt", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text("for returns/refunds within", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text("24 hours. God Bless!", styles: const PosStyles(align: PosAlign.center));
      
      if (orderId != null) {
        bytes += generator.feed(1);
        bytes += generator.text("Ref: $orderId", styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size1));
      }
      
      bytes += generator.feed(4); // Extra feed so you can tear it manually
      
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
      bytes += generator.text("PRINTER TEST OK", styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(3);
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      debugPrint("Error in printTest: $e");
      return false;
    }
  }
}
