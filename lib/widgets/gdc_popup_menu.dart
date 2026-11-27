import 'package:flutter/material.dart';

/// Represents a single styled option inside a [GdcPopupMenuButton].
class GdcPopupOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final bool isSelected;
  final bool isDestructive;
  final String? trailingBadge;
  final bool showDividerBefore;

  const GdcPopupOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.isSelected = false,
    this.isDestructive = false,
    this.trailingBadge,
    this.showDividerBefore = false,
  });
}

/// Framed icon trigger button used for overflow (`⋮`) and compact action popups.
class GdcPopupIconTrigger extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final bool isCircular;
  final bool isActive;
  final int activeBadgeCount;

  const GdcPopupIconTrigger({
    super.key,
    this.icon = Icons.more_vert_rounded,
    this.size = 36,
    this.iconSize = 18,
    this.isCircular = false,
    this.isActive = false,
    this.activeBadgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isActive
        ? colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)
        : (isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLowest);
    final borderColor = isActive
        ? colorScheme.primary.withValues(alpha: 0.45)
        : colorScheme.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.75);
    final fgColor = isActive ? colorScheme.primary : colorScheme.onSurface;

    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: isCircular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircular ? null : BorderRadius.circular(11),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: fgColor),
    );

    if (activeBadgeCount <= 0) {
      return button;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.surface, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              '$activeBadgeCount',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: colorScheme.onPrimary,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pill/chip trigger button used for filter, date, month, and bulk-action popups.
class GdcPopupPillTrigger extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isActive;
  final bool emphasized;
  final int activeBadgeCount;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const GdcPopupPillTrigger({
    super.key,
    required this.label,
    this.icon,
    this.isActive = false,
    this.emphasized = false,
    this.activeBadgeCount = 0,
    this.height,
    this.borderRadius = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final highlighted = isActive || emphasized;

    final bgColor = highlighted
        ? colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.11)
        : (isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLowest);
    final borderColor = highlighted
        ? colorScheme.primary.withValues(alpha: 0.42)
        : colorScheme.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.75);
    final iconColor =
        highlighted ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final textColor = highlighted ? colorScheme.primary : colorScheme.onSurface;

    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: -0.1,
            ),
          ),
          if (activeBadgeCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$activeBadgeCount',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onPrimary,
                  height: 1.1,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 17,
            color: highlighted
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// Builds a subtle non-interactive section header entry for popup menus.
PopupMenuEntry<T> buildGdcPopupMenuHeader<T>(
  BuildContext context,
  String title,
) {
  final colorScheme = Theme.of(context).colorScheme;
  return PopupMenuItem<T>(
    enabled: false,
    height: 30,
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
    ),
  );
}

/// Unified, elevated popup menu button styled for the GDC Admin design system.
class GdcPopupMenuButton<T> extends StatelessWidget {
  final List<GdcPopupOption<T>> options;
  final ValueChanged<T> onSelected;
  final T? initialValue;
  final String? tooltip;
  final String? menuTitle;
  final Widget trigger;
  final BoxConstraints? constraints;
  final Offset offset;

  const GdcPopupMenuButton({
    super.key,
    required this.options,
    required this.onSelected,
    required this.trigger,
    this.initialValue,
    this.tooltip,
    this.menuTitle,
    this.constraints,
    this.offset = const Offset(0, 8),
  });

  /// Overflow or icon-only popup button with framed container & optional badge.
  factory GdcPopupMenuButton.icon({
    Key? key,
    required List<GdcPopupOption<T>> options,
    required ValueChanged<T> onSelected,
    T? initialValue,
    String? tooltip,
    String? menuTitle,
    IconData icon = Icons.more_vert_rounded,
    double size = 36,
    double iconSize = 18,
    bool isCircular = false,
    bool isActive = false,
    int activeBadgeCount = 0,
    BoxConstraints? constraints,
    Offset offset = const Offset(0, 8),
  }) {
    return GdcPopupMenuButton<T>(
      key: key,
      options: options,
      onSelected: onSelected,
      initialValue: initialValue,
      tooltip: tooltip,
      menuTitle: menuTitle,
      constraints: constraints,
      offset: offset,
      trigger: GdcPopupIconTrigger(
        icon: icon,
        size: size,
        iconSize: iconSize,
        isCircular: isCircular,
        isActive: isActive,
        activeBadgeCount: activeBadgeCount,
      ),
    );
  }

