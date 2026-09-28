import 'package:flutter/material.dart';

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

  static bool isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600 && !isLandscape(context);

  static bool isTablet(BuildContext context) =>
      (MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200) ||
      (isLandscape(context) && MediaQuery.of(context).size.width < 1200);

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1200;

  /// Returns true if the device is in landscape mode or is a tablet/desktop screen width.
  static bool isLargeScreen(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 || isLandscape(context);

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    if (width >= 1200 && desktop != null) {
      return desktop!;
    } else if (width >= 600 && tablet != null) {
      return tablet!;
    } else {
      return mobile;
    }
  }
}
