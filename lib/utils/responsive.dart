import 'package:flutter/material.dart';

enum DisplayBreakpoint {
  compact,
  medium,
  expanded,
}

class Responsive extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const Responsive({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  static const double compactBreakpoint = 600.0;
  static const double expandedBreakpoint = 1024.0;

  static DisplayBreakpoint getBreakpoint(double width) {
    if (width < compactBreakpoint) {
      return DisplayBreakpoint.compact;
    } else if (width < expandedBreakpoint) {
      return DisplayBreakpoint.medium;
    } else {
      return DisplayBreakpoint.expanded;
    }
  }

  static bool isCompactWidth(double width) => width < compactBreakpoint;
  static bool isMediumWidth(double width) =>
      width >= compactBreakpoint && width < expandedBreakpoint;
  static bool isExpandedWidth(double width) => width >= expandedBreakpoint;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < compactBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= compactBreakpoint &&
      MediaQuery.of(context).size.width < expandedBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= expandedBreakpoint;

  static bool isLargeScreen(BuildContext context) =>
      MediaQuery.of(context).size.width >= compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        if (width >= expandedBreakpoint && desktop != null) {
          return desktop!;
        } else if (width >= compactBreakpoint && tablet != null) {
          return tablet!;
        } else {
          return mobile;
        }
      },
    );
  }
}
