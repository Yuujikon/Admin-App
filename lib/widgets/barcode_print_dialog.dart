import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/product.dart';
import '../providers/printer_provider.dart';
import '../utils/barcode_generator.dart';
import '../utils/format.dart';
import '../config/theme.dart';

/// A dialog that allows staff/admin to preview and print PLU barcode sticker labels for items.
class BarcodePrintDialog extends StatefulWidget {
  final String productName;
  final double price;
  final String barcode;

  const BarcodePrintDialog({
    super.key,
    required this.productName,
    required this.price,
    required this.barcode,
  });

  /// Convenience helper to launch dialog for a [Product]
  static Future<void> show(BuildContext context, Product product) async {
    final barcode = (product.barcode != null && product.barcode!.isNotEmpty)
        ? product.barcode!
        : BarcodeGenerator.generateInternalBarcode();

    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => BarcodePrintDialog(
        productName: product.name,
        price: product.price,
        barcode: barcode,
      ),
    );
  }

  /// Convenience helper to launch dialog for arbitrary item details (e.g. from Add/Edit sheet)
  static Future<void> showCustom(
    BuildContext context, {
    required String productName,
    required double price,
    required String? barcode,
  }) async {
    final effectiveBarcode = (barcode != null && barcode.isNotEmpty)
        ? barcode
        : BarcodeGenerator.generateInternalBarcode();

    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => BarcodePrintDialog(
        productName: productName.isEmpty ? 'Item Label' : productName,
        price: price,
        barcode: effectiveBarcode,
      ),
    );
  }

  @override
  State<BarcodePrintDialog> createState() => _BarcodePrintDialogState();
}

class _BarcodePrintDialogState extends State<BarcodePrintDialog> {
  int _copies = 1;
  bool _isThermalPrinting = false;

  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterProvider>();
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: GdcColors.emeraldPrimary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.qr_code_2_rounded,
                      color: GdcColors.emeraldPrimary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Print Item PLU Barcode',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        'Generate sticker labels for inventory items',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Item Details Summary Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.productName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              'PLU / Barcode: ',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              widget.barcode,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatPeso(widget.price),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Copies Selector & Presets
            Row(
              children: [
                const Text(
                  'Copies / Sticker Count:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed:
                      _copies > 1 ? () => setState(() => _copies--) : null,
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '$_copies',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => setState(() => _copies++),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Presets row: 1, 5, 10, 20, 50
            Row(
              children: [1, 5, 10, 20, 50].map((num) {
                final isSelected = _copies == num;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$num'),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _copies = num),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Real-Time PDF Print Preview Container
            SizedBox(
              height: 160,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PdfPreview(
                  build: (format) => _buildPdfLabel(format),
                  allowPrinting: false,
                  allowSharing: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  dynamicLayout: false,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Printing Action Buttons
            Row(
              children: [
                // Thermal Printer Button (if thermal printer connected)
                if (printer.connected)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isThermalPrinting
                          ? null
                          : () async {
                              setState(() => _isThermalPrinting = true);
                              final ok = await printer.printBarcodeLabel(
                                productName: widget.productName,
                                price: widget.price,
                                barcode: widget.barcode,
                                copies: _copies,
                              );
                              if (mounted) {
                                setState(() => _isThermalPrinting = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? 'Printed $_copies label(s) to thermal printer! 🖨️'
                                        : 'Failed to print label to thermal printer.'),
                                    backgroundColor:
                                        ok ? Colors.green : Colors.red,
                                  ),
                                );
                              }
                            },
                      icon: _isThermalPrinting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bluetooth_audio_rounded, size: 18),
                      label: Text('THERMAL (${_copies}x)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                if (printer.connected) const SizedBox(width: 12),

                // System Print / PDF Sticker Print Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final pdfBytes = await _buildPdfLabel(PdfPageFormat.a4);
                      await Printing.layoutPdf(
                        onLayout: (_) async => pdfBytes,
                        name: 'PLU_Barcode_${widget.barcode}',
                      );
                    },
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('PRINT STICKERS / PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GdcColors.emeraldPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> _buildPdfLabel(PdfPageFormat format) async {
    final pdf = pw.Document();

    // Standard 50mm x 30mm sticker label size
    const labelWidthMm = 50.0;
    const labelHeightMm = 30.0;

    final pageFormat = PdfPageFormat(
      labelWidthMm * PdfPageFormat.mm,
      labelHeightMm * PdfPageFormat.mm,
      marginAll: 2 * PdfPageFormat.mm,
    );

    for (int i = 0; i < _copies; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (pw.Context ctx) {
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'GDC SARI-SARI STORE',
                    style: pw.TextStyle(
                      fontSize: 5.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    widget.productName,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    formatPeso(widget.price),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: widget.barcode,
                      drawText: true,
                      textStyle: const pw.TextStyle(fontSize: 6),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return pdf.save();
  }
}
