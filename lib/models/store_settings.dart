import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../shared/services/time_service.dart';

enum OverrideType {
  fullClosure, // e.g., Dec 24 - Jan 1: Closed All Day ("Holidays")
  customOpenHours, // e.g., Dec 20 - Dec 23: Open 1:00 PM - 3:00 PM ("Preparing for Holidays")
  maintenanceWindow, // e.g., Dec 20 - Dec 23: Closed 1:00 PM - 3:00 PM for maintenance
}

class ScheduleOverride {
  final String id;
  final DateTime startDate; // Normalized to 00:00:00 of start day
  final DateTime endDate; // Normalized to 23:59:59 of end day
  final OverrideType type;
  final int?
      startMinutes; // Minutes from midnight (e.g. 13 * 60 = 780 for 1:00 PM)
  final int?
      endMinutes; // Minutes from midnight (e.g. 15 * 60 = 900 for 3:00 PM)
  final String reason; // e.g. "Preparing for Holidays", "Holidays"

  const ScheduleOverride({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.type,
    this.startMinutes,
    this.endMinutes,
    required this.reason,
  });

  ScheduleOverride copyWith({
    String? id,
    DateTime? startDate,
    DateTime? endDate,
    OverrideType? type,
    int? startMinutes,
    int? endMinutes,
    bool clearTimeWindow = false,
    String? reason,
  }) {
    return ScheduleOverride(
      id: id ?? this.id,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      type: type ?? this.type,
      startMinutes:
          clearTimeWindow ? null : (startMinutes ?? this.startMinutes),
      endMinutes: clearTimeWindow ? null : (endMinutes ?? this.endMinutes),
      reason: reason ?? this.reason,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'type': type.name,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'reason': reason,
      };

  factory ScheduleOverride.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return ScheduleOverride(
      id: map['id']?.toString() ?? '',
      startDate: parseDate(map['startDate']),
      endDate: parseDate(map['endDate']),
      type: OverrideType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => OverrideType.fullClosure,
      ),
      startMinutes: (map['startMinutes'] as num?)?.toInt(),
      endMinutes: (map['endMinutes'] as num?)?.toInt(),
      reason: map['reason']?.toString() ?? '',
    );
  }

  DateTime get normalizedStart =>
      DateTime(startDate.year, startDate.month, startDate.day);

  DateTime get normalizedEnd =>
      DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

  bool get isSingleDay =>
      startDate.year == endDate.year &&
      startDate.month == endDate.month &&
      startDate.day == endDate.day;

  /// Checks if a given DateTime falls inside this override's date range.
  bool appliesToDate(DateTime date) {
    return !date.isBefore(normalizedStart) && !date.isAfter(normalizedEnd);
  }

  /// Returns true if this override is active on the date of [now].
  bool isActiveAt(DateTime now) => appliesToDate(now);

  /// Returns true if this override has completely ended before [now].
  bool isPastAt(DateTime now) => now.isAfter(normalizedEnd);

  /// Returns true if this override begins after [now].
  bool isUpcomingAt(DateTime now) => now.isBefore(normalizedStart);

  /// Returns true if this override overlaps the inclusive date range [start]..[end].
  bool overlapsRange(DateTime start, DateTime end) {
    final otherStart = DateTime(start.year, start.month, start.day);
    final otherEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
    return !normalizedStart.isAfter(otherEnd) &&
        !otherStart.isAfter(normalizedEnd);
  }

  /// Checks if a specific DateTime is closed/blocked by this override.
  bool isDateTimeClosed(DateTime checkTime) {
    if (!appliesToDate(checkTime)) return false;

    if (type == OverrideType.fullClosure) {
      return true; // Closed all day (e.g. Dec 24 - Jan 1)
    }

    final int checkMins = checkTime.hour * 60 + checkTime.minute;
    final int sMins = startMinutes ?? 0;
    final int eMins = endMinutes ?? 1439;

    if (type == OverrideType.customOpenHours) {
      // Only open between sMins and eMins.
      if (sMins <= eMins) {
        return checkMins < sMins || checkMins > eMins;
      } else {
        // Overnight custom open window (e.g. 20:00 - 04:00)
        return checkMins < sMins && checkMins > eMins;
      }
    } else {
      // maintenanceWindow: Closed between sMins and eMins.
      if (sMins <= eMins) {
        return checkMins >= sMins && checkMins <= eMins;
      } else {
        // Overnight maintenance window
        return checkMins >= sMins || checkMins <= eMins;
      }
    }
  }

  String get typeLabel {
    switch (type) {
      case OverrideType.fullClosure:
        return 'Closed All Day';
      case OverrideType.customOpenHours:
        return 'Custom Open Hours';
      case OverrideType.maintenanceWindow:
        return 'Maintenance Window';
    }
  }

  String formatDateRange() {
    if (isSingleDay) {
      return DateFormat('MMM d, yyyy').format(startDate);
    }
    if (startDate.year == endDate.year) {
      return '${DateFormat('MMM d').format(startDate)} – ${DateFormat('MMM d, yyyy').format(endDate)}';
    }
    return '${DateFormat('MMM d, yyyy').format(startDate)} – ${DateFormat('MMM d, yyyy').format(endDate)}';
  }

  String formatTimeRange() {
    if (type == OverrideType.fullClosure) return 'Closed All Day';
    final sMins = startMinutes ?? 0;
    final eMins = endMinutes ?? 1439;
    return '${_formatMins(sMins)} – ${_formatMins(eMins)}';
  }

  static String _formatMins(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mStr = m.toString().padLeft(2, '0');
    return '$h12:$mStr $period';
  }
}

