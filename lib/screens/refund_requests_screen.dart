import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/refund_request.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';

class RefundRequestsScreen extends StatelessWidget {
  const RefundRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final reqs = inventory.refundRequests;
    final pendingReqs = reqs.where((r) => r.status == RefundStatus.pending).toList();
    final pastReqs = reqs.where((r) => r.status != RefundStatus.pending).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Refund Requests'),
            if (pendingReqs.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber),
                ),
                child: Text(
                  '${pendingReqs.length} PENDING',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                ),
              ),
            ],
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          inventory.initialize();
        },
        child: reqs.isEmpty 
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: const Center(child: Text('No refund requests found.', style: TextStyle(color: Colors.grey))),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (pendingReqs.isNotEmpty) ...[
                  Text('Pending Requests (${pendingReqs.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...pendingReqs.map((r) => _RefundCard(req: r, inventory: inventory, isPending: true)),
                  const SizedBox(height: 16),
                ],
                if (pastReqs.isNotEmpty) ...[
                  Text('Past Requests (${pastReqs.length})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  ...pastReqs.map((r) => _RefundCard(req: r, inventory: inventory, isPending: false)),
                ],
              ],
            ),
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
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(req.createdAt);

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
            Text('Ref #: ${req.transactionId} • $dateStr', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
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
                if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: (req.status == RefundStatus.approved ? Colors.green : (req.status == RefundStatus.rejected ? Colors.red : Colors.grey)).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (req.status == RefundStatus.approved ? Colors.green : (req.status == RefundStatus.rejected ? Colors.red : Colors.grey)).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              req.status == RefundStatus.approved ? Icons.check_circle_outline : Icons.info_outline,
                              size: 16,
                              color: req.status == RefundStatus.approved ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'STORE RESPONSE:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: req.status == RefundStatus.approved ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          req.adminNotes!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
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
                      child: const Text('REJECT / REFUSE')
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
          builder: (context, setSt) {
            final responseText = notesCtrl.text.trim();
            final bool isValid = condition != null && responseText.isNotEmpty;

            return AlertDialog(
              title: const Text('Approve Refund Request'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1. Select Item Condition (Required):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      _conditionOption(setSt, 'Restockable / Return to Shelf', RefundCondition.restockable, condition, (v) => condition = v),
                      _conditionOption(setSt, 'Damaged Item', RefundCondition.damaged, condition, (v) => condition = v),
                      _conditionOption(setSt, 'Expired Item', RefundCondition.expired, condition, (v) => condition = v),
                      const SizedBox(height: 16),
                      const Text('2. Store Response to Customer (Mandatory *):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 3,
                        onChanged: (_) => setSt(() {}),
                        decoration: InputDecoration(
                          hintText: 'Enter store explanation or return instructions for customer...',
                          border: const OutlineInputBorder(),
                          errorText: responseText.isEmpty ? 'Store response is mandatory to maintain store rating.' : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Quick Suggestions:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ActionChip(
                            label: const Text('Approved per return policy', style: TextStyle(fontSize: 10)),
                            onPressed: () {
                              notesCtrl.text = 'Approved per store return policy. Thank you for your business!';
                              setSt(() {});
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                          ActionChip(
                            label: const Text('Item inspected & accepted', style: TextStyle(fontSize: 10)),
                            onPressed: () {
                              notesCtrl.text = 'Item state inspected and verified. Refund approved.';
                              setSt(() {});
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: isValid ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
                  child: const Text('APPROVE REFUND'),
                ),
              ],
            );
          },
        ),
      );

      if (res == true && condition != null && notesCtrl.text.trim().isNotEmpty) {
        await inventory.approveRefundRequest(req, condition: condition!, notes: notesCtrl.text.trim());
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Refund approved with store response ✅'), backgroundColor: Colors.green),
          );
        }
      }
    } else {
      final res = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setSt) {
            final responseText = notesCtrl.text.trim();
            final bool isValid = responseText.isNotEmpty;

            return AlertDialog(
              title: const Text('Decline / Reject Refund'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Store Response / Rejection Reason (Mandatory *):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      const Text(
                        'A polite, clear store response is required so customers understand the reason for declining:',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 3,
                        onChanged: (_) => setSt(() {}),
                        decoration: InputDecoration(
                          hintText: 'Explain why this refund request cannot be granted...',
                          border: const OutlineInputBorder(),
                          errorText: responseText.isEmpty ? 'Store response is mandatory to maintain store rating.' : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Quick Suggestions:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ActionChip(
                            label: const Text('Beyond return timeframe', style: TextStyle(fontSize: 10)),
                            onPressed: () {
                              notesCtrl.text = 'Request exceeds our allowed return timeframe per store policy.';
                              setSt(() {});
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                          ActionChip(
                            label: const Text('Item consumed/opened', style: TextStyle(fontSize: 10)),
                            onPressed: () {
                              notesCtrl.text = 'Item has been consumed or opened beyond store return eligibility.';
                              setSt(() {});
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                          ActionChip(
                            label: const Text('No valid proof provided', style: TextStyle(fontSize: 10)),
                            onPressed: () {
                              notesCtrl.text = 'Unable to verify item condition or receipt details.';
                              setSt(() {});
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: isValid ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('DECLINE REFUND'),
                ),
              ],
            );
          },
        ),
      );

      if (res == true && notesCtrl.text.trim().isNotEmpty) {
        final storeResponse = notesCtrl.text.trim();
        await inventory.rejectRefundRequest(req, storeResponse, notes: storeResponse);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Refund request declined with store response.'), backgroundColor: Colors.orange),
          );
        }
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
