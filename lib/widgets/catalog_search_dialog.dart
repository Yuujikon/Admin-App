import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';

class CatalogSearchDialog extends StatefulWidget {
  const CatalogSearchDialog({super.key});

  @override
  State<CatalogSearchDialog> createState() => _CatalogSearchDialogState();
}

class _CatalogSearchDialogState extends State<CatalogSearchDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<InventoryProvider>().catalog;
    final filtered = catalog.where((p) {
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) || 
             (p.brand?.toLowerCase().contains(q) ?? false);
    }).toList();

    return AlertDialog(
      title: const Text('Search Product Catalog'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search by name or brand...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No matching products found in catalog.', style: TextStyle(color: Colors.grey)),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (ctx, i) {
                    final p = filtered[i];
                    return ListTile(
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${p.brand ?? 'No Brand'} • ${p.category}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
