import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/purchase_order.dart';
import '../models/receiving_record.dart';
import '../models/supplier.dart';
import 'po_pdf_printer.dart';

/// Type of supplier notice document.
enum NoticeType {
  backorder,
  cancellation,
  fullDelivery,
}

extension NoticeTypeExtension on NoticeType {
  String get title {
    switch (this) {
      case NoticeType.backorder:
        return 'PARTIAL DELIVERY & BACK-ORDER NOTICE';
      case NoticeType.cancellation:
        return 'REMAINING ORDER CANCELLATION NOTICE';
      case NoticeType.fullDelivery:
        return 'DELIVERY RECEIPT & FULFILLMENT CONFIRMATION';
    }
  }

  String get shortCode {
    switch (this) {
      case NoticeType.backorder:
        return 'BON';
      case NoticeType.cancellation:
        return 'CN';
      case NoticeType.fullDelivery:
        return 'DRC';
    }
  }
}

/// Utility for generating, printing, and sharing formal Supplier Notices (Back-Orders, Deliveries & Cancellations).
class NoticePdfPrinter {
  /// Generates PDF document bytes for a formal Supplier Notice.
  ///
  /// Strictly reads supplier fields from [supplierSnapshot] (or [po.resolveSupplierSnapshot])
  /// and shares the exact same Supplier Details layout as [PoPdfPrinter].
  /// When [enforceValidation] is `true` (default), throws [SupplierValidationException]
  /// if mandatory supplier fields (`supplierName`, valid `email`, `phone`, `address`) are invalid.
  static Future<Uint8List> generateSupplierNoticePdf({
    required PurchaseOrder po,
    Supplier? supplier,
    SupplierSnapshot? supplierSnapshot,
    required NoticeType noticeType,
    String? cancellationReason,
    List<ReceivingItem>? itemsReceived,
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

    final String noticeRefNo =
        '${noticeType.shortCode}-${po.poNumber}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final DateTime noticeDate = DateTime.now();

    final isBackorder = noticeType == NoticeType.backorder;
    final isFullDelivery = noticeType == NoticeType.fullDelivery;
    final PdfColor headerColor = isFullDelivery
        ? PdfColors.teal900
        : isBackorder
            ? PdfColors.orange900
            : PdfColors.red900;
    final PdfColor badgeBgColor = isFullDelivery
        ? PdfColors.teal100
        : isBackorder
            ? PdfColors.orange100
            : PdfColors.red100;

    final String backorderRefId =
        (po.childPoId != null && po.childPoId!.trim().isNotEmpty)
            ? po.childPoId!.trim()
            : 'BO-${po.poNumber}';

    final String tableSectionTitle = isFullDelivery
        ? 'ITEMIZED DELIVERY FULFILLMENT SUMMARY'
        : isBackorder
            ? 'ITEMIZED BACK-ORDER SUMMARY'
            : 'ITEMIZED CANCELLATION SUMMARY';

    final List<String> tableHeaders = isFullDelivery
        ? [
            'Item Name',
            'SKU',
            'Ordered',
            'Accepted',
            'Rejected',
            'Unit Cost',
            'Line Total',
          ]
        : isBackorder
            ? [
                'Item Name',
                'SKU',
                'Ordered',
                'Accepted',
                'Rejected',
                'Back-Ordered',
                'Unit Cost',
              ]
            : [
                'Item Name',
                'SKU',
                'Ordered',
                'Received',
                'Cancelled Qty',
                'Reason',
                'Unit Cost',
              ];

    final String remarksText = isFullDelivery
        ? 'This confirmation verifies that Purchase Order #${po.poNumber} has been fully delivered, inspected, and accepted into GDC Sari-Sari Store inventory.'
        : isBackorder
            ? 'This notice confirms that partial delivery was received for PO #${po.poNumber} (Backorder Ref: $backorderRefId). Unfulfilled quantities listed above remain on active Back-Order and are expected on the next delivery.'
            : 'This notice confirms the formal cancellation of unfulfilled items for PO #${po.poNumber}. Billing has been updated to reflect only physical accepted deliveries.';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // ── Store Header & Notice Badge ─────────────────────────
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
                      'Procurement & Inventory Management',
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
                        color: badgeBgColor,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        noticeType.title,
                        style: pw.TextStyle(
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                          color: headerColor,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Notice Ref: $noticeRefNo',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                      ),
                    ),
                    pw.Text(
                      'Notice Date: ${dateFormat.format(noticeDate)}',
                      style: const pw.TextStyle(
                        fontSize: 9,
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

            // ── Supplier (Synchronized Snapshot Box) & Reference Info Section ───
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: PoPdfPrinter.buildSupplierPdfBox(
                    snapshot,
                    headerTitle: 'VENDOR / SUPPLIER DETAILS',
                  ),
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
                          'ORDER REFERENCE',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.teal900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Original PO #: ${po.poNumber}',
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (isBackorder || po.isBackOrder) ...[
                          pw.SizedBox(height: 2.5),
                          pw.Text(
                            'Backorder Ref: $backorderRefId',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.orange900,
                            ),
                          ),
                        ],
                        if (po.parentPoId != null &&
                            po.parentPoId!.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2.5),
                          pw.Text(
                            'Parent PO Ref: #${po.parentPoId}',
                            style: const pw.TextStyle(fontSize: 9.5),
                          ),
                        ],
                        pw.SizedBox(height: 2.5),
                        pw.Text(
                          'PO Order Date: ${dateFormat.format(po.orderDate)}',
                          style: const pw.TextStyle(fontSize: 9.5),
                        ),
                        if (po.requestedDeliveryDate != null) ...[
                          pw.SizedBox(height: 2.5),
                          pw.Text(
                            'Req. Delivery: ${dateFormat.format(po.requestedDeliveryDate!)}',
                            style: const pw.TextStyle(fontSize: 9.5),
                          ),
                        ],
                        pw.SizedBox(height: 2.5),
                        pw.Text(
                          'PO Status: ${po.status.displayName}',
                          style: const pw.TextStyle(fontSize: 9.5),
                        ),
                        if (cancellationReason != null &&
                            cancellationReason.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Cancellation Reason: ${cancellationReason.trim()}',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // ── Itemized Table ──────────────────────────────────────
            pw.Text(
              tableSectionTitle,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.teal900,
              ),
            ),
            pw.SizedBox(height: 8),

            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: headerColor),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellHeight: 24,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
              headers: tableHeaders,
              data: po.items.map((item) {
                final int accepted = item.receivedQty;
                final int rejected = item.rejectedQty;
                final int remaining = item.remainingQty;
                final String skuText =
                    item.sku.trim().isNotEmpty ? item.sku.trim() : 'N/A';

                if (isFullDelivery) {
                  final double lineTotal = accepted * item.effectiveUnitCost;
                  return [
                    item.productName,
                    skuText,
                    '${item.orderedQty}',
                    '$accepted',
                    '$rejected',
                    currencyFormat.format(item.effectiveUnitCost),
                    currencyFormat.format(lineTotal),
                  ];
                } else if (isBackorder) {
                  return [
                    item.productName,
                    skuText,
                    '${item.orderedQty}',
                    '$accepted',
                    '$rejected',
                    '$remaining',
                    currencyFormat.format(item.effectiveUnitCost),
                  ];
                } else {
                  return [
                    item.productName,
                    skuText,
                    '${item.orderedQty}',
                    '$accepted',
                    '$remaining',
                    cancellationReason ?? item.rejectionReason ?? 'Cancelled',
                    currencyFormat.format(item.effectiveUnitCost),
                  ];
                }
              }).toList(),
            ),
            pw.SizedBox(height: 16),