/// Configuration and master settings data model for store operation rules.
class StoreSettings {
  final bool isClosed;
  final String? closureMessage;
  final DateTime? scheduledCloseAt;
  final DateTime? scheduledOpenAt;

  // Operating Hours Settings
  final bool operatingHoursEnabled;
  final String? dailyOpenTime; // e.g. "08:00"
  final String? dailyCloseTime; // e.g. "21:00"
  final List<int> closedDaysOfWeek; // 1 = Mon ... 7 = Sun
  final List<ScheduleOverride> overrides; // Scheduled date/range overrides

  // Expiration windows in hours
  final int perishableWindowHours;
  final int mixedWindowHours;
  final int standardWindowHours;

  // Global Thresholds & Master Data
  final int globalLowStockThreshold;
  final List<String> masterCategories;
  final String? announcement;

  // Dynamic Velocity-Based Pricing Settings
  /// When true, applies the pure 15.0%–25.0% global velocity benchmark across all categories.
  /// When false (default), uses category-specific bounds for defined categories and 15%–25% for Others.
  final bool useGlobalVelocityBenchmarkOnly;

  /// Philippine sari-sari store selling price rounding step (e.g. 0.25, 0.50, or 1.00).
  final double priceRoundingStep;

  /// Rolling window in days (7 or 30) used to compute normalized salesVelocityScore.
  final int velocityWindowDays;

  final DateTime? updatedAt;

  /// Creates a [StoreSettings] instance.
  const StoreSettings({
    required this.isClosed,
    this.closureMessage,
    this.scheduledCloseAt,
    this.scheduledOpenAt,
    this.operatingHoursEnabled = false,
    this.dailyOpenTime = "08:00",
    this.dailyCloseTime = "21:00",
    this.closedDaysOfWeek = const [],
    this.overrides = const [],
    this.perishableWindowHours = 2,
    this.mixedWindowHours = 24,
    this.standardWindowHours = 72,
    this.globalLowStockThreshold = 5,
    this.masterCategories = const [
      'Fresh',
      'Grains',
      'Snacks',
      'Beverages',
      'Canned Goods',
      'Personal Care',
      'Condiments',
      'Others'
    ],
    this.announcement,
    this.useGlobalVelocityBenchmarkOnly = false,
    this.priceRoundingStep = 0.25,
    this.velocityWindowDays = 30,
    this.updatedAt,
  });

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory StoreSettings.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final rawOverrides = d['overrides'] as List?;
    final overridesList = rawOverrides != null
        ? rawOverrides
            .map((item) => ScheduleOverride.fromMap(
                Map<String, dynamic>.from(item as Map)))
            .toList()
        : const <ScheduleOverride>[];

