import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/inventory_provider.dart';
import '../../models/store_settings.dart';
import '../config/theme.dart';

class CategoryManagementScreen extends StatelessWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final settings = inventory.settings;
    final categories = settings.masterCategories;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Category Management'), backgroundColor: Theme.of(context).colorScheme.surface),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, inventory, settings),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Category'),
      ),
      body: categories.isEmpty 
          ? const Center(child: Text('No categories defined.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: categories.length,
              itemBuilder: (ctx, i) {
                final cat = categories[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(cat, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmDelete(context, inventory, settings, cat),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showAddDialog(BuildContext context, InventoryProvider inventory, StoreSettings settings) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Category Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              if (settings.masterCategories.contains(name)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category already exists.')));
                return;
              }

              final newCats = List<String>.from(settings.masterCategories)..add(name)..sort();
              await inventory.saveStoreSettings(StoreSettings(
                isClosed: settings.isClosed,
                closureMessage: settings.closureMessage,
                scheduledCloseAt: settings.scheduledCloseAt,
                scheduledOpenAt: settings.scheduledOpenAt,
                perishableWindowHours: settings.perishableWindowHours,
                mixedWindowHours: settings.mixedWindowHours,
                standardWindowHours: settings.standardWindowHours,
                globalLowStockThreshold: settings.globalLowStockThreshold,
                masterCategories: newCats,
                announcement: settings.announcement,
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, InventoryProvider inventory, StoreSettings settings, String cat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Remove "$cat" from the master list? This won\'t delete products in this category, but they will become "Others".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final newCats = List<String>.from(settings.masterCategories)..remove(cat);
              await inventory.saveStoreSettings(StoreSettings(
                isClosed: settings.isClosed,
                closureMessage: settings.closureMessage,
                scheduledCloseAt: settings.scheduledCloseAt,
                scheduledOpenAt: settings.scheduledOpenAt,
                perishableWindowHours: settings.perishableWindowHours,
                mixedWindowHours: settings.mixedWindowHours,
                standardWindowHours: settings.standardWindowHours,
                globalLowStockThreshold: settings.globalLowStockThreshold,
                masterCategories: newCats,
                announcement: settings.announcement,
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
