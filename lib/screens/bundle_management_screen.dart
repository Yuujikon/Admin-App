import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: b.photoBase64 != null 
                          ? Image.memory(base64Decode(b.photoBase64!), fit: BoxFit.cover)
                          : const Icon(Icons.auto_awesome_motion_rounded, color: Colors.grey),
                    ),
                    title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.category, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                        Text('${b.productIds.length} items', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(value: b.isActive, onChanged: (v) {
                          context.read<InventoryProvider>().saveBundle(ProductBundle(
                            id: b.id,
                            name: b.name,
                            description: b.description,
                            category: b.category,
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
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _BundleEditDialog(bundle: bundle),
    );
  }
}

class _BundleEditDialog extends StatefulWidget {
  final ProductBundle? bundle;
  const _BundleEditDialog({this.bundle});

  @override
  State<_BundleEditDialog> createState() => _BundleEditDialogState();
}

class _BundleEditDialogState extends State<_BundleEditDialog> {
  late TextEditingController nameCtrl, descCtrl;
  late List<String> selectedIds;
  late String category;
  String? photoBase64;
  File? localPhoto;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bundle;
    nameCtrl = TextEditingController(text: b?.name ?? '');
    descCtrl = TextEditingController(text: b?.description ?? '');
    selectedIds = List.from(b?.productIds ?? []);
    photoBase64 = b?.photoBase64;
    category = b?.category ?? 'General';
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 600, imageQuality: 70);
    if (image != null) {
      final bytes = await File(image.path).readAsBytes();
      setState(() {
        localPhoto = File(image.path);
        photoBase64 = base64Encode(bytes);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final products = inventory.products;
    final cats = ['General', ...inventory.settings.masterCategories];

    return AlertDialog(
      title: Text(widget.bundle == null ? 'Create Bundle' : 'Edit Bundle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: photoBase64 != null 
                    ? Image.memory(base64Decode(photoBase64!), fit: BoxFit.cover)
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined, size: 32, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('Add Visualization Image', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Bundle Name (e.g. Adobo Set)')),
            const SizedBox(height: 12),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: cats.contains(category) ? category : 'General',
              decoration: const InputDecoration(labelText: 'Display Category'),
              items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => category = v!),
            ),
            const SizedBox(height: 24),
            const Align(alignment: Alignment.centerLeft, child: Text('Select Products', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: 12),
            ...products.map((p) => CheckboxListTile(
              dense: true,
              title: Text(p.name),
              subtitle: Text(p.category),
              value: selectedIds.contains(p.id),
              onChanged: (v) {
                setState(() {
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
        if (widget.bundle != null)
          TextButton(
            onPressed: () {
              context.read<InventoryProvider>().deleteBundle(widget.bundle!.id);
              Navigator.pop(context);
            }, 
            child: const Text('Delete', style: TextStyle(color: Colors.red))
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: saving ? null : () async {
            if (nameCtrl.text.isEmpty) return;
            setState(() => saving = true);
            await context.read<InventoryProvider>().saveBundle(ProductBundle(
              id: widget.bundle?.id ?? '',
              name: nameCtrl.text.trim(),
              description: descCtrl.text.trim(),
              category: category,
              productIds: selectedIds,
              photoBase64: photoBase64,
            ));
            if (mounted) Navigator.pop(context);
          }, 
          child: saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Bundle')
        ),
      ],
    );
  }
}