    final rawRoundingStep =
        (d['priceRoundingStep'] as num?)?.toDouble() ?? 0.25;
    final double safeRoundingStep =
        (rawRoundingStep > 0 && rawRoundingStep.isFinite)
            ? rawRoundingStep
            : 0.25;
    final rawWindowDays = (d['velocityWindowDays'] as num?)?.toInt() ?? 30;
    final int safeWindowDays = rawWindowDays == 7 ? 7 : 30;

    return StoreSettings(
      isClosed: d['isClosed'] ?? false,
      closureMessage: d['closureMessage'],
      scheduledCloseAt: (d['scheduledCloseAt'] as Timestamp?)?.toDate(),
      scheduledOpenAt: (d['scheduledOpenAt'] as Timestamp?)?.toDate(),
      operatingHoursEnabled: d['operatingHoursEnabled'] ?? false,
      dailyOpenTime: d['dailyOpenTime'] ?? "08:00",
      dailyCloseTime: d['dailyCloseTime'] ?? "21:00",
      closedDaysOfWeek: List<int>.from(d['closedDaysOfWeek'] ?? []),
      overrides: overridesList,
      perishableWindowHours: d['perishableWindowHours'] ?? 2,
      mixedWindowHours: d['mixedWindowHours'] ?? 24,
      standardWindowHours: d['standardWindowHours'] ?? 72,
      globalLowStockThreshold:
          (d['globalLowStockThreshold'] as num? ?? 5).toInt(),
      masterCategories: List<String>.from(d['masterCategories'] ??
          [
            'Fresh',
            'Grains',
            'Snacks',
            'Beverages',
            'Canned Goods',
            'Personal Care',
            'Condiments',
            'Others'
          ]),
      announcement: d['announcement'],
      useGlobalVelocityBenchmarkOnly:
          d['useGlobalVelocityBenchmarkOnly'] == true,
      priceRoundingStep: safeRoundingStep,
      velocityWindowDays: safeWindowDays,
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Converts store settings instance to Map for Firestore persistence.
  Map<String, dynamic> toFirestore() {
    final sClose = scheduledCloseAt;
    final sOpen = scheduledOpenAt;
    return {
      'isClosed': isClosed,
      'closureMessage': closureMessage,
      'scheduledCloseAt': sClose != null ? Timestamp.fromDate(sClose) : null,
      'scheduledOpenAt': sOpen != null ? Timestamp.fromDate(sOpen) : null,
      'operatingHoursEnabled': operatingHoursEnabled,
      'dailyOpenTime': dailyOpenTime,
      'dailyCloseTime': dailyCloseTime,
      'closedDaysOfWeek': closedDaysOfWeek,
      'overrides': overrides.map((o) => o.toMap()).toList(),
      'perishableWindowHours': perishableWindowHours,
      'mixedWindowHours': mixedWindowHours,
      'standardWindowHours': standardWindowHours,
      'globalLowStockThreshold': globalLowStockThreshold,
      'masterCategories': masterCategories,
      'announcement': announcement,
      'useGlobalVelocityBenchmarkOnly': useGlobalVelocityBenchmarkOnly,
      'priceRoundingStep': priceRoundingStep,
      'velocityWindowDays': velocityWindowDays,
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  /// Returns a copy of [StoreSettings] with updated fields.
  StoreSettings copyWith({
    bool? isClosed,
    String? closureMessage,
    bool clearClosureMessage = false,
    DateTime? scheduledCloseAt,
    DateTime? scheduledOpenAt,
    bool clearScheduledOutage = false,
    bool? operatingHoursEnabled,
    String? dailyOpenTime,
    String? dailyCloseTime,
    List<int>? closedDaysOfWeek,
    List<ScheduleOverride>? overrides,
    int? perishableWindowHours,
    int? mixedWindowHours,
    int? standardWindowHours,
    int? globalLowStockThreshold,
    List<String>? masterCategories,
    String? announcement,
    bool? useGlobalVelocityBenchmarkOnly,
    double? priceRoundingStep,
    int? velocityWindowDays,
    DateTime? updatedAt,
  }) {
    return StoreSettings(
      isClosed: isClosed ?? this.isClosed,
      closureMessage:
          clearClosureMessage ? null : (closureMessage ?? this.closureMessage),
      scheduledCloseAt: clearScheduledOutage
          ? null
          : (scheduledCloseAt ?? this.scheduledCloseAt),
      scheduledOpenAt: clearScheduledOutage
          ? null
          : (scheduledOpenAt ?? this.scheduledOpenAt),
      operatingHoursEnabled:
          operatingHoursEnabled ?? this.operatingHoursEnabled,
      dailyOpenTime: dailyOpenTime ?? this.dailyOpenTime,
      dailyCloseTime: dailyCloseTime ?? this.dailyCloseTime,
      closedDaysOfWeek: closedDaysOfWeek ?? this.closedDaysOfWeek,
      overrides: overrides ?? this.overrides,
      perishableWindowHours:
          perishableWindowHours ?? this.perishableWindowHours,
      mixedWindowHours: mixedWindowHours ?? this.mixedWindowHours,
      standardWindowHours: standardWindowHours ?? this.standardWindowHours,
      globalLowStockThreshold:
          globalLowStockThreshold ?? this.globalLowStockThreshold,
      masterCategories: masterCategories ?? this.masterCategories,
      announcement: announcement ?? this.announcement,
      useGlobalVelocityBenchmarkOnly:
          useGlobalVelocityBenchmarkOnly ?? this.useGlobalVelocityBenchmarkOnly,
      priceRoundingStep: priceRoundingStep ?? this.priceRoundingStep,
      velocityWindowDays: velocityWindowDays ?? this.velocityWindowDays,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns all overrides that cover [date].
  List<ScheduleOverride> overridesForDate(DateTime date) {
    return overrides.where((o) => o.appliesToDate(date)).toList();
  }

  /// Returns the highest-priority active override matching [date], if any.
  /// Priority: fullClosure > currently-closed maintenanceWindow > customOpenHours > other maintenanceWindow.
  ScheduleOverride? activeOverrideFor(DateTime date) {
    final matching = overridesForDate(date);
    if (matching.isEmpty) return null;

    for (final o in matching) {
      if (o.type == OverrideType.fullClosure) return o;
    }
    for (final o in matching) {
      if (o.type == OverrideType.maintenanceWindow &&
          o.isDateTimeClosed(date)) {
        return o;
      }
    }
    for (final o in matching) {
      if (o.type == OverrideType.customOpenHours) return o;
    }
    return matching.first;
  }

  /// Returns the specific [ScheduleOverride] that is actively closing the store at [now], if any.
  ScheduleOverride? activeClosingOverrideAt(DateTime now) {
    final matching = overridesForDate(now);
    if (matching.isEmpty) return null;

    for (final o in matching) {
      if (o.type == OverrideType.fullClosure) return o;
    }
    for (final o in matching) {
      if (o.type == OverrideType.maintenanceWindow && o.isDateTimeClosed(now)) {
        return o;
      }
    }
    for (final o in matching) {
      if (o.type == OverrideType.customOpenHours && o.isDateTimeClosed(now)) {
        return o;
      }
    }
    return null;
  }

  /// Returns true if a legacy scheduled outage window (`scheduledCloseAt`..`scheduledOpenAt`) is active at [now].
  bool isScheduledOutageActiveAt(DateTime now) {
    final DateTime? sClose = scheduledCloseAt;
    final DateTime? sOpen = scheduledOpenAt;
    if (sClose != null && sOpen != null) {
      return now.isAfter(sClose) && now.isBefore(sOpen);
    }
    return false;
  }

  /// Evaluates manual, scheduled overrides, or operating hour constraints to determine if store is closed at [now].
  bool isEffectivelyClosedAt(DateTime now) {
    if (isClosed) return true;

    // 1. Check Scheduled Overrides with clear precedence
    final matching = overridesForDate(now);
    if (matching.isNotEmpty) {
      // Full-day closure or active maintenance window always closes the store
      for (final o in matching) {
        if (o.type == OverrideType.fullClosure) return true;
      }
      for (final o in matching) {
        if (o.type == OverrideType.maintenanceWindow &&
            o.isDateTimeClosed(now)) {
          return true;
        }
      }
      // Custom open hours override regular operating hours & closed days of week
      for (final o in matching) {
        if (o.type == OverrideType.customOpenHours) {
          return o.isDateTimeClosed(now);
        }
      }
    }

    // 2. Check Legacy Scheduled Outage
    if (isScheduledOutageActiveAt(now)) {
      return true;
    }

    // 3. Check Daily Operating Hours & Days if enabled
    if (operatingHoursEnabled) {
      if (closedDaysOfWeek.contains(now.weekday)) {
        return true;
      }
      final String? openStr = dailyOpenTime;
      final String? closeStr = dailyCloseTime;
      if (openStr != null && closeStr != null) {
        final openMins = _parseMinutes(openStr);
        final closeMins = _parseMinutes(closeStr);
        final curMins = now.hour * 60 + now.minute;

        if (openMins != null && closeMins != null) {
          if (openMins < closeMins) {
            if (curMins < openMins || curMins >= closeMins) {
              return true;
            }
          } else if (openMins > closeMins) {
            if (curMins < openMins && curMins >= closeMins) {
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  /// Evaluates manual, scheduled overrides, or operating hour constraints to determine if store is closed right now.
  bool get effectivelyClosed => isEffectivelyClosedAt(TimeService.now);

  /// Returns `true` when the store has closed for the day at [now] — triggering
  /// the end-of-day (store-closing) 30% low-stock resupply summary email.
  ///
  /// Triggers on:
  /// 1. Manual store close (`isClosed == true`),
  /// 2. Active scheduled outage (`scheduledCloseAt..scheduledOpenAt`),
  /// 3. Today's full-day closure override or `customOpenHours` end time reached, or
  /// 4. Regular daily closing time (`dailyCloseTime`, default `21:00`) reached.
  ///
  /// Does NOT fire early in the morning before opening time on a regular open day.
  bool hasStoreClosedForDayAt(DateTime now) {
    if (isClosed) return true;
    if (isScheduledOutageActiveAt(now)) return true;

    final int curMins = now.hour * 60 + now.minute;
    final matching = overridesForDate(now);
    if (matching.isNotEmpty) {
      for (final o in matching) {
        if (o.type == OverrideType.fullClosure) return true;
      }
      for (final o in matching) {
        if (o.type == OverrideType.customOpenHours && o.endMinutes != null) {
          return curMins >= o.endMinutes!;
        }
      }
    }

    final int closeMins = _parseMinutes(dailyCloseTime ?? '21:00') ?? (21 * 60);
    return curMins >= closeMins;
  }

  /// Returns `true` if the store has closed for the current day.
  bool get hasStoreClosedForDay => hasStoreClosedForDayAt(TimeService.now);

  /// Human-readable explanation text for store closure reason or active schedule label at [now].
  String closureReasonAt(DateTime now) {
    if (isClosed) {
      final String rawMsg = closureMessage?.trim() ?? '';
      final String reasonText =
          rawMsg.isNotEmpty ? rawMsg : 'Will be back soon.';
      final DateTime time = updatedAt ?? scheduledCloseAt ?? now;
      final String formattedTime = DateFormat('MMM d, h:mm a').format(time);
      return '$formattedTime — $reasonText';
    }

    final active = activeOverrideFor(now);
    if (active != null) {
      final reason = active.reason.isNotEmpty
          ? active.reason
          : 'Holiday / Special Schedule';
      if (active.type == OverrideType.fullClosure) {
        return 'Closed: $reason (${active.formatDateRange()})';
      } else if (active.type == OverrideType.customOpenHours) {
        if (active.isDateTimeClosed(now)) {
          return '$reason (Open ${active.formatTimeRange()} only).';
        } else {
          return 'Open: $reason (${active.formatTimeRange()})';
        }
      } else {
        if (active.isDateTimeClosed(now)) {
          return 'Closed for maintenance: $reason (${active.formatTimeRange()}).';
        }
      }
    }

    if (isScheduledOutageActiveAt(now)) {
      final reopens = DateFormat('MMM d, h:mm a').format(scheduledOpenAt!);
      return (closureMessage != null && closureMessage!.trim().isNotEmpty)
          ? closureMessage!
          : 'Scheduled closure active until $reopens.';
    }

    if (operatingHoursEnabled) {
      if (closedDaysOfWeek.contains(now.weekday)) {
        final dayName = DateFormat('EEEE').format(now);
        return 'Store is closed on ${dayName}s per regular schedule.';
      }
      final String? openStr = dailyOpenTime;
      final String? closeStr = dailyCloseTime;
      if (openStr != null && closeStr != null) {
        final openMins = _parseMinutes(openStr);
        final closeMins = _parseMinutes(closeStr);
        final curMins = now.hour * 60 + now.minute;

        if (openMins != null && closeMins != null) {
          bool outside = false;
          if (openMins < closeMins) {
            outside = curMins < openMins || curMins >= closeMins;
          } else if (openMins > closeMins) {
            outside = curMins < openMins && curMins >= closeMins;
          }
          if (outside) {
            return 'Outside daily operating hours (${_formatTimeStr(openStr)} – ${_formatTimeStr(closeStr)}).';
          }
          return 'Open regular hours (${_formatTimeStr(openStr)} – ${_formatTimeStr(closeStr)}).';
        }
      }
    }

    return 'Store is currently open.';
  }

  /// Human-readable explanation text for store closure reason or active schedule label.
  String get closureReason => closureReasonAt(TimeService.now);

  /// Active status label for store status badges at [now].
  String activeStatusLabelAt(DateTime now) {
    if (isClosed) {
      return closureMessage?.trim().isNotEmpty == true
          ? closureMessage!
          : 'Emergency Maintenance Active';
    }
    final active = activeOverrideFor(now);
    if (active != null) {
      if (active.type == OverrideType.fullClosure) {
        return 'Closed: ${active.reason}';
      } else if (active.type == OverrideType.customOpenHours) {
        return '${active.reason} (Hours: ${active.formatTimeRange()})';
      } else {
        return '${active.reason} (Maintenance: ${active.formatTimeRange()})';
      }
    }
    if (operatingHoursEnabled) {
      return 'Regular Hours: ${_formatTimeStr(dailyOpenTime ?? "08:00")} – ${_formatTimeStr(dailyCloseTime ?? "21:00")}';
    }
    return 'Regular Store Hours';
  }

  /// Active status label for store status badges.
  String get activeStatusLabel => activeStatusLabelAt(TimeService.now);

  /// Status badge label describing store status at [now].
  String statusLabelAt(DateTime now) {
    if (isClosed) return 'MAINTENANCE';

    final active = activeOverrideFor(now);
    if (active != null) {
      if (active.isDateTimeClosed(now)) {
        return active.type == OverrideType.fullClosure
            ? 'HOLIDAY'
            : 'SPECIAL SCHEDULE';
      } else if (active.type == OverrideType.customOpenHours) {
        return 'SPECIAL HOURS';
      }
    }

    if (isScheduledOutageActiveAt(now)) {
      return 'SCHEDULED';
    }
    if (operatingHoursEnabled && isEffectivelyClosedAt(now)) {
      return 'OUT OF HOURS';
    }
    return 'OPEN';
  }

  /// Status badge label describing store status.
  String get statusLabel => statusLabelAt(TimeService.now);

  static int? _parseMinutes(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length < 2) return null;
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      return h * 60 + m;
    } catch (_) {
      return null;
    }
  }

  static String _formatTimeStr(String timeStr) {
    final mins = _parseMinutes(timeStr);
    if (mins == null) return timeStr;
    final h = mins ~/ 60;
    final m = mins % 60;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mStr = m.toString().padLeft(2, '0');
    return '$h12:$mStr $period';
  }
}
