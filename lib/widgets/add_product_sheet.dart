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

  @override
  Widget build(BuildContext context) {
    return ProductEditSheet(
      product: product,
      initialBarcode: initialBarcode,
      initialSupplierId: initialSupplierId,
    );
  }
}
