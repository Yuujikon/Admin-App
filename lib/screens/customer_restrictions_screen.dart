import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/customer.dart';
import '../providers/inventory_provider.dart';
import '../services/firestore_service.dart';
import '../utils/format.dart';

/// Screen for managing customer ghosting offenses, progressive ordering restrictions, and account unlock appeals.
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
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final customers = inventory.customers;

    // Filter customers with offenses or appeals
    final offendingCustomers = customers.where((c) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = c.name.toLowerCase().contains(q);
        final matchesEmail = c.email?.toLowerCase().contains(q) ?? false;
        if (!matchesName && !matchesEmail) return false;
      }
      return c.offenseCount > 0 ||
          c.isPermanentlyLocked ||
          c.appealStatus == 'pending';
    }).toList();

    final pendingAppeals = customers
        .where((c) => c.isPermanentlyLocked && c.appealStatus == 'pending')
        .toList();

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Customer Restrictions & Appeals'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Penalty Tier Rule Card
          Container(
            padding: const EdgeInsets.all(16),
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
                        color: Colors.amber.shade900, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'OFFENSE PENALTY TIERS',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Automated order restrictions enforced when pre-orders are uncollected or ghosted:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                _buildTierRow('1st Offense', '2-Hour Order Restriction'),
                _buildTierRow('2nd Offense', '24-Hour Order Restriction'),
                _buildTierRow(
                    '3rd Offense', '72-Hour (3-Day) Order Restriction'),
                _buildTierRow(
                    '4th Offense', 'Permanent Account Lock (Requires Appeal)'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section 1: Pending Unlock Appeals
          if (pendingAppeals.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.mark_email_unread_rounded,
                    color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  'PENDING UNLOCK APPEALS (${pendingAppeals.length})',
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
            ...pendingAppeals.map((c) => _buildAppealCard(context, c)),
            const SizedBox(height: 24),
          ],

          // Section 2: Search & All Offense Records
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 20),
              const SizedBox(width: 8),
              const Text(
                'CUSTOMER OFFENSE RECORDS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showManualFlagModal(context, customers),
                icon: const Icon(Icons.add_moderator_rounded, size: 16),
                label: const Text('Record Offense'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GdcColors.darkEmerald,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Field
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search customer name or email...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
          const SizedBox(height: 16),

          if (offendingCustomers.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _searchQuery.isNotEmpty
                    ? 'No matching customer offense records.'
                    : 'No customer accounts currently have ghosting offenses or locks.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...offendingCustomers
                .map((c) => _buildCustomerOffenseCard(context, c)),
        ],
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
          Text(
            description,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildAppealCard(BuildContext context, Customer c) {
    final theme = Theme.of(context);
    final submittedDate = c.appealSubmittedAt != null
        ? DateFormat('MMM d, yyyy h:mm a').format(c.appealSubmittedAt!)
        : 'Recently';

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
            Row(
              children: [
                CircleAvatar(
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
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (c.email != null)
                        Text(
                          c.email!,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant),
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
                  child: const Text(
                    'PERMANENT LOCK',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customer Statement ($submittedDate):',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.appealMessage ?? 'No statement provided.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmRejectAppeal(context, c),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject Appeal'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmApproveAppeal(context, c),
                    icon: const Icon(Icons.check_circle_rounded, size: 16),
                    label: const Text('Approve & Unlock'),
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
    } else if (c.offenseCount == 1) {
      badgeColor = Colors.amber.shade800;
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
                        : Icons.warning_amber_rounded,
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
                      if (c.email != null)
                        Text(
                          c.email!,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant),
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
                'Recorded Offense Log:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...c.offenseHistory.take(3).map((h) {
                final String reason = h['reason']?.toString() ?? 'Ghosted order';
                final String orderId = h['orderId']?.toString() ?? '';
                final int offenseNum = (h['offenseNumber'] as num? ?? 1).toInt();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• Offense #$offenseNum ($orderId): $reason',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            // Actions: Reset Offenses / Flag Offense
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _confirmResetOffenses(context, c),
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: const Text('Reset Offenses & Unlock'),
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

              if (mounted) {
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

  void _confirmApproveAppeal(BuildContext context, Customer c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Unlock Appeal?'),
        content: Text(
            'This will unlock ${c.name}\'s account and set their offense count to 3 so they can place pre-orders again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _fs.approveCustomerAppeal(c.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Unlocked ${c.name}\'s account!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: GdcColors.emeraldPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve & Unlock'),
          ),
        ],
      ),
    );
  }

  void _confirmRejectAppeal(BuildContext context, Customer c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Appeal?'),
        content: Text(
            'Keep ${c.name}\'s account permanently locked. They will be notified of the decision.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _fs.rejectCustomerAppeal(c.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Rejected appeal for ${c.name}'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject Appeal'),
          ),
        ],
      ),
    );
  }

  void _confirmResetOffenses(BuildContext context, Customer c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Offense Record?'),
        content: Text(
            'This will clear all recorded offenses and order restrictions for ${c.name}, resetting their record to 0.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _fs.resetCustomerOffenses(c.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Cleared offense history for ${c.name}'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: GdcColors.emeraldPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset Offenses'),
          ),
        ],
      ),
    );
  }
}