  /// Pill/chip popup selector with leading icon, label, active highlight & chevron.
  factory GdcPopupMenuButton.pill({
    Key? key,
    required String label,
    required List<GdcPopupOption<T>> options,
    required ValueChanged<T> onSelected,
    T? initialValue,
    String? tooltip,
    String? menuTitle,
    IconData? icon,
    bool isActive = false,
    bool emphasized = false,
    int activeBadgeCount = 0,
    double? height,
    double borderRadius = 14,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    BoxConstraints? constraints,
    Offset offset = const Offset(0, 8),
  }) {
    return GdcPopupMenuButton<T>(
      key: key,
      options: options,
      onSelected: onSelected,
      initialValue: initialValue,
      tooltip: tooltip,
      menuTitle: menuTitle,
      constraints: constraints,
      offset: offset,
      trigger: GdcPopupPillTrigger(
        label: label,
        icon: icon,
        isActive: isActive,
        emphasized: emphasized,
        activeBadgeCount: activeBadgeCount,
        height: height,
        borderRadius: borderRadius,
        padding: padding,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return PopupMenuButton<T>(
      initialValue: initialValue,
      tooltip: tooltip ?? '',
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      offset: offset,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
      surfaceTintColor: Colors.transparent,
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      menuPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      constraints: constraints ?? const BoxConstraints(minWidth: 204),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(
            alpha: isDark ? 0.45 : 0.85,
          ),
          width: 1,
        ),
      ),
      itemBuilder: (ctx) {
        final entries = <PopupMenuEntry<T>>[];
        if (menuTitle != null && menuTitle!.isNotEmpty) {
          entries.add(buildGdcPopupMenuHeader<T>(ctx, menuTitle!));
        }

        for (final option in options) {
          if (option.showDividerBefore && entries.isNotEmpty) {
            entries.add(const PopupMenuDivider(height: 10));
          }
          entries.add(
            PopupMenuItem<T>(
              value: option.value,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              height: option.subtitle != null ? 54 : 44,
              child: _GdcPopupOptionTile<T>(option: option),
            ),
          );
        }

        return entries;
      },
      child: trigger,
    );
  }
}

class _GdcPopupOptionTile<T> extends StatelessWidget {
  final GdcPopupOption<T> option;

  const _GdcPopupOptionTile({required this.option});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color accentColor = option.isDestructive
        ? colorScheme.error
        : (option.iconColor ??
            (option.isSelected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant));

    final Color iconBgColor = option.isDestructive
        ? colorScheme.error.withValues(alpha: isDark ? 0.18 : 0.10)
        : (option.iconColor != null
            ? option.iconColor!.withValues(alpha: isDark ? 0.20 : 0.12)
            : (option.isSelected
                ? colorScheme.primary.withValues(alpha: isDark ? 0.24 : 0.14)
                : colorScheme.surfaceContainerHighest.withValues(
                    alpha: isDark ? 0.55 : 0.65,
                  )));

    final Color labelColor = option.isDestructive
        ? colorScheme.error
        : (option.isSelected ? colorScheme.primary : colorScheme.onSurface);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: option.isSelected
            ? colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: option.isSelected
            ? Border.all(
                color: colorScheme.primary.withValues(alpha: 0.24),
                width: 1,
              )
            : null,
      ),
      child: Row(
        children: [
          if (option.icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(option.icon, size: 16, color: accentColor),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        option.isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: labelColor,
                    letterSpacing: -0.1,
                  ),
                ),
                if (option.subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    option.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (option.trailingBadge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: option.isSelected
                    ? colorScheme.primary.withValues(alpha: 0.16)
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: isDark ? 0.7 : 0.85,
                      ),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                option.trailingBadge!,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: option.isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (option.isSelected) ...[
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(
                  alpha: isDark ? 0.25 : 0.14,
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.check_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
