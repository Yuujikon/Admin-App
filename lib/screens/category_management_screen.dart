import 'package:flutter/material.dart';
import 'category_bundle_management_screen.dart';

/// Legacy entry point for Category Management.
/// Delegates to the unified [CategoryBundleManagementScreen].
class CategoryManagementScreen extends StatelessWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CategoryBundleManagementScreen(initialIndex: 0);
  }
}
