import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/order.dart';

class StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const StatusBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).semantic;
    final (label, bg, fg) = switch (status) {
      OrderStatus.pending        => ('Pending',   semantic.warning.withValues(alpha: 0.1), semantic.warning),
      OrderStatus.staging        => ('Packing',   semantic.info.withValues(alpha: 0.1),    semantic.info),
      OrderStatus.ready          => ('Ready',     semantic.success.withValues(alpha: 0.1), semantic.success),
      OrderStatus.collected      => ('Collected', semantic.success.withValues(alpha: 0.1), semantic.success),
      OrderStatus.cancelled      => ('Cancelled', Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1), Theme.of(context).colorScheme.error),
      OrderStatus.refunded        => ('Refunded',  Theme.of(context).disabledColor.withValues(alpha: 0.1), Theme.of(context).disabledColor),
      OrderStatus.refundRequested => ('Refund Requested', semantic.warning.withValues(alpha: 0.1), semantic.warning),
      OrderStatus.refundRejected  => ('Refund Rejected',  Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1), Theme.of(context).colorScheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(50)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}