import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../utils/format.dart';

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

  String _cleanPeso(String text) => text.replaceAll('₱', 'P');

  // Helper to pad strings for manual left-right alignment (32 chars wide for 58mm)
  String _formatRow(String left, String right) {
    int space = 32 - (left.length + right.length);
    if (space < 1) space = 1;
    return left + (" " * space) + right;
  }

  Future<void> printReceipt({
    required List<CartItem> items,
    required double total,
    required double cash,
    required double change,
    String? orderId,
  }) async {
    bool isConnected = await PrintBluetoothThermal.connectionStatus;
    if (!isConnected) return;

    List<int> bytes = [];
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);

    bytes += generator.reset();
    
    // BASIC TEXT ONLY - HIGH COMPATIBILITY
    bytes += generator.text("GDC SARI-SARI STORE", styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center));
    
    final date = DateFormat('MM/dd/yy HH:mm').format(DateTime.now());
    bytes += generator.text("Date: $date");
    if (orderId != null) {
      bytes += generator.text("ID: ${orderId.length > 8 ? orderId.substring(0, 8) : orderId}");
    }
    bytes += generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center));

    for (var item in items) {
      final name = item.name.length > 20 ? '${item.name.substring(0, 17)}...' : item.name;
      bytes += generator.text(_formatRow("${item.qty}x $name", _cleanPeso(formatPeso(item.price * item.qty))));
    }

    bytes += generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text(_formatRow("TOTAL", _cleanPeso(formatPeso(total))), styles: const PosStyles(bold: true));
    bytes += generator.text(_formatRow("CASH", _cleanPeso(formatPeso(cash))));
    bytes += generator.text(_formatRow("CHANGE", _cleanPeso(formatPeso(change))));
    bytes += generator.text("--------------------------------", styles: const PosStyles(align: PosAlign.center));
    
    bytes += generator.text("THANK YOU!", styles: const PosStyles(align: PosAlign.center));
    
    bytes += generator.feed(4); // Extra feed so you can tear it manually
    await PrintBluetoothThermal.writeBytes(bytes);
  }

  Future<void> printTest() async {
    bool isConnected = await PrintBluetoothThermal.connectionStatus;
    if (!isConnected) return;
    List<int> bytes = [];
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    bytes += generator.reset();
    bytes += generator.text("PRINTER TEST OK", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(3);
    await PrintBluetoothThermal.writeBytes(bytes);
  }
}