            // ── Billing Summary & Notes ─────────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'NOTICE REMARKS & POLICY',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          remarksText,
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: PdfColors.grey800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  flex: 2,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      children: [
                        _pdfSummaryRow(
                          'Total Ordered Qty:',
                          '${po.totalOrderedQty}',
                        ),
                        _pdfSummaryRow(
                          'Total Accepted Qty:',
                          '${po.totalReceivedQty}',
                        ),
                        if (isBackorder)
                          _pdfSummaryRow(
                            'Back-Ordered Qty:',
                            '${po.totalRemainingQty}',
                            isBold: true,
                            color: PdfColors.orange900,
                          ),
                        if (po.totalRejectedQty > 0)
                          _pdfSummaryRow(
                            'Total Rejected Qty:',
                            '${po.totalRejectedQty}',
                            color: PdfColors.red800,
                          ),
                        pw.Divider(color: PdfColors.grey300),
                        _pdfSummaryRow(
                          'Updated Payable Value:',
                          currencyFormat.format(po.totalReceivedValue),
                          isBold: true,
                          color: PdfColors.teal900,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            // ── Signatures Section ──────────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 160,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top:
                              pw.BorderSide(color: PdfColors.grey400, width: 1),
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Authorized Store Representative',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 160,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top:
                              pw.BorderSide(color: PdfColors.grey400, width: 1),
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Supplier Acknowledgment Signature',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _pdfSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.grey800,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.grey800,
            ),
          ),
        ],
      ),
    );
  }

  /// Direct system print launcher for Notice PDF.
  static Future<void> printNoticePdf(
    BuildContext context,
    PurchaseOrder po,
    Supplier? supplier,
    NoticeType noticeType, {
    SupplierSnapshot? supplierSnapshot,
    String? cancellationReason,
    bool enforceValidation = true,
  }) async {
    try {
      final pdfBytes = await generateSupplierNoticePdf(
        po: po,
        supplier: supplier,
        supplierSnapshot: supplierSnapshot,
        noticeType: noticeType,
        cancellationReason: cancellationReason,
        enforceValidation: enforceValidation,
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: '${noticeType.shortCode}_PO_${po.poNumber}.pdf',
      );
    } on SupplierValidationException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Cannot print notice PDF: ${e.validationResult.summaryMessage}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  /// System native share launcher for Notice PDF.
  static Future<void> shareNoticePdf(
    BuildContext context,
    PurchaseOrder po,
    Supplier? supplier,
    NoticeType noticeType, {
    SupplierSnapshot? supplierSnapshot,
    String? cancellationReason,
    bool enforceValidation = true,
  }) async {
    try {
      final pdfBytes = await generateSupplierNoticePdf(
        po: po,
        supplier: supplier,
        supplierSnapshot: supplierSnapshot,
        noticeType: noticeType,
        cancellationReason: cancellationReason,
        enforceValidation: enforceValidation,
      );
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '${noticeType.shortCode}_PO_${po.poNumber}.pdf',
      );
    } on SupplierValidationException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Cannot share notice PDF: ${e.validationResult.summaryMessage}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }
}
