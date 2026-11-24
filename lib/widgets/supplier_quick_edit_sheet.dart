import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/supplier.dart';
import '../providers/inventory_provider.dart';
import '../providers/procurement_provider.dart';
import '../utils/email_validator.dart';
import '../utils/format.dart';

/// Quick-Edit Bottom Sheet for completing or correcting supplier details directly inside
/// the Purchase Order or Backorder review/dispatch flow, with an option to persist changes
/// back to the master Supplier profile in Firestore.
class SupplierQuickEditSheet extends StatefulWidget {
  final SupplierSnapshot initialSnapshot;
  final bool initialAutoNotifyLowStock;
  final String? existingPoId;

  const SupplierQuickEditSheet({
    super.key,
    required this.initialSnapshot,
    this.initialAutoNotifyLowStock = true,
    this.existingPoId,
  });

  /// Opens the Quick-Edit sheet and returns the updated [SupplierSnapshot] if saved, or `null` if cancelled.
  static Future<SupplierSnapshot?> show({
    required BuildContext context,
    required SupplierSnapshot initialSnapshot,
    bool initialAutoNotifyLowStock = true,
    String? existingPoId,
  }) {
    return showModalBottomSheet<SupplierSnapshot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupplierQuickEditSheet(
        initialSnapshot: initialSnapshot,
        initialAutoNotifyLowStock: initialAutoNotifyLowStock,
        existingPoId: existingPoId,
      ),
    );
  }

  @override
  State<SupplierQuickEditSheet> createState() => _SupplierQuickEditSheetState();
}

class _SupplierQuickEditSheetState extends State<SupplierQuickEditSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _tinCtrl;
  late final TextEditingController _termsCtrl;

  bool _syncToMasterProfile = true;
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
    final s = widget.initialSnapshot;
    _nameCtrl = TextEditingController(text: s.supplierName);
    _contactCtrl = TextEditingController(text: s.contactPerson);
    _emailCtrl = TextEditingController(text: s.email);
    _phoneCtrl = TextEditingController(text: s.phone);
    _addressCtrl = TextEditingController(text: s.address);
    _tinCtrl = TextEditingController(text: s.tin);
    _termsCtrl = TextEditingController(text: s.paymentTerms);
    _syncToMasterProfile = s.supplierId.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _tinCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  SupplierSnapshot _buildDraftSnapshot() {
    final rawPhone = _phoneCtrl.text.trim();
    return widget.initialSnapshot.copyWith(
      supplierName: _nameCtrl.text.trim(),
      contactPerson: _contactCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: rawPhone.isNotEmpty ? formatPhoneNumber(rawPhone) : '',
      address: _addressCtrl.text.trim(),
      tin: _tinCtrl.text.trim(),
      paymentTerms: _termsCtrl.text.trim(),
      snapshottedAt: DateTime.now(),
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);

    try {
      final updatedSnapshot = _buildDraftSnapshot();

      // Optionally sync changes back to master Firestore suppliers/{id} profile
      if (_syncToMasterProfile &&
          updatedSnapshot.supplierId.trim().isNotEmpty) {
        final inventory = context.read<InventoryProvider>();
        final existing = await inventory.getSupplierById(
          updatedSnapshot.supplierId,
        );
        final updatedMaster = updatedSnapshot.toSupplier(
          autoNotifyLowStock:
              existing?.autoNotifyLowStock ?? widget.initialAutoNotifyLowStock,
        );
        await inventory.saveSupplier(updatedMaster);
      }

      // If editing an already-persisted PO/Backorder, update its Firestore snapshot too
      if (widget.existingPoId != null &&
          widget.existingPoId!.trim().isNotEmpty &&
          mounted) {
        await context
            .read<ProcurementProvider>()
            .updatePurchaseOrderSupplierSnapshot(
              widget.existingPoId!,
              updatedSnapshot,
            );
      }

      if (!mounted) return;
      Navigator.of(context).pop(updatedSnapshot);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save supplier details: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canSyncMaster = widget.initialSnapshot.supplierId.trim().isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.edit_note_rounded,
                        color: Colors.teal.shade800,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick-Edit Supplier Details',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Complete required fields for PO & Backorder PDFs',
                            style:
                                TextStyle(fontSize: 11.5, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Scrollable Form Fields
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Supplier / Business Name *',
                          prefixIcon: Icon(Icons.business_rounded),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (val) {
                          final v = (val ?? '').trim();
                          if (v.isEmpty ||
                              v.toLowerCase() == 'unnamed supplier') {
                            return 'Supplier Name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _contactCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Contact Person',
                          hintText: 'e.g. Juan Dela Cruz',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Supplier Email Address *',
                          hintText: 'orders@supplier.com',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (val) => EmailValidator.validate(val),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Contact Number / Phone *',
                          hintText: 'e.g. 0917 123 4567',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (val) {
                          final v = (val ?? '').trim();
                          final digits =
                              v.replaceAll(RegExp(r'[^0-9]'), '').length;
                          if (v.isEmpty) {
                            return 'Contact number is required for PDF';
                          }
                          if (digits < 7) {
                            return 'Enter a valid phone number (at least 7 digits)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressCtrl,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Physical Business Address *',
                          hintText:
                              'Street, Barangay, City / Municipality, Province',
                          prefixIcon: Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        validator: (val) {
                          final v = (val ?? '').trim();
                          if (v.isEmpty) {
                            return 'Physical Address is required for PO/Backorder PDF';
                          }
                          if (v.length < 5) {
                            return 'Please enter a complete physical address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _tinCtrl,
                        decoration: const InputDecoration(
                          labelText: 'TIN / Business ID (Optional)',
                          hintText: 'e.g. 123-456-789-000',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Payment Terms',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _presetTerms.map((term) {
                          final selected =
                              _termsCtrl.text.trim().toLowerCase() ==
                                  term.toLowerCase();
                          return ChoiceChip(
                            label: Text(term,
                                style: const TextStyle(fontSize: 11.5)),
                            selected: selected,
                            onSelected: (_) {
                              setState(() => _termsCtrl.text = term);
                            },
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _termsCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Custom / Selected Payment Terms',
                          hintText: 'e.g. COD, Net 15, Net 30',
                          prefixIcon: Icon(Icons.payments_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Master Profile Sync Toggle
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: SwitchListTile(
                          dense: true,
                          title: const Text(
                            'Save changes to master Supplier profile',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            canSyncMaster
                                ? 'Updates Firestore suppliers record so future POs & Backorders stay accurate.'
                                : 'Master supplier ID unavailable; applies to this document only.',
                            style: const TextStyle(fontSize: 11),
                          ),
                          value: canSyncMaster && _syncToMasterProfile,
                          onChanged: canSyncMaster
                              ? (val) =>
                                  setState(() => _syncToMasterProfile = val)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Footer Buttons
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(
                          _saving ? 'Saving...' : 'Apply & Save Details',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
