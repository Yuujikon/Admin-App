import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../config/theme.dart';
import '../utils/format.dart';

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() => _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final customers = inventory.customers.where((c) {
      final q = _search.toLowerCase();
      return q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Customer Rewards'), 
        backgroundColor: Theme.of(context).colorScheme.surface,
        scrolledUnderElevation: 2,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: () => _showCustomerSheet(context, null),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('New Customer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search customer name or phone…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () => setState(() { _searchCtrl.clear(); _search = ''; }))
                  : null,
              ),
            ),
          ),
          Expanded(
            child: customers.isEmpty
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stars_rounded, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    Text(_search.isEmpty ? 'No customers yet.' : 'No matches found.', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: customers.length,
                  itemBuilder: (context, i) {
                    final c = customers[i];
                    return _CustomerCard(customer: c);
                  },
                ),
          ),
        ],
      ),
    );
  }

  void _showCustomerSheet(BuildContext context, Customer? customer) {
    final nameCtrl = TextEditingController(text: customer?.name ?? '');
    final phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    final notesCtrl = TextEditingController(text: customer?.notes ?? '');
    bool saving = false;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24, right: 24, top: 12
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(2))),
              Text(customer == null ? 'Add New Customer' : 'Edit Customer Details', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline_rounded))),
              const SizedBox(height: 16),
              TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined))),
              const SizedBox(height: 16),
              TextField(controller: notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes / Preferences', prefixIcon: Icon(Icons.note_alt_outlined), hintText: 'e.g. Likes no plastic bags')),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  if (nameCtrl.text.isEmpty) return;
                  setSt(() => saving = true);
                  final c = Customer(
                    id: customer?.id ?? '',
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    loyaltyPoints: customer?.loyaltyPoints ?? 0,
                    totalSpent: customer?.totalSpent ?? 0,
                    lastVisit: customer?.lastVisit,
                    notes: notesCtrl.text.trim(),
                    createdAt: customer?.createdAt ?? DateTime.now(),
                  );
                  await context.read<InventoryProvider>().saveCustomer(c);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: saving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('SAVE CUSTOMER'),
              ),
              if (customer != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _confirmDelete(context, customer),
                  child: Text('Delete Customer', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Customer c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Customer?'),
        content: Text('Are you sure you want to remove ${c.name}? This will delete their rewards history permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.read<InventoryProvider>().deleteCustomer(c.id);
              Navigator.pop(ctx); // Dialog
              Navigator.pop(context); // Sheet
            },
            child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final tier = _getTier(customer.totalSpent);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: tier.color.withValues(alpha: 0.1),
          child: Icon(tier.icon, color: tier.color, size: 24),
        ),
        title: Row(
          children: [
            Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: tier.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(tier.name, style: TextStyle(color: tier.color, fontSize: 9, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(customer.phone, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('Lifetime: ${formatPeso(customer.totalSpent)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Points', style: Theme.of(context).textTheme.labelSmall),
              Text('${customer.loyaltyPoints}', 
                   style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
            ],
          ),
        ),
        onTap: () => _showCustomerDetails(context),
      ),
    );
  }

  void _showCustomerDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => _CustomerDetailsSheet(customer: customer),
    );
  }
}

class _TierInfo {
  final String name;
  final IconData icon;
  final Color color;
  final double nextThreshold;
  _TierInfo(this.name, this.icon, this.color, this.nextThreshold);
}

_TierInfo _getTier(double spent) {
  if (spent >= 50000) return _TierInfo('DIAMOND', Icons.diamond_rounded, Colors.cyan, 0);
  if (spent >= 15000) return _TierInfo('GOLD', Icons.workspace_premium_rounded, Colors.amber.shade700, 50000);
  if (spent >= 5000)  return _TierInfo('SILVER', Icons.stars_rounded, Colors.blueGrey, 15000);
  return _TierInfo('BRONZE', Icons.shield_rounded, Colors.brown.shade400, 5000);
}

class _CustomerDetailsSheet extends StatelessWidget {
  final Customer customer;
  const _CustomerDetailsSheet({required this.customer});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final txs = inventory.transactions.where((t) => t.customerId == customer.id).toList();
    final semantic = Theme.of(context).semantic;
    final tier = _getTier(customer.totalSpent);
    final double progress = tier.nextThreshold == 0 ? 1.0 : (customer.totalSpent / tier.nextThreshold).clamp(0, 1);

