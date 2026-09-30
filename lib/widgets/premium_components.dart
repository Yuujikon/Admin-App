import 'package:flutter/material.dart';

/// 1. Premium Card Component with 24px extreme radii and diffused M3 drop shadows.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double borderRadius;
  final bool hasShadow;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.backgroundColor,
    this.borderColor,
    this.onTap,
    this.borderRadius = 24.0,
    this.hasShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.surfaceContainerLow;
    final border = borderColor ?? theme.colorScheme.outlineVariant.withValues(alpha: 0.35);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border, width: 1),
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  color: theme.brightness == Brightness.light
                      ? Colors.black.withValues(alpha: 0.04)
                      : Colors.transparent,
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                )
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.05),
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 2. Premium Empty State Component with soft M3 icon container, bold title, and subtle subtitle.
class PremiumEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  const PremiumEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PremiumCard(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      hasShadow: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: colorScheme.primary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(
                onPressed: onActionPressed,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: Text(actionLabel!, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 3. Anti-Stretching Max-Width Container (Prevents full-width stretch on 1000px+ tablet views).
class MaxWidthContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  const MaxWidthContainer({
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

/// 4. Asymmetric 70/30 Split-Pane Layout Wrapper for Tablet Landscape views (e.g. POS & Inventory).
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
    this.spacing = 20.0,
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

/// 5. Fluid Responsive Grid Wrapper without rigid aspect ratios.
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
    this.maxCrossAxisExtent = 240.0,
    this.crossAxisSpacing = 14.0,
    this.mainAxisSpacing = 14.0,
    this.targetItemHeight = 115.0,
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
