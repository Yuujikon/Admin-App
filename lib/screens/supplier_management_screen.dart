import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/supplier.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../widgets/supplier_sheet.dart';
import 'supplier_detail_screen.dart';

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
    final allProducts = provider.products;

    final filteredSuppliers = allSuppliers.where((s) {
      final query = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(query) ||
             s.category.toLowerCase().contains(query) ||
             s.contactName.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Suppliers & Restock'),
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
                final lowStockCount = allProducts.where((p) => 
                  p.status == ProductStatus.published && 
                  p.stock <= p.lowStockThreshold && 
                  p.supplierId == s.id
                ).length;

                return _SupplierCard(supplier: s, lowStockCount: lowStockCount);
              },
            ),
    );
  }

  void _showSupplierSheet(BuildContext context, Supplier? supplier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SupplierSheet(supplier: supplier),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final int lowStockCount;
  const _SupplierCard({required this.supplier, required this.lowStockCount});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierDetailScreen(supplier: supplier))),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                child: Text(supplier.name[0].toUpperCase(), 
                     style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
              ),
              title: Text(supplier.name, style: Theme.of(context).textTheme.titleSmall),
              subtitle: Text(supplier.category, style: Theme.of(context).textTheme.labelSmall),
              trailing: lowStockCount > 0 
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orange.shade800),
                        const SizedBox(width: 4),
                        Text('$lowStockCount LOW', 
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                      ],
                    ),
                  )
                : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(supplier.contactName.isEmpty ? 'No contact name' : supplier.contactName, 
                       style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  Icon(Icons.phone_outlined, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(supplier.phone, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// REMOVED _SupplierSheet and _SupplierSheetState as they are now in widgets/supplier_sheet.dart

