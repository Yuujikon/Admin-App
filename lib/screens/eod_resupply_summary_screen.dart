import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/daily_resupply_log.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../widgets/responsive_layout.dart';
import 'product_detail_screen.dart';

/// Dedicated viewer for the End-of-Day (Store-Closing) ≤ 30% Low-Stock Resupply
/// Summary, accessible from the More tab and from Inventory Alerts.
class EodResupplySummaryScreen extends StatefulWidget {
  final String? initialDateKey;

  const EodResupplySummaryScreen({
    super.key,
    this.initialDateKey,
  });

  @override
  State<EodResupplySummaryScreen> createState() =>
      _EodResupplySummaryScreenState();
}

class _EodResupplySummaryScreenState extends State<EodResupplySummaryScreen> {
  String? _selectedDateKey;
  bool _isSyncing = false;
  late Stream<List<DailyResupplyLog>> _historyStream;

  @override
  void initState() {
    super.initState();
    _selectedDateKey = widget.initialDateKey;
    final inv = context.read<InventoryProvider>();
    _historyStream = inv.dailyResupplyLogsHistoryStream(limit: 30);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<InventoryProvider>().refreshTodayResupplyLog();
    });
  }

  Future<void> _syncLiveStock() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await context.read<InventoryProvider>().refreshTodayResupplyLog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Synced live ≤ 30% low-stock inventory for today.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _sendTodaySummary(InventoryProvider inv, bool isSent) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await inv.sendDailyResupplySummaryEmailNow(
      forceResend: isSent,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.sent ? Colors.green.shade800 : Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDateChipLabel(String dateKey, String todayKey) {
    if (dateKey == todayKey) return 'Today';
    final parsed = DateTime.tryParse(dateKey);
    if (parsed == null) return dateKey;
    return DateFormat('MMM d').format(parsed);
  }

  String _formatFullDate(String dateKey) {
    final parsed = DateTime.tryParse(dateKey);
    if (parsed == null) return dateKey;
    return DateFormat('EEEE, MMM d, yyyy').format(parsed);
  }

  Product? _findLiveProduct(InventoryProvider inv, String productId) {
    for (final p in inv.products) {
      if (p.id == productId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final inv = context.watch<InventoryProvider>();
    final todayLog = inv.todayResupplyLog;
    final todayKey = todayLog.dateKey;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text(
          'End-of-Day Resupply Summary',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Sync live ≤ 30% stock',
            onPressed: _isSyncing ? null : _syncLiveStock,
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: StreamBuilder<List<DailyResupplyLog>>(
        stream: _historyStream,
        builder: (context, snapshot) {
          final history = snapshot.data ?? const <DailyResupplyLog>[];

          // Merge today's live log with historical Firestore logs (newest first).
          final Map<String, DailyResupplyLog> logsByDate = {
            todayKey: todayLog,
          };
          for (final log in history) {
            if (log.dateKey == todayKey) {
              logsByDate[todayKey] = todayLog;
            } else {
              logsByDate[log.dateKey] = log;
            }
          }
          final sortedDateKeys = logsByDate.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          final String activeDateKey = (_selectedDateKey != null &&
                  logsByDate.containsKey(_selectedDateKey))
              ? _selectedDateKey!
              : todayKey;
          final DailyResupplyLog activeLog = logsByDate[activeDateKey]!;
          final bool isToday = activeDateKey == todayKey;
          final items = activeLog.sortedItems;

          final int oosCount = items.where((i) => i.isOutOfStock).length;
          final int onlineOosCount =
              items.where((i) => i.onlineOutOfStock).length;
          final int totalSuggested = activeLog.totalSuggestedUnits;

          final bool isSending = isToday && inv.isSendingDailyResupplyEmail;
          final bool isSent = activeLog.summaryEmailSent;
          final bool isFailed =
              !isSent && activeLog.summaryEmailStatus == 'failed';
          final Color statusColor = isSent
              ? Colors.green.shade700
              : isFailed
                  ? cs.error
                  : Colors.teal.shade700;

          final String statusLabel;
          if (isSending) {
            statusLabel = 'Sending...';
          } else if (isSent) {
            final sentStr = activeLog.summaryEmailSentAt != null
                ? DateFormat('h:mm a').format(activeLog.summaryEmailSentAt!)
                : activeLog.dateKey;
            statusLabel = 'Emailed at $sentStr';
          } else if (isFailed) {
            statusLabel = 'Email Failed';
          } else if (items.isEmpty) {
            statusLabel = 'All Stock Healthy';
          } else if (isToday) {
            final closeTime = inv.settings.dailyCloseTime ?? '21:00';
            statusLabel = 'Queued for Close ($closeTime)';
          } else {
            statusLabel = 'Not Emailed';
          }

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).padding.bottom + 32,
              ),
              child: MaxWidthWrapper(
                maxWidth: 1000.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date Selector Strip (Today + Past EOD Logs)
                    if (sortedDateKeys.length > 1) ...[
                      Text(
                        'Resupply Log History',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: sortedDateKeys.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, index) {
                            final key = sortedDateKeys[index];
                            final log = logsByDate[key]!;
                            final selected = key == activeDateKey;
                            final count = log.itemCount;
                            final label =
                                '${_formatDateChipLabel(key, todayKey)}${count > 0 ? ' ($count)' : ''}';
                            return ChoiceChip(
                              selected: selected,
                              avatar: Icon(
                                log.summaryEmailSent
                                    ? Icons.mark_email_read_rounded
                                    : (count > 0
                                        ? Icons.warning_amber_rounded
                                        : Icons.check_circle_outline_rounded),
                                size: 15,
                                color: selected
                                    ? cs.onPrimaryContainer
                                    : (log.summaryEmailSent
                                        ? Colors.green.shade700
                                        : (count > 0
                                            ? Colors.amber.shade800
                                            : cs.outline)),
                              ),
                              label: Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onSelected: (_) =>
                                  setState(() => _selectedDateKey = key),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Status & Email Dispatch Header Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isSent
                                      ? Icons.mark_email_read_rounded
                                      : Icons.summarize_rounded,
                                  color: statusColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatFullDate(activeLog.dateKey),
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Recipient: ${activeLog.storeEmail}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tracks all products whose 100% physical store stock reached ≤ 30% of original stock. The 75% online cap and 25% walk-in POS reserve remain unaffected.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                          if (isFailed &&
                              activeLog.summaryEmailError != null &&
                              activeLog.summaryEmailError!
                                  .trim()
                                  .isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.errorContainer.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Error: ${activeLog.summaryEmailError}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          if (isToday && items.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                alignment: WrapAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed:
                                        _isSyncing ? null : _syncLiveStock,
                                    icon: const Icon(Icons.sync_rounded,
                                        size: 16),
                                    label: const Text('Sync Live Stock'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: isSending
                                        ? null
                                        : () => _sendTodaySummary(inv, isSent),
                                    icon: isSending
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.send_rounded,
                                            size: 16),
                                    label: Text(
                                      isSent
                                          ? 'Resend Summary to Gmail'
                                          : 'Send Summary to Gmail',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // KPI Summary Strip
                    Row(
                      children: [
                        Expanded(
                          child: _KpiTile(
                            label: 'Items ≤ 30%',
                            value: '${items.length}',
                            sublabel: '$oosCount physical OOS',
                            color: items.isEmpty
                                ? GdcColors.darkEmerald
                                : Colors.amber.shade800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiTile(
                            label: 'Online OOS',
                            value: '$onlineOosCount',
                            sublabel: '25% reserve active',
                            color: onlineOosCount > 0 ? cs.error : cs.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiTile(
                            label: 'Suggested Restock',
                            value: '+$totalSuggested',
                            sublabel: 'total units',
                            color: Colors.teal.shade700,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Products List Header
                    Row(
                      children: [
                        Text(
                          'Low-Stock Products (${items.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        if (items.isNotEmpty)
                          Text(
                            'Tap an item to inspect',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (items.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 36,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 44,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'All Inventory Healthy',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'No products reached ≤ 30% of their original physical stock on ${activeLog.dateKey}.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final item = items[index];
                          final liveProduct =
                              _findLiveProduct(inv, item.productId);
                          return _ResupplyProductCard(
                            item: item,
                            onTap: liveProduct == null
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ProductDetailScreen(
                                          product: liveProduct,
                                        ),
                                      ),
                                    ),
                          );
                        },
                      ),

                    // Email Audit Metadata Footer
                    if (activeLog.summaryEmailSent ||
                        activeLog.summaryEmailSentBy != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Email Dispatch Audit',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Status: ${activeLog.summaryEmailSent ? 'Sent' : (activeLog.summaryEmailStatus ?? 'Pending')}'
                              '${activeLog.summaryEmailSentAt != null ? ' • ${DateFormat('MMM d, yyyy • h:mm a').format(activeLog.summaryEmailSentAt!)}' : ''}'
                              '${activeLog.summaryEmailSentBy != null ? '\nDispatched by: ${activeLog.summaryEmailSentBy}' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String sublabel;
  final Color color;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            sublabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResupplyProductCard extends StatelessWidget {
  final DailyResupplyItem item;
  final VoidCallback? onTap;

  const _ResupplyProductCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bool isOos = item.isOutOfStock;
    final Color accent = isOos ? cs.error : Colors.amber.shade800;
    final int orig = item.effectiveOriginalStock;
    final String hitTime = DateFormat('h:mm a').format(item.firstTriggeredAt);

    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOos
                          ? Icons.error_outline_rounded
                          : Icons.warning_amber_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.category} • Hit 30% at $hitTime',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isOos ? 'OUT OF STOCK' : '≤ 30% LOW STOCK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: 'Physical (POS)',
                    value: '${item.availableStock} / $orig ${item.unit}',
                    color: accent,
                  ),
                  _MetricChip(
                    label: '30% Alert',
                    value: '≤ ${item.lowStockThreshold} ${item.unit}',
                    color: cs.onSurfaceVariant,
                  ),
                  _MetricChip(
                    label: 'Online (75% cap)',
                    value: item.onlineOutOfStock
                        ? 'Out of Stock'
                        : '${item.onlineStock} ${item.unit}',
                    color: item.onlineOutOfStock ? cs.error : cs.primary,
                  ),
                  _MetricChip(
                    label: 'Suggested Restock',
                    value: '+${item.suggestedResupplyQty} ${item.unit}',
                    color: Colors.teal.shade700,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
