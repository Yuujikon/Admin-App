import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/printer_provider.dart';
import '../config/theme.dart';
import '../utils/totp.dart';
import 'user_management_screen.dart';
import 'supplier_management_screen.dart';
import 'shift_screen.dart';
import 'loss_management_screen.dart';
import 'reports_screen.dart';
import 'bundle_management_screen.dart';
import 'category_management_screen.dart';
import 'sales_history_screen.dart';
import 'refund_requests_screen.dart';

class MoreManagementScreen extends StatelessWidget {
  const MoreManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final bool isAdmin = auth.role == UserRole.admin;
    final bool isInv   = auth.role == UserRole.inventoryManager;
    final bool isCashier = auth.role == UserRole.cashier;

    final semantic = Theme.of(context).semantic;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Store Management',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _menuItem(
                context,
                icon: Icons.point_of_sale_rounded,
                title: 'Shift & Cash Register',
                subtitle: 'X/Z readings, cash drops & opening float',
                color: Colors.green.shade800,
                target: const ShiftScreen(),
              ),
              const SizedBox(height: 12),
              if (isAdmin) ...[
                _menuItem(
                  context,
                  icon: Icons.manage_accounts_outlined,
                  title: 'Staff & Roles',
                  subtitle: 'Manage cashier permissions & history',
                  color: semantic.info,
                  target: const UserManagementScreen(),
                ),
                const SizedBox(height: 12),
              ],
              if (isAdmin || isInv) ...[
                _menuItem(
                  context,
                  icon: Icons.local_shipping_outlined,
                  title: 'Suppliers',
                  subtitle: 'Manage delivery contacts and restocks',
                  color: semantic.success,
                  target: const SupplierManagementScreen(),
                ),
                const SizedBox(height: 12),
                _menuItem(
                  context,
                  icon: Icons.category_outlined,
                  title: 'Categories',
                  subtitle: 'Manage master category list',
                  color: Colors.blue.shade700,
                  target: const CategoryManagementScreen(),
                ),
                const SizedBox(height: 12),
                _menuItem(
                  context,
                  icon: Icons.auto_awesome_motion_rounded,
                  title: 'Cooking Bundles',
                  subtitle: 'Group items into recipe sets',
                  color: Colors.orange.shade700,
                  target: const BundleManagementScreen(),
                ),
                const SizedBox(height: 12),
                _menuItem(
                  context,
                  icon: Icons.delete_sweep_outlined,
                  title: 'Loss & Waste',
                  subtitle: 'View expired or damaged items',
                  color: semantic.warning,
                  target: const LossManagementScreen(),
                ),
                const SizedBox(height: 12),
              ],
              if (isAdmin) ...[
                _menuItem(
                  context,
                  icon: Icons.analytics_outlined,
                  title: 'Monthly Reports',
                  subtitle: 'Sales, expenses, and net profit',
                  color: Colors.purple.withValues(alpha: 0.7),
                  target: const ReportsScreen(),
                ),
                const SizedBox(height: 12),
              ],
              if (isAdmin || isCashier) ...[
                _menuItem(
                  context,
                  icon: Icons.history_rounded,
                  title: 'Sales History',
                  subtitle: 'View past store transactions',
                  color: Colors.blueGrey,
                  target: const SalesHistoryScreen(),
                ),
                const SizedBox(height: 12),
              ],
              if (isAdmin) ...[
                _menuItem(
                  context,
                  icon: Icons.assignment_return_rounded,
                  title: 'Refund Requests',
                  subtitle: 'Manage online refund claims',
                  color: Theme.of(context).colorScheme.error,
                  target: const RefundRequestsScreen(),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: SwitchListTile(
                  title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Soothing for nighttime use'),
                  secondary: Icon(
                    context.watch<ThemeProvider>().isDarkMode ? Icons.dark_mode : Icons.light_mode,
                    color: GdcColors.secondaryGreen,
                  ),
                  value: context.watch<ThemeProvider>().isDarkMode,
                  onChanged: (v) => context.read<ThemeProvider>().toggleTheme(v),
                ),
              ),
              const Divider(height: 32),
              const _AccountSecuritySection(),
              const SizedBox(height: 16),
              const _AdminProfileSection(),
              const SizedBox(height: 16),
              const _PrinterToolsSection(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext context, {
    required IconData icon, 
    required String title, 
    required String subtitle, 
    required Color color,
    required Widget target
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
        trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => target)),
      ),
    );
  }
}

