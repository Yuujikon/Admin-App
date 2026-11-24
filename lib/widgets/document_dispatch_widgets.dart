import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/supplier.dart';
import '../shared/services/admin_messaging_service.dart';

/// Clear Recipients Banner (`To: [Supplier Email]` and `Copy: [Store Email]`) paired with
/// a quick "Preview PDF" button for visual verification before final dispatch.
class RecipientsPreviewBanner extends StatelessWidget {
  final SupplierSnapshot snapshot;
  final String storeEmail;
  final VoidCallback? onPreviewPdf;
  final VoidCallback? onFixSupplier;
  final String previewButtonLabel;
  final bool isLoadingPreview;

  const RecipientsPreviewBanner({
    super.key,
    required this.snapshot,
    required this.storeEmail,
    this.onPreviewPdf,
    this.onFixSupplier,
    this.previewButtonLabel = 'Preview PDF',
    this.isLoadingPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final validation = snapshot.validateForDispatch();
    final isReady = validation.isValid;
    final cleanSupplierEmail = snapshot.email.trim();
    final cleanStoreEmail = storeEmail.trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isReady
            ? Colors.blueGrey.shade50.withValues(alpha: 0.7)
            : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isReady ? Colors.blueGrey.shade200 : Colors.amber.shade400,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.forward_to_inbox_rounded,
                size: 16,
                color: isReady ? Colors.teal.shade800 : Colors.amber.shade900,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'DISPATCH RECIPIENTS (DUAL-COPY PARITY)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color:
                        isReady ? Colors.teal.shade900 : Colors.amber.shade900,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: isLoadingPreview
                    ? null
                    : (isReady ? onPreviewPdf : onFixSupplier),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      isReady ? Colors.teal.shade900 : Colors.amber.shade900,
                  side: BorderSide(
                    color:
                        isReady ? Colors.teal.shade300 : Colors.amber.shade600,
                  ),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: isLoadingPreview
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isReady
                            ? Icons.visibility_rounded
                            : Icons.build_circle_outlined,
                        size: 15,
                      ),
                label: Text(
                  isReady ? previewButtonLabel : 'Fix to Preview',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _RecipientLine(
            tag: 'To',
            role: 'Supplier',
            email: cleanSupplierEmail.isNotEmpty
                ? cleanSupplierEmail
                : 'Missing supplier email',
            isValid:
                validation.blockingIssues.every((i) => i.fieldKey != 'email'),
          ),
          const SizedBox(height: 4),
          _RecipientLine(
            tag: 'Copy',
            role: 'Store/Admin',
            email: cleanStoreEmail.isNotEmpty
                ? cleanStoreEmail
                : 'Store email not configured',
            isValid: cleanStoreEmail.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

class _RecipientLine extends StatelessWidget {
  final String tag;
  final String role;
  final String email;
  final bool isValid;

  const _RecipientLine({
    required this.tag,
    required this.role,
    required this.email,
    required this.isValid,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isValid ? Colors.teal.shade100 : Colors.red.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            tag,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: isValid ? Colors.teal.shade900 : Colors.red.shade900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              children: [
                TextSpan(
                  text: '$role: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: email,
                  style: TextStyle(
                    fontWeight: isValid ? FontWeight.w500 : FontWeight.w700,
                    color: isValid
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.red.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens a full visual in-app PDF Preview modal before final dispatch so staff can verify
/// every supplier field, line item, and total on the rendered Purchase Order or Backorder PDF.
Future<void> showDocumentPdfPreviewModal({
  required BuildContext context,
  required String title,
  required String fileName,
  required Future<Uint8List> Function() buildPdf,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 720,
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
              color: Colors.teal.shade800,
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          fileName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PdfPreview(
                pdfFileName: fileName,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                build: (_) => buildPdf(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Unified step-by-step dispatch progress modal:
/// `Validating Data` -> `Generating PDF` -> `Sending to Supplier & Store`
/// with explicit per-recipient status reporting, PDF preview/share, and one-tap retry.
class DispatchProgressDialog extends StatefulWidget {
  final String documentTitle;
  final Future<DocumentDispatchResult> Function(
    void Function(DispatchStage stage) onStageChanged,
  ) onExecute;

  const DispatchProgressDialog({
    super.key,
    required this.documentTitle,
    required this.onExecute,
  });

  /// Runs the unified dispatch pipeline inside a progress modal and returns the final [DocumentDispatchResult].
  static Future<DocumentDispatchResult?> run({
    required BuildContext context,
    required String documentTitle,
    required Future<DocumentDispatchResult> Function(
      void Function(DispatchStage stage) onStageChanged,
    ) onExecute,
  }) {
    return showDialog<DocumentDispatchResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DispatchProgressDialog(
        documentTitle: documentTitle,
        onExecute: onExecute,
      ),
    );
  }

  @override
  State<DispatchProgressDialog> createState() => _DispatchProgressDialogState();
}

class _DispatchProgressDialogState extends State<DispatchProgressDialog> {
  DispatchStage _currentStage = DispatchStage.validating;
  DocumentDispatchResult? _result;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _startPipeline();
  }

  Future<void> _startPipeline() async {
    setState(() {
      _running = true;
      _result = null;
      _currentStage = DispatchStage.validating;
    });

    try {
      final res = await widget.onExecute((stage) {
        if (mounted) {
          setState(() => _currentStage = stage);
        }
      });
      if (mounted) {
        setState(() {
          _result = res;
          _running = false;
          _currentStage = res.isFullSuccess
              ? DispatchStage.completed
              : DispatchStage.failed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _currentStage = DispatchStage.failed;
          _result = DocumentDispatchResult(
            validationPassed: true,
            pdfGenerated: false,
            pdfError: e.toString(),
            supplierEmail: '',
            storeEmail: '',
            supplierEmailSent: false,
            storeCopyEmailSent: false,
          );
        });
      }
    }
  }

  int _stageOrder(DispatchStage s) {
    switch (s) {
      case DispatchStage.validating:
        return 0;
      case DispatchStage.generatingPdf:
        return 1;
      case DispatchStage.sendingEmails:
        return 2;
      case DispatchStage.completed:
      case DispatchStage.failed:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final currentOrder = _stageOrder(_currentStage);

    final bool step1Done =
        result != null ? result.validationPassed : currentOrder > 0;
    final bool step1Failed = result != null && !result.validationPassed;

    final bool step2Done =
        result != null ? result.pdfGenerated : currentOrder > 1;
    final bool step2Failed =
        result != null && result.validationPassed && !result.pdfGenerated;

    final bool step3Done = result != null && result.isFullSuccess;
    final bool step3Failed =
        result != null && result.pdfGenerated && !result.isFullSuccess;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _running
                  ? Colors.teal.shade50
                  : (result?.isFullSuccess == true
                      ? Colors.green.shade50
                      : Colors.orange.shade50),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _running
                  ? Icons.send_rounded
                  : (result?.isFullSuccess == true
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded),
              color: _running
                  ? Colors.teal.shade800
                  : (result?.isFullSuccess == true
                      ? Colors.green.shade800
                      : Colors.orange.shade900),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.documentTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _running
                      ? _currentStage.label
                      : (result?.isFullSuccess == true
                          ? 'Delivered to Supplier & Store'
                          : 'Action Required'),
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PipelineStepRow(
                label: '1. Validating Data',
                isActive: _running && _currentStage == DispatchStage.validating,
                isDone: step1Done,
                isFailed: step1Failed,
                detail: step1Failed
                    ? result.validationResult?.summaryMessage
                    : null,
              ),
              const SizedBox(height: 10),
              _PipelineStepRow(
                label: '2. Generating PO / Backorder PDF',
                isActive:
                    _running && _currentStage == DispatchStage.generatingPdf,
                isDone: step2Done,
                isFailed: step2Failed,
                detail: step2Failed ? result.pdfError : null,
              ),
              const SizedBox(height: 10),
              _PipelineStepRow(
                label: '3. Sending to Supplier & Store',
                isActive:
                    _running && _currentStage == DispatchStage.sendingEmails,
                isDone: step3Done,
                isFailed: step3Failed,
              ),
              if (result != null && result.pdfGenerated) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _RecipientOutcomeTile(
                  role: 'Supplier Email',
                  email: result.supplierEmail,
                  sent: result.supplierEmailSent,
                  error: result.supplierError,
                ),
                const SizedBox(height: 8),
                _RecipientOutcomeTile(
                  role: 'Store / Admin Copy',
                  email: result.storeEmail,
                  sent: result.storeCopyEmailSent,
                  error: result.storeError,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: _running
          ? null
          : [
              if (result != null &&
                  result.pdfBytes != null &&
                  result.pdfFileName != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Share / Save PDF'),
                  onPressed: () async {
                    await Printing.sharePdf(
                      bytes: result.pdfBytes!,
                      filename: result.pdfFileName!,
                    );
                  },
                ),
              if (result != null && !result.isFullSuccess)
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade900,
                  ),
                  onPressed: _startPipeline,
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(result),
                child: const Text('Done'),
              ),
            ],
    );
  }
}

class _PipelineStepRow extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDone;
  final bool isFailed;
  final String? detail;

  const _PipelineStepRow({
    required this.label,
    required this.isActive,
    required this.isDone,
    required this.isFailed,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    Widget leading;
    Color textColor;

    if (isFailed) {
      leading =
          Icon(Icons.cancel_rounded, color: Colors.red.shade700, size: 20);
      textColor = Colors.red.shade900;
    } else if (isDone) {
      leading = Icon(Icons.check_circle_rounded,
          color: Colors.green.shade700, size: 20);
      textColor = Colors.green.shade900;
    } else if (isActive) {
      leading = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
      textColor = Colors.teal.shade900;
    } else {
      leading = Icon(Icons.radio_button_unchecked_rounded,
          color: Colors.grey.shade400, size: 20);
      textColor = Colors.grey.shade600;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: (isActive || isDone || isFailed)
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
        if (detail != null && detail!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              detail!,
              style: TextStyle(fontSize: 11, color: Colors.red.shade800),
            ),
          ),
        ],
      ],
    );
  }
}

class _RecipientOutcomeTile extends StatelessWidget {
  final String role;
  final String email;
  final bool sent;
  final String? error;

  const _RecipientOutcomeTile({
    required this.role,
    required this.email,
    required this.sent,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: sent ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sent ? Colors.green.shade200 : Colors.red.shade300,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            sent ? Icons.mark_email_read_rounded : Icons.error_outline_rounded,
            size: 18,
            color: sent ? Colors.green.shade800 : Colors.red.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$role — ${sent ? "Delivered" : "Delivery Failed"}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: sent ? Colors.green.shade900 : Colors.red.shade900,
                  ),
                ),
                Text(
                  email.isNotEmpty ? email : '(Not configured)',
                  style: const TextStyle(fontSize: 11),
                ),
                if (!sent && error != null && error!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    error!,
                    style:
                        TextStyle(fontSize: 10.5, color: Colors.red.shade800),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
