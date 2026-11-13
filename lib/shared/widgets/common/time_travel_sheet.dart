import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../providers/inventory_provider.dart';
import '../../../providers/order_provider.dart';
import '../../services/time_service.dart';

/// Modal Bottom Sheet for Time Simulation & Fast-Forward Controls.
class TimeTravelSheet extends StatefulWidget {
  const TimeTravelSheet({super.key});

  /// Displays the modal time travel sheet.
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const TimeTravelSheet(),
    );
  }

  @override
  State<TimeTravelSheet> createState() => _TimeTravelSheetState();
}

class _TimeTravelSheetState extends State<TimeTravelSheet> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Update live clock every second
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _notifyProviders(BuildContext context) {
    // Notify key providers to re-evaluate time-dependent checks
    try {
      context.read<OrderProvider>().checkExpirationsNow();
      context.read<InventoryProvider>().notifyListeners();
      context.read<OrderProvider>().notifyListeners();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeService = context.watch<TimeService>();
    final simulatedNow = TimeService.now;
    final isSimulated = timeService.isSimulated;

    final dateFormatted =
        DateFormat('EEEE, MMM d, yyyy').format(simulatedNow);
    final timeFormatted = DateFormat('h:mm:ss a').format(simulatedNow);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Sheet Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSimulated
                      ? Colors.amber.shade100
                      : theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSimulated
                      ? Icons.more_time_rounded
                      : Icons.access_time_filled_rounded,
                  color: isSimulated
                      ? Colors.amber.shade900
                      : theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time Simulation & Fast-Forward',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Demonstrate batch expirations, store hours & timeouts',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Live Clock Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isSimulated
                  ? Colors.amber.shade50.withValues(alpha: 0.6)
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSimulated
                    ? Colors.amber.shade400
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: isSimulated ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSimulated
                            ? Colors.amber.shade800
                            : GdcColors.emeraldPrimary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isSimulated
                            ? 'FAST-FORWARDED (${timeService.formattedOffset})'
                            : 'LIVE REAL-WORLD TIME',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      dateFormatted,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  timeFormatted,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: isSimulated
                        ? Colors.amber.shade900
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Fast-Forward Presets Label
          Text(
            'FAST-FORWARD PRESETS',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),

          // Preset Chips Grid
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              _PresetChip(
                label: '+30 Minutes',
                subtitle: 'Order Timeout Test',
                icon: Icons.timer_outlined,
                onTap: () {
                  timeService.addMinutes(30);
                  _notifyProviders(context);
                },
              ),
              _PresetChip(
                label: '+1 Hour',
                subtitle: 'Short Shift Test',
                icon: Icons.hourglass_bottom_rounded,
                onTap: () {
                  timeService.addHours(1);
                  _notifyProviders(context);
                },
              ),
              _PresetChip(
                label: '+2 Hours',
                subtitle: 'Perishable Expiration Test',
                icon: Icons.warning_amber_rounded,
                highlight: true,
                onTap: () {
                  timeService.addHours(2);
                  _notifyProviders(context);
                },
              ),
              _PresetChip(
                label: '+6 Hours',
                subtitle: 'Shift End Test',
                icon: Icons.work_history_outlined,
                onTap: () {
                  timeService.addHours(6);
                  _notifyProviders(context);
                },
              ),
              _PresetChip(
                label: '+1 Day',
                subtitle: 'Next Day Store Hours Test',
                icon: Icons.today_rounded,
                highlight: true,
                onTap: () {
                  timeService.addDays(1);
                  _notifyProviders(context);
                },
              ),
              _PresetChip(
                label: '+3 Days',
                subtitle: 'Batch Lot Expiry',
                icon: Icons.date_range_rounded,
                onTap: () {
                  timeService.addDays(3);
                  _notifyProviders(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Action Buttons: Reset to Real-World Clock & Done
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isSimulated
                      ? () {
                          timeService.reset();
                          _notifyProviders(context);
                        }
                      : null,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Reset to Real-World Clock',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: GdcColors.emeraldPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Done',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool highlight;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.subtitle,
    required this.icon,
    this.highlight = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: highlight
          ? Colors.amber.shade100.withValues(alpha: 0.6)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highlight
              ? Colors.amber.shade400
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: highlight ? Colors.amber.shade900 : colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: highlight
                          ? Colors.amber.shade900
                          : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9,
                      color: highlight
                          ? Colors.amber.shade800
                          : colorScheme.onSurfaceVariant,
                    ),
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
