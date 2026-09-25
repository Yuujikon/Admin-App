import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEmployeeDialog(context),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Employee'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users')
            .where('isCustomer', isNotEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading staff: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final docs = snapshot.data?.docs ?? [];
          final staff = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final role = data['role'] ?? 'none';
            return role != 'none';
          }).toList();

          if (staff.isEmpty) {
            return const Center(child: Text('No active staff found. Click "Add Employee" below.'));
          }

          final semantic = Theme.of(context).semantic;

          return ListView(
            padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 88),
            children: [
              _sectionHeader('Active Staff (${staff.length})', semantic.info),
              ...staff.map((d) => _userCard(context, d)),
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

  Widget _userCard(BuildContext context, DocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;
    final email = data['email'] ?? 'No email';
    final role = data['role'] ?? 'cashier';
    final createdAt = data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : null;
    final isMainAdmin = email == 'markjeo.hinampas@gmail.com';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5), width: 1.5),
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
            Text('Role: ${_getRoleLabel(role)}', 
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
                  value: ['admin', 'inventoryManager', 'cashier'].contains(role) ? role : 'cashier',
                  onChanged: (newRole) {
                    if (newRole != null) {
                      FirebaseFirestore.instance.collection('users').doc(d.id).update({'role': newRole});
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'inventoryManager', child: Text('Inv Mgr', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'cashier', child: Text('Cashier', style: TextStyle(fontSize: 13))),
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

  String _getRoleLabel(String role) => switch (role) {
    'admin'            => 'ADMIN',
    'inventoryManager' => 'INV MGR',
    'cashier'          => 'CASHIER',
    _                  => role.toUpperCase(),
  };

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
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff?'),
        content: Text('Are you sure you want to remove $email? They will lose access to the staff portal immediately.'),
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
        title: Text('Role Permissions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Admin: Full access to POS, Inventory, Reports, and Settings.', style: TextStyle(fontSize: 13)),
            SizedBox(height: 6),
            Text('• Inv Mgr: Manage Inventory Stock, Suppliers, and Loss.', style: TextStyle(fontSize: 13)),
            SizedBox(height: 6),
            Text('• Cashier: Access to POS and Pre-Orders only.', style: TextStyle(fontSize: 13)),
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
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  String _selectedRole = 'cashier';
  bool _obscurePass = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }

    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
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
        password: password,
      );

      if (userCred.user != null) {
        final uid = userCred.user!.uid;
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': email,
          'role': _selectedRole,
          'isCustomer': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Employee $email created successfully!'),
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
      title: const Row(
        children: [
          Icon(Icons.person_add_rounded),
          SizedBox(width: 8),
          Text('Add New Employee', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the email and password for the new staff member. They will use these credentials to log in.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              enabled: !_loading,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Staff Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              enabled: !_loading,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'Temporary Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Assigned Role',
                prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                DropdownMenuItem(value: 'inventoryManager', child: Text('Inventory Manager')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: _loading ? null : (v) {
                if (v != null) setState(() => _selectedRole = v);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ],
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
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('CREATE EMPLOYEE'),
        ),
      ],
    );
  }
}
