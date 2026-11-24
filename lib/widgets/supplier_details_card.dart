import 'package:flutter/material.dart';

import '../models/supplier.dart';

/// Structured Supplier Details Card with clear visual hierarchy, payment/validation badges,
/// icon-paired metadata rows, inline missing-data warning pills, and a Quick-Edit trigger.
class SupplierDetailsCard extends StatelessWidget {
  final SupplierSnapshot snapshot;
  final VoidCallback? onQuickEdit;
  final bool isHydrating;
  final bool compact;
  final String? title;

  const SupplierDetailsCard({
    super.key,
    required this.snapshot,
    this.onQuickEdit,
    this.isHydrating = false,
    this.compact = false,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final validation = snapshot.validateForDispatch();
    final isReady = validation.isValid;

    final Color borderColor =
        isReady ? Colors.teal.shade200 : Colors.red.shade300;
    final Color headerBg = isReady
        ? Colors.teal.shade50.withValues(alpha: 0.65)
        : Colors.red.shade50.withValues(alpha: 0.65);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isReady ? 1 : 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card Header: Supplier Name, Payment/Status Badges & Quick Edit ──
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 10 : 12,
            ),
            color: headerBg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: isReady ? Colors.teal.shade100 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    size: compact ? 18 : 20,
                    color: isReady ? Colors.teal.shade900 : Colors.red.shade900,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null) ...[
                        Text(
                          title!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              snapshot.supplierName.trim().isNotEmpty
                                  ? snapshot.supplierName.trim()
                                  : 'Unnamed Supplier',
                              style: TextStyle(
                                fontSize: compact ? 14 : 15.5,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isHydrating) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Validation Status Badge
                          _StatusBadgePill(
                            icon: isReady
                                ? Icons.verified_rounded
                                : Icons.error_outline_rounded,
                            label: isReady
                                ? 'Verified for PDF & Email'
                                : '${validation.blockingIssues.length} Required Field${validation.blockingIssues.length == 1 ? '' : 's'} Missing',
                            bgColor: isReady
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                            fgColor: isReady
                                ? Colors.green.shade900
                                : Colors.red.shade900,
                          ),
                          // Payment Terms Badge
                          if (snapshot.paymentTerms.trim().isNotEmpty)
                            _StatusBadgePill(
                              icon: Icons.payments_outlined,
                              label: snapshot.paymentTerms.trim(),
                              bgColor: Colors.blue.shade50,
                              fgColor: Colors.blue.shade900,
                            ),
                          // Category Badge
                          if (snapshot.category.trim().isNotEmpty)
                            _StatusBadgePill(
                              icon: Icons.category_outlined,
                              label: snapshot.category.trim(),
                              bgColor: colorScheme.surfaceContainerHighest,
                              fgColor: colorScheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onQuickEdit != null) ...[
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: onQuickEdit,
                    style: TextButton.styleFrom(
                      foregroundColor:
                          isReady ? Colors.teal.shade900 : Colors.red.shade900,
                      backgroundColor: colorScheme.surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: borderColor),
                      ),
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 15),
                    label: Text(
                      isReady ? 'Quick Edit' : 'Fix Details',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Icon-Paired Metadata Rows ──────────────────────────────────────
          Padding(
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Contact Person',
                  value: snapshot.contactPerson.trim(),
                  placeholder: 'Not specified (optional)',
                  isMissingBlocking: false,
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Supplier Email',
                  value: snapshot.email.trim(),
                  placeholder: 'Missing Email – Required for dispatch',
                  isMissingBlocking: validation.blockingIssues
                      .any((i) => i.fieldKey == 'email'),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Contact Number',
                  value: snapshot.phone.trim(),
                  placeholder: 'Missing Phone – Required for PDF',
                  isMissingBlocking: validation.blockingIssues
                      .any((i) => i.fieldKey == 'phone'),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'Physical Address',
                  value: snapshot.address.trim(),
                  placeholder:
                      'Missing Address – Required for PO/Backorder PDF',
                  isMissingBlocking: validation.blockingIssues
                      .any((i) => i.fieldKey == 'address'),
                ),
                if (snapshot.tin.trim().isNotEmpty || !compact) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    label: 'TIN / Business ID',
                    value: snapshot.tin.trim(),
                    placeholder: 'Not specified (optional)',
                    isMissingBlocking: false,
                  ),
                ],

                // ── Inline Missing-Data Warning Pills ────────────────────────
                if (validation.blockingIssues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: validation.blockingIssues.map((issue) {
                      return InkWell(
                        onTap: onQuickEdit,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 14,
                                color: Colors.red.shade800,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  issue.message,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                              ),
                              if (onQuickEdit != null) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 10,
                                  color: Colors.red.shade800,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
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

class _StatusBadgePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color fgColor;

  const _StatusBadgePill({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String placeholder;
  final bool isMissingBlocking;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.isMissingBlocking,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasValue = value.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            size: 16,
            color: isMissingBlocking
                ? Colors.red.shade700
                : colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            hasValue ? value : placeholder,
            style: TextStyle(
              fontSize: 12,
              fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
              fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
              color: isMissingBlocking
                  ? Colors.red.shade800
                  : (hasValue
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ],
    );
  }
}
