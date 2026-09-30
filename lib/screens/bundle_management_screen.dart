import 'package:flutter/material.dart';
import 'category_bundle_management_screen.dart';

/// Legacy entry point for Cooking Bundle Management.
/// Delegates to the unified [CategoryBundleManagementScreen].
class BundleManagementScreen extends StatelessWidget {
  const BundleManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CategoryBundleManagementScreen(initialIndex: 1);
  }
}
