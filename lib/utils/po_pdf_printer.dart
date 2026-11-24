import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/purchase_order.dart';
import '../models/supplier.dart';

/// PDF Generation and Printing Utility for Purchase Orders.
class PoPdfPrinter {
  /// Builds the standardized Supplier Details PDF box shared across PO PDFs and Backorder/Notice PDFs.
  ///
  /// Strictly reads from a validated [SupplierSnapshot] so there are never `null` strings,
  /// blank gaps, or mismatched supplier fields across document types.
  static pw.Widget buildSupplierPdfBox(
    SupplierSnapshot snapshot, {
    String headerTitle = 'VENDOR / SUPPLIER DETAILS',
  }) {
    final cleanName = snapshot.supplierName.trim();
    final cleanContact = snapshot.contactPerson.trim();
    final cleanEmail = snapshot.email.trim();
    final cleanPhone = snapshot.phone.trim();
    final cleanAddress = snapshot.address.trim();
    final cleanTin = snapshot.tin.trim();
    final cleanTerms = snapshot.paymentTerms.trim();

    pw.Widget metaRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2.5),
        child: pw.RichText(
          text: pw.TextSpan(
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey900),
            children: [
              pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
              pw.TextSpan(text: value),
            ],
          ),
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            headerTitle,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.teal900,
              letterSpacing: 0.5,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            cleanName.isNotEmpty ? cleanName : 'Unassigned Supplier',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          if (cleanContact.isNotEmpty) metaRow('Contact Person', cleanContact),
          if (cleanEmail.isNotEmpty) metaRow('Email', cleanEmail),
          if (cleanPhone.isNotEmpty) metaRow('Phone', cleanPhone),
          if (cleanAddress.isNotEmpty) metaRow('Address', cleanAddress),
          if (cleanTin.isNotEmpty) metaRow('TIN / Business ID', cleanTin),
          if (cleanTerms.isNotEmpty) metaRow('Payment Terms', cleanTerms),
        ],
      ),
    );
  }

  /// Generates printable PDF document bytes for a given [PurchaseOrder].
  ///
  /// Reads supplier metadata strictly from [supplierSnapshot] (or [po.resolveSupplierSnapshot]).
  /// When [enforceValidation] is `true` (default), throws [SupplierValidationException] if mandatory
  /// supplier fields (`supplierName`, valid `email`, `phone`, `address`) are missing or malformed.
  static Future<Uint8List> generatePoPdf(
    PurchaseOrder po,
    Supplier? supplier, {
    SupplierSnapshot? supplierSnapshot,
    bool enforceValidation = true,
  }) async {
    final SupplierSnapshot snapshot =
        supplierSnapshot ?? po.resolveSupplierSnapshot(supplier);

    if (enforceValidation) {
      final validation = snapshot.validateForDispatch();
      if (!validation.isValid) {
        throw SupplierValidationException(validation);
      }
    }

    final pdf = pw.Document();
    final dateFormat = DateFormat('MMM dd, yyyy');
    final currencyFormat =
        NumberFormat.currency(symbol: 'PHP ', decimalDigits: 2);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header Title & Store Branding
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'GDC SARI-SARI STORE',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal800,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Store Management & Procurement',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: po.isBackOrder
                            ? PdfColors.orange100
                            : PdfColors.teal100,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        po.isBackOrder ? 'BACK ORDER' : 'PURCHASE ORDER',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: po.isBackOrder
                              ? PdfColors.orange900
                              : PdfColors.teal900,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'PO #: ${po.poNumber}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Order Date: ${dateFormat.format(po.orderDate)}',
                      style: const pw.TextStyle(
                        fontSize: 9.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 16),
            pw.Divider(color: PdfColors.grey300, thickness: 1),
            pw.SizedBox(height: 12),

            // Supplier Details (Validated Snapshot) & Order Information
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: buildSupplierPdfBox(snapshot),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(6),
                      border:
                          pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ORDER SUMMARY',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.teal900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Status: ${po.status.displayName}',
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.teal900,
                          ),
                        ),
                        pw.SizedBox(height: 2.5),
                        pw.Text(
                          'Order Reference: #${po.poNumber}',
                          style: const pw.TextStyle(fontSize: 9.5),
                        ),
                        if (po.parentPoId != null &&
                            po.parentPoId!.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2.5),
                          pw.Text(
                            'Parent PO Ref: #${po.parentPoId}',
                            style: const pw.TextStyle(fontSize: 9.5),
                          ),
                        ],
                        if (po.childPoId != null &&
                            po.childPoId!.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2.5),
                          pw.Text(
                            'Backorder Ref: ${po.childPoId}',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.orange900,
                            ),
                          ),
                        ],
                        pw.SizedBox(height: 2.5),
                        pw.Text(
                          'Total Line Items: ${po.items.length}',
                          style: const pw.TextStyle(fontSize: 9.5),
                        ),
                        pw.SizedBox(height: 2.5),
                        pw.Text(
                          'Total Ordered Units: ${po.totalOrderedQty}',
                          style: const pw.TextStyle(fontSize: 9.5),
                        ),
                        if (po.requestedDeliveryDate != null) ...[
                          pw.SizedBox(height: 2.5),
                          pw.Text(
                            'Req. Delivery: ${dateFormat.format(po.requestedDeliveryDate!)}',
                            style: const pw.TextStyle(fontSize: 9.5),
                          ),
                        ],
                        if (po.rfqId.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2.5),
                          pw.Text(
                            'RFQ Ref: #${po.rfqId}',
                            style: const pw.TextStyle(fontSize: 9.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            // Itemized Table
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(
                color: PdfColors.grey300,
                width: 0.5,
              ),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.teal800,
              ),
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                ),
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              headers: [
                '#',
                'Product Name',
                'SKU / Barcode',
                'Ordered Qty',
                'Unit Cost',
                'Subtotal',
              ],
              data: List.generate(po.items.length, (index) {
                final item = po.items[index];
                final subtotal = item.orderedQty * item.unitCost;
                return [
                  '${index + 1}',
                  item.productName,
                  item.sku.isNotEmpty ? item.sku : 'N/A',
                  '${item.orderedQty}',
                  currencyFormat.format(item.unitCost),
                  currencyFormat.format(subtotal),
                ];
              }),
            ),

            pw.SizedBox(height: 16),

            // Total Summary Box
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 240,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.teal50,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: PdfColors.teal300),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Total Items:',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                          pw.Text(
                            '${po.totalOrderedQty} units',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (snapshot.paymentTerms.trim().isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Payment Terms:',
                              style: const pw.TextStyle(fontSize: 9.5),
                            ),
                            pw.Text(
                              snapshot.paymentTerms.trim(),
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                      pw.SizedBox(height: 4),
                      pw.Divider(color: PdfColors.teal200, thickness: 0.5),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Grand Total:',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.teal900,
                            ),
                          ),
                          pw.Text(
                            currencyFormat.format(po.totalOrderedValue),
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.teal900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.Spacer(),

            // Footer Signatures & Terms
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Prepared By: Store Procurement Staff',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Authorized System Purchase Order',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal800,
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Directly sends the Purchase Order PDF to the system print manager.
  static Future<void> printPoPdf(
    BuildContext context,
    PurchaseOrder po,
    Supplier? supplier, {
    SupplierSnapshot? supplierSnapshot,
    bool enforceValidation = true,
  }) async {
    try {
      final pdfBytes = await generatePoPdf(
        po,
        supplier,
        supplierSnapshot: supplierSnapshot,
        enforceValidation: enforceValidation,
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'Purchase_Order_${po.poNumber}.pdf',
      );
    } on SupplierValidationException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Cannot generate PO PDF: ${e.validationResult.summaryMessage}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  /// Opens the native system share/save dialog for the Purchase Order PDF.
  static Future<void> sharePoPdf(
    BuildContext context,
    PurchaseOrder po,
    Supplier? supplier, {
    SupplierSnapshot? supplierSnapshot,
    bool enforceValidation = true,
  }) async {
    try {
      final pdfBytes = await generatePoPdf(
        po,
        supplier,
        supplierSnapshot: supplierSnapshot,
        enforceValidation: enforceValidation,
      );
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Purchase_Order_${po.poNumber}.pdf',
      );
    } on SupplierValidationException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Cannot share PO PDF: ${e.validationResult.summaryMessage}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  /// Shows a choice modal bottom sheet offering Preview, Print, or Share options.
  static Future<void> showPoPdfOptionsDialog(
    BuildContext context,
    PurchaseOrder po,
    Supplier? supplier, {
    SupplierSnapshot? supplierSnapshot,
  }) async {
    final snapshot = supplierSnapshot ?? po.resolveSupplierSnapshot(supplier);
    final validation = snapshot.validateForDispatch();

    await showModalBottomSheet(
      context: context,
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
                          'Purchase Order Copy',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'PO #${po.poNumber} — ${snapshot.supplierName}',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(ctx).colorScheme.onSurfaceVariant,
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
              if (!validation.isValid) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.red.shade800, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Incomplete supplier details: ${validation.summaryMessage}',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Option 1: Print PDF
              ListTile(
                enabled: validation.isValid,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                  ),
                ),
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  child: Icon(Icons.print_rounded, color: Colors.teal.shade800),
                ),
                title: const Text(
                  'Print Purchase Order',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Send directly to system or network printer',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  Navigator.pop(ctx);
                  await printPoPdf(
                    context,
                    po,
                    supplier,
                    supplierSnapshot: snapshot,
                  );
                },
              ),
              const SizedBox(height: 10),

              // Option 2: Share / Save PDF
              ListTile(
                enabled: validation.isValid,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                  ),
                ),
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: Icon(Icons.share_rounded, color: Colors.blue.shade800),
                ),
                title: const Text(
                  'Share or Save PDF Copy',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Send via Email, WhatsApp, or save to Device',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  Navigator.pop(ctx);
                  await sharePoPdf(
                    context,
                    po,
                    supplier,
                    supplierSnapshot: snapshot,
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
