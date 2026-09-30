import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../providers/order_provider.dart';
import 'pos_checkout_modal.dart';

/// Lightweight QR Scanner for Click & Collect Fast Checkout
class OrderQrScannerSheet extends StatefulWidget {
  const OrderQrScannerSheet({super.key});

  /// Opens the scanner modal and handles the complete QR checkout flow.
  static Future<void> scanAndCheckout(BuildContext context) async {
    final scannedCode = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => const OrderQrScannerSheet(),
    );

    if (scannedCode != null && scannedCode.isNotEmpty && context.mounted) {
      await processScannedOrderCode(context, scannedCode);
    }
  }

  @override
  State<OrderQrScannerSheet> createState() => _OrderQrScannerSheetState();
}

class _OrderQrScannerSheetState extends State<OrderQrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Customer QR Code',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.amber);
                  default:
                    return const Icon(Icons.flash_off, color: Colors.white);
                }
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_hasScanned) return;
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final raw = barcodes.first.rawValue;
                if (raw != null && raw.trim().isNotEmpty) {
                  _hasScanned = true;
                  Navigator.pop(context, raw.trim());
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Align customer QR code inside the frame to scan order.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Normalizes scanned QR string and triggers appropriate checkout or warning dialog.
Future<void> processScannedOrderCode(BuildContext context, String rawCode) async {
  final cleanCode = rawCode.trim();
  if (cleanCode.isEmpty) return;

  final orderProvider = context.read<OrderProvider>();
  final orders = orderProvider.orders;

  final extractedKey = _extractOrderIdKey(cleanCode).toLowerCase();

  PreOrder? matchedOrder;
  for (final o in orders) {
    final oId = o.orderId.toLowerCase().replaceAll('#', '');
    final docId = o.id.toLowerCase();
    if (oId == extractedKey || docId == extractedKey) {
      matchedOrder = o;
      break;
    }
  }

  if (matchedOrder == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order "$cleanCode" not found.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
    return;
  }

  // Handle Order Statuses
  if (matchedOrder.status == OrderStatus.pending ||
      matchedOrder.status == OrderStatus.staging) {
    // Show yellow warning modal if order is not bagged yet
    if (context.mounted) {
      await OrderNotBaggedDialog.show(context, matchedOrder);
    }
  } else if (matchedOrder.status == OrderStatus.ready) {
    // Immediately trigger PosCheckoutModal
    if (context.mounted) {
      await PosCheckoutModal.show(context, matchedOrder);
    }
  } else if (matchedOrder.status == OrderStatus.collected) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order #${matchedOrder.orderId} was ALREADY COLLECTED.'),
          backgroundColor: Colors.blue.shade700,
        ),
      );
    }
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order #${matchedOrder.orderId} status is ${matchedOrder.status.name.toUpperCase()}.'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
  }
}

String _extractOrderIdKey(String rawCode) {
  final clean = rawCode.trim();

  // Try JSON extraction
  if (clean.startsWith('{') && clean.endsWith('}')) {
    try {
      final map = jsonDecode(clean);
      if (map is Map) {
        if (map['orderId'] != null) return map['orderId'].toString().trim().replaceAll('#', '');
        if (map['id'] != null) return map['id'].toString().trim().replaceAll('#', '');
        if (map['order_id'] != null) return map['order_id'].toString().trim().replaceAll('#', '');
      }
    } catch (_) {}
  }

  // Regex match for GDC-XXXX pattern
  final gdcMatch = RegExp(r'GDC-\d{4,6}', caseSensitive: false).firstMatch(clean);
  if (gdcMatch != null) {
    return gdcMatch.group(0)!.toUpperCase().replaceAll('#', '');
  }

  return clean.replaceAll('#', '');
}