class _AccountSecuritySection extends StatelessWidget {
  const _AccountSecuritySection();

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => const _ChangePasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('My Staff Account', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_circle_outlined, color: Colors.blue),
                ),
                title: Text(
                  user?.email ?? 'Staff Account',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Currently logged in staff account', style: TextStyle(fontSize: 12)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: Colors.orange),
                ),
                title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Update your login password', style: TextStyle(fontSize: 12)),
                trailing: IconButton.filledTonal(
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  onPressed: () => _showChangePasswordDialog(context),
                ),
                onTap: () => _showChangePasswordDialog(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl     = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew     = true;
  bool _obscureConfirm = true;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentPass = _currentPassCtrl.text.trim();
    final newPass     = _newPassCtrl.text.trim();
    final confirmPass = _confirmPassCtrl.text.trim();

    if (currentPass.isEmpty) {
      setState(() => _error = 'Please enter your current password.');
      return;
    }
    if (newPass.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        setState(() {
          _loading = false;
          _error = 'No logged in user found.';
        });
        return;
      }

      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPass,
      );

      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPass);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully! ✅'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = switch (e.code) {
            'wrong-password' || 'invalid-credential' => 'Current password is incorrect.',
            'weak-password' => 'New password is too weak.',
            'requires-recent-login' => 'Please log out and log in again to change password.',
            _ => e.message ?? 'Failed to update password.',
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Error updating password: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: Colors.blue),
          SizedBox(width: 8),
          Text('Change Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Logged in as: ${user?.email ?? 'Staff Account'}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _currentPassCtrl,
                enabled: !_loading,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPassCtrl,
                enabled: !_loading,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: const Icon(Icons.lock_clock_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassCtrl,
                enabled: !_loading,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  prefixIcon: const Icon(Icons.check_circle_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
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
            : const Text('UPDATE PASSWORD'),
        ),
      ],
    );
  }
}

class _PrinterToolsSection extends StatelessWidget {
  const _PrinterToolsSection();

