import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/loss_record.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';

class BatchAuditSheet extends StatefulWidget {
  final Product product;
  const BatchAuditSheet({super.key, required this.product});

  @override
  State<BatchAuditSheet> createState() => _BatchAuditSheetState();
}

class _BatchAuditSheetState extends State<BatchAuditSheet> {
  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    Product p = widget.product;
    try {
      p = inventory.products.firstWhere((prod) => prod.id == widget.product.id);
    } catch (_) {}

    final List<ProductBatch> batches = List.from(p.batches);
    // Sort by FEFO (expiry date / created date ascending)
    batches.sort((a, b) {
      if (a.expiryDate != null && b.expiryDate != null) {
        return a.expiryDate!.compareTo(b.expiryDate!);
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    final int totalBatchStock = batches.fold(0, (sum, b) => sum + b.quantity);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20, right: 20, top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 2),
                      Text('Category: ${p.category} • Total Batches: ${batches.length}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$totalBatchStock ${p.unit} in Batches',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            if (batches.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No active delivery batches recorded yet.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: batches.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final b = batches[index];
                  final now = DateTime.now();

                  bool isExpired = b.expiryDate != null && b.expiryDate!.isBefore(now);
                  bool isNearExpiry = b.expiryDate != null && !isExpired && b.expiryDate!.difference(now).inDays <= 30;
                  bool isDepleted = b.quantity <= 0;

                  Color statusColor = Colors.green;
                  String statusLabel = 'ACTIVE';

                  if (isDepleted) {
                    statusColor = Colors.grey;
                    statusLabel = 'DEPLETED';
                  } else if (isExpired) {
                    statusColor = Colors.red;
                    statusLabel = 'EXPIRED';
                  } else if (isNearExpiry) {
                    statusColor = Colors.orange.shade800;
                    statusLabel = 'NEAR EXPIRY';
                  }

                  final int days = b.expiryDate?.difference(now).inDays ?? 999;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isDepleted ? Icons.inventory_2_outlined : (isExpired ? Icons.event_busy : Icons.inventory_rounded),
                            color: statusColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Batch #${b.id.length >= 8 ? b.id.substring(0, 8) : b.id}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Received: ${DateFormat('MMM d, yyyy').format(b.createdAt)} • Unit Cost: ${formatPeso(b.unitCost)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              if (b.invoiceNumber != null && b.invoiceNumber!.isNotEmpty)
                                Text('Invoice/DR: ${b.invoiceNumber}', style: const TextStyle(fontSize: 10, color: Colors.blue)),
                              if (b.expiryDate != null)
                                Text(
                                  days <= 0 ? 'Expired on ${DateFormat('MMM d, yyyy').format(b.expiryDate!)}' : 'Expires in $days days (${DateFormat('MMM d, yyyy').format(b.expiryDate!)})',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isExpired || isNearExpiry ? statusColor : Colors.grey),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${b.quantity} ${p.unit}',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isDepleted ? Colors.grey : Colors.green.shade800),
                            ),
                            if (!isDepleted)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 18),
                                onSelected: (val) {
                                  if (val == 'spoil') {
                                    _logBatchLossDialog(context, p, b);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'spoil',
                                    child: Row(
                                      children: [
                                        Icon(Icons.remove_circle_outline, size: 16, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Mark Loss / Spoiled'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _logBatchLossDialog(BuildContext context, Product product, ProductBatch batch) {
    final qtyCtrl = TextEditingController(text: '1');
    LossType lossType = LossType.expired;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Text('Mark Batch Stock Write-off'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Product: ${product.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Available in Batch: ${batch.quantity} ${product.unit}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity Lost/Spoiled', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LossType>(
                initialValue: lossType,
                decoration: const InputDecoration(labelText: 'Reason for Loss', border: OutlineInputBorder()),
                items: LossType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase()))).toList(),
                onChanged: (val) {
                  if (val != null) setSt(() => lossType = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final qty = int.tryParse(qtyCtrl.text) ?? 0;
                if (qty <= 0 || qty > batch.quantity) return;

                final inventory = context.read<InventoryProvider>();
                await inventory.logLoss(LossRecord(
                  id: '',
                  productId: product.id,
                  productName: product.name,
                  qty: qty,
                  unitPrice: batch.unitCost > 0 ? batch.unitCost : product.costPrice,
                  type: lossType,
                  notes: 'Write-off from Batch #${batch.id.length >= 8 ? batch.id.substring(0, 8) : batch.id}',
                  createdAt: DateTime.now(),
                ));

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
              child: const Text('Confirm Write-off'),
            ),
          ],
        ),
      ),
    );
  }
}
