import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';
import '../utils/barcode_generator.dart';

/// A Material 3 GridView for POS that displays PLU / internal items (barcodes starting with '200')
/// so cashiers can quickly tap to add items like fresh eggs, rice, or produce without scanning.
class QuickSelectGrid extends StatelessWidget {
  final Function(Product) onProductSelected;

  const QuickSelectGrid({
    super.key,
    required this.onProductSelected,
  });

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    // Filter for published items whose barcode starts with '200'
    final pluProducts = inventory.products.where((p) {
      return p.status == ProductStatus.published && 
             BarcodeGenerator.isInternalPluBarcode(p.barcode);
    }).toList();

    if (pluProducts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No PLU Quick Select Items',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Items saved without barcodes (starting with 200) will appear here for 1-tap POS checkout.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.85,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: pluProducts.length,
      itemBuilder: (context, index) {
        final product = pluProducts[index];
        final bool isOutOfStock = product.totalStock <= 0;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
          ),
          child: InkWell(
            onTap: isOutOfStock ? null : () => onProductSelected(product),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: product.photoBase64 != null
                          ? Image.memory(base64Decode(product.photoBase64!), fit: BoxFit.cover)
                          : Center(
                              child: Icon(
                                Icons.shopping_basket_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: 28,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatPeso(product.price),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${product.totalStock} ${product.unit}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isOutOfStock ? Colors.red : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
