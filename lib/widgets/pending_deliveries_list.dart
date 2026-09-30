import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/restock_inquiry.dart';
import '../providers/restock_provider.dart';
import '../utils/format.dart';
import '../widgets/premium_components.dart';
import 'receive_delivery_sheet.dart';

class PendingDeliveriesList extends StatelessWidget {
  const PendingDeliveriesList({super.key});

  @override
  Widget build(BuildContext context) {
    final restockProvider = context.watch<RestockProvider>();
    final pendingInquiries = restockProvider.inquiries
        .where((i) =>
            i.status == RestockInquiryStatus.pending ||
            i.status == RestockInquiryStatus.sent ||
            i.status == RestockInquiryStatus.acknowledged ||
            i.status == RestockInquiryStatus.partiallyFulfilled)
        .toList();

    if (pendingInquiries.isEmpty) {
      return const PremiumEmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No Pending Supplier Deliveries',
        subtitle: 'All restock orders have been received and reconciled.',
      );
    }

    return ResponsiveCardGrid(
      children: pendingInquiries.map((inquiry) {
        final bool isPartial =
            inquiry.status == RestockInquiryStatus.partiallyFulfilled;

        final String etaText = inquiry.expectedDeliveryDate != null
            ? 'ETA: ${DateFormat('MMM d, yyyy').format(inquiry.expectedDeliveryDate!)}'
            : 'Scheduled Arrival: Pending Supplier';

        return PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Supplier Name & Delivery Status Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        inquiry.supplierName.isNotEmpty
                            ? inquiry.supplierName[0].toUpperCase()
                            : 'S',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inquiry.supplierName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          if (inquiry.supplierContact != null &&
                              inquiry.supplierContact!.isNotEmpty)
                            Text(
                              'Contact: ${inquiry.supplierContact}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            'Order #${inquiry.inquiryNumber} • Placed ${DateFormat('MMM d, yyyy').format(inquiry.createdAt)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (isPartial ? Colors.orange : Colors.blue)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isPartial
                                ? Colors.orange.shade400
                                : Colors.blue.shade300),
                      ),
                      child: Text(
                        isPartial ? 'PARTIAL DELIVERY' : 'AWAITING SHIPMENT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isPartial
                              ? Colors.orange.shade900
                              : Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Expected Arrival Time (ETA) Banner
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: inquiry.expectedDeliveryDate != null
                            ? Colors.teal.shade700
                            : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        etaText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: inquiry.expectedDeliveryDate != null
                              ? Colors.teal.shade900
                              : Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Item Breakdown Chips
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: inquiry.items.map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '${item.productName}: ${item.requestedQty} ${item.unit}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),

                const Divider(height: 24),

                // Footer: Order Totals & Action Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${inquiry.items.length} items (${inquiry.totalRequestedQty} total pcs)',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Total Order: ${formatPeso(inquiry.totalOrderedValue)}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.green),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) =>
                              ReceiveDeliverySheet(inquiry: inquiry),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 18),
                      label: const Text('VERIFY & RECEIVE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade800,
                        foregroundColor: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      );
  }
}
