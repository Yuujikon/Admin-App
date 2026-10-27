import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/responsive_layout.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  Future<int> _getActiveAdminCount() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .where('isDisabled', isEqualTo: false)
        .get();
    return snap.docs.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Staff & Role Management'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelp(context),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEmployeeDialog(context),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add New Staff'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text('Error loading staff: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          final docs = allDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['isCustomer'] != true;
          }).toList();

          final pendingRequests = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final role = data['role'] ?? 'none';
            final status = data['status'] as String?;
            final isDisabled = data['isDisabled'] == true;
            return (status == 'pending' || role == 'none') &&
                !isDisabled &&
                status != 'denied';
          }).toList();

          final activeStaff = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final role = data['role'] ?? 'none';
            final status = data['status'] as String?;
            final isDisabled = data['isDisabled'] == true;
            return (status == 'approved' ||
                    (role != 'none' &&
                        role != 'disabled' &&
                        status != 'pending')) &&
                !isDisabled &&
                status != 'denied';
          }).toList();

          final inactiveStaff = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final role = data['role'] ?? 'none';
            final status = data['status'] as String?;
            final isDisabled = data['isDisabled'] == true;
            return isDisabled || role == 'disabled' || status == 'denied';
          }).toList();

          if (pendingRequests.isEmpty &&
              activeStaff.isEmpty &&
              inactiveStaff.isEmpty) {
            return const Center(
                child: Text('No staff records found. Click "Add New Staff" below.'));
          }

          final semantic = Theme.of(context).semantic;

          return ListView(
            padding:
                const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 88),
            children: [
              // PENDING APPROVAL REQUESTS
              _sectionHeader('Pending Approval Requests (${pendingRequests.length})',
                  Colors.amber.shade800),
              if (pendingRequests.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No pending registration requests.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ResponsiveCardGrid(
                  children: pendingRequests
                      .map((d) => _pendingUserCard(context, d))
                      .toList(),
                ),
              const SizedBox(height: 16),

              // ACTIVE STAFF
              _sectionHeader(
                  'Active Staff (${activeStaff.length})', semantic.info),
              if (activeStaff.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No active staff currently.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ResponsiveCardGrid(
                  children:
                      activeStaff.map((d) => _activeUserCard(context, d)).toList(),
                ),
              const SizedBox(height: 16),

              // INACTIVE / DENIED STAFF
              _sectionHeader(
                  'Staff History / Inactive & Denied (${inactiveStaff.length})',
                  Colors.grey),
              if (inactiveStaff.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No inactive or denied staff records.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ResponsiveCardGrid(
                  children: inactiveStaff
                      .map((d) => _inactiveUserCard(context, d))
                      .toList(),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color.withValues(alpha: 0.9))),
        ],
      ),
    );
  }

  Widget _pendingUserCard(BuildContext context, DocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;
    final email = data['email'] ?? 'No email';
    final name = data['name'] as String? ?? email.split('@').first;
    final requestedRole = data['requestedRole'] as String? ?? 'cashier';
    final authMethod = data['authMethod'] as String? ?? 'email';
    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : null;

    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'P';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: Colors.amber.shade300.withValues(alpha: 0.8), width: 1.5),
      ),
      color: Colors.amber.shade50.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.amber.shade100,
                child: Text(
                  initials,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                      fontSize: 16),
                ),
              ),
              title: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(email,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Req: ${_getRoleLabel(requestedRole)}',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          authMethod == 'google' ? 'Google Auth' : 'Email/Pass',
                          style: const TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (createdAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Requested: ${DateFormat('MMM dd, yyyy').format(createdAt)}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _confirmDeny(context, d.id, name, email),
                  icon: const Icon(Icons.cancel_outlined,
                      size: 14, color: Colors.red),
                  label: const Text('DENY',
                      style:
                          TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () =>
                      _showApproveDialog(context, d.id, name, email, requestedRole),
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      size: 14, color: Colors.white),
                  label: const Text('APPROVE & ASSIGN ROLE',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeUserCard(BuildContext context, DocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;
    final email = data['email'] ?? 'No email';
    final name = data['name'] as String? ?? email.split('@').first;
    final role = data['role'] ?? 'cashier';
    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : null;

    final currentUser = FirebaseAuth.instance.currentUser;
    final isCurrentUser = currentUser != null &&
        (d.id == currentUser.uid || email == currentUser.email);

    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'S';
    final roleColor = _getRoleBadgeColor(role);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
            width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: roleColor.withValues(alpha: 0.15),
          child: Text(
            initials,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: roleColor, fontSize: 16),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCurrentUser) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'YOU',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: roleColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                _getRoleLabel(role),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: roleColor),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(email,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (createdAt != null)
              Text('Joined: ${DateFormat('MMM dd, yyyy').format(createdAt)}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: true,
              onChanged: (_) =>
                  _confirmDisable(context, d.id, name, email, role),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (val) {
                if (val == 'role') {
                  _showEditRoleDialog(context, d.id, name, email, role);
                } else if (val == 'reset_pin') {
                  _showResetPinDialog(context, d.id, name, email);
                } else if (val == 'revoke') {
                  _confirmDisable(context, d.id, name, email, role);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'role',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit Role', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'reset_pin',
                  child: Row(
                    children: [
                      Icon(Icons.lock_reset_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Reset Security PIN',
                          style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'revoke',
                  child: Row(
                    children: [
                      const Icon(Icons.block_rounded,
                          size: 18, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        isCurrentUser ? 'Disable My Account' : 'Revoke Access',
                        style: const TextStyle(fontSize: 13, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _inactiveUserCard(BuildContext context, DocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;
    final email = data['email'] ?? 'No email';
    final name = data['name'] as String? ?? email.split('@').first;
    final previousRole = data['previousRole'] ?? 'cashier';
    final status = data['status'] as String?;
    final disabledAt = data['disabledAt'] != null
        ? (data['disabledAt'] as Timestamp).toDate()
        : (data['deniedAt'] != null
            ? (data['deniedAt'] as Timestamp).toDate()
            : null);

    final isDenied = status == 'denied';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: isDenied ? Colors.red.shade100 : Colors.grey,
          child: Icon(
              isDenied ? Icons.gpp_bad_rounded : Icons.person_off_rounded,
              color: isDenied ? Colors.red : Colors.white,
              size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.grey)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDenied ? Colors.red.shade50 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isDenied ? 'DENIED' : 'INACTIVE',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isDenied ? Colors.red.shade800 : Colors.grey.shade700),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text('Previous/Req Role: ${_getRoleLabel(previousRole)}',
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold)),
            if (disabledAt != null)
              Text(
                '${isDenied ? "Denied" : "Disabled"}: ${DateFormat('MMM dd, yyyy').format(disabledAt)}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: false,
              onChanged: (_) =>
                  _confirmActivate(context, d.id, name, email, previousRole),
            ),
            ElevatedButton.icon(
              onPressed: () =>
                  _confirmActivate(context, d.id, name, email, previousRole),
              icon: const Icon(Icons.restart_alt_rounded, size: 14),
              label: const Text('RE-ENABLE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRoleLabel(String role) => switch (role) {
        'admin' => 'Admin',
        'inventoryManager' => 'Inventory Manager',
        'cashier' => 'Cashier',
        _ => role.toUpperCase(),
      };

  Color _getRoleBadgeColor(String role) {
    return switch (role) {
      'admin' => const Color(0xFF7E57C2), // Purple
      'cashier' => const Color(0xFF4CAF50), // Green
      'inventoryManager' => const Color(0xFF2196F3), // Blue
      _ => Colors.grey,
    };
  }

  void _showApproveDialog(
      BuildContext context, String id, String name, String email, String initialRequestedRole) {
    String selectedRole =
        ['admin', 'inventoryManager', 'cashier'].contains(initialRequestedRole)
            ? initialRequestedRole
            : 'cashier';

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green),
              SizedBox(width: 8),
              Text('Approve Registration'),
            ],
          ),
          content: Container(
            width: 440,
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text('Applicant: $name',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              Text('Email: $email',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(
                    labelText: 'Assign Authorized Role',
                    border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: 'admin', child: Text('Admin (Purple Badge)')),
                  DropdownMenuItem(
                      value: 'cashier', child: Text('Cashier (Green Badge)')),
                  DropdownMenuItem(
                      value: 'inventoryManager',
                      child: Text('Inventory Manager (Blue Badge)')),
                ],
                onChanged: (v) {
                  if (v != null) setSt(() => selectedRole = v);
                },
              ),
            ],
          ),
        ),
        actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                FirebaseFirestore.instance.collection('users').doc(id).update({
                  'role': selectedRole,
                  'status': 'approved',
                  'isDisabled': false,
                  'approvedAt': FieldValue.serverTimestamp(),
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Approved $name ($email) as ${_getRoleLabel(selectedRole)}!')),
                );
              },
              child: const Text('APPROVE & GRANT ACCESS'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeny(BuildContext context, String id, String name, String email) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Deny Registration Request?'),
        content: Text(
            'Are you sure you want to deny $name ($email)? They will be blocked from accessing the staff portal.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              FirebaseFirestore.instance.collection('users').doc(id).update({
                'status': 'denied',
                'role': 'none',
                'isDisabled': true,
                'deniedAt': FieldValue.serverTimestamp(),
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Denied $name ($email) registration request.')),
              );
            },
            child: const Text('DENY REQUEST'),
          ),
        ],
      ),
    );
  }

  void _showEditRoleDialog(
      BuildContext context, String id, String name, String email, String currentRole) async {
    String selected =
        ['admin', 'inventoryManager', 'cashier'].contains(currentRole)
            ? currentRole
            : 'cashier';

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Text('Edit Staff Role'),
          content: Container(
            width: 440,
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Staff Member: $name',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                Text('Email: $email',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: ['admin', 'cashier', 'inventoryManager'].contains(selected)
                      ? selected
                      : 'cashier',
                  decoration: const InputDecoration(
                      labelText: 'Assigned Role', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'admin', child: Text('Admin (Purple Badge)')),
                    DropdownMenuItem(
                        value: 'cashier', child: Text('Cashier (Green Badge)')),
                    DropdownMenuItem(
                        value: 'inventoryManager',
                        child: Text('Inventory Manager (Blue Badge)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setSt(() => selected = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () async {
                // Safety check: if demoting an admin, make sure another active admin exists
                if (currentRole == 'admin' && selected != 'admin') {
                  final activeAdmins = await _getActiveAdminCount();
                  if (activeAdmins <= 1) {
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        useRootNavigator: true,
                        builder: (alertCtx) => AlertDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange),
                              SizedBox(width: 8),
                              Text('Cannot Demote Admin'),
                            ],
                          ),
                          content: Text(
                              'You cannot demote $name ($email) because it is currently the only active Store Admin account. Please approve or assign another staff member as an Admin first.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(alertCtx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                    return;
                  }
                }

                FirebaseFirestore.instance.collection('users').doc(id).update({
                  'role': selected,
                  'status': 'approved',
                  'isDisabled': false,
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Updated $name ($email) role to ${_getRoleLabel(selected)}')),
                );
              },
              child: const Text('UPDATE ROLE'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetPinDialog(
      BuildContext context, String docId, String name, String email) {
    final pinCtrl = TextEditingController();

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Staff Security PIN'),
        content: Container(
          width: 440,
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text('Reset 4-digit PIN for: $name',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            Text('Email: $email',
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New 4-Digit Security PIN',
                prefixIcon: Icon(Icons.pin_rounded),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final newPin = pinCtrl.text.trim();
              if (newPin.length != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a 4-digit PIN.')),
                );
                return;
              }

              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(docId)
                  .update({'pin': newPin});

              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Security PIN for $name ($email) updated successfully.')),
                );
              }
            },
            child: const Text('SAVE PIN'),
          ),
        ],
      ),
    );
  }

  void _confirmDisable(
      BuildContext context, String id, String name, String email, String currentRole) async {
    // Safety check: if disabling an admin account, ensure another active admin exists
    if (currentRole == 'admin') {
      final activeAdmins = await _getActiveAdminCount();
      if (activeAdmins <= 1) {
        if (context.mounted) {
          showDialog(
            context: context,
            useRootNavigator: true,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Cannot Disable Account'),
                ],
              ),
              content: Text(
                'You cannot disable $name ($email) because it is currently the only active Store Admin account. To retire or disable this account, please first approve or assign another staff member as an Admin.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable Employee Account?'),
        content: Text(
            'Are you sure you want to disable $name ($email)? They will lose access to the staff portal immediately, but their profile history will be saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('users').doc(id).update({
                'isDisabled': true,
                'status': 'denied',
                'previousRole': currentRole,
                'role': 'disabled',
                'disabledAt': FieldValue.serverTimestamp(),
              });
              Navigator.pop(ctx);

              final currentUser = FirebaseAuth.instance.currentUser;
              final isSelf = currentUser?.uid == id || currentUser?.email == email;

              if (context.mounted) {
                if (isSelf) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Your admin account has been disabled. Logging out...')),
                  );
                  context.read<AppAuthProvider>().logout();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Disabled $name ($email). Account moved to Staff History.')),
                  );
                }
              }
            },
            child: const Text('DISABLE EMPLOYEE'),
          ),
        ],
      ),
    );
  }

  void _confirmActivate(
      BuildContext context, String id, String name, String email, String previousRole) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-enable Employee?'),
        content: Text(
            'Are you sure you want to re-activate $name ($email) with role ${_getRoleLabel(previousRole)}? They will regain access to the staff portal.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              FirebaseFirestore.instance.collection('users').doc(id).update({
                'isDisabled': false,
                'status': 'approved',
                'role': previousRole,
                'activatedAt': FieldValue.serverTimestamp(),
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Re-activated $email successfully!')),
              );
            },
            child: const Text('RE-ACTIVATE STAFF'),
          ),
        ],
      ),
    );
  }

  void _showAddEmployeeDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogCtx) => const _AddEmployeeDialog(),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => const AlertDialog(
        title: Text('Role Permissions & Badges'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '• Admin (Purple Badge): Full access to POS, Inventory, Reports, and Staff Settings.',
                style: TextStyle(fontSize: 13)),
            SizedBox(height: 6),
            Text(
                '• Inventory Manager (Blue Badge): Manage Stock, Suppliers, Bundles, and Loss Logs.',
                style: TextStyle(fontSize: 13)),
            SizedBox(height: 6),
            Text('• Cashier (Green Badge): Access to POS and Pre-Orders only.',
                style: TextStyle(fontSize: 13)),
            SizedBox(height: 12),
            Text(
                '• Admin Retirement: To disable your own admin account, ensure another active Admin exists first.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _AddEmployeeDialog extends StatefulWidget {
  const _AddEmployeeDialog();

  @override
  State<_AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<_AddEmployeeDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _selectedRole = 'cashier';
  bool _obscurePin = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Please enter staff full name.');
      return;
    }

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid real email address.');
      return;
    }

    if (pin.length < 4) {
      setState(
          () => _error = 'Security PIN/Password must be at least 4 digits.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'EmployeeApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final userCred = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: pin.length >= 6
            ? pin
            : '${pin}0000', // ensure valid firebase auth pass
      );

      if (userCred.user != null) {
        await userCred.user!.sendEmailVerification().catchError((e) {
          debugPrint('Error sending verification email: $e');
        });

        final uid = userCred.user!.uid;
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': name,
          'email': email,
          'pin': pin,
          'role': _selectedRole,
          'status': 'approved',
          'isDisabled': false,
          'isCustomer': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Staff $name ($email) created! Verification email sent.'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = switch (e.code) {
            'email-already-in-use' => 'This email is already registered.',
            'invalid-email' => 'Invalid email format.',
            'weak-password' => 'Password is too weak.',
            _ => e.message ?? 'Failed to create employee account.',
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Error creating account: $e';
        });
      }
    } finally {
      await secondaryApp?.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.person_add_rounded),
          SizedBox(width: 8),
          Text('Add New Staff',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Container(
        width: 440,
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter staff profile details and security credentials for system access.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Staff Full Name',
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailCtrl,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Staff Email',
                  prefixIcon: Icon(Icons.email_outlined, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: ['admin', 'cashier', 'inventoryManager']
                        .contains(_selectedRole)
                    ? _selectedRole
                    : 'cashier',
                decoration: const InputDecoration(
                  labelText: 'Assigned Role',
                  prefixIcon: Icon(Icons.admin_panel_settings_outlined, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'admin', child: Text('Admin (Purple Badge)')),
                  DropdownMenuItem(
                      value: 'cashier', child: Text('Cashier (Green Badge)')),
                  DropdownMenuItem(
                      value: 'inventoryManager',
                      child: Text('Inventory Manager (Blue Badge)')),
                ],
                onChanged: _loading
                    ? null
                    : (v) {
                        if (v != null) setState(() => _selectedRole = v);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pinCtrl,
                enabled: !_loading,
                obscureText: _obscurePin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Initial Security PIN / Password',
                  prefixIcon: const Icon(Icons.pin_rounded, size: 20),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscurePin ? Icons.visibility_off : Icons.visibility,
                        size: 20),
                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('CREATE STAFF'),
        ),
      ],
    );
  }
}
