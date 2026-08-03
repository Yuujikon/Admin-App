import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/supplier.dart';
import '../providers/inventory_provider.dart';

class SupplierManagementScreen extends StatefulWidget {
  const SupplierManagementScreen({super.key});

  @override
  State<SupplierManagementScreen> createState() => _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen> {
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final allSuppliers = provider.suppliers;
    final filteredSuppliers = allSuppliers.where((s) {
      final query = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(query) ||
             s.category.toLowerCase().contains(query) ||
             s.contactName.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Suppliers'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search suppliers...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _searchQuery.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18), 
                      onPressed: () => setState(() { _searchCtrl.clear(); _searchQuery = ''; })
                    ) 
                  : null,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSupplierSheet(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New Supplier'),
      ),
      body: filteredSuppliers.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_shipping_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1)),
                  const SizedBox(height: 16),
                  Text(_searchQuery.isEmpty ? 'No suppliers added yet.' : 'No matches found.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            )
          : ListView.builder(
              itemCount: filteredSuppliers.length,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
              itemBuilder: (context, index) {
                final s = filteredSuppliers[index];
                return _SupplierCard(supplier: s);
              },
            ),
    );
  }

  void _showSupplierSheet(BuildContext context, Supplier? supplier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SupplierSheet(supplier: supplier),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  const _SupplierCard({required this.supplier});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              child: Text(supplier.name[0].toUpperCase(), 
                   style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
            ),
            title: Text(supplier.name, style: Theme.of(context).textTheme.titleSmall),
            subtitle: Text(supplier.category, style: Theme.of(context).textTheme.labelSmall),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Auto-Notify', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    SizedBox(
                      height: 30,
                      child: Switch(
                        value: supplier.autoNotifyLowStock,
                        onChanged: (v) {
                          final updated = supplier.copyWith(autoNotifyLowStock: v);
                          context.read<InventoryProvider>().saveSupplier(updated);
                        },
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                      builder: (_) => _SupplierSheet(supplier: supplier),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(supplier.contactName.isEmpty ? 'No contact name' : supplier.contactName, 
                     style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _launchCaller(supplier.phone),
                  icon: const Icon(Icons.call_outlined, size: 16),
                  label: Text(supplier.phone, style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _launchCaller(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

class _SupplierSheet extends StatefulWidget {
  final Supplier? supplier;
  const _SupplierSheet({this.supplier});

  @override
  State<_SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends State<_SupplierSheet> {
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
    final suppliers = context.read<InventoryProvider>().suppliers;
    final existingCategories = suppliers.map((s) => s.category).toSet().toList()..sort();

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
                subtitle: const Text('Notify when stock ≤ 5', style: TextStyle(fontSize: 12)),
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
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Supplier?'),
        content: const Text('This will permanently remove this supplier and its contact info.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await context.read<InventoryProvider>().deleteSupplier(widget.supplier!.id);
              if (!mounted) return;
              Navigator.pop(ctx); // Dialog
              Navigator.pop(context); // Sheet
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
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      category: _category.text.trim(),
      autoNotifyLowStock: _autoNotify,
    );
    await context.read<InventoryProvider>().saveSupplier(s);
    if (mounted) Navigator.pop(context);
  }
}
