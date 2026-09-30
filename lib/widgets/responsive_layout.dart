import 'package:flutter/material.dart';

/// Reusable Anti-Stretching Container for forms, dialogs, and list pages.
class MaxWidthWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  const MaxWidthWrapper({
    super.key,
    required this.child,
    this.maxWidth = 720.0,
    this.alignment = Alignment.topCenter,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Reusable Master-Detail Split-Pane Layout for Tablet Landscape views (e.g. POS & Inventory).
class SplitPaneLayout extends StatelessWidget {
  final Widget mainPane;
  final Widget sidePane;
  final double mainFlex;
  final double sideFlex;
  final double spacing;

  const SplitPaneLayout({
    super.key,
    required this.mainPane,
    required this.sidePane,
    this.mainFlex = 7,
    this.sideFlex = 3,
    this.spacing = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: mainFlex.toInt(),
            child: mainPane,
          ),
          SizedBox(width: spacing),
          Expanded(
            flex: sideFlex.toInt(),
            child: sidePane,
          ),
        ],
      );
    }

    return Column(
      children: [
        mainPane,
        SizedBox(height: spacing),
        sidePane,
      ],
    );
  }
}

/// Reusable Fluid Grid Wrapper that dynamically calculates column extent and ratios without fixed aspect ratio overflows.
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double maxCrossAxisExtent;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double targetItemHeight;
  final EdgeInsetsGeometry? padding;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.maxCrossAxisExtent = 220.0,
    this.crossAxisSpacing = 12.0,
    this.mainAxisSpacing = 12.0,
    this.targetItemHeight = 110.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final int columns = (width / maxCrossAxisExtent).ceil().clamp(2, 6);
        final double itemWidth = (width - (crossAxisSpacing * (columns - 1))) / columns;
        final double dynamicRatio = (itemWidth / targetItemHeight).clamp(0.8, 2.5);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCrossAxisExtent,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
            childAspectRatio: dynamicRatio,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}

/// Universal Material 3 Empty State Component with soft iconography, typography, and action callback.
class GlobalEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onActionTextPressed;

  const GlobalEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onActionTextPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: colorScheme.primary),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (actionLabel != null && onActionTextPressed != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onActionTextPressed,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(actionLabel!, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
