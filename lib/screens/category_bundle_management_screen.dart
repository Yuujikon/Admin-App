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
      length: 3,
      initialIndex: widget.initialIndex,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text('Categories, Bundles & Variant Groups'),
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
                text: 'Meal Bundles',
              ),
              Tab(
                icon: Icon(Icons.account_tree_outlined),
                text: 'Parent Groups',
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
            _buildParentGroupsTab(context, inventory, products),
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
        content: Container(
          width: 420,
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              hintText: 'e.g. Beverages, Canned Goods',
            ),
            autofocus: true,
          ),
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
        content: Container(
          width: 420,
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Category Name'),
            autofocus: true,
          ),
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
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
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
                                    Text(
                                      '• ${b.productIds.length} items',
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

  // ── PARENT GROUPS TAB ──────────────────────────────────────────────────────

  Widget _buildParentGroupsTab(
    BuildContext context,
    InventoryProvider inventory,
    List<Product> products,
  ) {
    final parentIds = inventory.uniqueParentIds;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateParentGroupDialog(context, products),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Group'),
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
                  .tertiaryContainer
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
                            .tertiary
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.account_tree_rounded,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${parentIds.length} Parent Variant Groups',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Group products into variant families (e.g. GRP-PALMOLIVE-SHAMPOO). Link products, rename or delete group IDs to manage variant families.',
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
            if (parentIds.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No parent variant groups created yet.'),
                ),
              )
            else
              ResponsiveCardGrid(
                children: parentIds.map((pId) {
                  final linkedProducts = inventory.getProductsByParentId(pId);
                  return _parentGroupCard(
                      context, inventory, pId, linkedProducts, products);
                }).toList(),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _parentGroupCard(
    BuildContext context,
    InventoryProvider inventory,
    String parentId,
    List<Product> linkedProducts,
    List<Product> allProducts,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .tertiaryContainer
                .withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.account_tree_outlined,
            color: Theme.of(context).colorScheme.tertiary,
            size: 22,
          ),
        ),
        title: Text(
          parentId,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          '${linkedProducts.length} ${linkedProducts.length == 1 ? "product linked" : "products linked"}',
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Linked Products:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    TextButton.icon(
                      onPressed: () => _showLinkProductsDialog(
                          context, parentId, allProducts),
                      icon: const Icon(Icons.add_link_rounded, size: 14),
                      label: const Text('+ Link Products',
                          style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (linkedProducts.isEmpty)
                  const Text('No products currently assigned to this group.',
                      style: TextStyle(fontSize: 11, color: Colors.grey))
                else
                  ...linkedProducts.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 14, color: Colors.purple),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.name,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              formatPeso(p.price),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline,
                                  size: 16, color: Colors.red.shade400),
                              tooltip: 'Unlink from group',
                              onPressed: () async {
                                await inventory
                                    .saveProduct(p.copyWith(parentId: ''));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Unlinked "${p.name}" from "$parentId"! ✅'),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showLinkProductsDialog(
                          context, parentId, allProducts),
                      icon: const Icon(Icons.add_link_rounded, size: 16),
                      label: const Text('+ Link Products',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _showEditParentGroupDialog(
                          context, inventory, parentId),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Rename',
                          style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () => _confirmDeleteParentGroup(
                          context, inventory, parentId, linkedProducts.length),
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: Colors.red),
                      label: const Text('Delete',
                          style: TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditParentGroupDialog(
    BuildContext context,
    InventoryProvider inventory,
    String oldParentId,
  ) {
    final ctrl = TextEditingController(text: oldParentId);
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Parent Group ID'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'New Parent Group ID',
            hintText: 'e.g. GRP-PALMOLIVE-SHAMPOO',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newId = ctrl.text.trim();
              if (newId.isEmpty || newId == oldParentId) {
                Navigator.pop(ctx);
                return;
              }

              final linked = inventory.getProductsByParentId(oldParentId);
              for (final p in linked) {
                await inventory.saveProduct(p.copyWith(parentId: newId));
              }

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Renamed group "$oldParentId" to "$newId" across ${linked.length} products! ✅'),
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteParentGroup(
    BuildContext context,
    InventoryProvider inventory,
    String parentId,
    int productCount,
  ) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Group "$parentId"?'),
        content: Text(
          'Are you sure you want to delete this parent group ID?\n\n'
          '• This will un-group $productCount ${productCount == 1 ? "product" : "products"} linked to "$parentId".\n'
          '• The products themselves will NOT be deleted.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final linked = inventory.getProductsByParentId(parentId);
              for (final p in linked) {
                await inventory.saveProduct(p.copyWith(parentId: ''));
              }

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Deleted group "$parentId" and un-grouped $productCount products! ✅'),
                  ),
                );
              }
            },
            child: const Text('Delete Group',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showLinkProductsDialog(
    BuildContext context,
    String parentId,
    List<Product> allProducts,
  ) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _LinkProductsDialog(
        parentId: parentId,
        allProducts: allProducts,
      ),
    );
  }

  void _showCreateParentGroupDialog(
    BuildContext context,
    List<Product> allProducts,
  ) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _CreateParentGroupDialog(allProducts: allProducts),
    );
  }
}

// ── LINK PRODUCTS DIALOG ─────────────────────────────────────────────────────

class _LinkProductsDialog extends StatefulWidget {
  final String parentId;
  final List<Product> allProducts;

  const _LinkProductsDialog({
    required this.parentId,
    required this.allProducts,
  });

  @override
  State<_LinkProductsDialog> createState() => _LinkProductsDialogState();
}

