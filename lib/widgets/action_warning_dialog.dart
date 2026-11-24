import 'package:flutter/material.dart';

enum ActionWarningSeverity {
  danger,
  warning,
  info,
}

/// Standardized warning & confirmation dialog for critical system actions
/// to prevent human error and accidental modifications.
class ActionWarningDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final ActionWarningSeverity severity;
  final IconData? icon;
  final List<String>? details;
  final bool requireCheckbox;
  final String? checkboxLabel;

  const ActionWarningDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.severity = ActionWarningSeverity.warning,
    this.icon,
    this.details,
    this.requireCheckbox = false,
    this.checkboxLabel,
  });

  /// Helper to display the dialog and return true if confirmed, false otherwise.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    ActionWarningSeverity severity = ActionWarningSeverity.warning,
    IconData? icon,
    List<String>? details,
    bool requireCheckbox = false,
    String? checkboxLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => ActionWarningDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        severity: severity,
        icon: icon,
        details: details,
        requireCheckbox: requireCheckbox,
        checkboxLabel: checkboxLabel,
      ),
    );
    return result ?? false;
  }

  @override
  State<ActionWarningDialog> createState() => _ActionWarningDialogState();
}

class _ActionWarningDialogState extends State<ActionWarningDialog> {
  bool _isChecked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color primaryColor;
    final Color iconBgColor;
    final IconData defaultIcon;

    switch (widget.severity) {
      case ActionWarningSeverity.danger:
        primaryColor = colorScheme.error;
        iconBgColor = colorScheme.errorContainer.withValues(alpha: 0.6);
        defaultIcon = Icons.warning_amber_rounded;
        break;
      case ActionWarningSeverity.warning:
        primaryColor = Colors.amber.shade800;
        iconBgColor = Colors.amber.shade100;
        defaultIcon = Icons.error_outline_rounded;
        break;
      case ActionWarningSeverity.info:
        primaryColor = colorScheme.primary;
        iconBgColor = colorScheme.primaryContainer.withValues(alpha: 0.6);
        defaultIcon = Icons.info_outline_rounded;
        break;
    }

    final displayIcon = widget.icon ?? defaultIcon;
    final isConfirmDisabled = widget.requireCheckbox && !_isChecked;

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.all(20),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              displayIcon,
              color: primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            if (widget.details != null && widget.details!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.details!.map((detail) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor)),
                          Expanded(
                            child: Text(
                              detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            if (widget.requireCheckbox) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _isChecked = !_isChecked),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Checkbox(
                      value: _isChecked,
                      onChanged: (val) =>
                          setState(() => _isChecked = val ?? false),
                      activeColor: primaryColor,
                    ),
                    Expanded(
                      child: Text(
                        widget.checkboxLabel ??
                            'I understand the consequences of this action',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: colorScheme.outlineVariant,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            widget.cancelLabel,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isConfirmDisabled
                ? primaryColor.withValues(alpha: 0.4)
                : primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed:
              isConfirmDisabled ? null : () => Navigator.pop(context, true),
          child: Text(
            widget.confirmLabel,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
