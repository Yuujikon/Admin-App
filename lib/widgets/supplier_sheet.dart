import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/supplier.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';

class SupplierSheet extends StatefulWidget {
  final Supplier? supplier;
  const SupplierSheet({super.key, this.supplier});

  @override
  State<SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends State<SupplierSheet> {
  late TextEditingController _name, _contact, _phone, _email, _category;
  late bool _autoNotify;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _name = TextEditingController(text: s?.name ?? '');
    _contact = TextEditingController(text: s?.contactName ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _email = TextEditingController(text: s?.email ?? '');
    _category = TextEditingController(text: s?.category ?? 'General');
    _autoNotify = s?.autoNotifyLowStock ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.read<InventoryProvider>();
    final existingCategories = inventory.suppliers.map((s) => s.category).toSet().toList()..sort();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16, right: 16, top: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(widget.supplier == null ? 'Add Supplier' : 'Edit Supplier',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (widget.supplier != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: _confirmDelete,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Business Name', prefixIcon: Icon(Icons.business))),
            const SizedBox(height: 12),
            TextField(controller: _contact, decoration: const InputDecoration(labelText: 'Contact Person', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email_outlined)), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            
            // Category Autocomplete
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue value) {
                if (value.text == '') return existingCategories;
                return existingCategories.where((c) => c.toLowerCase().contains(value.text.toLowerCase()));
              },
              onSelected: (c) => _category.text = c,
              fieldViewBuilder: (ctx, ctrl, focus, onFieldSubmitted) {
                if (ctrl.text.isEmpty && _category.text.isNotEmpty) ctrl.text = _category.text;
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
                  onChanged: (v) => _category.text = v,
                );
              },
            ),
            
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SwitchListTile(
                title: const Text('Auto-Notify Low Stock', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: const Text('Sends internal alert when items are low', style: TextStyle(fontSize: 12)),
                value: _autoNotify,
                onChanged: (v) => setState(() => _autoNotify = v),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                : const Text('SAVE SUPPLIER', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Supplier?'),
        content: const Text('This will permanently remove this supplier and its contact info.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              
              try {
                await context.read<InventoryProvider>().deleteSupplier(widget.supplier!.id);
                if (ctx.mounted) Navigator.pop(ctx); // Close Dialog
                navigator.pop(); // Close Sheet
                navigator.pop(); // Close Detail Screen if open
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final s = Supplier(
      id: widget.supplier?.id ?? '',
      name: _name.text.trim(),
      contactName: _contact.text.trim(),
      phone: formatPhoneNumber(_phone.text.trim()),
      email: _email.text.trim(),
      category: _category.text.trim(),
      autoNotifyLowStock: _autoNotify,
    );
    await context.read<InventoryProvider>().saveSupplier(s);
    if (mounted) Navigator.pop(context);
  }
}