class _LinkProductsDialogState extends State<_LinkProductsDialog> {
  late Set<String> _selectedProductIds;
  String _search = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedProductIds = widget.allProducts
        .where((p) => p.parentId == widget.parentId)
        .map((p) => p.id)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.allProducts.where((p) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          (p.brand?.toLowerCase().contains(q) ?? false) ||
          p.category.toLowerCase().contains(q);
    }).toList();

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Link Products to Group',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            widget.parentId,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
      content: Container(
        width: 480,
        constraints: const BoxConstraints(maxWidth: 480),
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search product or brand...',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final p = filtered[i];
                  final isChecked = _selectedProductIds.contains(p.id);
                  final hasOtherGroup = p.parentId != null &&
                      p.parentId!.isNotEmpty &&
                      p.parentId != widget.parentId;

                  return CheckboxListTile(
                    dense: true,
                    title: Text(p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(
                      hasOtherGroup
                          ? '${p.category} • Current Group: ${p.parentId}'
                          : '${p.category} • ${formatPeso(p.price)}',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            hasOtherGroup ? Colors.orange.shade800 : Colors.grey,
                      ),
                    ),
                    value: isChecked,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedProductIds.add(p.id);
                        } else {
                          _selectedProductIds.remove(p.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  final inventory = context.read<InventoryProvider>();
                  setState(() => _saving = true);

                  for (final p in widget.allProducts) {
                    final isNowSelected = _selectedProductIds.contains(p.id);
                    final isCurrentlyInGroup = p.parentId == widget.parentId;

                    if (isNowSelected && !isCurrentlyInGroup) {
                      // Attach to group
                      await inventory
                          .saveProduct(p.copyWith(parentId: widget.parentId));
                    } else if (!isNowSelected && isCurrentlyInGroup) {
                      // Remove from group
                      await inventory.saveProduct(p.copyWith(parentId: ''));
                    }
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Updated linked products for "${widget.parentId}"! ✅'),
                      ),
                    );
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save Links'),
        ),
      ],
    );
  }
}

// ── CREATE PARENT GROUP DIALOG ───────────────────────────────────────────────

class _CreateParentGroupDialog extends StatefulWidget {
  final List<Product> allProducts;

  const _CreateParentGroupDialog({required this.allProducts});

  @override
  State<_CreateParentGroupDialog> createState() =>
      __CreateParentGroupDialogState();
}

class __CreateParentGroupDialogState extends State<_CreateParentGroupDialog> {
  final _groupIdCtrl = TextEditingController();
  final Set<String> _selectedProductIds = {};
  String _search = '';
  bool _saving = false;

  @override
  void dispose() {
    _groupIdCtrl.dispose();
    super.dispose();
  }

  void _autoSuggestGroupId() {
    if (_selectedProductIds.isEmpty) return;
    final selectedProducts = widget.allProducts
        .where((p) => _selectedProductIds.contains(p.id))
        .toList();

    final firstBrand = selectedProducts.first.brand;
    final firstName = selectedProducts.first.name;

    final rawText = (firstBrand != null && firstBrand.isNotEmpty)
        ? '$firstBrand ${firstName.split(" ").take(2).join(" ")}'
        : firstName.split(" ").take(2).join(" ");

    final cleanSlug = rawText
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');

    if (cleanSlug.isNotEmpty) {
      _groupIdCtrl.text = 'GRP-$cleanSlug';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.allProducts.where((p) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          (p.brand?.toLowerCase().contains(q) ?? false) ||
          p.category.toLowerCase().contains(q);
    }).toList();

    return AlertDialog(
      title: const Text('New Parent Variant Group'),
      content: Container(
        width: 480,
        constraints: const BoxConstraints(maxWidth: 480),
        height: 450,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _groupIdCtrl,
              decoration: InputDecoration(
                labelText: 'Parent Group ID *',
                hintText: 'e.g. GRP-PALMOLIVE-SHAMPOO',
                prefixIcon: const Icon(Icons.account_tree_outlined, size: 18),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.auto_awesome_rounded,
                      size: 16, color: Colors.purple),
                  tooltip: 'Suggest Group ID from selection',
                  onPressed: _autoSuggestGroupId,
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Select Products to Include:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search product or brand...',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final p = filtered[i];
                  final isChecked = _selectedProductIds.contains(p.id);

                  return CheckboxListTile(
                    dense: true,
                    title: Text(p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(
                        '${p.category} • ${formatPeso(p.price)}${p.parentId != null && p.parentId!.isNotEmpty ? " (Group: ${p.parentId})" : ""}',
                        style: const TextStyle(fontSize: 11)),
                    value: isChecked,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedProductIds.add(p.id);
                        } else {
                          _selectedProductIds.remove(p.id);
                        }
                        if (_groupIdCtrl.text.isEmpty) {
                          _autoSuggestGroupId();
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  final newGroupId = _groupIdCtrl.text.trim();
                  if (newGroupId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Please enter a Parent Group ID.')),
                    );
                    return;
                  }
                  if (_selectedProductIds.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Please select at least one product.')),
                    );
                    return;
                  }

                  final inventory = context.read<InventoryProvider>();
                  setState(() => _saving = true);

                  for (final p in widget.allProducts) {
                    if (_selectedProductIds.contains(p.id)) {
                      await inventory
                          .saveProduct(p.copyWith(parentId: newGroupId));
                    }
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Created Group "$newGroupId" with ${_selectedProductIds.length} products! ✅'),
                      ),
                    );
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create Group'),
        ),
      ],
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
      content: Container(
        width: 480,
        constraints: const BoxConstraints(maxWidth: 480),
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
