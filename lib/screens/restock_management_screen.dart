import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/inventory_provider.dart';
import '../../models/product.dart';
import '../../utils/format.dart';
import '../config/theme.dart';

class RestockManagementScreen extends StatelessWidget {
  const RestockManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final lowStock = inventory.products.where((p) => p.stock <= p.lowStockThreshold).toList();
    
    // Sort low stock by priority (out of stock first)
    lowStock.sort((a, b) => a.stock.compareTo(b.stock));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Restock Management'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          if (lowStock.isNotEmpty)
            TextButton.icon(
              onPressed: () => _emailAllSuppliers(context, lowStock),
              icon: const Icon(Icons.email_outlined),
              label: const Text('Email All'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: lowStock.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 64, color: Theme.of(context).semantic.success.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  const Text('All items are well-stocked!', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lowStock.length,
              itemBuilder: (context, i) {
                final p = lowStock[i];
                final isOutOfStock = p.stock <= 0;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isOutOfStock ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1))),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: (isOutOfStock ? Colors.red : Colors.orange).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isOutOfStock ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                        color: isOutOfStock ? Colors.red : Colors.orange,
                      ),
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p.category} • Current: ${p.stock} ${p.unit}'),
                        Text('Threshold: ${p.lowStockThreshold} ${p.unit}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    trailing: IconButton.filledTonal(
                      onPressed: () => _emailSpecificRestock(context, p),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      tooltip: 'Draft Restock Email',
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _emailSpecificRestock(BuildContext context, Product p) async {
    final buffer = StringBuffer('Sari-Sari Store Restock Request\n\n');
    buffer.writeln('Item: ${p.name}');
    buffer.writeln('Category: ${p.category}');
    buffer.writeln('Current Stock: ${p.stock} ${p.unit}');
    buffer.writeln('Threshold: ${p.lowStockThreshold} ${p.unit}');
    buffer.writeln('Suggested Restock: ${p.lowStockThreshold * 3} ${p.unit}');
    buffer.writeln('\nPlease let us know if this is available for delivery. Thank you!');

    final body = buffer.toString();
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: '', 
      queryParameters: {
        'subject': 'Restock Request: ${p.name}',
        'body': body,
      },
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      await Clipboard.setData(ClipboardData(text: body));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied restock details to clipboard.')));
      }
    }
  }

  void _emailAllSuppliers(BuildContext context, List<Product> items) async {
    final buffer = StringBuffer('Sari-Sari Store - Compiled Restock List\n\n');
    buffer.writeln('The following items need restocking:\n');
    
    for (final p in items) {
      buffer.writeln('• ${p.name} (${p.category})');
      buffer.writeln('  Current: ${p.stock} ${p.unit} | Suggested: ${p.lowStockThreshold * 3} ${p.unit}\n');
    }

    final body = buffer.toString();
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: '', 
      queryParameters: {
        'subject': 'Urgent Restock Request - GDC Sari-Sari Store',
        'body': body,
      },
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      await Clipboard.setData(ClipboardData(text: body));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied list to clipboard.')));
      }
    }
  }
}
