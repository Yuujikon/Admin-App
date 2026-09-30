import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/bundle.dart';
import '../models/product.dart';
import '../models/store_settings.dart';
import '../providers/inventory_provider.dart';
import '../utils/format.dart';
import '../widgets/responsive_layout.dart';

class CategoryBundleManagementScreen extends StatefulWidget {
  final int initialIndex;
  const CategoryBundleManagementScreen({super.key, this.initialIndex = 0});

  @override
  State<CategoryBundleManagementScreen> createState() =>
      _CategoryBundleManagementScreenState();
}

class _CategoryBundleManagementScreenState
    extends State<CategoryBundleManagementScreen> {
  String _bundleCategoryFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final settings = inventory.settings;
    final categories = settings.masterCategories;
    final bundles = inventory.bundles;
    final products = inventory.products;

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialIndex,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text('Categories & Cooking Bundles'),
          backgroundColor: Theme.of(context).colorScheme.surface,
          bottom: TabBar(
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor:
                Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(
                icon: Icon(Icons.category_outlined),
                text: 'Categories',
              ),
              Tab(
                icon: Icon(Icons.auto_awesome_motion_rounded),
                text: 'Cooking Bundles',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildCategoriesTab(
                context, inventory, settings, categories, products, bundles),
            _buildBundlesTab(
                context, inventory, settings, categories, bundles, products),
          ],
        ),
      ),
    );
  }

  // ── CATEGORIES TAB ─────────────────────────────────────────────────────────

  Widget _buildCategoriesTab(
    BuildContext context,
    InventoryProvider inventory,
    StoreSettings settings,
    List<String> categories,
    List<Product> products,
    List<ProductBundle> bundles,
  ) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCategoryDialog(context, inventory, settings),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Category'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overview Header Card
            Card(
              elevation: 0,
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.category_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${categories.length} Categories',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Organize store inventory and meal recipe sets for quick POS access.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (categories.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No categories created yet.'),
                ),
              )
            else
              ResponsiveCardGrid(
                children: categories.map((cat) {
                  final productCount =
                      products.where((p) => p.category == cat).length;
                  final bundleCount =
                      bundles.where((b) => b.category == cat).length;
                  return _categoryCard(context, inventory, settings, cat,
                      productCount, bundleCount);
                }).toList(),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _categoryCard(
    BuildContext context,
    InventoryProvider inventory,
    StoreSettings settings,
    String cat,
    int productCount,
    int bundleCount,
  ) {
    final initials = cat.isNotEmpty ? cat[0].toUpperCase() : '?';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        title: Text(cat,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          '$productCount ${productCount == 1 ? "product" : "products"} • $bundleCount ${bundleCount == 1 ? "bundle" : "bundles"}',
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Edit Category',
              onPressed: () =>
                  _showEditCategoryDialog(context, inventory, settings, cat),
            ),
            IconButton(
              icon:
                  const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              tooltip: 'Delete Category',
              onPressed: () => _confirmDeleteCategory(
                  context, inventory, settings, cat, productCount, bundleCount),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCategoryDialog(BuildContext context, InventoryProvider inventory,
      StoreSettings settings) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g. Beverages, Canned Goods',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              if (settings.masterCategories.contains(name)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Category already exists.')),
                );
                return;
              }

              final newCats = List<String>.from(settings.masterCategories)
                ..add(name)
                ..sort();
              await inventory.saveStoreSettings(
                  settings.copyWith(masterCategories: newCats));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(BuildContext context,
      InventoryProvider inventory, StoreSettings settings, String oldCat) {
    final ctrl = TextEditingController(text: oldCat);
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Category'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Category Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName == oldCat) {
                Navigator.pop(ctx);
                return;
              }

              final newCats = List<String>.from(settings.masterCategories);
              final index = newCats.indexOf(oldCat);
              if (index != -1) {
                newCats[index] = newName;
                newCats.sort();
              }
              await inventory.saveStoreSettings(
                  settings.copyWith(masterCategories: newCats));

              for (final b in inventory.bundles) {
                if (b.category == oldCat) {
                  await inventory.saveBundle(ProductBundle(
                    id: b.id,
                    name: b.name,
                    description: b.description,
                    category: newName,
                    productIds: b.productIds,
                    photoBase64: b.photoBase64,
                    isActive: b.isActive,
                  ));
                }
              }

              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCategory(
    BuildContext context,
    InventoryProvider inventory,
    StoreSettings settings,
    String cat,
    int productCount,
    int bundleCount,
  ) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$cat"?'),
        content: Text(
          'Remove "$cat" from master category list?'
          '${productCount > 0 ? "\n\n• $productCount products in this category will default to \"Others\"." : ""}'
          '${bundleCount > 0 ? "\n• $bundleCount bundles in this category will default to \"General\"." : ""}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final newCats = List<String>.from(settings.masterCategories)
                ..remove(cat);
              await inventory.saveStoreSettings(
                  settings.copyWith(masterCategories: newCats));

              for (final b in inventory.bundles) {
                if (b.category == cat) {
                  await inventory.saveBundle(ProductBundle(
                    id: b.id,
                    name: b.name,
                    description: b.description,
                    category: 'General',
                    productIds: b.productIds,
                    photoBase64: b.photoBase64,
                    isActive: b.isActive,
                  ));
                }
              }

              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── BUNDLES TAB ────────────────────────────────────────────────────────────

  Widget _buildBundlesTab(
    BuildContext context,
    InventoryProvider inventory,
    StoreSettings settings,
    List<String> categories,
    List<ProductBundle> bundles,
    List<Product> products,
  ) {
    final filterCats = ['All', 'General', ...categories];
    final filteredBundles = _bundleCategoryFilter == 'All'
        ? bundles
        : bundles.where((b) => b.category == _bundleCategoryFilter).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBundleEditDialog(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Bundle'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: filterCats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = filterCats[i];
                final selected = _bundleCategoryFilter == cat;
                return FilterChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) =>
                      setState(() => _bundleCategoryFilter = cat),
                );
              },
            ),
          ),
          Expanded(
            child: filteredBundles.isEmpty
                ? const Center(
                    child: Text('No meal bundles created for this category.'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    child: ResponsiveCardGrid(
                      children: filteredBundles.map((b) {
                        final includedProducts = products
                            .where((p) => b.productIds.contains(p.id))
                            .toList();
                        final double calculatedPrice =
                            includedProducts.fold(0.0, (sum, p) => sum + p.price);

                        return Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: ExpansionTile(
                            shape: const RoundedRectangleBorder(
                                side: BorderSide.none),
                            collapsedShape: const RoundedRectangleBorder(
                                side: BorderSide.none),
                            tilePadding: const EdgeInsets.all(12),
                            leading: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: b.photoBase64 != null
                                  ? Image.memory(base64Decode(b.photoBase64!),
                                      fit: BoxFit.cover)
                                  : const Icon(Icons.auto_awesome_motion_rounded,
                                      color: Colors.grey),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    b.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                ),
                                Text(
                                  formatPeso(calculatedPrice),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        b.category.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: Colors.orange.shade200),
                                      ),
                                      child: Text(
                                        'BUNDLE DISCOUNT',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${b.productIds.length} items',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Divider(),
                                    const Text('Included Products in Bundle:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                    const SizedBox(height: 6),
                                    if (includedProducts.isEmpty)
                                      const Text(
                                          'No products currently linked to this bundle.',
                                          style: TextStyle(
                                              fontSize: 11, color: Colors.grey))
                                    else
                                      ...includedProducts.map((p) => Padding(
                                            padding:
                                                const EdgeInsets.only(bottom: 4),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                    Icons.check_circle_outline,
                                                    size: 14,
                                                    color: Colors.green),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                    child: Text(p.name,
                                                        style: const TextStyle(
                                                            fontSize: 12))),
                                                Text(formatPeso(p.price),
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ],
                                            ),
                                          )),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () =>
                                              _showBundleEditDialog(context, b),
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 16),
                                          label: const Text('Edit Bundle',
                                              style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showBundleEditDialog(BuildContext context, ProductBundle? bundle) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _BundleEditDialog(bundle: bundle),
    );
  }
}

// ── BUNDLE EDIT DIALOG ───────────────────────────────────────────────────────

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
    final image = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 600, imageQuality: 70);
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
      title: Text(widget.bundle == null
          ? 'Create Cooking Bundle'
          : 'Edit Cooking Bundle'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
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
                      ? Image.memory(base64Decode(photoBase64!),
                          fit: BoxFit.cover)
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                size: 32, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('Add Visualization Image',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Bundle Name (e.g. Adobo Set)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: cats.contains(category)
                    ? category
                    : (cats.isNotEmpty ? cats.first : null),
                decoration:
                    const InputDecoration(labelText: 'Display Category'),
                items: cats
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => category = v!),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Select Products Included',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              ...products.map((p) => CheckboxListTile(
                    dense: true,
                    title: Text(p.name),
                    subtitle: Text('${p.category} • ${formatPeso(p.price)}'),
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
      ),
      actions: [
        if (widget.bundle != null)
          TextButton(
            onPressed: () {
              context.read<InventoryProvider>().deleteBundle(widget.bundle!.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: saving
              ? null
              : () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final inv = context.read<InventoryProvider>();
                  setState(() => saving = true);
                  await inv.saveBundle(ProductBundle(
                    id: widget.bundle?.id ?? '',
                    name: nameCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    category: category,
                    productIds: selectedIds,
                    photoBase64: photoBase64,
                  ));
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
          child: saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save Bundle'),
        ),
      ],
    );
  }
}
