import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/customer.dart';
import '../providers/inventory_provider.dart';
import '../services/firestore_service.dart';
import '../shared/services/time_service.dart';
import '../utils/format.dart';
import '../widgets/action_warning_dialog.dart';
import '../widgets/admin_filter_bar.dart';

/// Screen for managing customer complaints, ghosting offenses, progressive ordering restrictions, and account unlock appeals.
class CustomerRestrictionsScreen extends StatefulWidget {
  const CustomerRestrictionsScreen({super.key});

  @override
  State<CustomerRestrictionsScreen> createState() =>
      _CustomerRestrictionsScreenState();
}

class _CustomerRestrictionsScreenState
    extends State<CustomerRestrictionsScreen> {
  final FirestoreService _fs = FirestoreService();
  String _searchQuery = '';
  String _selectedFilter = 'all'; // 'all', 'appeals', 'restricted', 'locked'

  @override
  Widget build(BuildContext context) {
    context.watch<TimeService>();
    final inventory = context.watch<InventoryProvider>();
    final customers = inventory.customers;
    final rawAppeals = inventory.appeals;

    // Filter customers with offenses or appeals
    final offendingCustomers = customers.where((c) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = c.name.toLowerCase().contains(q);
        final matchesEmail = c.email?.toLowerCase().contains(q) ?? false;
        final matchesPhone = c.phone.toLowerCase().contains(q);
        if (!matchesName && !matchesEmail && !matchesPhone) return false;
      }
      return c.offenseCount > 0 ||
          c.isPermanentlyLocked ||
          c.appealStatus == 'pending';
    }).toList();

    // Build comprehensive pending appeals list from customers, users, and appeals collection
    final pendingAppealsMap = <String, Customer>{};

    for (final c in customers) {
      if (c.appealStatus == 'pending' ||
          (c.isPermanentlyLocked && c.appealStatus == 'pending')) {
        pendingAppealsMap[c.id] = c;
        if (c.email != null && c.email!.isNotEmpty) {
          pendingAppealsMap[c.email!.toLowerCase()] = c;
        }
      }
    }

    for (final a in rawAppeals) {
      final st = (a['status'] ?? a['appealStatus'] ?? 'pending')
          .toString()
          .toLowerCase();
      if (st == 'pending') {
        final uid =
            (a['userId'] ?? a['customerId'] ?? a['id'] ?? '').toString();
        final email = (a['customerEmail'] ?? a['userEmail'] ?? a['email'] ?? '')
            .toString()
            .toLowerCase();

        final alreadyMatched =
            (uid.isNotEmpty && pendingAppealsMap.containsKey(uid)) ||
                (email.isNotEmpty && pendingAppealsMap.containsKey(email));

        if (!alreadyMatched) {
          DateTime? subDate;
          final rawTS = a['createdAt'] ?? a['submittedAt'] ?? a['timestamp'];
          if (rawTS is Timestamp) subDate = rawTS.toDate();

          final syntheticCustomer = Customer(
            id: uid.isNotEmpty
                ? uid
                : (a['id'] ??
                        'appeal_${TimeService.now.millisecondsSinceEpoch}')
                    .toString(),
            name: (a['customerName'] ?? a['name'] ?? 'Customer (Appealed)')
                .toString(),
            email: (a['customerEmail'] ?? a['userEmail'] ?? a['email'] ?? '')
                .toString(),
            phone: (a['customerPhone'] ?? a['phone'] ?? '').toString(),
            createdAt: subDate ?? TimeService.now,
            offenseCount: 4,
            isPermanentlyLocked: true,
            appealStatus: 'pending',
            appealMessage: (a['appealMessage'] ??
                    a['message'] ??
                    a['reason'] ??
                    'No statement provided by customer.')
                .toString(),
            appealSubmittedAt: subDate ?? TimeService.now,
          );

          pendingAppealsMap[syntheticCustomer.id] = syntheticCustomer;
        }
      }
    }

    final pendingAppeals = pendingAppealsMap.values.toSet().toList();

    final int temporaryRestrictedCount =
        customers.where((c) => c.isRestricted && !c.isPermanentlyLocked).length;
    final int lockedCount = customers.where((c) => c.isPermanentlyLocked).length;

    // Apply Filter Tab Selection
    List<Customer> filteredOffendingCustomers = offendingCustomers.where((c) {
      if (_selectedFilter == 'appeals') return c.appealStatus == 'pending';
      if (_selectedFilter == 'restricted') return c.isRestricted && !c.isPermanentlyLocked;
      if (_selectedFilter == 'locked') return c.isPermanentlyLocked;
      return true;
    }).toList();

    List<Customer> filteredAppeals = pendingAppeals.where((c) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = c.name.toLowerCase().contains(q);
        final matchesEmail = c.email?.toLowerCase().contains(q) ?? false;
        final matchesReason = c.appealMessage?.toLowerCase().contains(q) ?? false;
        if (!matchesName && !matchesEmail && !matchesReason) return false;
      }
      return true;
    }).toList();

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Customer Complaints & Restrictions'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Stat Counters Header
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  title: 'Pending Complaints',
                  count: pendingAppeals.length,
                  icon: Icons.mark_email_unread_rounded,
                  color: Colors.red,
                  isSelected: _selectedFilter == 'appeals',
                  onTap: () => setState(() => _selectedFilter =
                      _selectedFilter == 'appeals' ? 'all' : 'appeals'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  context,
                  title: 'Temp Restrictions',
                  count: temporaryRestrictedCount,
                  icon: Icons.timer_outlined,
                  color: Colors.amber.shade900,
                  isSelected: _selectedFilter == 'restricted',
                  onTap: () => setState(() => _selectedFilter =
                      _selectedFilter == 'restricted' ? 'all' : 'restricted'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  context,
                  title: 'Permanent Locks',
                  count: lockedCount,
                  icon: Icons.lock_rounded,
                  color: Colors.deepOrange,
                  isSelected: _selectedFilter == 'locked',
                  onTap: () => setState(() => _selectedFilter =
                      _selectedFilter == 'locked' ? 'all' : 'locked'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Penalty Tier Rule Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.gavel_rounded,
                        color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'OFFENSE PENALTY TIERS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Automated order restrictions enforced when pre-orders are uncollected or ghosted:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                _buildTierRow('1st Offense', '2-Hour Order Restriction'),
                _buildTierRow('2nd Offense', '24-Hour Order Restriction'),
                _buildTierRow(
                    '3rd Offense', '72-Hour (3-Day) Order Restriction'),
                _buildTierRow(
                    '4th Offense', 'Permanent Account Lock (Requires Complaint/Appeal Review)'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Automated Search Field & Action Bar
          AdminFilterBar(
            searchQuery: _searchQuery,
            searchHint: 'Search customer name, email, or complaint details…',
            onSearchChanged: (val) => setState(() => _searchQuery = val.trim()),
            totalCount: customers.length,
            filteredCount: offendingCustomers.length,
            itemUnit: 'records',
            extraActions: [
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showManualFlagModal(context, customers),
                icon: const Icon(Icons.add_moderator_rounded, size: 16),
                label: const Text('Record Offense'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GdcColors.darkEmerald,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All Records'),
                  selected: _selectedFilter == 'all',
                  onSelected: (_) => setState(() => _selectedFilter = 'all'),
                  selectedColor: GdcColors.emeraldPrimary.withValues(alpha: 0.2),
                  checkmarkColor: GdcColors.darkEmerald,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Pending Complaints (${pendingAppeals.length})'),
                  selected: _selectedFilter == 'appeals',
                  onSelected: (_) => setState(() => _selectedFilter = 'appeals'),
                  selectedColor: Colors.red.shade100,
                  checkmarkColor: Colors.red,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Temp Restricted ($temporaryRestrictedCount)'),
                  selected: _selectedFilter == 'restricted',
                  onSelected: (_) => setState(() => _selectedFilter = 'restricted'),
                  selectedColor: Colors.amber.shade100,
                  checkmarkColor: Colors.amber.shade900,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Permanent Locks ($lockedCount)'),
                  selected: _selectedFilter == 'locked',
                  onSelected: (_) => setState(() => _selectedFilter = 'locked'),
                  selectedColor: Colors.deepOrange.shade100,
                  checkmarkColor: Colors.deepOrange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 1: Pending Complaints & Appeals
          if ((_selectedFilter == 'all' || _selectedFilter == 'appeals') &&
              filteredAppeals.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.mark_email_unread_rounded,
                    color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  'PENDING CUSTOMER COMPLAINTS & APPEALS (${filteredAppeals.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...filteredAppeals.map((c) => _buildAppealCard(context, c)),
            const SizedBox(height: 24),
          ],

          // Section 2: All Customer Offense & Restriction Records
          if (_selectedFilter != 'appeals') ...[
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  'CUSTOMER RESTRICTION & OFFENSE RECORDS (${filteredOffendingCustomers.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (filteredOffendingCustomers.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _searchQuery.isNotEmpty
                      ? 'No matching customer offense records found.'
                      : 'No customer accounts currently match the selected restriction filter.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else
              ...filteredOffendingCustomers
                  .map((c) => _buildCustomerOffenseCard(context, c)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierRow(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.amber.shade900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppealCard(BuildContext context, Customer c) {
    final theme = Theme.of(context);
    final submittedDate = c.appealSubmittedAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(c.appealSubmittedAt!)
        : 'Recently';
    final regDate = DateFormat('MMM d, yyyy').format(c.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Customer Avatar, Name, Email, Phone & Lock Badge
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.red.shade100,
                  child: const Icon(Icons.no_accounts_rounded, color: Colors.red),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (c.email != null && c.email!.isNotEmpty)
                        Text(
                          c.email!,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      if (c.phone.isNotEmpty)
                        Text(
                          'Phone: ${c.phone}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c.isPermanentlyLocked ? 'PERMANENT LOCK' : 'RESTRICTED',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Customer Summary Row
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Registered: $regDate',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    'Lifetime Spend: ${formatPeso(c.totalSpent)}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Complaint / Appeal Statement Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CUSTOMER COMPLAINT / APPEAL STATEMENT:',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Colors.red.shade900),
                      ),
                      Text(
                        submittedDate,
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.appealMessage ?? 'No statement provided by customer.',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.red.shade900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Action Buttons: Reject Complaint vs Remove Restriction & Approve
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmRejectAppeal(context, c),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('REJECT COMPLAINT'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showRemoveRestrictionModal(context, c),
                    icon: const Icon(Icons.lock_open_rounded, size: 16),
                    label: const Text('REMOVE RESTRICTION'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GdcColors.emeraldPrimary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerOffenseCard(BuildContext context, Customer c) {
    final theme = Theme.of(context);

    Color badgeColor = Colors.orange;
    if (c.isPermanentlyLocked) {
      badgeColor = Colors.red;
    } else if (c.isRestricted) {
      badgeColor = Colors.amber.shade900;
    } else {
      badgeColor = Colors.blueGrey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: badgeColor.withValues(alpha: 0.15),
                  child: Icon(
                    c.isPermanentlyLocked
                        ? Icons.lock_rounded
                        : c.isRestricted
                            ? Icons.timer_outlined
                            : Icons.history_rounded,
                    color: badgeColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (c.email != null && c.email!.isNotEmpty)
                        Text(
                          c.email!,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      if (c.phone.isNotEmpty)
                        Text(
                          'Phone: ${c.phone}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.primary),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c.offenseStatusLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (c.isRestricted && !c.isPermanentlyLocked && c.restrictedUntil != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 16, color: Colors.amber.shade900),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Temporary Order Restriction active until ${DateFormat('MMM d, h:mm a').format(c.restrictedUntil!)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Offense History Log Summary
            if (c.offenseHistory.isNotEmpty) ...[
              const Text(
                'Recorded Offense & Restriction Log:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...c.offenseHistory.take(4).map((h) {
                final String reason = h['reason']?.toString() ?? 'Ghosted order';
                final String orderId = h['orderId']?.toString() ?? '';
                final String flaggedType = h['flaggedType']?.toString() ?? 'Offense';
                final int offenseNum = (h['offenseNumber'] as num? ?? 1).toInt();
                final bool isLifted = flaggedType == 'Restriction Lifted';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isLifted ? Icons.check_circle_outline_rounded : Icons.fiber_manual_record_rounded,
                        size: 12,
                        color: isLifted ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isLifted
                              ? '[LIFTED] $reason'
                              : 'Offense #$offenseNum (${orderId.isNotEmpty ? orderId : "System"}): $reason',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isLifted ? FontWeight.bold : FontWeight.normal,
                            color: isLifted ? Colors.green.shade800 : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            // Actions: Remove Restriction / Reset Offenses
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (c.isRestricted || c.isPermanentlyLocked) ...[
                  ElevatedButton.icon(
                    onPressed: () => _showRemoveRestrictionModal(context, c),
                    icon: const Icon(Icons.lock_open_rounded, size: 16),
                    label: const Text('Remove Restriction'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GdcColors.darkEmerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: () => _confirmResetOffenses(context, c),
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: const Text('Reset Record'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveRestrictionModal(BuildContext context, Customer c) {
    final reasonCtrl = TextEditingController(
        text: c.appealMessage != null && c.appealMessage!.isNotEmpty
            ? 'Complaint resolved: ${c.appealMessage}'
            : '');
    bool resetOffenses = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: GdcColors.emeraldPrimary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_open_rounded, color: GdcColors.darkEmerald),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Remove Restriction',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Customer Overview Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (c.email != null && c.email!.isNotEmpty)
                        Text(
                          c.email!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.isPermanentlyLocked ? Colors.red.shade100 : Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              c.offenseStatusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: c.isPermanentlyLocked ? Colors.red.shade900 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Reason for Removing Restriction / Resolution Notes:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g. Complaint verified - order delay was due to store delay / Granted 1st grace period',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),

                // Checkbox: Reset Offense Count to 0
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: GdcColors.darkEmerald,
                  title: const Text(
                    'Also reset total offense count to 0 (Clean Record)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'If unchecked, ordering restriction is lifted but offense history level is retained.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  value: resetOffenses,
                  onChanged: (val) {
                    setDialogState(() {
                      resetOffenses = val ?? false;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final reason = reasonCtrl.text.trim();
                Navigator.pop(ctx);

                await _fs.liftCustomerRestriction(
                  customerId: c.id,
                  reason: reason.isNotEmpty
                      ? reason
                      : 'Restriction removed by store management following complaint review',
                  resetOffenses: resetOffenses,
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Successfully removed ordering restriction for ${c.name}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Remove Restriction'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GdcColors.darkEmerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualFlagModal(BuildContext context, List<Customer> customers) {
    final emailCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Customer Offense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manually apply a ghosting offense penalty to a customer account. The penalty duration will automatically escalate based on their offense count.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Customer Email Address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason / Notes',
                hintText: 'e.g. Uncollected pre-order #GDC-1042',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              final reason = reasonCtrl.text.trim();
              if (email.isEmpty) return;

              Navigator.pop(ctx);
              await _fs.recordCustomerOffense(
                email: email,
                customerName: email,
                orderId: 'MANUAL',
                reason: reason.isNotEmpty
                    ? reason
                    : 'Manual Admin Ghosting Flag',
                isManualAdminFlag: true,
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Recorded offense penalty for $email'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: GdcColors.darkEmerald,
              foregroundColor: Colors.white,
            ),
            child: const Text('Apply Penalty'),
          ),
        ],
      ),
    );
  }

  void _confirmRejectAppeal(BuildContext context, Customer c) async {
    final confirm = await ActionWarningDialog.show(
      context,
      title: 'Reject Complaint / Appeal?',
      message:
          'Keep ${c.name}\'s account restricted/locked. They will be notified of the decision.',
      confirmLabel: 'Reject Complaint',
      cancelLabel: 'Cancel',
      severity: ActionWarningSeverity.danger,
      icon: Icons.block_rounded,
      details: [
        'Customer: ${c.name}',
        'Email: ${c.email ?? "N/A"}',
      ],
    );

    if (confirm) {
      await _fs.rejectCustomerAppeal(c.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejected complaint/appeal for ${c.name}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _confirmResetOffenses(BuildContext context, Customer c) async {
    final confirm = await ActionWarningDialog.show(
      context,
      title: 'Reset Offense Record?',
      message:
          'This will clear all recorded offenses and ordering restrictions for ${c.name}, resetting their record to 0.',
      confirmLabel: 'Reset Offenses',
      cancelLabel: 'Cancel',
      severity: ActionWarningSeverity.warning,
      icon: Icons.restore_rounded,
      details: [
        'Customer: ${c.name}',
        'Current Offense Count: ${c.offenseCount}',
      ],
    );

    if (confirm) {
      await _fs.resetCustomerOffenses(c.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleared offense history for ${c.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}
