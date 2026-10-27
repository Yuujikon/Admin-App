import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/printer_provider.dart';
import '../services/auth_service.dart';
import '../config/theme.dart';
import '../utils/totp.dart';
import 'user_management_screen.dart';
import 'supplier_management_screen.dart';
import 'shift_screen.dart';
import 'reports_screen.dart';
import 'category_bundle_management_screen.dart';
import 'sales_history_screen.dart';
import 'inventory_records_screen.dart';
import 'admin_app.dart';
import '../widgets/responsive_layout.dart';

class MoreManagementScreen extends StatelessWidget {
  final void Function(AppTab)? onNavigateToTab;

  const MoreManagementScreen({
    super.key,
    this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final user = auth.currentUser;
    final rawEmail = user?.email ?? 'Maria Reyes';
    final name = (user?.displayName != null && user!.displayName!.isNotEmpty)
        ? user.displayName!
        : (rawEmail.contains('@') ? rawEmail.split('@').first : rawEmail);
    final initials = name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : 'MR');

    final bool isAdmin = auth.role == UserRole.admin;
    final bool isInv = auth.role == UserRole.inventoryManager;
    final bool isCashier = auth.role == UserRole.cashier;

    final semantic = Theme.of(context).semantic;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(context).padding.bottom + 96),
          child: MaxWidthWrapper(
            maxWidth: 1000.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Store Management Header Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GDC SARI-SARI STORE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Store Management',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Top Right User Card Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFFDBEAFE),
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1FAE5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _getRoleLabel(auth.role),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // 1. Operational Tools
                _sectionHeader(
                  context,
                  title: 'Operational tools',
                  subtitle: 'Daily store activity',
                ),
                _menuItemCard(
                  context,
                  icon: Icons.access_time_rounded,
                  iconBg: GdcColors.creamActiveBackground,
                  iconColor: GdcColors.darkEmerald,
                  title: 'Shift & Cash Register',
                  subtitle: 'X/Z readings, cash drops & opening float',
                  onTap: () {
                    if (onNavigateToTab != null) {
                      onNavigateToTab!(AppTab.shift);
                    } else {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ShiftScreen()));
                    }
                  },
                ),
                if (isAdmin || isCashier) ...[
                  _menuItemCard(
                    context,
                    icon: Icons.access_time_rounded,
                    iconBg: const Color(0xFFF1F5F9),
                    iconColor: const Color(0xFF475569),
                    title: 'Sales History',
                    subtitle: 'View & search past transactions',
                    onTap: () {
                      if (onNavigateToTab != null) {
                        onNavigateToTab!(AppTab.salesHistory);
                      } else {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SalesHistoryScreen()));
                      }
                    },
                  ),
                ],
                const SizedBox(height: 24),

                // 2. Inventory & Supply Chain
                if (isAdmin || isInv) ...[
                  _sectionHeader(
                    context,
                    title: 'Inventory & supply chain',
                    subtitle: 'Products, deliveries and partners',
                  ),
                  _menuItemCard(
                    context,
                    icon: Icons.article_outlined,
                    iconBg: GdcColors.creamActiveBackground,
                    iconColor: GdcColors.darkEmerald,
                    title: 'Inventory Records & Logs',
                    subtitle:
                        'Delivery logs, batch expiry & stock adjustments',
                    onTap: () {
                      if (onNavigateToTab != null) {
                        onNavigateToTab!(AppTab.inventoryRecords);
                      } else {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const InventoryRecordsScreen()));
                      }
                    },
                  ),
                  _menuItemCard(
                    context,
                    icon: Icons.local_shipping_outlined,
                    iconBg: const Color(0xFFF1F5F9),
                    iconColor: const Color(0xFF475569),
                    title: 'Suppliers',
                    subtitle: 'Contact directory and restock histories',
                    onTap: () {
                      if (onNavigateToTab != null) {
                        onNavigateToTab!(AppTab.suppliers);
                      } else {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const SupplierManagementScreen()));
                      }
                    },
                  ),
                  _menuItemCard(
                    context,
                    icon: Icons.inventory_2_outlined,
                    iconBg: const Color(0xFFFFEDD5),
                    iconColor: const Color(0xFFEA580C),
                    title: 'Categories, Bundles & Groups',
                    subtitle: 'Master categories, meal sets & variant families',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const CategoryBundleManagementScreen())),
                  ),
                  const SizedBox(height: 24),
                ],

                // 3. Administration & Finance
                if (isAdmin) ...[
                  _sectionHeader(
                    context,
                    title: 'Administration & Finance',
                    subtitle: 'Roles, permissions & reports',
                  ),
                  _menuItemCard(
                    context,
                    icon: Icons.manage_accounts_outlined,
                    iconBg: const Color(0xFFF3E8FF),
                    iconColor: GdcColors.violetAccent,
                    title: 'Staff & Roles',
                    subtitle: 'Manage staff accounts, PINs & permissions',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const UserManagementScreen())),
                  ),
                  _menuItemCard(
                    context,
                    icon: Icons.analytics_outlined,
                    iconBg: const Color(0xFFFCE7F3),
                    iconColor: Colors.purple.shade700,
                    title: 'Financial & Loss Reports',
                    subtitle:
                        'Sales, net profit, expenses & stock loss tracking',
                    onTap: () {
                      if (onNavigateToTab != null) {
                        onNavigateToTab!(AppTab.reports);
                      } else {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ReportsScreen()));
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                // 4. App Preferences & Tools
                _sectionTitle(context, 'App Preferences & Tools'),
                Card(
                  child: SwitchListTile(
                    title: const Text('Dark Mode',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text(
                        'Soothing dark palette for nighttime use',
                        style: TextStyle(fontSize: 12)),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: GdcColors.darkEmerald.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        context.watch<ThemeProvider>().isDarkMode
                            ? Icons.dark_mode
                            : Icons.light_mode,
                        color: GdcColors.darkEmerald,
                      ),
                    ),
                    value: context.watch<ThemeProvider>().isDarkMode,
                    onChanged: (v) =>
                        context.read<ThemeProvider>().toggleTheme(v),
                  ),
                ),
                const SizedBox(height: 16),
                const _AccountSecuritySection(),
                const SizedBox(height: 16),
                const _MyStaffAccountSection(),
                const SizedBox(height: 16),
                const _PrinterToolsSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItemCard(
    BuildContext context, {
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.5),
          size: 20,
        ),
        onTap: onTap,
      ),
    );
  }

  String _getRoleLabel(UserRole role) => switch (role) {
        UserRole.admin => 'Admin',
        UserRole.inventoryManager => 'Inv Manager',
        UserRole.cashier => 'Cashier',
        UserRole.none => 'Guest',
      };

  Color _getRoleColor(UserRole role, BuildContext context) {
    return switch (role) {
      UserRole.admin => GdcColors.violetAccent,
      UserRole.inventoryManager => Colors.blue.shade600,
      UserRole.cashier => GdcColors.emeraldPrimary,
      UserRole.none => Theme.of(context).disabledColor,
    };
  }
}

