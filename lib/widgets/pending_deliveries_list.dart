import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/restock_inquiry.dart';
import '../providers/restock_provider.dart';
import '../widgets/premium_components.dart';
import 'receive_delivery_sheet.dart';

class PendingDeliveriesList extends StatelessWidget {
  const PendingDeliveriesList({super.key});

  @override
  Widget build(BuildContext context) {
    final restockProvider = context.watch<RestockProvider>();
    final pendingInquiries = restockProvider.inquiries.where((i) =>
      i.status == RestockInquiryStatus.pending ||
      i.status == RestockInquiryStatus.sent ||
      i.status == RestockInquiryStatus.acknowledged ||
      i.status == RestockInquiryStatus.partiallyFulfilled
    ).toList();

    if (pendingInquiries.isEmpty) {
      return const PremiumEmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No Pending Supplier Deliveries',
        subtitle: 'All restock orders have been received and reconciled.',
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pendingInquiries.length,
      itemBuilder: (context, index) {
        final inquiry = pendingInquiries[index];
        final bool isPartial = inquiry.status == RestockInquiryStatus.partiallyFulfilled;

        return PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isPartial ? Colors.orange : Colors.blue).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isPartial ? Icons.pending_actions_rounded : Icons.local_shipping_rounded,
                          color: isPartial ? Colors.orange.shade800 : Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inquiry.supplierName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Order #${inquiry.inquiryNumber} • ${DateFormat('MMM d, yyyy').format(inquiry.createdAt)}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isPartial ? Colors.orange : Colors.blue).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isPartial ? 'PARTIAL DELIVERY' : 'AWAITING DELIVERY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isPartial ? Colors.orange.shade800 : Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Expected Items: ${inquiry.items.length} items (${inquiry.totalRequestedQty} total pcs)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ReceiveDeliverySheet(inquiry: inquiry),
                      );
                    },
                    icon: const Icon(Icons.move_to_inbox_rounded, size: 16),
                    label: const Text('RECEIVE DELIVERY'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
