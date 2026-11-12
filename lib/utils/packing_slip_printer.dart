import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order.dart';
import '../utils/format.dart';

/// Packing Slip PDF Printing Helper for GDC Sari-Sari Admin.
class PackingSlipPrinter {
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
                if (order.customerPhone.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('PHONE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      pw.Text(order.customerPhone, style: pw.TextStyle(fontSize: 9)),
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
                          formatPeso(item.unitPrice * item.qty),
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
