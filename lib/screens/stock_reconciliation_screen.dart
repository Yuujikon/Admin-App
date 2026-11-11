import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../models/loss_record.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';
import '../widgets/premium_components.dart';

class StockReconciliationScreen extends StatefulWidget {
  final Product? initialProduct;

  const StockReconciliationScreen({super.key, this.initialProduct});

  @override
  State<StockReconciliationScreen> createState() =>
      _StockReconciliationScreenState();
}

class _StockReconciliationScreenState extends State<StockReconciliationScreen> {
  Product? _selectedProduct;
  final Map<String, TextEditingController> _batchCountControllers = {};
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
    if (_selectedProduct != null) {
      _initControllersForProduct(_selectedProduct!);
    }
  }

  void _initControllersForProduct(Product product) {
    for (var controller in _batchCountControllers.values) {
      controller.dispose();
    }
    _batchCountControllers.clear();

    for (var b in product.batches) {
      _batchCountControllers[b.id] =
          TextEditingController(text: b.quantity.toString());
    }
  }

  @override
  void dispose() {
    for (var controller in _batchCountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final products = inventory.products;

    if (_selectedProduct != null) {
      try {
        _selectedProduct =
            products.firstWhere((p) => p.id == _selectedProduct!.id);
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Audit & Reconciliation'),
        actions: [
          if (_selectedProduct != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reset Physical Counts',
              onPressed: () =>
                  setState(() => _initControllersForProduct(_selectedProduct!)),
            ),
        ],
      ),
      body: SafeArea(
        child: MaxWidthContainer(
          maxWidth: 900,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Selector
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Product for Shelf Count Audit',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return Autocomplete<Product>(
                            displayStringForOption: (Product p) => p.name,
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) {
                                return products;
                              }
                              final q = textEditingValue.text.toLowerCase();
                              return products.where((p) =>
                                  p.name.toLowerCase().contains(q) ||
                                  (p.barcode?.toLowerCase().contains(q) ??
                                      false) ||
                                  p.category.toLowerCase().contains(q));
                            },
                            onSelected: (Product p) {
                              setState(() {
                                _selectedProduct = p;
                                _initControllersForProduct(p);
                              });
                            },
                            fieldViewBuilder: (context, textController,
                                focusNode, onFieldSubmitted) {
                              if (_selectedProduct != null &&
                                  !focusNode.hasFocus &&
                                  (textController.text.isEmpty ||
                                      textController.text !=
                                          _selectedProduct!.name)) {
                                textController.text = _selectedProduct!.name;
                              }
                              return TextFormField(
                                controller: textController,
                                focusNode: focusNode,
                                decoration: InputDecoration(
                                  hintText: 'Search or choose product...',
                                  prefixIcon:
                                      const Icon(Icons.inventory_2_outlined),
                                  suffixIcon: _selectedProduct != null ||
                                          textController.text.isNotEmpty
                                      ? IconButton(
                                          icon:
                                              const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            textController.clear();
                                            setState(() {
                                              _selectedProduct = null;
                                            });
                                          },
                                        )
                                      : const Icon(Icons.arrow_drop_down),
                                ),
                                onChanged: (val) {
                                  if (_selectedProduct != null &&
                                      val != _selectedProduct!.name) {
                                    setState(() {
                                      _selectedProduct = null;
                                    });
                                  }
                                },
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 8,
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: Container(
                                    width: constraints.maxWidth,
                                    constraints:
                                        const BoxConstraints(maxHeight: 280),
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(
                                              height: 1,
                                              indent: 12,
                                              endIndent: 12),
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                        final Product option =
                                            options.elementAt(index);
                                        final bool isSelected =
                                            option.id == _selectedProduct?.id;
                                        return ListTile(
                                          dense: true,
                                          selected: isSelected,
                                          selectedTileColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withValues(alpha: 0.2),
                                          leading: Icon(
                                            Icons.inventory_2_outlined,
                                            size: 20,
                                            color: isSelected
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : Colors.grey.shade600,
                                          ),
                                          title: Text(
                                            option.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                          ),
                                          subtitle: Text(
                                            '${option.category} • Stock: ${option.totalStock} ${option.unit}${option.barcode != null ? " • Barcode: ${option.barcode}" : ""}',
                                            style:
                                                const TextStyle(fontSize: 11),
                                          ),
                                          trailing: Text(
                                            formatPeso(option.price),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                          onTap: () => onSelected(option),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (_selectedProduct == null)
                const Expanded(
                  child: PremiumEmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'No Product Selected',
                    subtitle:
                        'Choose a product above to inspect expected batches and reconcile physical counts.',
                  ),
                )
              else ...[
                Expanded(
                  child: ListView(
                    children: [
                      _buildProductSummaryHeader(_selectedProduct!),
                      const SizedBox(height: 16),
                      _buildBatchesAuditList(_selectedProduct!),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionFooter(_selectedProduct!, inventory),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductSummaryHeader(Product p) {
    final int systemTotal = p.batches.fold(0, (s, b) => s + b.quantity);
    int physicalTotal = 0;

    for (var b in p.batches) {
      final ctrl = _batchCountControllers[b.id];
      final val = int.tryParse(ctrl?.text ?? '') ?? b.quantity;
      physicalTotal += val;
    }

    final int discrepancy = physicalTotal - systemTotal;
    final Color discColor = discrepancy == 0
        ? Colors.green.shade700
        : (discrepancy < 0
            ? Theme.of(context).colorScheme.error
            : Colors.orange.shade800);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryColumn('Expected System Qty', '$systemTotal ${p.unit}',
              Colors.blue.shade800),
          Container(
              width: 1,
              height: 36,
              color: Theme.of(context).colorScheme.outlineVariant),
          _summaryColumn('Actual Physical Qty', '$physicalTotal ${p.unit}',
              Colors.black87),
          Container(
              width: 1,
              height: 36,
              color: Theme.of(context).colorScheme.outlineVariant),
          _summaryColumn('Discrepancy Variance',
              '${discrepancy > 0 ? '+' : ''}$discrepancy ${p.unit}', discColor),
        ],
      ),
    );
  }

  Widget _summaryColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _buildBatchesAuditList(Product p) {
    final batches = List<ProductBatch>.from(p.batches);
    batches.sort((a, b) {
      if (a.expiryDate != null && b.expiryDate != null) {
        return a.expiryDate!.compareTo(b.expiryDate!);
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    if (batches.isEmpty) {
      return const PremiumEmptyState(
        icon: Icons.assignment_late_outlined,
        title: 'No Batches Found',
        subtitle: 'This product has no active delivery batches recorded.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active Batches (FEFO Sorted)',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: batches.length,
          itemBuilder: (context, index) {
            final b = batches[index];
            final ctrl = _batchCountControllers[b.id] ??=
                TextEditingController(text: b.quantity.toString());
            final int physicalVal = int.tryParse(ctrl.text) ?? b.quantity;
            final int batchDiff = physicalVal - b.quantity;

            final now = DateTime.now();
            final bool isExpired =
                b.expiryDate != null && b.expiryDate!.isBefore(now);
            final int daysRemaining =
                b.expiryDate?.difference(now).inDays ?? 999;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: batchDiff != 0
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isExpired ? Colors.red : Colors.green)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isExpired
                            ? Icons.event_busy_rounded
                            : Icons.inventory_2_rounded,
                        color: isExpired ? Colors.red : Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Batch #${b.id.length >= 8 ? b.id.substring(0, 8) : b.id}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Received: ${DateFormat('MMM d, yyyy').format(b.createdAt)} • Cost: ${formatPeso(b.unitCost)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                          if (b.expiryDate != null)
                            Text(
                              isExpired
                                  ? 'EXPIRED on ${DateFormat('MMM d, yyyy').format(b.expiryDate!)}'
                                  : 'Expires in $daysRemaining days (${DateFormat('MMM d, yyyy').format(b.expiryDate!)})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isExpired
                                    ? Colors.red
                                    : (daysRemaining <= 30
                                        ? Colors.orange.shade800
                                        : Colors.grey),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        textAlign: TextAlign.center,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Shelf Count',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          suffixText: p.unit,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionFooter(Product p, InventoryProvider inventory) {
    int totalDiff = 0;
    for (var b in p.batches) {
      final ctrl = _batchCountControllers[b.id];
      final val = int.tryParse(ctrl?.text ?? '') ?? b.quantity;
      totalDiff += (val - b.quantity);
    }

    return Center(
      child: PrimaryButton(
        onPressed: (_isProcessing || totalDiff == 0)
            ? null
            : () => _reconcileStock(p, inventory),
        isLoading: _isProcessing,
        icon: Icons.check_circle_rounded,
        backgroundColor: totalDiff < 0
            ? Theme.of(context).colorScheme.error
            : Colors.green.shade700,
        foregroundColor: Colors.white,
        minWidth: 200,
        maxWidth: 350,
        child: Text(_isProcessing
            ? 'Processing Reconciliation...'
            : (totalDiff == 0
                ? 'PHYSICAL COUNT MATCHES SYSTEM'
                : 'RESOLVE & ADJUST STOCK (${totalDiff > 0 ? '+' : ''}$totalDiff ${p.unit})')),
      ),
    );
  }

  Future<void> _reconcileStock(
      Product product, InventoryProvider inventory) async {
    setState(() => _isProcessing = true);

    try {
      final List<ProductBatch> updatedBatches = [];
      int netAdjustment = 0;

      for (var b in product.batches) {
        final ctrl = _batchCountControllers[b.id];
        final newQty = int.tryParse(ctrl?.text ?? '') ?? b.quantity;
        final diff = newQty - b.quantity;

        if (diff != 0) {
          netAdjustment += diff;

          // If discrepancy (shortage/loss), log a LossRecord
          if (diff < 0) {
            final int lostQty = diff.abs();
            await inventory.logLoss(LossRecord(
              id: '',
              productId: product.id,
              productName: product.name,
              qty: lostQty,
              unitPrice: b.unitCost > 0 ? b.unitCost : product.costPrice,
              type: LossType.damaged,
              notes:
                  'Audit Discrepancy Reconciliation on Batch #${b.id.length >= 8 ? b.id.substring(0, 8) : b.id}',
              createdAt: DateTime.now(),
            ));
          }
        }

        updatedBatches.add(ProductBatch(
          id: b.id,
          productId: b.productId,
          quantity: newQty,
          unitCost: b.unitCost,
          expiryDate: b.expiryDate,
          createdAt: b.createdAt,
          invoiceNumber: b.invoiceNumber,
        ));
      }

      final int newTotalStock =
          (product.stock + netAdjustment).clamp(0, 999999);
      final updatedProduct = product.copyWith(
        stock: newTotalStock,
        batches: updatedBatches,
      );

      await inventory.saveProduct(updatedProduct);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reconciliation Complete for "${product.name}" ✅'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error reconciling stock: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