  static void showPrinterDialog(BuildContext context, PrinterProvider printer) async {
    final devices = await printer.getDevices();

    if (context.mounted) {
      showDialog(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Bluetooth Printer'),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.isEmpty
                ? const Text('No paired bluetooth devices found. Please pair your thermal printer in your device Bluetooth settings first.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (context, i) {
                      final d = devices[i];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth_rounded, color: Colors.blue),
                        title: Text(d.name.isEmpty ? 'Unknown Device' : d.name),
                        subtitle: Text(d.macAdress),
                        trailing: printer.device?.macAdress == d.macAdress && printer.connected
                            ? Icon(Icons.check_circle, color: Theme.of(context).semantic.success)
                            : null,
                        onTap: () {
                          printer.connect(d);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            if (printer.connected)
              TextButton(
                onPressed: () {
                  printer.disconnect();
                  Navigator.pop(ctx);
                },
                child: Text('Disconnect', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final printer = context.watch<PrinterProvider>();
    final color = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('Printer Tools', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (printer.connected ? Colors.blue : Colors.grey).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    printer.connected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
                    color: printer.connected ? Colors.blue : Colors.grey,
                  ),
                ),
                title: Text(
                  printer.connected
                      ? (printer.device?.name.isNotEmpty == true ? printer.device!.name : 'Bluetooth Printer')
                      : 'Bluetooth Printer',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  printer.connected
                      ? 'Connected (${printer.device?.macAdress ?? ''})'
                      : 'Tap to connect paired bluetooth printer',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: printer.isConnecting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton.filledTonal(
                        icon: Icon(
                          printer.connected ? Icons.settings_rounded : Icons.bluetooth_searching_rounded,
                          size: 20,
                        ),
                        tooltip: printer.connected ? 'Manage' : 'Connect',
                        onPressed: () => showPrinterDialog(context, printer),
                      ),
                onTap: () => showPrinterDialog(context, printer),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Icon(Icons.print_rounded, color: printer.connected ? color : Colors.grey),
                title: const Text('Test Print', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  printer.connected
                      ? 'Send sample test ticket to printer'
                      : 'Connect a printer above to test',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton.filledTonal(
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  tooltip: 'Test Print',
                  onPressed: printer.connected
                      ? () async {
                          final success = await printer.printTest();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success ? "Test print sent!" : "Test print failed."),
                              ),
                            );
                          }
                        }
                      : () => showPrinterDialog(context, printer),
                ),
                onTap: printer.connected
                    ? () async {
                        final success = await printer.printTest();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(success ? "Test print sent!" : "Test print failed."),
                            ),
                          );
                        }
                      }
                    : () => showPrinterDialog(context, printer),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminProfileSection extends StatelessWidget {
  const _AdminProfileSection();

  Future<void> _launchAuthenticatorApp(BuildContext context, AppAuthProvider auth) async {
    if (!auth.isTotpLinked) {
      // First time setup: prompt to add token via otpauth://
      final uri = auth.totpUri;
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          auth.markTotpLinked();
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Authenticator app. Please copy secret key manually.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authenticator app not found. Please copy secret key or install Google Authenticator.')),
          );
        }
      }
    } else {
      // Token already linked: open Google Authenticator app directly without adding token again
      final directUris = [
        Uri.parse('android-app://com.google.android.apps.authenticator2'),
        Uri.parse('intent://#Intent;package=com.google.android.apps.authenticator2;end'),
      ];

      bool launched = false;
      for (final uri in directUris) {
        try {
          launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) break;
        } catch (_) {}
      }

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please open Google Authenticator on your device.')),
        );
      }
    }
  }

  void _showSetupDialog(BuildContext context, AppAuthProvider auth) {
    final readableSecret = TotpUtils.formatSecretReadable(auth.totpSecret);

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Google Authenticator Setup', 
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Zero-typing setup: Tap below to automatically link your key to Google Authenticator:', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _launchAuthenticatorApp(context, auth),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('OPEN AUTHENTICATOR APP', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Manual Setup Option:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            const Text('Account Name: GDC Admin', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      readableSecret,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13, letterSpacing: 1),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20, color: Colors.blue),
                    tooltip: 'Copy Key',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: auth.totpSecret));
                      auth.markTotpLinked();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Secret key copied to clipboard!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final readableSecret = TotpUtils.formatSecretReadable(auth.totpSecret);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('Account Security (Google Authenticator 2FA)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  value: auth.totpEnabled,
                  onChanged: (val) => auth.setTotpEnabled(val),
                  title: const Text('Require 6-Digit Code on Login', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    auth.totpEnabled 
                        ? '6-digit Google Authenticator 2FA is active.' 
                        : '6-digit Google Authenticator 2FA is turned off.',
                    style: TextStyle(fontSize: 11, color: auth.totpEnabled ? Colors.green.shade700 : Colors.red.shade700),
                  ),
                  secondary: Icon(
                    auth.totpEnabled ? Icons.security_rounded : Icons.security_outlined,
                    color: auth.totpEnabled ? Colors.blue : Colors.grey,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.verified_user_rounded, color: Colors.blue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Google Authenticator TOTP Key', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('Secret: $readableSecret', style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_2_rounded, color: Colors.blue),
                      tooltip: 'Setup Instructions',
                      onPressed: () => _showSetupDialog(context, auth),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: () => _launchAuthenticatorApp(context, auth),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('OPEN AUTHENTICATOR APP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: () => _showSetupDialog(context, auth),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('SETUP KEY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
