import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../models/order.dart';
import '../providers/printer_provider.dart';
import '../services/receipt_printer_service.dart';
import '../utils/format.dart';

/// Packing Slip PDF Printing Helper for GDC Sari-Sari Admin.
class PackingSlipPrinter {
  /// Displays a print destination chooser dialog allowing staff to decide where to send the packing slip.
  static Future<void> showPrintDestinationDialog(
      BuildContext context, List<PreOrder> orders) async {
    if (orders.isEmpty) return;

    final printerProvider =
        Provider.of<PrinterProvider>(context, listen: false);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Theme.of(ctx).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.print_rounded,
                    color: Theme.of(ctx).colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Print Destination',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        orders.length == 1
                            ? 'Packing Slip #${orders.first.orderId}'
                            : '${orders.length} Selected Orders',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Option 1: System Print / Save as PDF
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                    color: Theme.of(ctx).colorScheme.outlineVariant),
              ),
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade50,
                child: Icon(Icons.picture_as_pdf_rounded,
                    color: Colors.blue.shade800),
              ),
              title: const Text('System Print / Save as PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text(
                  'Send to Wi-Fi printer, Bluetooth, or export PDF file',
                  style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.pop(ctx);
                await printBulkPackingSlips(orders);
              },
            ),
            const SizedBox(height: 10),

            // Option 2: Live PDF Preview & Print
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                    color: Theme.of(ctx).colorScheme.outlineVariant),
              ),
              leading: CircleAvatar(
                backgroundColor: Colors.green.shade50,
                child: Icon(Icons.preview_rounded, color: Colors.green.shade800),
              ),
              title: const Text('Preview 80mm Slip First',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text(
                  'Inspect layout before printing or exporting',
                  style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                showPdfPreviewModal(context, orders);
              },
            ),
            const SizedBox(height: 10),

            // Option 3: Bluetooth Thermal Printer - 80mm Roll
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                    color: Theme.of(ctx).colorScheme.outlineVariant),
              ),
              leading: CircleAvatar(
                backgroundColor: Colors.orange.shade50,
                child: Icon(Icons.print_rounded,
                    color: Colors.orange.shade900),
              ),
              title: Text(
                printerProvider.connected
                    ? 'Bluetooth Thermal Printer (80mm Wide Roll)'
                    : 'Bluetooth Thermal Printer - 80mm Roll',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(
                printerProvider.connected
                    ? 'Print 80mm (48 columns) ESC/POS pick list (${printerProvider.device?.name})'
                    : 'Send 80mm packing slip bytes directly to paired thermal printer',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.pop(ctx);
                await _printThermalDirect(context, orders, paperWidthMm: 80);
              },
            ),
            const SizedBox(height: 10),

            // Option 4: Bluetooth Thermal Printer - 58mm Roll
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                    color: Theme.of(ctx).colorScheme.outlineVariant),
              ),
              leading: CircleAvatar(
                backgroundColor: Colors.amber.shade50,
                child: Icon(Icons.receipt_long_rounded,
                    color: Colors.amber.shade900),
              ),
              title: Text(
                printerProvider.connected
                    ? 'Bluetooth Thermal Printer (58mm Compact Roll)'
                    : 'Bluetooth Thermal Printer - 58mm Roll',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(
                printerProvider.connected
                    ? 'Print 58mm (32 columns) ESC/POS pick list (${printerProvider.device?.name})'
                    : 'Send 58mm compact packing slip bytes directly to paired thermal printer',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.pop(ctx);
                await _printThermalDirect(context, orders, paperWidthMm: 58);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

  static Future<void> _printThermalDirect(
      BuildContext context, List<PreOrder> orders,
      {required int paperWidthMm}) async {
    final printerProvider =
        Provider.of<PrinterProvider>(context, listen: false);

    if (printerProvider.connected) {
      for (final order in orders) {
        final bytes = await ReceiptPrinterService.generatePackingSlipBytes(
            order,
            paperWidthMm: paperWidthMm);
        await PrintBluetoothThermal.writeBytes(bytes);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Sent ${orders.length} packing slips (${paperWidthMm}mm) to Bluetooth printer! 🖨️'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      await printBulkPackingSlips(orders);
    }
  }

  /// Displays a live PDF Preview modal for single or bulk packing slips.
  static Future<void> showPdfPreviewModal(
      BuildContext context, List<PreOrder> orders) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: Text(orders.length == 1
              ? 'Packing Slip Preview #${orders.first.orderId}'
              : 'Bulk Packing Slips Preview (${orders.length})'),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        body: PdfPreview(
          build: (format) => buildPackingSlipPdf(orders),
          allowPrinting: true,
          allowSharing: true,
        ),
      ),
    );
  }

  /// Triggers system print or thermal layout for a single pre-order packing slip.
  static Future<void> printPackingSlip(PreOrder order) async {
    final pdfBytes = await buildPackingSlipPdf([order]);
    await Printing.layoutPdf(
      onLayout: (_) async => pdfBytes,
      name: 'Packing_Slip_${order.orderId}.pdf',
    );
  }

  /// Triggers system print for multiple pre-order packing slips in bulk.
  static Future<void> printBulkPackingSlips(List<PreOrder> orders) async {
    if (orders.isEmpty) return;
    final pdfBytes = await buildPackingSlipPdf(orders);
    await Printing.layoutPdf(
      onLayout: (_) async => pdfBytes,
      name: 'Bulk_Packing_Slips_${orders.length}_Orders.pdf',
    );
  }

  /// Builds a PDF Document containing 80mm thermal/compact paper format packing slips.
  static Future<Uint8List> buildPackingSlipPdf(List<PreOrder> orders) async {
    final pdf = pw.Document();

    for (final order in orders) {
      final totalQty = order.items.fold(0, (sum, i) => sum + i.qty);
      final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(order.createdAt);

      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(
            80 * PdfPageFormat.mm,
            double.infinity,
            marginAll: 4 * PdfPageFormat.mm,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                // Store Header
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'GDC SARI-SARI STORE',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'ORDER FULFILLMENT PICK LIST',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Divider(thickness: 1),
                    ],
                  ),
                ),
                pw.SizedBox(height: 4),

                // Order Header Details
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('ORDER ID:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('#${order.orderId}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('CUSTOMER:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text(order.customerName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('PHONE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      pw.Text(order.customerPhone!, style: pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('DATE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text(dateStr, style: pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),

                // Items Pick Checklist
                pw.Text(
                  'ITEMS TO PACK ($totalQty items):',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                ),
                pw.SizedBox(height: 4),

                ...order.items.map((item) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('[  ] ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.SizedBox(
                          width: 24,
                          child: pw.Text('${item.qty}x', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            item.name,
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Text(
                          formatPeso(item.price * item.qty),
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  );
                }),

                pw.SizedBox(height: 6),
                pw.Divider(thickness: 1),

                // Total Value
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL VALUE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text(formatPeso(order.total), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                  ],
                ),
                pw.SizedBox(height: 10),

                // Signature & Audit Box
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Packed By: __________________________', style: const pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(height: 4),
                      pw.Text('Checked By: ________________________', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),

                // Tear / Cut Divider for Bulk Roll Printing
                if (orders.length > 1) ...[
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          '- - - - - - - - - - - - - - - - - - - - - - - - - - -',
                          style: pw.TextStyle(color: PdfColors.grey600, fontSize: 8),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'CUT HERE',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                            color: PdfColors.grey800,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '- - - - - - - - - - - - - - - - - - - - - - - - - - -',
                          style: pw.TextStyle(color: PdfColors.grey600, fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                ],
                pw.SizedBox(height: 12),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }
}
