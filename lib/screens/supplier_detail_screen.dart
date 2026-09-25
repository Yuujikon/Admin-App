import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../models/supplier.dart';
import '../models/product.dart';
import '../models/restock_inquiry.dart';
import '../providers/inventory_provider.dart';
import '../providers/restock_provider.dart';
import '../services/notification_service.dart';
import '../config/theme.dart';
import '../utils/format.dart';
import '../widgets/status_badge.dart';
import '../widgets/supplier_sheet.dart';
import '../widgets/restock_inquiry_sheet.dart';

class SupplierDetailScreen extends StatefulWidget {
  final Supplier supplier;
  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    // Refresh supplier data in case it was edited
    final currentSupplier = inventory.suppliers.firstWhere(
      (s) => s.id == widget.supplier.id, 
      orElse: () => widget.supplier
    );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(currentSupplier.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Restock'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(supplier: currentSupplier),
          _RestockTab(supplier: currentSupplier),
          _HistoryTab(supplierId: currentSupplier.id),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final Supplier supplier;
  const _OverviewTab({required this.supplier});

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).semantic;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Header Card ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(supplier.name[0].toUpperCase(), 
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(height: 16),
              Text(supplier.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
              Text(supplier.category, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Contact Section ──────────────────────────────────────────────────
        Text('CONTACT INFORMATION', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        _infoTile(context, Icons.person_outline, 'Contact Person', supplier.contactName.isEmpty ? 'Not set' : supplier.contactName),
        _infoTile(context, Icons.phone_outlined, 'Phone', supplier.phone, trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _launchAction('tel:${supplier.phone}'),
              icon: Icon(Icons.call_rounded, color: semantic.success),
              tooltip: 'Call Supplier',
            ),
            IconButton(
              onPressed: () async {
                final msg = 'Hello ${supplier.name}, this is GDC Store regarding inventory restocking.';
                await NotificationService.showSmsNotificationPopUp(
                  title: '💬 SMS to ${supplier.name}',
                  body: msg,
                );
                _launchAction('sms:${supplier.phone}?body=${Uri.encodeComponent(msg)}');
              },
              icon: Icon(Icons.message_rounded, color: semantic.info),
              tooltip: 'Send SMS',
            ),
          ],
        )),
        _infoTile(context, Icons.email_outlined, 'Email', supplier.email, trailing: IconButton(
          onPressed: () => _launchAction('mailto:${supplier.email}'),
          icon: Icon(Icons.email_rounded, color: semantic.info),
        )),
        const SizedBox(height: 24),

        // ── Settings Section ─────────────────────────────────────────────────
        Text('SETTINGS', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: SwitchListTile(
            title: const Text('Auto-Notify Low Stock', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: const Text('Sends internal alert when items are low', style: TextStyle(fontSize: 12)),
            value: supplier.autoNotifyLowStock,
            onChanged: (v) {
              context.read<InventoryProvider>().saveSupplier(supplier.copyWith(autoNotifyLowStock: v));
            },
          ),
        ),
        const SizedBox(height: 32),

        ElevatedButton.icon(
          onPressed: () => _showEditSheet(context),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('EDIT SUPPLIER DETAILS'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Widget _infoTile(BuildContext context, IconData icon, String label, String value, {Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  void _launchAction(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SupplierSheet(supplier: supplier),
    );
  }
}

class _RestockTab extends StatefulWidget {
  final Supplier supplier;
  const _RestockTab({required this.supplier});

  @override
  State<_RestockTab> createState() => _RestockTabState();
}

class _RestockTabState extends State<_RestockTab> {
  final Set<String> _manualIds = {};

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final restockProvider = context.watch<RestockProvider>();

    final lowStockItems = inventory.products.where((p) => 
      p.status == ProductStatus.published && 
      p.totalStock <= p.lowStockThreshold &&
      p.supplierId == widget.supplier.id
    ).toList();

    final manualItems = inventory.products.where((p) => 
      _manualIds.contains(p.id)
    ).toList();

    // Combine and remove duplicates just in case
    final allToRestock = [...lowStockItems, ...manualItems].toSet().toList();

    final activeInquiries = restockProvider.inquiries.where((ri) => 
      ri.supplierId == widget.supplier.id && 
      (ri.status == RestockInquiryStatus.draft || 
       ri.status == RestockInquiryStatus.pending ||
       ri.status == RestockInquiryStatus.sent ||
       ri.status == RestockInquiryStatus.acknowledged ||
       ri.status == RestockInquiryStatus.partiallyFulfilled)
    ).toList();

    // Only show items that don't already have an active/draft/pending/sent inquiry in the active list
    final filteredToRestock = allToRestock.where((p) {
      return !activeInquiries.any((ri) => ri.items.any((rii) => rii.productId == p.id));
    }).toList();

    return RefreshIndicator(
      onRefresh: () => restockProvider.refresh(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (activeInquiries.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ACTIVE INQUIRIES', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1)),
                Text('${activeInquiries.length} pending', style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...activeInquiries.map((ri) => _InquiryCard(inquiry: ri)),
            const SizedBox(height: 24),
          ],

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ITEMS TO RESTOCK', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1)),
            TextButton.icon(
              onPressed: () => _showManualPicker(inventory.products.where((p) => p.supplierId == widget.supplier.id).toList()),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('ADD MANUALLY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filteredToRestock.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
                    SizedBox(height: 12),
                    Text('No items selected for restock.', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('All low-stock items are added to active inquiries above or are fully available.', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          )
        else ...[
          Container(
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: filteredToRestock.map((p) => ListTile(
                dense: true,
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Stock: ${p.totalStock} / Min: ${p.lowStockThreshold} ${p.unit}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatPeso(p.costPrice), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    if (_manualIds.contains(p.id))
                      IconButton(
                        onPressed: () => setState(() => _manualIds.remove(p.id)),
                        icon: const Icon(Icons.close_rounded, size: 16, color: Colors.red),
                      ),
                  ],
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final count = await restockProvider.generateInquiries(filteredToRestock, [widget.supplier], inventory.adminName);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generated $count restock inquiry.')));
                setState(() => _manualIds.clear());
              }
            },
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('GENERATE INQUIRY'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ],
    ),
  );
}

  void _showManualPicker(List<Product> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (ctx, sc) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select Products to Restock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: sc,
                    itemCount: products.length,
                    itemBuilder: (c, i) {
                      final p = products[i];
                      final bool isSelected = _manualIds.contains(p.id);
                      final bool isLowStock = p.stock <= p.lowStockThreshold;

                      return CheckboxListTile(
                        title: Text(p.name, style: TextStyle(fontWeight: isSelected || isLowStock ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text('Stock: ${p.stock} ${p.unit}'),
                        secondary: isLowStock ? const Icon(Icons.warning_amber_rounded, color: Colors.orange) : null,
                        value: isSelected || isLowStock,
                        onChanged: isLowStock ? null : (v) {
                          setModalState(() {
                            if (v == true) _manualIds.add(p.id);
                            else _manualIds.remove(p.id);
                          });
                          setState(() {});
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('DONE SELECTING'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final String supplierId;
  const _HistoryTab({required this.supplierId});

  @override
  Widget build(BuildContext context) {
    final restock = context.watch<RestockProvider>();
    final history = restock.inquiries.where((ri) => 
      ri.supplierId == supplierId &&
      (ri.status == RestockInquiryStatus.fulfilled || 
       ri.status == RestockInquiryStatus.cancelled)
    ).toList();

    if (history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 64, color: Colors.black12),
            SizedBox(height: 16),
            Text('No restock history for this supplier.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final ri = history[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(ri.inquiryNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Sent: ${DateFormat('MMM dd, yyyy').format(ri.sentAt ?? ri.createdAt)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => sendRestockEmail(context, ri, updateStatus: false),
                  icon: const Icon(Icons.email_outlined, color: Colors.blue, size: 20),
                  tooltip: 'Resend Email',
                ),
                _StatusBadge(status: ri.status),
              ],
            ),
            onTap: () => _showHistoryDetails(context, ri),
          ),
        );
      },
    );
  }

  void _showHistoryDetails(BuildContext context, RestockInquiry ri) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ri.inquiryNumber),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusBadge(status: ri.status),
                const SizedBox(height: 16),
                ...ri.items.map((i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ${i.productName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('  Requested: ${i.requestedQty} ${i.unit} (Current: ${i.currentStock})', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              sendRestockEmail(context, ri, updateStatus: false);
            },
            child: const Text('RESEND EMAIL'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
        ],
      ),
    );
  }
}

class _InquiryCard extends StatefulWidget {
  final RestockInquiry inquiry;
  const _InquiryCard({required this.inquiry});

  @override
  State<_InquiryCard> createState() => _InquiryCardState();
}

class _InquiryCardState extends State<_InquiryCard> {
  Timer? _timer;
  String _timeAgo = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _updateTime();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTime() {
    setState(() {
      _timeAgo = formatTimeAgo(widget.inquiry.sentAt ?? widget.inquiry.createdAt);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inquiry = widget.inquiry;
    final bool isSent = inquiry.status == RestockInquiryStatus.sent || 
                       inquiry.status == RestockInquiryStatus.acknowledged;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16), 
        side: BorderSide(color: isSent ? Colors.green.shade100 : Colors.blue.shade100)
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(inquiry.inquiryNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Row(
              children: [
                Text('${inquiry.items.length} items'),
                const SizedBox(width: 8),
                const Text('•', style: TextStyle(color: Colors.grey)),
                const SizedBox(width: 8),
                Text(_timeAgo, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
              ],
            ),
            trailing: _StatusBadge(status: inquiry.status),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                if (inquiry.status == RestockInquiryStatus.draft || inquiry.status == RestockInquiryStatus.pending)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => sendRestockEmail(context, inquiry),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('SEND INQUIRY'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                  )
                else ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.read<RestockProvider>().updateStatus(inquiry.id, RestockInquiryStatus.fulfilled),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                      label: const Text('FULFILLED'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.read<RestockProvider>().updateStatus(inquiry.id, RestockInquiryStatus.cancelled),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                if (inquiry.status == RestockInquiryStatus.draft) ...[
                  IconButton(
                    onPressed: () => _showEditSheet(context),
                    icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                  ),
                  const SizedBox(width: 8),
                ],
                if (inquiry.status == RestockInquiryStatus.sent || 
                    inquiry.status == RestockInquiryStatus.acknowledged ||
                    inquiry.status == RestockInquiryStatus.partiallyFulfilled)
                  IconButton(
                    onPressed: () {
                      sendRestockEmail(context, inquiry);
                      context.read<RestockProvider>().resendInquiry(inquiry);
                    },
                    icon: const Icon(Icons.email_outlined, color: Colors.blue),
                    tooltip: 'Resend Email',
                  ),
                IconButton(
                  onPressed: () => _confirmDelete(context, inquiry),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                ),
              ],
            ),
          ),
          if (isSent && widget.inquiry.sentAt != null)
            if (DateTime.now().difference(widget.inquiry.sentAt!).inHours >= 1)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('No response from supplier? Try resending or calling.', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => RestockInquirySheet(inquiry: widget.inquiry),
    );
  }

  void _confirmDelete(BuildContext context, RestockInquiry ri) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Inquiry?'),
        content: const Text('This will remove the tracking record. The items will become eligible for a new restock inquiry.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              context.read<RestockProvider>().deleteInquiry(ri.id);
              Navigator.pop(ctx);
            }, 
            child: const Text('DELETE', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }
}

void sendRestockEmail(BuildContext context, RestockInquiry inquiry, {bool updateStatus = true}) async {
  final buffer = StringBuffer('Dear ${inquiry.supplierName},\n\n');
  buffer.writeln('Good day! We would like to request a restock for the following items:\n');
  for (final item in inquiry.items) {
    buffer.writeln('• ${item.productName} (SKU: ${item.sku})');
    buffer.writeln('  Requested Quantity: ${item.requestedQty} ${item.unit}');
    buffer.writeln('');
  }
  buffer.writeln('\nReference Number: ${inquiry.inquiryNumber}');
  buffer.writeln('Please let us know the total amount and estimated delivery date. Thank you!\n\nBest regards,\nGDC Sari-Sari Store');

  final body = buffer.toString();
  final subject = 'Restock Request: ${inquiry.inquiryNumber}';
  final email = inquiry.supplierContact ?? '';

  // To target Gmail specifically on Android, we can use the 'intent' scheme.
  // This tells Android to open the Gmail package specifically.
  // If it fails (e.g. Gmail not installed), it falls back to standard mailto.
  final String gmailIntent = 'intent:#Intent;action=android.intent.action.SENDTO;dat=mailto:$email;sub=${Uri.encodeComponent(subject)};body=${Uri.encodeComponent(body)};package=com.google.android.gm;end';
  
  // Standard mailto as fallback
  final Uri mailtoUri = Uri(
    scheme: 'mailto',
    path: email,
    query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );

  try {
    bool launched = false;
    
    // 1. Try launching Gmail directly via Android Intent (Android only)
    if (Theme.of(context).platform == TargetPlatform.android) {
      final Uri intentUri = Uri.parse(gmailIntent);
      if (await canLaunchUrl(intentUri)) {
        launched = await launchUrl(intentUri);
      }
    }

    // 2. If Intent failed or not on Android, use standard mailto
    if (!launched) {
      if (await canLaunchUrl(mailtoUri)) {
        launched = await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      }
    }

    if (launched) {
      if (updateStatus && context.mounted) {
        context.read<RestockProvider>().sendInquiry(inquiry);
      }
    } else {
      // 3. Absolute Fallback: Copy to clipboard
      await Clipboard.setData(ClipboardData(text: body));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Gmail. Details copied to clipboard.'))
        );
      }
    }
  } catch (e) {
    debugPrint('Gmail Launch Error: $e');
    await Clipboard.setData(ClipboardData(text: body));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error opening email app.'))
      );
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final RestockInquiryStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color = switch (status) {
      RestockInquiryStatus.draft => Colors.grey,
      RestockInquiryStatus.pending => Colors.orange,
      RestockInquiryStatus.sent => Colors.blue,
      RestockInquiryStatus.acknowledged => Colors.cyan,
      RestockInquiryStatus.partiallyFulfilled => Colors.purple,
      RestockInquiryStatus.fulfilled => Colors.green,
      RestockInquiryStatus.cancelled => Colors.red,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(status.name.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
