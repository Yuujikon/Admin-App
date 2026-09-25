import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/refund_request.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';

class RefundRequestsScreen extends StatelessWidget {
  const RefundRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final reqs = inventory.refundRequests;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Refund Requests')),
      body: reqs.isEmpty 
        ? const Center(child: Text('No refund requests.'))
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (reqs.any((r) => r.status == RefundStatus.pending)) ...[
                const Text('Pending Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ...reqs.where((r) => r.status == RefundStatus.pending).map((r) => _RefundCard(req: r, inventory: inventory, isPending: true)),
                const SizedBox(height: 16),
              ],
              if (reqs.any((r) => r.status != RefundStatus.pending)) ...[
                const Text('Past Requests', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                ...reqs.where((r) => r.status != RefundStatus.pending).map((r) => _RefundCard(req: r, inventory: inventory, isPending: false)),
              ],
            ],
          ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  final RefundRequest req;
  final InventoryProvider inventory;
  final bool isPending;
  const _RefundCard({required this.req, required this.inventory, required this.isPending});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.assignment_return_rounded, color: Theme.of(context).colorScheme.error),
        ),
        title: Row(
          children: [
            Expanded(child: Text(req.customerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
            Text(formatPeso(req.total), style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Ref #:${req.transactionId}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text('Reason: ${req.reason}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Text('Refund Items:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                ...req.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text('${item.qty}x', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.name, style: const TextStyle(fontSize: 12))),
                      Text(formatPeso(item.price * item.qty), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                )),
                const Divider(),
                if (req.adminNotes != null) ...[
                  const Text('Admin Notes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                  Text(req.adminNotes!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  const Divider(),
                ],
                if (isPending) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => _handleRefund(context, req, inventory, false), 
                      child: const Text('REJECT')
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _handleRefund(context, req, inventory, true), 
                      child: const Text('APPROVE')
                    )),
                  ]),
                ] else Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (req.status == RefundStatus.approved ? Colors.green : Colors.red).withValues(alpha: 0.1), 
                    borderRadius: BorderRadius.circular(12)
                  ),
                  child: Center(
                    child: Text(
                      '${req.status.name.toUpperCase()}${req.condition != null ? " (${req.condition!.name.toUpperCase()})" : ""}', 
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: req.status == RefundStatus.approved ? Colors.green : Colors.red)
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleRefund(BuildContext context, RefundRequest req, InventoryProvider inventory, bool approve) async {
    final notesCtrl = TextEditingController();
    
    if (approve) {
      RefundCondition? condition;
      
      final res = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setSt) => AlertDialog(
            title: const Text('Approve Refund'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select item condition:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  _conditionOption(setSt, 'Expired Item', RefundCondition.expired, condition, (v) => condition = v),
                  _conditionOption(setSt, 'Damaged Item', RefundCondition.damaged, condition, (v) => condition = v),
                  _conditionOption(setSt, 'Restockable / Return to Shelf', RefundCondition.restockable, condition, (v) => condition = v),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Admin Description / Notes',
                      hintText: 'Add details about the item state...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: condition == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('APPROVE'),
              ),
            ],
          ),
        ),
      );

      if (res == true && condition != null) {
        await inventory.approveRefundRequest(req, condition: condition!, notes: notesCtrl.text.trim());
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refund approved')));
      }
    } else {
      final res = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject Refund'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Provide a reason for the customer:'),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Rejection Reason',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true), 
              child: const Text('REJECT', style: TextStyle(color: Colors.red))
            ),
          ],
        ),
      );

      if (res == true && notesCtrl.text.trim().isNotEmpty) {
        await inventory.rejectRefundRequest(req, notesCtrl.text.trim(), notes: 'Rejected: ${notesCtrl.text.trim()}');
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refund rejected')));
      }
    }
  }

  Widget _conditionOption(StateSetter setSt, String label, RefundCondition value, RefundCondition? current, ValueChanged<RefundCondition> onSelected) {
    return RadioListTile<RefundCondition>(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      groupValue: current,
      dense: true,
      contentPadding: EdgeInsets.zero,
      onChanged: (v) {
        if (v != null) {
          setSt(() => onSelected(v));
        }
      },
    );
  }
}
