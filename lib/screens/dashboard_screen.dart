import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/inventory_provider.dart';
import '../../models/store_settings.dart';
import '../../providers/order_provider.dart';
import '../../providers/expense_provider.dart';
import '../../models/order.dart';
import '../../utils/format.dart';
import '../config/theme.dart';

class DashboardScreen extends StatelessWidget {
  final Function(int, {String? category}) onTabChange;
  const DashboardScreen({super.key, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    final inventory   = context.watch<InventoryProvider>();
    final transactions = inventory.transactions;
    final orders       = context.watch<OrderProvider>().orders;
    final expenses     = context.watch<ExpenseProvider>().expenses;
    final isClosed     = inventory.settings.effectivelyClosed;

    final today      = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayTx    = transactions.where(
            (t) => DateFormat('yyyy-MM-dd').format(t.createdAt) == today).toList();
    final todaySales = todayTx.fold(0.0, (s, t) => s + t.total);
    final todayExp   = expenses
        .where((e) => DateFormat('yyyy-MM-dd').format(e.createdAt) == today)
        .fold(0.0, (s, e) => s + e.amount);
    final pending    = orders.where((o) => o.status == OrderStatus.pending).length;
    final net        = todaySales - todayExp;
    final totalLoss  = inventory.lossRecords.fold(0.0, (s, r) => s + r.totalLoss);
    final semantic = Theme.of(context).semantic;

    // Low Stock Alerts
    final lowStock = inventory.products.where((p) => p.stock <= 5).toList();

    // Movement Insights (Last 30 Days)
    final fastMoving = inventory.fastMovingItems;
    final slowMoving = inventory.slowMovingItems;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overview',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(DateFormat('EEEE, MMMM d').format(DateTime.now()),
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
              // Store Status Toggle
              ActionChip(
                backgroundColor: isClosed ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1) : (inventory.settings.scheduledCloseAt != null ? semantic.warning.withValues(alpha: 0.1) : semantic.success.withValues(alpha: 0.1)),
                side: BorderSide(color: isClosed ? Theme.of(context).colorScheme.error.withValues(alpha: 0.2) : (inventory.settings.scheduledCloseAt != null ? semantic.warning.withValues(alpha: 0.2) : semantic.success.withValues(alpha: 0.2))),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                avatar: Icon(isClosed ? Icons.storefront_outlined : (inventory.settings.scheduledCloseAt != null ? Icons.schedule : Icons.storefront), 
                             size: 16, color: isClosed ? Theme.of(context).colorScheme.error : (inventory.settings.scheduledCloseAt != null ? semantic.warning : semantic.success)),
                label: Text(isClosed ? 'CLOSED' : (inventory.settings.scheduledCloseAt != null ? 'SCHEDULED' : 'OPEN'),
                            style: TextStyle(color: isClosed ? Theme.of(context).colorScheme.error : (inventory.settings.scheduledCloseAt != null ? semantic.warning : semantic.success), fontWeight: FontWeight.w800, fontSize: 11)),
                onPressed: () => _showStatusDialog(context, inventory),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Stat cards
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16, mainAxisSpacing: 16,
            childAspectRatio: 1.25,
            children: [
              _StatCard("Today's Sales", formatPeso(todaySales),
                  Icons.auto_graph_rounded, semantic.success),
              _StatCard("Net Income",    formatPeso(net),
                  Icons.wallet_rounded,
                  net >= 0 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error),
              _StatCard("Expenses",      formatPeso(todayExp),
                  Icons.receipt_long_rounded,  Theme.of(context).colorScheme.error, 
                  onTap: () => onTabChange(4, category: null)), // Go to Expenses
              _StatCard("Pending Orders","$pending",
                  Icons.pending_actions_rounded, semantic.warning,
                  onTap: () => onTabChange(3, category: null)), // Go to Orders
            ],
          ),

          const SizedBox(height: 16),

          // Summary row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(child: InkWell(
                  onTap: () => onTabChange(3, category: null),
                  child: _MiniStat('Sales', '${todayTx.length}'))),
                const _Divider(),
                Expanded(child: _MiniStat('Units',
                    '${todayTx.fold(0, (s, t) => s + t.items.fold(0, (a, i) => a + i.qty))}')),
                const _Divider(),
                Expanded(child: _MiniStat('Average', todayTx.isEmpty
                    ? '—' : formatPeso(todaySales / todayTx.length))),
              ],
            ),
          ),

          const SizedBox(height: 24),
          
          // ── Fast Moving Items ──────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.bolt, size: 20, color: semantic.warning),
              const SizedBox(width: 8),
              Text('Fast Moving Items (30d)',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          if (fastMoving.isEmpty)
             Card(child: Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('No sales records', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12)))))
          else
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: fastMoving.take(10).length,
                itemBuilder: (context, index) {
                  final entry = fastMoving[index];
                  return Card(
                    margin: const EdgeInsets.only(right: 12),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('${entry.value} sold', style: TextStyle(fontSize: 11, color: semantic.warning)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 16),

          // ── Slow Moving Items ──────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.hourglass_bottom, size: 20, color: semantic.info),
              const SizedBox(width: 8),
              Text('Slow Moving Items (30d)',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          if (slowMoving.isEmpty)
             Card(child: Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('Everythings moving!', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12)))))
          else
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: slowMoving.take(10).length,
                itemBuilder: (context, index) {
                  final p = slowMoving[index];
                  final sold = inventory.recentMovementCounts[p.name] ?? 0;
                  return Card(
                    margin: const EdgeInsets.only(right: 12),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(sold == 0 ? 'No sales' : '$sold sold', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          if (lowStock.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Text('Low Stock Alerts',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.error)),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: lowStock.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = lowStock[index];
                  return ListTile(
                    dense: true,
                    onTap: () => onTabChange(2, category: 'Low Stock'), // Go to Inventory -> Low Stock
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(p.category, style: const TextStyle(fontSize: 10)),
                    trailing: Text('${p.stock} ${p.unit} left', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 24),
          Text('Recent Transactions',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          if (todayTx.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No transactions today', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            )),

          ...todayTx.take(5).map((tx) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(Icons.receipt, color: Theme.of(context).colorScheme.primary)),
              title: Text(formatPeso(tx.total),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${tx.items.length} item${tx.items.length != 1 ? 's' : ''} · '
                  '${DateFormat('hh:mm a').format(tx.createdAt)}'),
              trailing: Text(formatPeso(tx.change),
                  style: Theme.of(context).textTheme.labelSmall),
            ),
          )),
        ]),
      ),
    );
  }

  void _showStatusDialog(BuildContext context, InventoryProvider inventory) {
    final settings = inventory.settings;
    final isClosed = settings.isClosed;
    final controller = TextEditingController(text: settings.closureMessage);
    
    DateTime? schedClose = settings.scheduledCloseAt;
    DateTime? schedOpen = settings.scheduledOpenAt;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Store Management'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Status Overview ──────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isClosed ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1) : Theme.of(context).semantic.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(isClosed ? Icons.lock : Icons.lock_open, color: isClosed ? Theme.of(context).colorScheme.error : Theme.of(context).semantic.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isClosed ? 'Store is currently CLOSED' : 'Store is currently OPEN',
                          style: TextStyle(fontWeight: FontWeight.bold, color: isClosed ? Theme.of(context).colorScheme.error : Theme.of(context).semantic.success),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                const Text('Manual Toggle', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Closure Notice',
                    hintText: 'Optional message for customers',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isClosed ? Theme.of(context).semantic.success : Theme.of(context).colorScheme.error,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    try {
                      await inventory.toggleStoreStatus(!isClosed, message: controller.text.trim());
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Store status updated successfully')),
                      );
                    } catch (e) {
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Theme.of(context).colorScheme.error),
                      );
                    }
                  },
                  icon: Icon(isClosed ? Icons.play_arrow_rounded : Icons.power_settings_new_rounded),
                  label: Text(isClosed ? 'Open Store Now' : 'Close Store Now'),
                ),

                const Divider(height: 48),
                Text('Scheduled Outing', style: Theme.of(context).textTheme.titleSmall),
                Text('Automatically close and reopen the store.', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 16),
                
                // Start Time
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Starts At', style: TextStyle(fontSize: 13)),
                  subtitle: Text(schedClose == null ? 'Not set' : DateFormat('MMM d, h:mm a').format(schedClose!)),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
                    if (date != null) {
                      final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                      if (time != null) {
                        setDialogState(() => schedClose = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                      }
                    }
                  },
                ),

                // End Time
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reopens At', style: TextStyle(fontSize: 13)),
                  subtitle: Text(schedOpen == null ? 'Not set' : DateFormat('MMM d, h:mm a').format(schedOpen!)),
                  trailing: const Icon(Icons.restore, size: 18),
                  onTap: () async {
                    final date = await showDatePicker(context: context, initialDate: schedClose ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
                    if (date != null) {
                      final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 11, minute: 0));
                      if (time != null) {
                        setDialogState(() => schedOpen = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                      }
                    }
                  },
                ),

                if (schedClose != null && schedOpen != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await inventory.toggleStoreStatus(isClosed, 
                            message: 'Scheduled Closure: ${DateFormat('MMM d').format(schedClose!)} – ${DateFormat('MMM d').format(schedOpen!)}',
                            closeAt: schedClose,
                            openAt: schedOpen,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Schedule saved successfully')),
                          );
                        } catch (e) {
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Theme.of(context).colorScheme.error),
                          );
                        }
                      },
                      child: const Text('Save Schedule'),
                    ),
                  ),

                if (settings.scheduledCloseAt != null)
                  TextButton(
                    onPressed: () async {
                      await inventory.toggleStoreStatus(isClosed, closeAt: null, openAt: null);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text('Clear Schedule', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),

                const Divider(height: 48),
                Text('Store Announcement', style: Theme.of(context).textTheme.titleSmall),
                Text('Display a scrolling ticker to customers.', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Current Announcement',
                    hintText: 'e.g. Fresh batch of donuts at 3PM!',
                    border: OutlineInputBorder(),
                  ),
                  controller: TextEditingController(text: settings.announcement),
                  onSubmitted: (v) => inventory.saveStoreSettings(StoreSettings(
                    isClosed: settings.isClosed,
                    closureMessage: settings.closureMessage,
                    scheduledCloseAt: settings.scheduledCloseAt,
                    scheduledOpenAt: settings.scheduledOpenAt,
                    perishableWindowHours: settings.perishableWindowHours,
                    mixedWindowHours: settings.mixedWindowHours,
                    standardWindowHours: settings.standardWindowHours,
                    announcement: v.trim().isEmpty ? null : v.trim(),
                  )),
                ),

                const Divider(height: 48),
                Text('Order Expiration Windows', style: Theme.of(context).textTheme.titleSmall),
                Text('Time customers have to pick up their orders.', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 16),

                _WindowInput(
                  label: 'Perishables Only',
                  hint: 'e.g. 2 hours',
                  value: settings.perishableWindowHours,
                  onChanged: (v) => inventory.saveStoreSettings(StoreSettings(
                    isClosed: settings.isClosed,
                    closureMessage: settings.closureMessage,
                    scheduledCloseAt: settings.scheduledCloseAt,
                    scheduledOpenAt: settings.scheduledOpenAt,
                    perishableWindowHours: v,
                    mixedWindowHours: settings.mixedWindowHours,
                    standardWindowHours: settings.standardWindowHours,
                  )),
                ),
                const SizedBox(height: 12),
                _WindowInput(
                  label: 'Mixed Orders',
                  hint: 'e.g. 24 hours',
                  value: settings.mixedWindowHours,
                  onChanged: (v) => inventory.saveStoreSettings(StoreSettings(
                    isClosed: settings.isClosed,
                    closureMessage: settings.closureMessage,
                    scheduledCloseAt: settings.scheduledCloseAt,
                    scheduledOpenAt: settings.scheduledOpenAt,
                    perishableWindowHours: settings.perishableWindowHours,
                    mixedWindowHours: v,
                    standardWindowHours: settings.standardWindowHours,
                  )),
                ),
                const SizedBox(height: 12),
                _WindowInput(
                  label: 'Non-Perishables',
                  hint: 'e.g. 72 hours',
                  value: settings.standardWindowHours,
                  onChanged: (v) => inventory.saveStoreSettings(StoreSettings(
                    isClosed: settings.isClosed,
                    closureMessage: settings.closureMessage,
                    scheduledCloseAt: settings.scheduledCloseAt,
                    scheduledOpenAt: settings.scheduledOpenAt,
                    perishableWindowHours: settings.perishableWindowHours,
                    mixedWindowHours: settings.mixedWindowHours,
                    standardWindowHours: v,
                  )),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _StatCard(this.label, this.value, this.icon, this.color, {this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).brightness == Brightness.light 
              ? Colors.black.withValues(alpha: 0.03) 
              : Colors.transparent,
          blurRadius: 10,
          offset: const Offset(0, 4),
        )
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
                  maxLines: 1),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  const _MiniStat(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
    Text(label,
        style: const TextStyle(color: Colors.grey, fontSize: 10),
        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
  ]);
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5));
}

class _WindowInput extends StatelessWidget {
  final String label;
  final String hint;
  final int value;
  final ValueChanged<int> onChanged;

  const _WindowInput({required this.label, required this.hint, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: TextField(
            keyboardType: TextInputType.number,
            textAlign: TextAlign.end,
            decoration: InputDecoration(
              hintText: hint,
              suffixText: ' hr',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            controller: TextEditingController(text: value.toString()),
            onSubmitted: (v) {
              final n = int.tryParse(v);
              if (n != null) onChanged(n);
            },
          ),
        ),
      ],
    );
  }
}
