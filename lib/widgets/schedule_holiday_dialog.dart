import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/store_settings.dart';
import '../providers/inventory_provider.dart';
import '../shared/services/time_service.dart';

/// Unified, reactive dialog for managing regular operating hours, weekly closed
/// days, instant store open/close (emergency stop), and scheduled holiday or
/// maintenance overrides.
class ScheduleHolidayDialog extends StatefulWidget {
  const ScheduleHolidayDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const ScheduleHolidayDialog(),
    );
  }

  @override
  State<ScheduleHolidayDialog> createState() => _ScheduleHolidayDialogState();
}

class _ScheduleHolidayDialogState extends State<ScheduleHolidayDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _reasonCtrl = TextEditingController();

  bool _isSaving = false;

  // Add / Edit override form state
  ScheduleOverride? _editingOverride;
  DateTimeRange? _selectedDateRange;
  OverrideType _selectedType = OverrideType.fullClosure;
  TimeOfDay _customStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _customEnd = const TimeOfDay(hour: 15, minute: 0);

  static const List<({int weekday, String short, String full})> _weekdays = [
    (weekday: DateTime.monday, short: 'Mon', full: 'Monday'),
    (weekday: DateTime.tuesday, short: 'Tue', full: 'Tuesday'),
    (weekday: DateTime.wednesday, short: 'Wed', full: 'Wednesday'),
    (weekday: DateTime.thursday, short: 'Thu', full: 'Thursday'),
    (weekday: DateTime.friday, short: 'Fri', full: 'Friday'),
    (weekday: DateTime.saturday, short: 'Sat', full: 'Saturday'),
    (weekday: DateTime.sunday, short: 'Sun', full: 'Sunday'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ── Formatting & Parsing Helpers ───────────────────────────────────────────

  static TimeOfDay _parseTimeOfDay(String? timeStr, TimeOfDay fallback) {
    if (timeStr == null || !timeStr.contains(':')) return fallback;
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return fallback;
    }
  }

  static String _formatTime24(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _formatTimeDisplay(TimeOfDay time) {
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final h12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final mStr = time.minute.toString().padLeft(2, '0');
    return '$h12:$mStr $period';
  }

  static int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  static String _formatDurationSummary(TimeOfDay open, TimeOfDay close) {
    final openMins = _toMinutes(open);
    final closeMins = _toMinutes(close);
    if (openMins == closeMins) return '24 hrs / day';
    final int diff = closeMins > openMins
        ? closeMins - openMins
        : (1440 - openMins) + closeMins;
    final hrs = diff ~/ 60;
    final mins = diff % 60;
    final overnight = closeMins < openMins ? ' (Overnight)' : '';
    if (mins == 0) return '$hrs hr${hrs == 1 ? '' : 's'} / day$overnight';
    return '${hrs}h ${mins}m / day$overnight';
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await task();
    } catch (e) {
      _showSnack('Failed to save changes: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Immediate Open / Close Actions ─────────────────────────────────────────

  Future<void> _reopenFromEmergency(InventoryProvider inventory) async {
    await _runBusy(() async {
      await inventory.toggleStoreStatus(
        false,
        message: null,
        closeAt: null,
        openAt: null,
      );
      _showSnack('Store close stopped — store is now OPEN.');
    });
  }

  Future<void> _showCloseNowDialog(
    InventoryProvider inventory, {
    bool editingExistingNotice = false,
  }) async {
    final msgCtrl = TextEditingController(
      text: inventory.settings.closureMessage ?? '',
    );
    final quickReasons = [
      'Emergency Maintenance',
      'Temporarily Closed — Back Soon',
      'Quick Errand',
      'Restocking Inventory',
      'Power / Internet Outage',
    ];

    final confirmed = await showDialog<String>(
      context: context,
      builder: (dlgCtx) {
        final errColor = Theme.of(dlgCtx).colorScheme.error;
        return StatefulBuilder(
          builder: (dlgCtx, setLocalState) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(
                  editingExistingNotice
                      ? Icons.edit_note_rounded
                      : Icons.power_settings_new_rounded,
                  color: errColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    editingExistingNotice
                        ? 'Update Closure Notice'
                        : 'Close Store Now',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    editingExistingNotice
                        ? 'Update the message customers see while the store is closed.'
                        : 'This immediately closes the store and shows your notice to customers until you tap "Stop Store Close".',
                    style: Theme.of(dlgCtx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: quickReasons.map((reason) {
                      return ActionChip(
                        label:
                            Text(reason, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setLocalState(() => msgCtrl.text = reason);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: msgCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Closure Notice for Customers',
                      hintText: 'e.g. Temporarily closed — will be back soon',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: errColor,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(
                  editingExistingNotice
                      ? Icons.check_rounded
                      : Icons.block_rounded,
                  size: 18,
                ),
                label: Text(
                  editingExistingNotice ? 'Save Notice' : 'Close Store Now',
                ),
                onPressed: () {
                  final text = msgCtrl.text.trim().isNotEmpty
                      ? msgCtrl.text.trim()
                      : 'Temporarily closed — will be back soon';
                  Navigator.pop(dlgCtx, text);
                },
              ),
            ],
          ),
        );
      },
    );

    msgCtrl.dispose();
    if (confirmed == null) return;

    await _runBusy(() async {
      await inventory.toggleStoreStatus(true, message: confirmed);
      _showSnack(
        editingExistingNotice
            ? 'Closure notice updated.'
            : 'Store closed immediately. Tap "Stop Store Close" anytime to reopen.',
      );
    });
  }

  Future<void> _stopActiveOverride(
    InventoryProvider inventory,
    ScheduleOverride override,
    DateTime now,
  ) async {
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final extendsPastToday = override.normalizedEnd.isAfter(todayEnd);

    final choice = await showDialog<String>(
      context: context,
      builder: (dlgCtx) {
        final succColor = Colors.green.shade700;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.lock_open_rounded, color: succColor, size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Stop Active Closure',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Currently active: ${override.reason.isNotEmpty ? override.reason : override.typeLabel}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${override.formatDateRange()} • ${override.formatTimeRange()}',
                style: Theme.of(dlgCtx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                extendsPastToday
                    ? 'You can remove this entire schedule, or reopen just for today and keep the remaining days scheduled.'
                    : 'Removing this schedule will reopen the store immediately.',
                style: Theme.of(dlgCtx).textTheme.bodyMedium,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            if (extendsPastToday)
              OutlinedButton(
                onPressed: () => Navigator.pop(dlgCtx, 'today_only'),
                child: const Text('Reopen Today Only'),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: succColor,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(
                extendsPastToday ? 'Remove Entire Schedule' : 'Stop & Reopen',
              ),
              onPressed: () => Navigator.pop(dlgCtx, 'remove_all'),
            ),
          ],
        );
      },
    );

    if (choice == null) return;

    await _runBusy(() async {
      final settings = inventory.settings;
      final updated = List<ScheduleOverride>.from(settings.overrides);
      if (choice == 'today_only') {
        final tomorrow =
            DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        final idx = updated.indexWhere((o) => o.id == override.id);
        if (idx != -1) {
          updated[idx] = updated[idx].copyWith(startDate: tomorrow);
        }
        await inventory
            .saveStoreSettings(settings.copyWith(overrides: updated));
        _showSnack('Reopened for today! Schedule resumes tomorrow.');
      } else {
        updated.removeWhere((o) => o.id == override.id);
        await inventory
            .saveStoreSettings(settings.copyWith(overrides: updated));
        if (_editingOverride?.id == override.id) {
          _resetOverrideForm();
        }
        _showSnack('Schedule stopped — store reopened.');
      }
    });
  }

  Future<void> _deleteOverride(
    InventoryProvider inventory,
    ScheduleOverride override,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove Scheduled Override?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Remove "${override.reason.isNotEmpty ? override.reason : override.typeLabel}" '
          '(${override.formatDateRange()})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dlgCtx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _runBusy(() async {
      final settings = inventory.settings;
      final updated =
          settings.overrides.where((o) => o.id != override.id).toList();
      await inventory.saveStoreSettings(settings.copyWith(overrides: updated));
      if (_editingOverride?.id == override.id) {
        _resetOverrideForm();
      }
      _showSnack('Scheduled override removed.');
    });
  }

  Future<void> _clearExpiredOverrides(
    InventoryProvider inventory,
    DateTime now,
  ) async {
    await _runBusy(() async {
      final settings = inventory.settings;
      final remaining =
          settings.overrides.where((o) => !o.isPastAt(now)).toList();
      final removedCount = settings.overrides.length - remaining.length;
      if (removedCount == 0) return;
      await inventory
          .saveStoreSettings(settings.copyWith(overrides: remaining));
      _showSnack(
        'Cleared $removedCount expired schedule${removedCount == 1 ? '' : 's'}.',
      );
    });
  }

  Future<void> _pauseOperatingHours(InventoryProvider inventory) async {
    await _runBusy(() async {
      await inventory.saveStoreSettings(
        inventory.settings.copyWith(operatingHoursEnabled: false),
      );
      _showSnack('Regular operating hours paused — store is now OPEN.');
    });
  }

  // ── Override Form Helpers ──────────────────────────────────────────────────

  void _startEditingOverride(ScheduleOverride override) {
    setState(() {
      _editingOverride = override;
      _selectedDateRange = DateTimeRange(
        start: DateTime(
          override.startDate.year,
          override.startDate.month,
          override.startDate.day,
        ),
        end: DateTime(
          override.endDate.year,
          override.endDate.month,
          override.endDate.day,
        ),
      );
      _selectedType = override.type;
      if (override.startMinutes != null) {
        _customStart = TimeOfDay(
          hour: override.startMinutes! ~/ 60,
          minute: override.startMinutes! % 60,
        );
      }
      if (override.endMinutes != null) {
        _customEnd = TimeOfDay(
          hour: override.endMinutes! ~/ 60,
          minute: override.endMinutes! % 60,
        );
      }
      _reasonCtrl.text = override.reason;
    });
    _tabController.animateTo(2);
  }

  void _resetOverrideForm() {
    setState(() {
      _editingOverride = null;
      _selectedDateRange = null;
      _selectedType = OverrideType.fullClosure;
      _customStart = const TimeOfDay(hour: 9, minute: 0);
      _customEnd = const TimeOfDay(hour: 15, minute: 0);
      _reasonCtrl.clear();
    });
  }

  Future<void> _saveOverride(InventoryProvider inventory) async {
    if (_selectedDateRange == null) {
      _showSnack('Please select a date or date range first.', isError: true);
      return;
    }

    if (_selectedType != OverrideType.fullClosure &&
        _toMinutes(_customEnd) <= _toMinutes(_customStart)) {
      _showSnack('End time must be after start time.', isError: true);
      return;
    }

    final startDay = DateTime(
      _selectedDateRange!.start.year,
      _selectedDateRange!.start.month,
      _selectedDateRange!.start.day,
    );
    final endDay = DateTime(
      _selectedDateRange!.end.year,
      _selectedDateRange!.end.month,
      _selectedDateRange!.end.day,
      23,
      59,
      59,
    );

    final defaultReason = switch (_selectedType) {
      OverrideType.fullClosure => 'Closed All Day',
      OverrideType.maintenanceWindow => 'Scheduled Maintenance',
      OverrideType.customOpenHours => 'Special Operating Hours',
    };

    final override = ScheduleOverride(
      id: _editingOverride?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      startDate: startDay,
      endDate: endDay,
      type: _selectedType,
      startMinutes: _selectedType == OverrideType.fullClosure
          ? null
          : _toMinutes(_customStart),
      endMinutes: _selectedType == OverrideType.fullClosure
          ? null
          : _toMinutes(_customEnd),
      reason: _reasonCtrl.text.trim().isEmpty
          ? defaultReason
          : _reasonCtrl.text.trim(),
    );

    final wasEditing = _editingOverride != null;
    await _runBusy(() async {
      final settings = inventory.settings;
      final updatedList = List<ScheduleOverride>.from(settings.overrides);
      if (wasEditing) {
        final idx = updatedList.indexWhere((o) => o.id == override.id);
        if (idx != -1) {
          updatedList[idx] = override;
        } else {
          updatedList.add(override);
        }
      } else {
        updatedList.add(override);
      }

      await inventory.saveStoreSettings(
        settings.copyWith(overrides: updatedList),
      );

      _resetOverrideForm();
      _tabController.animateTo(1);

      final String snackMsg = wasEditing
          ? 'Schedule override updated.'
          : switch (override.type) {
              OverrideType.fullClosure => 'Store closure scheduled.',
              OverrideType.customOpenHours => 'Custom open hours saved.',
              OverrideType.maintenanceWindow => 'Maintenance window scheduled.',
            };
      _showSnack(snackMsg);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.width < 520;

    return ListenableBuilder(
      listenable: TimeService.instance,
      builder: (context, _) => Consumer<InventoryProvider>(
        builder: (context, inventory, _) {
          final now = TimeService.now;
          final settings = inventory.settings;
          final activeAndUpcomingCount =
              settings.overrides.where((o) => !o.isPastAt(now)).length;

          return Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 24,
              vertical: isCompact ? 16 : 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: screenSize.height * 0.88,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTopBar(context, settings, now),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: _buildLiveStatusBanner(
                      context,
                      inventory,
                      settings,
                      now,
                      isCompact,
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12.5,
                    ),
                    tabs: [
                      const Tab(
                        icon: Icon(Icons.schedule_rounded, size: 18),
                        text: 'Regular Hours',
                      ),
                      Tab(
                        icon: Badge(
                          isLabelVisible: activeAndUpcomingCount > 0,
                          label: Text('$activeAndUpcomingCount'),
                          child: const Icon(Icons.event_note_rounded, size: 18),
                        ),
                        text: 'Scheduled',
                      ),
                      Tab(
                        icon: Icon(
                          _editingOverride != null
                              ? Icons.edit_calendar_rounded
                              : Icons.add_circle_outline_rounded,
                          size: 18,
                        ),
                        text: _editingOverride != null
                            ? 'Edit Schedule'
                            : 'Add Override',
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  if (_isSaving) const LinearProgressIndicator(minHeight: 2),
                  Flexible(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRegularHoursTab(context, inventory, settings),
                        _buildScheduledOverridesTab(
                            context, inventory, settings, now),
                        _buildAddEditOverrideTab(
                            context, inventory, settings, now, isCompact),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    StoreSettings settings,
    DateTime now,
  ) {
    final cs = Theme.of(context).colorScheme;
    final label = settings.statusLabelAt(now);
    final (badgeColor, badgeIcon) = _statusStyle(context, label);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(Icons.calendar_month_rounded, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Schedule & Holiday Hours',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 12, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        DateFormat('EEE, MMM d • h:mm a').format(now),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (TimeService.instance.isSimulated) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'SIM ${TimeService.instance.formattedOffset}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon, size: 13, color: badgeColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusBanner(
    BuildContext context,
    InventoryProvider inventory,
    StoreSettings settings,
    DateTime now,
    bool isCompact,
  ) {
    final cs = Theme.of(context).colorScheme;
    final errColor = cs.error;
    final succColor = Colors.green.shade700;
    final warnColor = Colors.orange.shade800;

    final isClosed = settings.isEffectivelyClosedAt(now);
    final closingOverride = settings.activeClosingOverrideAt(now);
    final scheduledOutageActive = settings.isScheduledOutageActiveAt(now);
    final reason = settings.closureReasonAt(now);

    final Color accentColor;
    final IconData statusIcon;
    final String headline;

    if (settings.isClosed) {
      accentColor = errColor;
      statusIcon = Icons.lock_rounded;
      headline = 'Store is CLOSED (Manual / Emergency)';
    } else if (closingOverride != null) {
      accentColor = closingOverride.type == OverrideType.fullClosure
          ? errColor
          : warnColor;
      statusIcon = closingOverride.type == OverrideType.fullClosure
          ? Icons.event_busy_rounded
          : Icons.build_circle_rounded;
      headline = 'Store is CLOSED (${closingOverride.typeLabel})';
    } else if (scheduledOutageActive) {
      accentColor = warnColor;
      statusIcon = Icons.schedule_rounded;
      headline = 'Store is CLOSED (Scheduled Outage)';
    } else if (isClosed) {
      accentColor = warnColor;
      statusIcon = Icons.access_time_filled_rounded;
      headline = 'Store is CLOSED (Outside Regular Hours)';
    } else {
      accentColor = succColor;
      statusIcon = Icons.storefront_rounded;
      headline = 'Store is OPEN';
    }

    // Build contextual quick-action buttons
    final List<Widget> actionWidgets = [];
    if (settings.isClosed) {
      actionWidgets.add(
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: succColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.lock_open_rounded, size: 17),
          label: const Text(
            'Stop Store Close',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          onPressed: _isSaving ? null : () => _reopenFromEmergency(inventory),
        ),
      );
      actionWidgets.add(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('Edit Notice', style: TextStyle(fontSize: 12)),
          onPressed: _isSaving
              ? null
              : () => _showCloseNowDialog(
                    inventory,
                    editingExistingNotice: true,
                  ),
        ),
      );
    } else if (closingOverride != null) {
      actionWidgets.add(
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: succColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.lock_open_rounded, size: 17),
          label: const Text(
            'Stop Closure & Reopen',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          onPressed: _isSaving
              ? null
              : () => _stopActiveOverride(inventory, closingOverride, now),
        ),
      );
    } else if (scheduledOutageActive) {
      actionWidgets.add(
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: succColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.lock_open_rounded, size: 17),
          label: const Text(
            'Stop Scheduled Close',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          onPressed: _isSaving
              ? null
              : () => _runBusy(() async {
                    await inventory.clearExpiredSchedule();
                    _showSnack('Scheduled closure stopped — store reopened.');
                  }),
        ),
      );
    } else if (isClosed) {
      actionWidgets.add(
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: succColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text(
            'Reopen Now (Pause Hours)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          onPressed: _isSaving ? null : () => _pauseOperatingHours(inventory),
        ),
      );
    } else {
      actionWidgets.add(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: errColor,
            side: BorderSide(color: errColor.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.power_settings_new_rounded, size: 17),
          label: const Text(
            'Close Store Now',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          onPressed: _isSaving ? null : () => _showCloseNowDialog(inventory),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isCompact && actionWidgets.length == 1) ...[
                const SizedBox(width: 12),
                actionWidgets.first,
              ],
            ],
          ),
          if (isCompact || actionWidgets.length > 1) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actionWidgets,
            ),
          ],
        ],
      ),
    );
  }

  // ── TAB 1: Regular Operating Hours & Weekly Closed Days ────────────────────

  Widget _buildRegularHoursTab(
    BuildContext context,
    InventoryProvider inventory,
    StoreSettings settings,
  ) {
    final cs = Theme.of(context).colorScheme;
    final openTime = _parseTimeOfDay(
        settings.dailyOpenTime, const TimeOfDay(hour: 8, minute: 0));
    final closeTime = _parseTimeOfDay(
        settings.dailyCloseTime, const TimeOfDay(hour: 21, minute: 0));

    final presets = <({String label, TimeOfDay open, TimeOfDay close})>[
      (
        label: '6 AM – 9 PM',
        open: const TimeOfDay(hour: 6, minute: 0),
        close: const TimeOfDay(hour: 21, minute: 0),
      ),
      (
        label: '7 AM – 10 PM',
        open: const TimeOfDay(hour: 7, minute: 0),
        close: const TimeOfDay(hour: 22, minute: 0),
      ),
      (
        label: '8 AM – 9 PM',
        open: const TimeOfDay(hour: 8, minute: 0),
        close: const TimeOfDay(hour: 21, minute: 0),
      ),
      (
        label: '8 AM – 8 PM',
        open: const TimeOfDay(hour: 8, minute: 0),
        close: const TimeOfDay(hour: 20, minute: 0),
      ),
    ];

    final closedDayNames = _weekdays
        .where((w) => settings.closedDaysOfWeek.contains(w.weekday))
        .map((w) => w.short)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              secondary: Icon(
                settings.operatingHoursEnabled
                    ? Icons.schedule_rounded
                    : Icons.all_inclusive_rounded,
                color: settings.operatingHoursEnabled
                    ? cs.primary
                    : cs.onSurfaceVariant,
              ),
              title: const Text(
                'Enforce Daily Operating Hours',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Text(
                settings.operatingHoursEnabled
                    ? 'Store automatically closes outside opening/closing hours and on closed days.'
                    : 'Paused — store stays open unless closed manually or by a holiday override.',
                style: const TextStyle(fontSize: 12),
              ),
              value: settings.operatingHoursEnabled,
              onChanged: _isSaving
                  ? null
                  : (enabled) => _runBusy(() async {
                        await inventory.saveStoreSettings(
                          settings.copyWith(operatingHoursEnabled: enabled),
                        );
                        _showSnack(
                          enabled
                              ? 'Daily operating hours enabled.'
                              : 'Daily operating hours paused.',
                        );
                      }),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Daily Opening & Closing Times',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatDurationSummary(openTime, closeTime),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TimePickerCard(
                  label: 'Opening Time',
                  value: _formatTimeDisplay(openTime),
                  icon: Icons.wb_sunny_outlined,
                  enabled: !_isSaving,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: openTime,
                    );
                    if (picked != null && mounted) {
                      await _runBusy(() async {
                        await inventory.saveStoreSettings(
                          settings.copyWith(
                            operatingHoursEnabled: true,
                            dailyOpenTime: _formatTime24(picked),
                            dailyCloseTime: _formatTime24(closeTime),
                          ),
                        );
                        _showSnack(
                          'Opening time set to ${_formatTimeDisplay(picked)}.',
                        );
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimePickerCard(
                  label: 'Closing Time',
                  value: _formatTimeDisplay(closeTime),
                  icon: Icons.nights_stay_outlined,
                  enabled: !_isSaving,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: closeTime,
                    );
                    if (picked != null && mounted) {
                      await _runBusy(() async {
                        await inventory.saveStoreSettings(
                          settings.copyWith(
                            operatingHoursEnabled: true,
                            dailyOpenTime: _formatTime24(openTime),
                            dailyCloseTime: _formatTime24(picked),
                          ),
                        );
                        _showSnack(
                          'Closing time set to ${_formatTimeDisplay(picked)}.',
                        );
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: presets.map((preset) {
              final isSelected = settings.operatingHoursEnabled &&
                  openTime == preset.open &&
                  closeTime == preset.close;
              return ChoiceChip(
                label:
                    Text(preset.label, style: const TextStyle(fontSize: 11.5)),
                selected: isSelected,
                visualDensity: VisualDensity.compact,
                onSelected: _isSaving
                    ? null
                    : (_) => _runBusy(() async {
                          await inventory.saveStoreSettings(
                            settings.copyWith(
                              operatingHoursEnabled: true,
                              dailyOpenTime: _formatTime24(preset.open),
                              dailyCloseTime: _formatTime24(preset.close),
                            ),
                          );
                          _showSnack('Hours updated to ${preset.label}.');
                        }),
              );
            }).toList(),
          ),
          const Divider(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Weekly Closed Days',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              Text(
                closedDayNames.isEmpty
                    ? 'Open all 7 days'
                    : 'Closed: ${closedDayNames.join(', ')}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color:
                      closedDayNames.isEmpty ? Colors.green.shade700 : cs.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap any day to mark the store regularly closed every week.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _weekdays.map((day) {
              final isClosedDay =
                  settings.closedDaysOfWeek.contains(day.weekday);
              return FilterChip(
                label: Text(
                  day.short,
                  style: TextStyle(
                    fontWeight: isClosedDay ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                selected: isClosedDay,
                selectedColor: cs.errorContainer,
                checkmarkColor: cs.error,
                onSelected: _isSaving
                    ? null
                    : (selected) => _runBusy(() async {
                          final updatedDays =
                              List<int>.from(settings.closedDaysOfWeek);
                          if (selected) {
                            if (!updatedDays.contains(day.weekday)) {
                              updatedDays.add(day.weekday);
                            }
                          } else {
                            updatedDays.remove(day.weekday);
                          }
                          updatedDays.sort();
                          await inventory.saveStoreSettings(
                            settings.copyWith(closedDaysOfWeek: updatedDays),
                          );
                        }),
              );
            }).toList(),
          ),
          if (!settings.operatingHoursEnabled &&
              settings.closedDaysOfWeek.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Enable "Enforce Daily Operating Hours" above for weekly closed days to take effect.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── TAB 2: Active, Upcoming & Past Scheduled Overrides ─────────────────────

  Widget _buildScheduledOverridesTab(
    BuildContext context,
    InventoryProvider inventory,
    StoreSettings settings,
    DateTime now,
  ) {
    final cs = Theme.of(context).colorScheme;

    final activeList = settings.overrides
        .where((o) => o.isActiveAt(now))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final upcomingList = settings.overrides
        .where((o) => o.isUpcomingAt(now))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final pastList = settings.overrides.where((o) => o.isPastAt(now)).toList()
      ..sort((a, b) => b.endDate.compareTo(a.endDate));

    if (settings.overrides.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.event_available_rounded,
                    size: 36, color: cs.primary),
              ),
              const SizedBox(height: 14),
              const Text(
                'No Scheduled Holidays or Overrides',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Plan holiday closures, special custom open hours, or maintenance windows ahead of time. You can stop or edit them here anytime.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _tabController.animateTo(2),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Holiday / Custom Schedule'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (activeList.isNotEmpty) ...[
            _SectionHeader(
              title: 'Active Today',
              count: activeList.length,
              color: cs.error,
            ),
            const SizedBox(height: 8),
            ...activeList.map((o) => _buildOverrideCard(
                  context,
                  inventory,
                  o,
                  now,
                  status: _OverrideStatus.active,
                )),
            const SizedBox(height: 16),
          ],
          if (upcomingList.isNotEmpty) ...[
            _SectionHeader(
              title: 'Upcoming',
              count: upcomingList.length,
              color: cs.primary,
            ),
            const SizedBox(height: 8),
            ...upcomingList.map((o) => _buildOverrideCard(
                  context,
                  inventory,
                  o,
                  now,
                  status: _OverrideStatus.upcoming,
                )),
            const SizedBox(height: 16),
          ],
          if (pastList.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SectionHeader(
                  title: 'Past / Expired',
                  count: pastList.length,
                  color: cs.onSurfaceVariant,
                ),
                TextButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _clearExpiredOverrides(inventory, now),
                  icon: const Icon(Icons.cleaning_services_rounded, size: 15),
                  label: Text(
                    'Clear Expired (${pastList.length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...pastList.map((o) => _buildOverrideCard(
                  context,
                  inventory,
                  o,
                  now,
                  status: _OverrideStatus.past,
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildOverrideCard(
    BuildContext context,
    InventoryProvider inventory,
    ScheduleOverride override,
    DateTime now, {
    required _OverrideStatus status,
  }) {
    final cs = Theme.of(context).colorScheme;
    final Color typeColor;
    final IconData typeIcon;

    switch (override.type) {
      case OverrideType.fullClosure:
        typeColor = cs.error;
        typeIcon = Icons.block_rounded;
        break;
      case OverrideType.customOpenHours:
        typeColor = Colors.blue.shade700;
        typeIcon = Icons.schedule_rounded;
        break;
      case OverrideType.maintenanceWindow:
        typeColor = Colors.orange.shade800;
        typeIcon = Icons.build_rounded;
        break;
    }

    final isPast = status == _OverrideStatus.past;
    final isActive = status == _OverrideStatus.active;
    final effectiveColor = isPast ? cs.onSurfaceVariant : typeColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? typeColor.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: isPast ? 0.2 : 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? typeColor.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: isPast ? 0.5 : 1),
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(typeIcon, size: 18, color: effectiveColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            override.reason.isNotEmpty
                                ? override.reason
                                : override.typeLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: isPast ? cs.onSurfaceVariant : null,
                            ),
                          ),
                        ),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeColor,
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          override.typeLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: effectiveColor,
                          ),
                        ),
                        Text(
                          '•',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        Text(
                          override.formatDateRange(),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (override.type != OverrideType.fullClosure) ...[
                          Text(
                            '•',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          Text(
                            override.formatTimeRange(),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!isPast)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  onPressed:
                      _isSaving ? null : () => _startEditingOverride(override),
                ),
              const SizedBox(width: 6),
              if (isActive)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        Colors.green.shade700.withValues(alpha: 0.14),
                    foregroundColor: Colors.green.shade800,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text(
                    'Stop Now',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onPressed: _isSaving
                      ? null
                      : () => _stopActiveOverride(inventory, override, now),
                )
              else
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Delete', style: TextStyle(fontSize: 12)),
                  onPressed: _isSaving
                      ? null
                      : () => _deleteOverride(inventory, override),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── TAB 3: Add / Edit Scheduled Override ───────────────────────────────────

  Widget _buildAddEditOverrideTab(
    BuildContext context,
    InventoryProvider inventory,
    StoreSettings settings,
    DateTime now,
    bool isCompact,
  ) {
    final cs = Theme.of(context).colorScheme;
    final errColor = cs.error;
    final today = DateTime(now.year, now.month, now.day);

    final bool timeInvalid = _selectedType != OverrideType.fullClosure &&
        _toMinutes(_customEnd) <= _toMinutes(_customStart);

    // Check overlapping existing overrides (excluding the one being edited)
    final List<ScheduleOverride> overlapping = _selectedDateRange == null
        ? const []
        : settings.overrides.where((o) {
            if (_editingOverride != null && o.id == _editingOverride!.id) {
              return false;
            }
            return o.overlapsRange(
              _selectedDateRange!.start,
              _selectedDateRange!.end,
            );
          }).toList();

    final List<String> quickReasons = switch (_selectedType) {
      OverrideType.fullClosure => [
          'Public Holiday',
          'Christmas / New Year',
          'Family Event',
          'Restocking Day',
          'Store Renovation',
        ],
      OverrideType.customOpenHours => [
          'Holiday Eve Hours',
          'Half Day',
          'Preparing for Holidays',
          'Extended Hours',
        ],
      OverrideType.maintenanceWindow => [
          'Inventory Count',
          'System Maintenance',
          'Deep Cleaning',
          'Delivery Unloading',
        ],
    };

    final String typeHelperText = switch (_selectedType) {
      OverrideType.fullClosure =>
        'Store will be completely closed all day on the selected date(s).',
      OverrideType.customOpenHours =>
        'Overrides regular hours — store will ONLY be open during the time window below.',
      OverrideType.maintenanceWindow =>
        'Store will close temporarily during the time window below on the selected date(s).',
    };

    final Color ctaColor = switch (_selectedType) {
      OverrideType.fullClosure => errColor,
      OverrideType.customOpenHours => Colors.blue.shade700,
      OverrideType.maintenanceWindow => Colors.orange.shade800,
    };

    final String ctaLabel = _editingOverride != null
        ? 'Update Schedule'
        : switch (_selectedType) {
            OverrideType.fullClosure => 'Schedule Store Closure',
            OverrideType.customOpenHours => 'Save Custom Open Hours',
            OverrideType.maintenanceWindow => 'Schedule Maintenance Window',
          };

    final IconData ctaIcon = _editingOverride != null
        ? Icons.save_rounded
        : switch (_selectedType) {
            OverrideType.fullClosure => Icons.block_rounded,
            OverrideType.customOpenHours => Icons.event_available_rounded,
            OverrideType.maintenanceWindow => Icons.build_rounded,
          };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_editingOverride != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_calendar_rounded,
                      size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Editing: ${_editingOverride!.reason.isNotEmpty ? _editingOverride!.reason : _editingOverride!.typeLabel}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _resetOverrideForm,
                    child: const Text('Cancel Edit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Step 1: Date Range
          const Text(
            '1. Select Date or Range',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(
                label: const Text('Today', style: TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _selectedDateRange =
                        DateTimeRange(start: today, end: today);
                  });
                },
              ),
              ActionChip(
                label: const Text('Tomorrow', style: TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final tomorrow = today.add(const Duration(days: 1));
                  setState(() {
                    _selectedDateRange =
                        DateTimeRange(start: tomorrow, end: tomorrow);
                  });
                },
              ),
              ActionChip(
                label: const Text('This Weekend',
                    style: TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final daysToSat = (DateTime.saturday - today.weekday + 7) % 7;
                  final sat = today.add(Duration(days: daysToSat));
                  final sun = sat.add(const Duration(days: 1));
                  setState(() {
                    _selectedDateRange = DateTimeRange(start: sat, end: sun);
                  });
                },
              ),
              ActionChip(
                label:
                    const Text('Next 3 Days', style: TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _selectedDateRange = DateTimeRange(
                      start: today,
                      end: today.add(const Duration(days: 2)),
                    );
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(
              _selectedDateRange == null
                  ? 'Tap to pick date or range (e.g. Dec 24 – Jan 1)'
                  : _formatDateRangeLabel(_selectedDateRange!),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final firstDate = DateTime(today.year, today.month, 1);
              final lastDate = DateTime(today.year + 2, 12, 31);
              final picked = await showDateRangePicker(
                context: context,
                firstDate: firstDate,
                lastDate: lastDate,
                currentDate: today,
                initialDateRange: _selectedDateRange,
              );
              if (picked != null) {
                setState(() => _selectedDateRange = picked);
              }
            },
          ),
          const SizedBox(height: 16),

          // Step 2: Schedule Type
          const Text(
            '2. Schedule Type',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          SegmentedButton<OverrideType>(
            segments: [
              ButtonSegment(
                value: OverrideType.fullClosure,
                label: Text(
                  isCompact ? 'Closed' : 'Closed All Day',
                  style: const TextStyle(fontSize: 11.5),
                ),
                icon: const Icon(Icons.block_rounded, size: 15),
              ),
              ButtonSegment(
                value: OverrideType.customOpenHours,
                label: Text(
                  isCompact ? 'Custom' : 'Custom Hours',
                  style: const TextStyle(fontSize: 11.5),
                ),
                icon: const Icon(Icons.schedule_rounded, size: 15),
              ),
              ButtonSegment(
                value: OverrideType.maintenanceWindow,
                label: Text(
                  isCompact ? 'Maint.' : 'Maintenance',
                  style: const TextStyle(fontSize: 11.5),
                ),
                icon: const Icon(Icons.build_rounded, size: 15),
              ),
            ],
            selected: {_selectedType},
            onSelectionChanged: (val) {
              setState(() => _selectedType = val.first);
            },
          ),
          const SizedBox(height: 6),
          Text(
            typeHelperText,
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),

          // Step 3: Optional Time Window
          if (_selectedType != OverrideType.fullClosure) ...[
            const SizedBox(height: 14),
            Text(
              _selectedType == OverrideType.maintenanceWindow
                  ? '3. Maintenance Window'
                  : '3. Custom Open Hours',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TimePickerCard(
                    label: _selectedType == OverrideType.maintenanceWindow
                        ? 'Closed From'
                        : 'Open From',
                    value: _formatTimeDisplay(_customStart),
                    icon: Icons.access_time_rounded,
                    enabled: !_isSaving,
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _customStart,
                      );
                      if (t != null) setState(() => _customStart = t);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimePickerCard(
                    label: _selectedType == OverrideType.maintenanceWindow
                        ? 'Closed Until'
                        : 'Open Until',
                    value: _formatTimeDisplay(_customEnd),
                    icon: Icons.access_time_filled_rounded,
                    enabled: !_isSaving,
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _customEnd,
                      );
                      if (t != null) setState(() => _customEnd = t);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                (
                  label: '8 AM – 12 PM',
                  s: const TimeOfDay(hour: 8, minute: 0),
                  e: const TimeOfDay(hour: 12, minute: 0),
                ),
                (
                  label: '1 PM – 3 PM',
                  s: const TimeOfDay(hour: 13, minute: 0),
                  e: const TimeOfDay(hour: 15, minute: 0),
                ),
                (
                  label: '1 PM – 5 PM',
                  s: const TimeOfDay(hour: 13, minute: 0),
                  e: const TimeOfDay(hour: 17, minute: 0),
                ),
                (
                  label: '9 AM – 6 PM',
                  s: const TimeOfDay(hour: 9, minute: 0),
                  e: const TimeOfDay(hour: 18, minute: 0),
                ),
              ].map((p) {
                return ActionChip(
                  label: Text(p.label, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _customStart = p.s;
                      _customEnd = p.e;
                    });
                  },
                );
              }).toList(),
            ),
            if (timeInvalid) ...[
              const SizedBox(height: 6),
              Text(
                'End time must be later than start time.',
                style: TextStyle(
                  color: errColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],

          const SizedBox(height: 16),
          Text(
            _selectedType == OverrideType.fullClosure
                ? '3. Reason / Customer Notice'
                : '4. Reason / Customer Notice',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: quickReasons.map((reason) {
              return ActionChip(
                label: Text(reason, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _reasonCtrl.text = reason),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonCtrl,
            decoration: InputDecoration(
              labelText: 'Notice shown to customers',
              hintText: _selectedType == OverrideType.fullClosure
                  ? 'e.g. Closed for Christmas Holidays'
                  : _selectedType == OverrideType.maintenanceWindow
                      ? 'e.g. Brief inventory check & cleaning'
                      : 'e.g. Shortened hours for Holiday Eve',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),

          if (overlapping.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Overlaps with ${overlapping.length} existing schedule${overlapping.length == 1 ? '' : 's'}: '
                      '${overlapping.map((o) => o.reason.isNotEmpty ? o.reason : o.typeLabel).join(', ')}.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: ctaColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: Icon(ctaIcon, size: 18),
            label: Text(
              ctaLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: (_isSaving || timeInvalid)
                ? null
                : () => _saveOverride(inventory),
          ),
        ],
      ),
    );
  }

  static String _formatDateRangeLabel(DateTimeRange range) {
    final sameDay = range.start.year == range.end.year &&
        range.start.month == range.end.month &&
        range.start.day == range.end.day;
    if (sameDay) {
      return '${DateFormat('EEE, MMM d, yyyy').format(range.start)} (1 day)';
    }
    final days = range.end.difference(range.start).inDays + 1;
    final startStr = range.start.year == range.end.year
        ? DateFormat('MMM d').format(range.start)
        : DateFormat('MMM d, yyyy').format(range.start);
    final endStr = DateFormat('MMM d, yyyy').format(range.end);
    return '$startStr → $endStr ($days days)';
  }

  static (Color, IconData) _statusStyle(BuildContext context, String label) {
    final errColor = Theme.of(context).colorScheme.error;
    final succColor = Colors.green.shade700;
    final warnColor = Colors.orange.shade700;

    return switch (label) {
      'MAINTENANCE' || 'CLOSED' => (errColor, Icons.warning_amber_rounded),
      'HOLIDAY' => (errColor, Icons.event_busy_rounded),
      'SPECIAL SCHEDULE' => (Colors.deepOrange.shade700, Icons.build_rounded),
      'SPECIAL HOURS' => (Colors.blue.shade700, Icons.schedule_rounded),
      'SCHEDULED' => (warnColor, Icons.schedule_rounded),
      'OUT OF HOURS' => (warnColor, Icons.access_time_rounded),
      _ => (succColor, Icons.storefront_rounded),
    };
  }
}

enum _OverrideStatus { active, upcoming, past }

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(50),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _TimePickerCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Icon(icon, size: 20, color: cs.primary),
          ],
        ),
      ),
    );
  }
}
