import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/refund_request.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';
import '../widgets/responsive_layout.dart';

enum RefundFilter { all, pending, approved, rejected }

class RefundRequestsScreen extends StatefulWidget {
  const RefundRequestsScreen({super.key});

  @override
  State<RefundRequestsScreen> createState() => _RefundRequestsScreenState();
}

class _RefundRequestsScreenState extends State<RefundRequestsScreen> {
  RefundFilter _selectedFilter = RefundFilter.all;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final reqs = inventory.refundRequests;

    final pendingCount =
        reqs.where((r) => r.status == RefundStatus.pending).length;
    final approvedCount =
        reqs.where((r) => r.status == RefundStatus.approved).length;
    final rejectedCount =
        reqs.where((r) => r.status == RefundStatus.rejected).length;

    final filteredReqs = reqs.where((r) {
      return switch (_selectedFilter) {
        RefundFilter.all => true,
        RefundFilter.pending => r.status == RefundStatus.pending,
        RefundFilter.approved => r.status == RefundStatus.approved,
        RefundFilter.rejected => r.status == RefundStatus.rejected,
      };
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(
              child: Text(
                'Customer Refund Claims',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pendingCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber),
                ),
                child: Text(
                  '$pendingCount PENDING',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900),
                ),
              ),
            ],
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter Chips Segmented Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterChip('All (${reqs.length})', RefundFilter.all),
                const SizedBox(width: 8),
                _filterChip('Pending ($pendingCount)', RefundFilter.pending),
                const SizedBox(width: 8),
                _filterChip('Approved ($approvedCount)', RefundFilter.approved),
                const SizedBox(width: 8),
                _filterChip('Rejected ($rejectedCount)', RefundFilter.rejected),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                inventory.initialize();
              },
              child: filteredReqs.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.4,
                          child: const Center(
                            child: Text(
                                'No refund requests matching this filter.',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      child: ResponsiveCardGrid(
                        children: filteredReqs
                            .map((r) => _RefundCard(req: r, inventory: inventory))
                            .toList(),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, RefundFilter filter) {
    final selected = _selectedFilter == filter;
    return FilterChip(
      label: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      selected: selected,
      onSelected: (_) => setState(() => _selectedFilter = filter),
    );
  }
}

class _RefundCard extends StatelessWidget {
  final RefundRequest req;
  final InventoryProvider inventory;
  const _RefundCard({required this.req, required this.inventory});

  void _showImageLightbox(BuildContext context, String photoBase64) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child:
                  Image.memory(base64Decode(photoBase64), fit: BoxFit.contain),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(req.createdAt);
    final isPending = req.status == RefundStatus.pending;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: (isPending
                    ? Colors.amber
                    : (req.status == RefundStatus.approved
                        ? Colors.green
                        : Colors.red))
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.assignment_return_rounded,
            color: isPending
                ? Colors.amber.shade900
                : (req.status == RefundStatus.approved
                    ? Colors.green
                    : Colors.red),
          ),
        ),
        title: Row(
          children: [
            Expanded(
                child: Text(req.customerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14))),
            Text(formatPeso(req.total),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text('Order #${req.transactionId}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    req.reason,
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(dateStr,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Text('Refund Items:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                ...req.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text('${item.qty}x',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(item.name,
                                  style: const TextStyle(fontSize: 12))),
                          Text(formatPeso(item.price * item.qty),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
                if (req.photoBase64 != null && req.photoBase64!.isNotEmpty) ...[
                  const Divider(),
                  const Text('Photo Proof:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showImageLightbox(context, req.photoBase64!),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.memory(base64Decode(req.photoBase64!),
                              fit: BoxFit.cover, width: 100, height: 100),
                          Container(
                            color: Colors.black.withValues(alpha: 0.2),
                            child: const Icon(Icons.zoom_in_rounded,
                                color: Colors.white, size: 24),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const Divider(),
                if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: (req.status == RefundStatus.approved
                              ? Colors.green
                              : (req.status == RefundStatus.rejected
                                  ? Colors.red
                                  : Colors.grey))
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (req.status == RefundStatus.approved
                                ? Colors.green
                                : (req.status == RefundStatus.rejected
                                    ? Colors.red
                                    : Colors.grey))
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              req.status == RefundStatus.approved
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                              size: 16,
                              color: req.status == RefundStatus.approved
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'STORE RESPONSE:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: req.status == RefundStatus.approved
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          req.adminNotes!,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                ],
                if (isPending) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () =>
                                _handleRefund(context, req, inventory, false),
                            child: const Text('REJECT REQUEST'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                _handleRefund(context, req, inventory, true),
                            child: const Text('APPROVE REFUND'))),
                  ]),
                ] else
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: (req.status == RefundStatus.approved
                                ? Colors.green
                                : Colors.red)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: Center(
                      child: Text(
                          '${req.status.name.toUpperCase()}${req.condition != null ? " (${req.condition!.name.toUpperCase()})" : ""}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: req.status == RefundStatus.approved
                                  ? Colors.green
                                  : Colors.red)),
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

  void _handleRefund(BuildContext context, RefundRequest req,
      InventoryProvider inventory, bool approve) async {
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
              content: Container(
                width: 480,
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1. Select Item Condition (Required):',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      RadioListTile<RefundCondition>(
                        title: const Text('Restockable / Return to Shelf',
                            style: TextStyle(fontSize: 13)),
                        value: RefundCondition.restockable,
                        groupValue: condition,
                        onChanged: (v) => setSt(() => condition = v),
                      ),
                      RadioListTile<RefundCondition>(
                        title: const Text('Damaged Item',
                            style: TextStyle(fontSize: 13)),
                        value: RefundCondition.damaged,
                        groupValue: condition,
                        onChanged: (v) => setSt(() => condition = v),
                      ),
                      RadioListTile<RefundCondition>(
                        title: const Text('Expired Item',
                            style: TextStyle(fontSize: 13)),
                        value: RefundCondition.expired,
                        groupValue: condition,
                        onChanged: (v) => setSt(() => condition = v),
                      ),
                      const SizedBox(height: 16),
                      const Text('2. Store Response to Customer (Mandatory *):',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 3,
                        onChanged: (_) => setSt(() {}),
                        decoration: InputDecoration(
                          hintText:
                              'Enter store explanation or return instructions for customer...',
                          border: const OutlineInputBorder(),
                          errorText: responseText.isEmpty
                              ? 'Store response is mandatory to maintain store rating.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: isValid ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white),
                  child: const Text('APPROVE REFUND'),
                ),
              ],
            );
          },
        ),
      );

      if (res == true &&
          condition != null &&
          notesCtrl.text.trim().isNotEmpty) {
        await inventory.approveRefundRequest(req,
            condition: condition!, notes: notesCtrl.text.trim());
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Refund approved with store response ✅'),
                backgroundColor: Colors.green),
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
              content: Container(
                width: 480,
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'Store Response / Rejection Reason (Mandatory *):',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 3,
                        onChanged: (_) => setSt(() {}),
                        decoration: InputDecoration(
                          hintText:
                              'Explain why this refund request cannot be granted...',
                          border: const OutlineInputBorder(),
                          errorText: responseText.isEmpty
                              ? 'Store response is mandatory to maintain store rating.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('CANCEL')),
                ElevatedButton(
                  onPressed: isValid ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white),
                  child: const Text('DECLINE REFUND'),
                ),
              ],
            );
          },
        ),
      );

      if (res == true && notesCtrl.text.trim().isNotEmpty) {
        final storeResponse = notesCtrl.text.trim();
        await inventory.rejectRefundRequest(req, storeResponse,
            notes: storeResponse);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Refund request declined with store response.'),
                backgroundColor: Colors.orange),
          );
        }
      }
    }
  }
}
