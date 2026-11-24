import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/purchase_order.dart';
import '../models/supplier.dart';
import '../providers/inventory_provider.dart';
import '../shared/services/admin_messaging_service.dart';
import '../utils/notice_pdf_printer.dart';
import 'document_dispatch_widgets.dart';
import 'supplier_details_card.dart';
import 'supplier_quick_edit_sheet.dart';

/// Unified Review & Dispatch Bottom Sheet for Supplier Notices
/// (Backorder Notices, Delivery Confirmations, and Cancellation / Close Short Notices).
///
/// Features:
/// - Live Firestore supplier hydration & immutable snapshot review (`SupplierDetailsCard`)
/// - Inline missing-data warning pills & in-flow Quick-Edit modal
/// - Recipients summary banner (`To: Supplier` & `Copy: Store`) with visual PDF Preview
/// - Pre-flight validation gate + Unified step-by-step dual-email dispatch pipeline
class SupplierNoticeDispatchSheet extends StatefulWidget {
  final PurchaseOrder po;
  final Supplier? initialSupplier;
  final NoticeType noticeType;
  final String? cancellationReason;
  final String? deliveryReceiptNo;
  final String actorEmail;

  const SupplierNoticeDispatchSheet({
    super.key,
    required this.po,
    this.initialSupplier,
    required this.noticeType,
    this.cancellationReason,
    this.deliveryReceiptNo,
    this.actorEmail = 'Admin',
  });

  /// Displays the [SupplierNoticeDispatchSheet] modal bottom sheet.
  static Future<DocumentDispatchResult?> show({
    required BuildContext context,
    required PurchaseOrder po,
    Supplier? supplier,
    required NoticeType noticeType,
    String? cancellationReason,
    String? deliveryReceiptNo,
    String actorEmail = 'Admin',
  }) {
    return showModalBottomSheet<DocumentDispatchResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => SupplierNoticeDispatchSheet(
        po: po,
        initialSupplier: supplier,
        noticeType: noticeType,
        cancellationReason: cancellationReason,
        deliveryReceiptNo: deliveryReceiptNo,
        actorEmail: actorEmail,
      ),
    );
  }

  @override
  State<SupplierNoticeDispatchSheet> createState() =>
      _SupplierNoticeDispatchSheetState();
}

