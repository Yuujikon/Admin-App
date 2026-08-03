import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading users: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No users found in database.'));
          }

          final semantic = Theme.of(context).semantic;

          // Separate users into Requests (role: none) and Active Staff
          final requests = docs.where((d) => (d.data() as Map)['role'] == 'none').toList();
          final staff = docs.where((d) => (d.data() as Map)['role'] != 'none').toList();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (requests.isNotEmpty) ...[
                _sectionHeader('Access Requests (${requests.length})', semantic.warning),
                ...requests.map((d) => _userCard(context, d, isRequest: true)),
                const SizedBox(height: 24),
              ],
              _sectionHeader('Active Staff (${staff.length})', semantic.info),
              ...staff.map((d) => _userCard(context, d, isRequest: false)),
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
          Container(width: 4, height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _userCard(BuildContext context, DocumentSnapshot d, {required bool isRequest}) {
    final data = d.data() as Map<String, dynamic>;
    final email = data['email'] ?? 'No email';
    final role = data['role'] ?? 'none';
    final createdAt = data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : null;
    final isMainAdmin = email == 'markjeo.hinampas@gmail.com';

    return Card(
      elevation: isRequest ? 2 : 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isRequest ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3) : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5), width: 1.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: _getRoleColor(role, context).withValues(alpha: 0.1),
          child: Icon(_getRoleIcon(role), color: _getRoleColor(role, context)),
        ),
        title: Text(email, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Role: ${role.toUpperCase().replaceAll('MANAGER', ' MGR')}', 
                 style: TextStyle(fontSize: 11, color: _getRoleColor(role, context), fontWeight: FontWeight.bold)),
            if (createdAt != null)
              Text('Joined: ${DateFormat('MMM dd, yyyy').format(createdAt)}', style: const TextStyle(fontSize: 10)),
          ],
        ),
        trailing: isMainAdmin ? const Chip(label: Text('OWNER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))) 
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  underline: const SizedBox(),
                  value: ['admin', 'inventoryManager', 'cashier', 'none'].contains(role) ? role : 'none',
                  onChanged: (newRole) {
                    if (newRole != null) {
                      FirebaseFirestore.instance.collection('users').doc(d.id).update({'role': newRole});
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'inventoryManager', child: Text('Inv Mgr', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'cashier', child: Text('Cashier', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'none', child: Text('Pending', style: TextStyle(fontSize: 13))),
                  ],
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: Theme.of(context).colorScheme.error),
                  onPressed: () => _confirmDelete(context, d.id, email),
                ),
              ],
            ),
      ),
    );
  }

  Color _getRoleColor(String role, BuildContext context) {
    final semantic = Theme.of(context).semantic;
    return switch (role) {
      'admin'            => semantic.success,
      'inventoryManager' => semantic.warning,
      'cashier'          => semantic.info,
      _                  => Theme.of(context).disabledColor,
    };
  }

  IconData _getRoleIcon(String role) => switch (role) {
    'admin'            => Icons.admin_panel_settings_rounded,
    'inventoryManager' => Icons.inventory_2_rounded,
    'cashier'          => Icons.point_of_sale_rounded,
    _                  => Icons.person_outline_rounded,
  };

  void _confirmDelete(BuildContext context, String id, String email) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove User?'),
        content: Text('Are you sure you want to remove $email? They will lose all access immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance.collection('users').doc(id).delete();
              Navigator.pop(ctx);
            },
            child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(
        title: Text('Role Permissions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Admin: Full access to everything.', style: TextStyle(fontSize: 13)),
            SizedBox(height: 4),
            Text('• Inv Mgr: Manage Stock, Suppliers, and Loss.', style: TextStyle(fontSize: 13)),
            SizedBox(height: 4),
            Text('• Cashier: POS and Order management only.', style: TextStyle(fontSize: 13)),
            SizedBox(height: 4),
            Text('• Pending: No access. Waiting for approval.', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
