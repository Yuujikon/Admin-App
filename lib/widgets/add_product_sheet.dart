import 'package:flutter/material.dart';
import '../models/product.dart';
import 'product_edit_sheet.dart';

/// Unified Add/Edit product sheet adapter forwarding to [ProductEditSheet].
class AddProductSheet extends StatelessWidget {
  final String? initialBarcode;
  final String? initialSupplierId;
  final Product? product;

  const AddProductSheet({
    super.key,
    this.initialBarcode,
    this.initialSupplierId,
    this.product,
  });

  /// Standard launcher for [AddProductSheet] as a bottom sheet with gesture safety & scroll control.
  static Future<T?> show<T>({
    required BuildContext context,
    String? initialBarcode,
    String? initialSupplierId,
    Product? product,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddProductSheet(
        initialBarcode: initialBarcode,
        initialSupplierId: initialSupplierId,
        product: product,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProductEditSheet(
      product: product,
      initialBarcode: initialBarcode,
      initialSupplierId: initialSupplierId,
    );
  }
}