class _SupplierNoticeDispatchSheetState
    extends State<SupplierNoticeDispatchSheet> {
  late PurchaseOrder _po;
  late SupplierSnapshot _snapshot;
  Supplier? _liveSupplier;
  bool _hydrating = true;
  String _storeEmail = '';

  @override
  void initState() {
    super.initState();
    _po = widget.po;
    _liveSupplier = widget.initialSupplier;
    _snapshot = _po.resolveSupplierSnapshot(_liveSupplier);
    _storeEmail = AdminMessagingService().storeEmailSync;

    AdminMessagingService().resolveStoreEmail().then((email) {
      if (mounted && email.isNotEmpty) {
        setState(() => _storeEmail = email);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateSupplier());
  }

  Future<void> _hydrateSupplier() async {
    if (_po.supplierId.trim().isEmpty) {
      if (mounted) setState(() => _hydrating = false);
      return;
    }

    final inventory = context.read<InventoryProvider>();
    final fresh = await inventory.fetchSupplierFresh(_po.supplierId);
    if (!mounted) return;
    setState(() {
      if (fresh != null) {
        _liveSupplier = fresh;
        _snapshot = _po.resolveSupplierSnapshot(fresh);
      }
      _hydrating = false;
    });
  }

  Future<void> _openQuickEdit() async {
    final updated = await SupplierQuickEditSheet.show(
      context: context,
      initialSnapshot: _snapshot,
      initialAutoNotifyLowStock: _liveSupplier?.autoNotifyLowStock ?? true,
      existingPoId: _po.id,
    );

    if (updated != null && mounted) {
      setState(() {
        _snapshot = updated;
        _po = _po.copyWith(
          supplierName: updated.supplierName,
          supplierSnapshot: updated,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Supplier details updated and synced to this order.',
          ),
          backgroundColor: Colors.teal.shade800,
        ),
      );
    }
  }

  Future<void> _previewPdf() async {
    final validation = _snapshot.validateForDispatch();
    if (!validation.isValid) {
      await _openQuickEdit();
      return;
    }

    final fileName = '${widget.noticeType.shortCode}_PO_${_po.poNumber}.pdf';
    await showDocumentPdfPreviewModal(
      context: context,
      title: widget.noticeType == NoticeType.backorder
          ? 'Back-Order Notice PDF Preview'
          : widget.noticeType == NoticeType.fullDelivery
              ? 'Delivery Confirmation PDF Preview'
              : 'Cancellation Notice PDF Preview',
      fileName: fileName,
      buildPdf: () => NoticePdfPrinter.generateSupplierNoticePdf(
        po: _po,
        supplier: _liveSupplier,
        supplierSnapshot: _snapshot,
        noticeType: widget.noticeType,
        cancellationReason: widget.cancellationReason,
        enforceValidation: true,
      ),
    );
  }

  Future<void> _dispatchNotice() async {
    final validation = _snapshot.validateForDispatch();
    if (!validation.isValid) {
      await _openQuickEdit();
      return;
    }

    final docTitle = widget.noticeType == NoticeType.backorder
        ? 'Dispatch Back-Order Notice'
        : widget.noticeType == NoticeType.fullDelivery
            ? 'Dispatch Delivery Confirmation'
            : 'Dispatch Cancellation Notice';

    final result = await DispatchProgressDialog.run(
      context: context,
      documentTitle: docTitle,
      onExecute: (onStage) =>
          AdminMessagingService().dispatchSupplierNoticeWithPdf(
        po: _po,
        supplier: _liveSupplier,
        supplierSnapshot: _snapshot,
        noticeType: widget.noticeType,
        cancellationReason: widget.cancellationReason,
        deliveryReceiptNo: widget.deliveryReceiptNo,
        storeEmailOverride: _storeEmail,
        actorEmail: widget.actorEmail,
        onStageChanged: onStage,
      ),
    );

    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBackorder = widget.noticeType == NoticeType.backorder;
    final isFullDelivery = widget.noticeType == NoticeType.fullDelivery;
    final Color accentColor = isFullDelivery
        ? Colors.teal.shade800
        : isBackorder
            ? Colors.orange.shade800
            : Colors.red.shade800;
    final Color accentBg = isFullDelivery
        ? Colors.teal.shade50
        : isBackorder
            ? Colors.orange.shade50
            : Colors.red.shade50;
    final IconData headerIcon = isFullDelivery
        ? Icons.verified_rounded
        : isBackorder
            ? Icons.assignment_return_rounded
            : Icons.cancel_outlined;

    final String backorderRef =
        (_po.childPoId != null && _po.childPoId!.trim().isNotEmpty)
            ? _po.childPoId!.trim()
            : 'BO-${_po.poNumber}';

    final validation = _snapshot.validateForDispatch();
    final bool canDispatch = validation.isValid;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(headerIcon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isBackorder
                            ? 'Back-Order Review & Dispatch'
                            : isFullDelivery
                                ? 'Delivery Confirmation Dispatch'
                                : 'Order Cancellation Dispatch',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        isBackorder
                            ? 'PO #${_po.poNumber} • Backorder Ref: $backorderRef'
                            : 'PO #${_po.poNumber}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Review Body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order / Backorder Metrics Summary
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accentBg.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _MetricPill(
                              label: 'Ordered',
                              value: '${_po.totalOrderedQty}',
                              color: Colors.blueGrey.shade800,
                            ),
                            _MetricPill(
                              label: 'Accepted',
                              value: '${_po.totalReceivedQty}',
                              color: Colors.green.shade800,
                            ),
                            if (!isFullDelivery)
                              _MetricPill(
                                label:
                                    isBackorder ? 'Backordered' : 'Cancelled',
                                value: '${_po.totalRemainingQty}',
                                color: accentColor,
                              ),
                            if (_po.totalRejectedQty > 0)
                              _MetricPill(
                                label: 'Rejected',
                                value: '${_po.totalRejectedQty}',
                                color: Colors.red.shade800,
                              ),
                          ],
                        ),
                        if (widget.cancellationReason != null &&
                            widget.cancellationReason!.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Reason: ${widget.cancellationReason!.trim()}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Structured Supplier Details Card (Single Source of Truth)
                  SupplierDetailsCard(
                    snapshot: _snapshot,
                    isHydrating: _hydrating,
                    title: 'Verified Supplier Snapshot',
                    onQuickEdit: _openQuickEdit,
                  ),

                  const SizedBox(height: 12),

                  // Dual-Recipient Preview Banner + Visual PDF Preview Trigger
                  RecipientsPreviewBanner(
                    snapshot: _snapshot,
                    storeEmail: _storeEmail,
                    previewButtonLabel: isBackorder
                        ? 'Preview Backorder PDF'
                        : 'Preview Notice PDF',
                    onPreviewPdf: _previewPdf,
                    onFixSupplier: _openQuickEdit,
                  ),
                ],
              ),
            ),
          ),

          // Footer Actions
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Skip / Later'),
                ),
                const Spacer(),
                if (canDispatch) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      await NoticePdfPrinter.shareNoticePdf(
                        context,
                        _po,
                        _liveSupplier,
                        widget.noticeType,
                        supplierSnapshot: _snapshot,
                        cancellationReason: widget.cancellationReason,
                      );
                    },
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Share PDF'),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        canDispatch ? accentColor : Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _dispatchNotice,
                  icon: Icon(
                    canDispatch
                        ? Icons.send_rounded
                        : Icons.warning_amber_rounded,
                    size: 17,
                  ),
                  label: Text(
                    canDispatch
                        ? 'Send to Supplier & Store'
                        : 'Fix Supplier to Send',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}