    // Calculate favorites
    final productCounts = <String, int>{};
    for (var tx in txs) {
      for (var item in tx.items) {
        productCounts[item.name] = (productCounts[item.name] ?? 0) + item.qty;
      }
    }
    final sortedFavorites = productCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(customer.name, style: Theme.of(context).textTheme.headlineMedium),
                          Row(
                            children: [
                              Text('Member since ${DateFormat('MMM yyyy').format(customer.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
                              if (customer.lastVisit != null) ...[
                                const Text(' · ', style: TextStyle(color: Colors.grey)),
                                Text('Last seen ${DateFormat('MMM d').format(customer.lastVisit!)}', style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // ── Membership Tier Card ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [tier.color, tier.color.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: tier.color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tier.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 1)),
                              const Text('Membership Status', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Icon(tier.icon, color: Colors.white, size: 40),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Points: ${customer.loyaltyPoints}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text('Spent: ${formatPeso(customer.totalSpent)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                      if (tier.nextThreshold > 0) ...[
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            color: Colors.white,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Spend ${formatPeso(tier.nextThreshold - customer.totalSpent)} more to reach ${ _getTier(tier.nextThreshold).name}', 
                             style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // ── Redeem Button ───────────────────────────────────────────
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: semantic.success, foregroundColor: Colors.white),
                  onPressed: customer.loyaltyPoints >= 50 ? () => _showRedeemDialog(context) : null,
                  icon: const Icon(Icons.card_giftcard_rounded),
                  label: Text(customer.loyaltyPoints >= 50 ? 'REDEEM REWARDS' : 'NEED 50 PTS TO REDEEM'),
                ),
                
                const SizedBox(height: 24),
                
                // ── Engagement Stats ─────────────────────────────────────────
                Row(
                  children: [
                    _StatBox(label: 'TOTAL VISITS', value: '${txs.length}', icon: Icons.shopping_bag_outlined),
                    const SizedBox(width: 12),
                    _StatBox(label: 'AVG. ORDER', value: formatPeso(txs.isEmpty ? 0 : customer.totalSpent / txs.length), icon: Icons.analytics_outlined),
                  ],
                ),
                const SizedBox(height: 32),
                
                if (customer.notes.isNotEmpty) ...[
                  Text('Customer Notes', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                    ),
                    child: Text(customer.notes, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
                  ),
                  const SizedBox(height: 32),
                ],
                
                if (sortedFavorites.isNotEmpty) ...[
                  Text('Favorite Items', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: sortedFavorites.take(5).length,
                      itemBuilder: (ctx, i) => Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(sortedFavorites[i].key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('${sortedFavorites[i].value} bought', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                Text('Recent Activity', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (txs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No purchase history yet.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)))),
                  )
                else
                  ...txs.take(10).map((tx) => _TransactionMiniCard(tx: tx)),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRedeemDialog(BuildContext context) {
    final pointsCtrl = TextEditingController(text: '50');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redeem Rewards'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter points to deduct for a discount or free item.'),
            const SizedBox(height: 16),
            TextField(
              controller: pointsCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Points to Deduct'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final pts = int.tryParse(pointsCtrl.text) ?? 0;
              if (pts <= 0 || pts > customer.loyaltyPoints) return;
              await context.read<InventoryProvider>().adjustPoints(customer.id, -pts);
              if (ctx.mounted) {
                Navigator.pop(ctx); 
                Navigator.pop(context); 
              }
            },
            child: const Text('Confirm Redemption'),
          ),
        ],
      ),
    );
  }
}

class _TransactionMiniCard extends StatelessWidget {
  final StoreTransaction tx;
  const _TransactionMiniCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        dense: true,
        title: Text(DateFormat('MMM dd, yyyy • hh:mm a').format(tx.createdAt), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        subtitle: Text(tx.items.map((i) => '${i.qty}x ${i.name}').join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatPeso(tx.total), style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
            Text('+${(tx.total / 100).floor()} pts', style: const TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatBox({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}
