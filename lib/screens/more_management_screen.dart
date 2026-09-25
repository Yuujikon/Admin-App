import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/printer_provider.dart';
import '../config/theme.dart';
import 'user_management_screen.dart';
import 'supplier_management_screen.dart';
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

    final semantic = Theme.of(context).semantic;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Store Management'), backgroundColor: Theme.of(context).colorScheme.surface),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isAdmin) ...[
            _menuItem(
              context,
              icon: Icons.manage_accounts_outlined,
              title: 'Staff & Roles',
              subtitle: 'Manage cashier permissions',
              color: semantic.info,
              target: const UserManagementScreen(),
            ),
            const SizedBox(height: 12),
          ],
          _menuItem(
            context,
            icon: Icons.local_shipping_outlined,
            title: 'Suppliers',
            subtitle: 'Manage delivery contacts and restocks',
            color: semantic.success,
            target: const SupplierManagementScreen(),
          ),
          const SizedBox(height: 12),
          if (isAdmin) ...[
            _menuItem(
              context,
              icon: Icons.category_outlined,
              title: 'Categories',
              subtitle: 'Manage master category list',
              color: Colors.blue.shade700,
              target: const CategoryManagementScreen(),
            ),
            const SizedBox(height: 12),
          ],
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
          _menuItem(
            context,
            icon: Icons.analytics_outlined,
            title: 'Monthly Reports',
            subtitle: 'Sales, expenses, and net profit',
            color: Colors.purple.withValues(alpha: 0.7),
            target: const ReportsScreen(),
          ),
          const SizedBox(height: 12),
          _menuItem(
            context,
            icon: Icons.history_rounded,
            title: 'Sales History',
            subtitle: 'View past store transactions',
            color: Colors.blueGrey,
            target: const SalesHistoryScreen(),
          ),
          const SizedBox(height: 12),
          _menuItem(
            context,
            icon: Icons.assignment_return_rounded,
            title: 'Refund Requests',
            subtitle: 'Manage online refund claims',
            color: Theme.of(context).colorScheme.error,
            target: const RefundRequestsScreen(),
          ),
          const SizedBox(height: 12),
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
          const _AdminProfileSection(),
          const SizedBox(height: 12),
          const _PrinterToolsSection(),
          const SizedBox(height: 32),
        ],
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
                    : OutlinedButton.icon(
                        icon: Icon(
                          printer.connected ? Icons.settings_rounded : Icons.bluetooth_searching_rounded,
                          size: 16,
                        ),
                        label: Text(printer.connected ? 'Manage' : 'Connect'),
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
                trailing: FilledButton.tonalIcon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Test'),
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

class _AdminProfileSection extends StatefulWidget {
  const _AdminProfileSection();

  @override
  State<_AdminProfileSection> createState() => _AdminProfileSectionState();
}

class _AdminProfileSectionState extends State<_AdminProfileSection> {
  final _phoneCtrl = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    if (!_editing) {
      _phoneCtrl.text = auth.phoneNumber ?? '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('Admin Security (SMS)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone_android, color: GdcColors.secondaryGreen),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Phone for OTP', style: TextStyle(fontWeight: FontWeight.bold)),
                          if (_editing)
                            TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                hintText: '+639123456789',
                                isDense: true,
                              ),
                            )
                          else
                            Text(auth.phoneNumber ?? 'Not Set', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(_editing ? Icons.check : Icons.edit, color: _editing ? Colors.green : Colors.grey),
                      onPressed: () async {
                        if (_editing) {
                          await auth.updatePhoneNumber(_phoneCtrl.text.trim());
                        }
                        setState(() => _editing = !_editing);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'A unique 6-digit OTP will be sent to this number whenever you access the Admin area.',
                  style: TextStyle(fontSize: 10, color: Colors.orange, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
