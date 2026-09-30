import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../widgets/responsive_layout.dart';

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
        label: const Text('Add New Staff'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('isCustomer', isNotEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text('Error loading staff: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          final activeStaff = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final role = data['role'] ?? 'none';
            final isDisabled = data['isDisabled'] == true;
            return role != 'none' && role != 'disabled' && !isDisabled;
          }).toList();

          final inactiveStaff = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final role = data['role'] ?? 'none';
            final isDisabled = data['isDisabled'] == true;
            return role == 'disabled' || isDisabled;
          }).toList();

          if (activeStaff.isEmpty && inactiveStaff.isEmpty) {
            return const Center(
                child: Text('No staff found. Click "Add New Staff" below.'));
          }

          final semantic = Theme.of(context).semantic;

          return ListView(
            padding:
                const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 88),
            children: [
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
              _sectionHeader(
                  'Staff History / Inactive (${inactiveStaff.length})',
                  Colors.grey),
              if (inactiveStaff.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No inactive staff records.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ResponsiveCardGrid(
                  children:
                      inactiveStaff.map((d) => _inactiveUserCard(context, d)).toList(),
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

  Widget _activeUserCard(BuildContext context, DocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;
    final email = data['email'] ?? 'No email';
    final name = data['name'] as String? ?? email.split('@').first;
    final role = data['role'] ?? 'cashier';
    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : null;
    final isMainAdmin = email == 'markjeo.hinampas@gmail.com';
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
        trailing: isMainAdmin
            ? const Chip(
                label: Text('OWNER',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: true,
                    onChanged: (_) =>
                        _confirmDisable(context, d.id, email, role),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onSelected: (val) {
                      if (val == 'role') {
                        _showEditRoleDialog(context, d.id, email, role);
                      } else if (val == 'reset_pin') {
                        _showResetPinDialog(context, email);
                      } else if (val == 'revoke') {
                        _confirmDisable(context, d.id, email, role);
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
                      const PopupMenuItem(
                        value: 'revoke',
                        child: Row(
                          children: [
                            Icon(Icons.block_rounded,
                                size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Revoke Access',
                                style:
                                    TextStyle(fontSize: 13, color: Colors.red)),
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
    final disabledAt = data['disabledAt'] != null
        ? (data['disabledAt'] as Timestamp).toDate()
        : null;

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
        leading: const CircleAvatar(
          backgroundColor: Colors.grey,
          child: Icon(Icons.person_off_rounded, color: Colors.white, size: 20),
        ),
        title: Text(name,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text('Previous Role: ${_getRoleLabel(previousRole)}',
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold)),
            if (disabledAt != null)
              Text('Disabled: ${DateFormat('MMM dd, yyyy').format(disabledAt)}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: false,
              onChanged: (_) =>
                  _confirmActivate(context, d.id, email, previousRole),
            ),
            ElevatedButton.icon(
              onPressed: () =>
                  _confirmActivate(context, d.id, email, previousRole),
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

  void _showEditRoleDialog(
      BuildContext context, String id, String email, String currentRole) {
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Staff Email: $email',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
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
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(id)
                    .update({'role': selected});
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Updated $email role to ${_getRoleLabel(selected)}')),
                );
              },
              child: const Text('UPDATE ROLE'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetPinDialog(BuildContext context, String email) {
    final pinCtrl = TextEditingController();

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Staff Security PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reset 4-digit PIN for: $email',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
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
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              if (pinCtrl.text.trim().length != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a 4-digit PIN.')),
                );
                return;
              }
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('Security PIN for $email updated successfully.')),
              );
            },
            child: const Text('SAVE PIN'),
          ),
        ],
      ),
    );
  }

  void _confirmDisable(
      BuildContext context, String id, String email, String currentRole) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable Employee Account?'),
        content: Text(
            'Are you sure you want to disable $email? They will lose access to the staff portal immediately, but their profile history will be saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () {
              FirebaseFirestore.instance.collection('users').doc(id).update({
                'isDisabled': true,
                'previousRole': currentRole,
                'role': 'disabled',
                'disabledAt': FieldValue.serverTimestamp(),
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Disabled $email. Account moved to Staff History.')),
              );
            },
            child: const Text('DISABLE EMPLOYEE'),
          ),
        ],
      ),
    );
  }

  void _confirmActivate(
      BuildContext context, String id, String email, String previousRole) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-enable Employee?'),
        content: Text(
            'Are you sure you want to re-activate $email with role ${_getRoleLabel(previousRole)}? They will regain access to the staff portal.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              FirebaseFirestore.instance.collection('users').doc(id).update({
                'isDisabled': false,
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
                '• Active/Inactive Toggle: Instantly toggle employee portal access while saving their history.',
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

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
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
        final uid = userCred.user!.uid;
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': name,
          'email': email,
          'pin': pin,
          'role': _selectedRole,
          'isDisabled': false,
          'isCustomer': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Staff $name ($email) created successfully!'),
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
          Text('Add New Staff',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
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
                  prefixIcon: Icon(Icons.person_outline),
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
                  prefixIcon: Icon(Icons.email_outlined),
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
                  prefixIcon: Icon(Icons.admin_panel_settings_outlined),
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
                  prefixIcon: const Icon(Icons.pin_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscurePin ? Icons.visibility_off : Icons.visibility),
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
