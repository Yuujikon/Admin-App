import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../models/bundle.dart';
import '../../providers/inventory_provider.dart';

class BundleManagementScreen extends StatelessWidget {
  const BundleManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final bundles = inventory.bundles;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Cooking Bundles'), backgroundColor: Theme.of(context).colorScheme.surface),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Bundle'),
      ),
      body: bundles.isEmpty 
          ? const Center(child: Text('No bundles created yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: bundles.length,
              itemBuilder: (ctx, i) {
                final b = bundles[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: b.photoBase64 != null 
                        ? CircleAvatar(backgroundImage: MemoryImage(base64Decode(b.photoBase64!)))
                        : const CircleAvatar(child: Icon(Icons.auto_awesome_motion_rounded)),
                    title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${b.productIds.length} items'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(value: b.isActive, onChanged: (v) {
                          context.read<InventoryProvider>().saveBundle(ProductBundle(
                            id: b.id,
                            name: b.name,
                            description: b.description,
                            productIds: b.productIds,
                            photoBase64: b.photoBase64,
                            isActive: v,
                          ));
                        }),
                        IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _showEditDialog(context, b)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showEditDialog(BuildContext context, ProductBundle? bundle) {
    final nameCtrl = TextEditingController(text: bundle?.name ?? '');
    final descCtrl = TextEditingController(text: bundle?.description ?? '');
    List<String> selectedIds = List.from(bundle?.productIds ?? []);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) {
          final products = context.read<InventoryProvider>().products;
          return AlertDialog(
            title: Text(bundle == null ? 'Create Bundle' : 'Edit Bundle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Bundle Name (e.g. Adobo Set)')),
                  const SizedBox(height: 12),
                  TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
                  const SizedBox(height: 24),
                  const Text('Select Products', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...products.map((p) => CheckboxListTile(
                    title: Text(p.name),
                    subtitle: Text(p.category),
                    value: selectedIds.contains(p.id),
                    onChanged: (v) {
                      setSt(() {
                        if (v == true) {
                          selectedIds.add(p.id);
                        } else {
                          selectedIds.remove(p.id);
                        }
                      });
                    },
                  )),
                ],
              ),
            ),
            actions: [
              if (bundle != null)
                TextButton(
                  onPressed: () {
                    context.read<InventoryProvider>().deleteBundle(bundle.id);
                    Navigator.pop(ctx);
                  }, 
                  child: const Text('Delete', style: TextStyle(color: Colors.red))
                ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  context.read<InventoryProvider>().saveBundle(ProductBundle(
                    id: bundle?.id ?? '',
                    name: nameCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    productIds: selectedIds,
                    photoBase64: bundle?.photoBase64,
                  ));
                  Navigator.pop(ctx);
                }, 
                child: const Text('Save Bundle')
              ),
            ],
          );
        }
      ),
    );
  }
}