// ── Account Security (Google Authenticator 2FA) ─────────────────────────────

class _AccountSecuritySection extends StatefulWidget {
  const _AccountSecuritySection();

  @override
  State<_AccountSecuritySection> createState() =>
      _AccountSecuritySectionState();
}

class _AccountSecuritySectionState extends State<_AccountSecuritySection> {
  bool _isKeyVisible = false;

  Future<void> _launchAuthenticatorApp(
      BuildContext context, AppAuthProvider auth) async {
    if (!auth.isTotpLinked) {
      final uri = auth.totpUri;
      try {
        final launched =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          auth.markTotpLinked();
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Could not open Authenticator app. Please copy secret key manually.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Authenticator app not found. Please copy secret key or install Google Authenticator.')),
          );
        }
      }
    } else {
      final directUris = [
        Uri.parse('android-app://com.google.android.apps.authenticator2'),
        Uri.parse(
            'intent://#Intent;package=com.google.android.apps.authenticator2;end'),
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
          const SnackBar(
              content:
                  Text('Please open Google Authenticator on your device.')),
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
        content: Container(
          width: 440,
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Zero-typing setup: Tap below to automatically link your key to Google Authenticator:',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _launchAuthenticatorApp(context, auth),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('OPEN AUTHENTICATOR APP',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
              const Text('Manual Setup Option:',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 4),
              const Text('Account Name: GDC Admin',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        readableSecret,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            fontSize: 13,
                            letterSpacing: 1),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          size: 20, color: Colors.blue),
                      tooltip: 'Copy Key',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: auth.totpSecret));
                        auth.markTotpLinked();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Secret key copied to clipboard!')),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final readableSecret = TotpUtils.formatSecretReadable(auth.totpSecret);
    const maskedSecret = "•••• •••• •••• ••••";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Account Security (Google Authenticator 2FA)',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  value: auth.totpEnabled,
                  onChanged: (val) => auth.setTotpEnabled(val),
                  title: const Text('Require 6-Digit Code on Login',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    auth.totpEnabled
                        ? '6-digit Google Authenticator 2FA is currently active.'
                        : '6-digit Google Authenticator 2FA is turned off.',
                    style: TextStyle(
                        fontSize: 11,
                        color: auth.totpEnabled
                            ? Colors.green.shade700
                            : Colors.red.shade700),
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (auth.totpEnabled ? Colors.blue : Colors.grey)
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      auth.totpEnabled
                          ? Icons.security_rounded
                          : Icons.security_outlined,
                      color: auth.totpEnabled ? Colors.blue : Colors.grey,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Google Authenticator TOTP Key',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(
                            _isKeyVisible ? readableSecret : maskedSecret,
                            style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                                fontFamily: 'monospace',
                                letterSpacing: 0.8),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                          _isKeyVisible
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.blue,
                          size: 20),
                      tooltip: _isKeyVisible ? 'Mask Key' : 'Show Key',
                      onPressed: () =>
                          setState(() => _isKeyVisible = !_isKeyVisible),
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_2_rounded,
                          color: Colors.blue, size: 20),
                      tooltip: 'QR / Setup Instructions',
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
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('OPEN AUTHENTICATOR APP',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: () => _showSetupDialog(context, auth),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('SETUP KEY',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
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

// ── My Staff Account Section ────────────────────────────────────────────────

class _MyStaffAccountSection extends StatelessWidget {
  const _MyStaffAccountSection();

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => const _ChangePasswordDialog(),
    );
  }

  void _showChangePinDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => const _ChangePinDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final user = auth.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'My Staff Account',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
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
                  child: const Icon(Icons.account_circle_outlined,
                      color: Colors.blue),
                ),
                title: Text(
                  auth.userFullName != null && auth.userFullName!.isNotEmpty
                      ? auth.userFullName!
                      : (user?.displayName != null && user!.displayName!.isNotEmpty
                          ? user.displayName!
                          : (user?.email?.split('@').first ?? 'Staff Account')),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                    user?.email ?? 'Currently logged in staff account',
                    style: const TextStyle(fontSize: 11)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      color: Colors.orange),
                ),
                title: const Text('Change Password',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: const Text('Update your login password',
                    style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => _showChangePasswordDialog(context),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.pin_rounded,
                      color: Colors.purple),
                ),
                title: const Text('Change 4-Digit Security PIN',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: const Text('Update your 4-digit security PIN',
                    style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => _showChangePinDialog(context),
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
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
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
    final newPass = _newPassCtrl.text.trim();
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
            'wrong-password' ||
            'invalid-credential' =>
              'Current password is incorrect.',
            'weak-password' => 'New password is too weak.',
            'requires-recent-login' =>
              'Please log out and log in again to change password.',
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
    final auth = context.watch<AppAuthProvider>();
    final user = auth.currentUser;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text('Change Password',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: Container(
        width: 440,
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account: ${auth.userFullName ?? user?.displayName ?? 'Staff Account'} (${user?.email ?? ''})',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey),
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
                    icon: Icon(_obscureCurrent
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
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
                    icon: Icon(
                        _obscureNew ? Icons.visibility_off : Icons.visibility),
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
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
              : const Text('UPDATE PASSWORD'),
        ),
      ],
    );
  }
}

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _currentPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentPin = _currentPinCtrl.text.trim();
    final newPin = _newPinCtrl.text.trim();
    final confirmPin = _confirmPinCtrl.text.trim();

    final auth = context.read<AppAuthProvider>();
    final userPin = auth.userPin;

    if (userPin != null && userPin.isNotEmpty) {
      if (currentPin.isEmpty) {
        setState(() => _error = 'Please enter your current 4-digit PIN.');
        return;
      }
      if (currentPin != userPin) {
        final isStaticValid = await AuthService().verifyPin(currentPin);
        if (!isStaticValid) {
          setState(() => _error = 'Current 4-digit PIN is incorrect.');
          return;
        }
      }
    }

    if (newPin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(newPin)) {
      setState(() => _error = 'New PIN must be exactly 4 digits.');
      return;
    }

    if (newPin != confirmPin) {
      setState(() => _error = 'New 4-digit PINs do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await auth.updateUserPin(newPin);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('4-Digit Security PIN updated successfully! 🔑'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to update PIN: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final user = auth.currentUser;
    final hasExistingPin = auth.userPin != null && auth.userPin!.isNotEmpty;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.pin_rounded, color: Colors.purple),
          SizedBox(width: 8),
          Expanded(
            child: Text('Change 4-Digit Security PIN',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: Container(
        width: 440,
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account: ${auth.userFullName ?? user?.displayName ?? 'Staff Account'} (${user?.email ?? ''})',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Text(
                hasExistingPin
                    ? 'Enter your current 4-digit PIN and set a new 4-digit PIN.'
                    : 'Set up your new 4-digit PIN for authorization and verification.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              if (hasExistingPin) ...[
                TextField(
                  controller: _currentPinCtrl,
                  enabled: !_loading,
                  obscureText: _obscureCurrent,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Current 4-Digit PIN',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCurrent
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _newPinCtrl,
                enabled: !_loading,
                obscureText: _obscureNew,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'New 4-Digit Security PIN',
                  prefixIcon: const Icon(Icons.pin_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureNew ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPinCtrl,
                enabled: !_loading,
                obscureText: _obscureConfirm,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'Confirm New 4-Digit PIN',
                  prefixIcon: const Icon(Icons.check_circle_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
          ),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('SAVE PIN'),
        ),
      ],
    );
  }
}

// ── Bluetooth ESC/POS Printer Section ────────────────────────────────────────

class _PrinterToolsSection extends StatefulWidget {
  const _PrinterToolsSection();

  @override
  State<_PrinterToolsSection> createState() => _PrinterToolsSectionState();
}

class _PrinterToolsSectionState extends State<_PrinterToolsSection> {
  String _paperWidth = '58mm';
  bool _autoPrint = true;

  static void showPrinterDialog(
      BuildContext context, PrinterProvider printer) async {
    final devices = await printer.getDevices();

    if (context.mounted) {
      showDialog(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Bluetooth Thermal Printer'),
          content: Container(
            width: 440,
            constraints: const BoxConstraints(maxWidth: 440),
            child: devices.isEmpty
                ? const Text(
                    'No paired bluetooth devices found. Please pair your thermal printer in your device Bluetooth settings first.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (context, i) {
                      final d = devices[i];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth_rounded,
                            color: Colors.blue),
                        title: Text(d.name.isEmpty ? 'Unknown Device' : d.name),
                        subtitle: Text(d.macAdress),
                        trailing: printer.device?.macAdress == d.macAdress &&
                                printer.connected
                            ? Icon(Icons.check_circle,
                                color: Theme.of(context).semantic.success)
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
                child: Text('Disconnect',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
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
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Bluetooth ESC/POS Printer',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (printer.connected ? Colors.blue : Colors.grey)
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    printer.connected
                        ? Icons.bluetooth_connected_rounded
                        : Icons.bluetooth_disabled_rounded,
                    color: printer.connected ? Colors.blue : Colors.grey,
                  ),
                ),
                title: Text(
                  printer.connected
                      ? (printer.device?.name.isNotEmpty == true
                          ? printer.device!.name
                          : 'Thermal Printer')
                      : 'Bluetooth Thermal Printer',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                subtitle: Text(
                  printer.connected
                      ? 'Connected (${printer.device?.macAdress ?? ''})'
                      : 'Tap to connect paired thermal printer',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: printer.isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              (printer.connected ? Colors.green : Colors.grey)
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          printer.connected ? 'PAIRED' : 'DISCONNECTED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: printer.connected
                                ? Colors.green.shade700
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                onTap: () => showPrinterDialog(context, printer),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.aspect_ratio_rounded,
                    color: Colors.blueGrey),
                title: const Text('Paper Width Control',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('Selected width: $_paperWidth',
                    style: const TextStyle(fontSize: 11)),
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: '58mm',
                        label: Text('58mm',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold))),
                    ButtonSegment(
                        value: '80mm',
                        label: Text('80mm',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold))),
                  ],
                  selected: {_paperWidth},
                  onSelectionChanged: (val) =>
                      setState(() => _paperWidth = val.first),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                title: const Text('Auto-Print After Sale',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: const Text(
                    'Automatically print receipt upon checkout',
                    style: TextStyle(fontSize: 11)),
                secondary:
                    const Icon(Icons.print_outlined, color: Colors.blueGrey),
                value: _autoPrint,
                onChanged: (val) => setState(() => _autoPrint = val),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Icon(Icons.print_rounded,
                    color: printer.connected ? color : Colors.grey),
                title: const Text('Print Test Receipt',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(
                  printer.connected
                      ? 'Send sample test receipt to thermal printer'
                      : 'Connect a printer above to test',
                  style: const TextStyle(fontSize: 11),
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
                                content: Text(success
                                    ? "Test print sent! 🖨️"
                                    : "Test print failed."),
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
                              content: Text(success
                                  ? "Test print sent! 🖨️"
                                  : "Test print failed."),
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
