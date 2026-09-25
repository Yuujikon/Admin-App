import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/loss_record.dart';
import '../config/theme.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';

class LossManagementScreen extends StatelessWidget {
  const LossManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lossRecords = context.watch<InventoryProvider>().lossRecords;
    final totalLossValue = lossRecords.fold(0.0, (s, r) => s + r.totalLoss);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Loss & Waste')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Column(
              children: [
                Text('Total Estimated Loss', style: Theme.of(context).textTheme.labelSmall),
                Text(formatPeso(totalLossValue), 
                     style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
          Expanded(
            child: lossRecords.isEmpty
                ? const Center(child: Text('No loss records found.'))
                : ListView.builder(
                    itemCount: lossRecords.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (context, index) {
                      final r = lossRecords[index];
                      return Card(
                        child: ListTile(
                          leading: _typeIcon(r.type, context),
                          title: Text(r.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${r.type.name.toUpperCase().replaceAll('_', ' ')} • ${r.qty} items'),
                              if (r.notes.isNotEmpty)
                                Text('"${r.notes}"', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 11)),
                              Text(DateFormat('MMM dd, yyyy').format(r.createdAt), style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                          trailing: Text('-${formatPeso(r.totalLoss)}', 
                                     style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _typeIcon(LossType type, BuildContext context) {
    final semantic = Theme.of(context).semantic;
    return switch (type) {
      LossType.expired     => Icon(Icons.timer_off, color: semantic.warning),
      LossType.damaged     => Icon(Icons.broken_image, color: Theme.of(context).colorScheme.error),
      LossType.lost        => Icon(Icons.not_listed_location, color: Theme.of(context).colorScheme.onSurfaceVariant),
      LossType.personalUse => Icon(Icons.person_outline, color: semantic.info),
      LossType.refundReturn => const Icon(Icons.assignment_return_rounded, color: Colors.deepOrange),
    };
  }
}
