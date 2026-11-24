import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/supplier.dart';
import '../providers/inventory_provider.dart';
import '../utils/email_validator.dart';
import '../utils/format.dart';
import 'premium_components.dart';

class SupplierSheet extends StatefulWidget {
  final Supplier? supplier;
  const SupplierSheet({super.key, this.supplier});

  @override
  State<SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends State<SupplierSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name,
      _contact,
      _phone,
      _email,
      _address,
      _tin,
      _paymentTerms,
      _category;
  late bool _autoNotify;
  bool _saving = false;

  static const List<String> _presetTerms = [
    'COD',
    'Net 7',
    'Net 15',
    'Net 30',
    'Net 60',
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _name = TextEditingController(text: s?.name ?? '');
    _contact = TextEditingController(text: s?.contactName ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _email = TextEditingController(text: s?.email ?? '');
    _address = TextEditingController(text: s?.address ?? '');
    _tin = TextEditingController(text: s?.tin ?? '');
    _paymentTerms = TextEditingController(text: s?.paymentTerms ?? '');
    _category = TextEditingController(text: s?.category ?? 'General');
    _autoNotify = s?.autoNotifyLowStock ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _tin.dispose();
    _paymentTerms.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.read<InventoryProvider>();
    final existingCategories =
        inventory.suppliers.map((s) => s.category).toSet().toList()..sort();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 24),
      child: SingleChildScrollView(
        child: MaxWidthContainer(
          maxWidth: MaxWidthContainer.formMaxWidth,
          alignment: Alignment.topCenter,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                        widget.supplier == null
                            ? 'Add Supplier'
                            : 'Edit Supplier',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (widget.supplier != null)
                      IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: _confirmDelete,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                        labelText: 'Business Name *',
                        prefixIcon: Icon(Icons.business)),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _contact,
                    decoration: const InputDecoration(
                        labelText: 'Contact Person',
                        prefixIcon: Icon(Icons.person_outline)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(
                        labelText: 'Phone Number *',
                        prefixIcon: Icon(Icons.phone_outlined)),
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      final trimmed = (v ?? '').trim();
                      if (trimmed.isEmpty) {
                        return 'Required for PO & Backorder PDFs';
                      }
                      final digits =
                          trimmed.replaceAll(RegExp(r'[^0-9]'), '').length;
                      if (digits < 7) return 'Enter at least 7 digits';
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                        labelText: 'Email Address *',
                        prefixIcon: Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => EmailValidator.validate(v),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _address,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Physical Business Address *',
                      hintText: 'Street, Barangay, City / Province',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      alignLabelWithHint: true,
                    ),
                    validator: (v) {
                      final trimmed = (v ?? '').trim();
                      if (trimmed.isEmpty) {
                        return 'Required for PO & Backorder PDFs';
                      }
                      if (trimmed.length < 5) {
                        return 'Enter full street/city address';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _tin,
                    decoration: const InputDecoration(
                        labelText: 'TIN / Business ID (Optional)',
                        hintText: 'e.g. 123-456-789-000',
                        prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _presetTerms.map((term) {
                          final selected =
                              _paymentTerms.text.trim().toLowerCase() ==
                                  term.toLowerCase();
                          return ChoiceChip(
                            label: Text(term,
                                style: const TextStyle(fontSize: 11.5)),
                            selected: selected,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) =>
                                setState(() => _paymentTerms.text = term),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _paymentTerms,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            labelText: 'Payment Terms (Optional)',
                            hintText: 'e.g. COD, Net 15, Net 30',
                            prefixIcon: Icon(Icons.payments_outlined)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Category Autocomplete
                SizedBox(
                  width: double.infinity,
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue value) {
                      if (value.text == '') return existingCategories;
                      return existingCategories.where((c) =>
                          c.toLowerCase().contains(value.text.toLowerCase()));
                    },
                    onSelected: (c) => _category.text = c,
                    fieldViewBuilder: (ctx, ctrl, focus, onFieldSubmitted) {
                      if (ctrl.text.isEmpty && _category.text.isNotEmpty) {
                        ctrl.text = _category.text;
                      }
                      return TextField(
                        controller: ctrl,
                        focusNode: focus,
                        decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(Icons.category_outlined)),
                        onChanged: (v) => _category.text = v,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: SwitchListTile(
                    title: const Text('Auto-Notify Low Stock',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        'Sends internal alert when items are low',
                        style: TextStyle(fontSize: 12)),
                    value: _autoNotify,
                    onChanged: (v) => setState(() => _autoNotify = v),
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  onPressed: _saving ? null : _save,
                  isLoading: _saving,
                  minWidth: 200,
                  maxWidth: 350,
                  child: const Text('SAVE SUPPLIER',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
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
        content: const Text(
            'This will permanently remove this supplier and its contact info.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              try {
                await context
                    .read<InventoryProvider>()
                    .deleteSupplier(widget.supplier!.id);
                if (ctx.mounted) Navigator.pop(ctx); // Close Dialog
                navigator.pop(); // Close Sheet
                navigator.pop(); // Close Detail Screen if open
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                scaffoldMessenger
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);
    final s = Supplier(
      id: widget.supplier?.id ?? '',
      name: _name.text.trim(),
      contactName: _contact.text.trim(),
      phone: formatPhoneNumber(_phone.text.trim()),
      email: _email.text.trim(),
      address: _address.text.trim(),
      tin: _tin.text.trim(),
      paymentTerms: _paymentTerms.text.trim(),
      category: _category.text.trim(),
      autoNotifyLowStock: _autoNotify,
    );
    await context.read<InventoryProvider>().saveSupplier(s);
    if (mounted) Navigator.pop(context);
  }
}
