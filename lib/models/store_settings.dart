import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  /// Checks if a given DateTime falls inside this override's date range
  bool appliesToDate(DateTime date) {
    final dayStart = DateTime(startDate.year, startDate.month, startDate.day);
    final dayEnd =
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    return !date.isBefore(dayStart) && !date.isAfter(dayEnd);
  }

  /// Checks if a specific pickup DateTime is blocked by this override
  bool isDateTimeClosed(DateTime checkTime) {
    if (!appliesToDate(checkTime)) return false;

    if (type == OverrideType.fullClosure) {
      return true; // Closed all day (e.g. Dec 24 - Jan 1)
    }

    final int checkMins = checkTime.hour * 60 + checkTime.minute;
    final int sMins = startMinutes ?? 0;
    final int eMins = endMinutes ?? 1439;

    if (type == OverrideType.customOpenHours) {
      // Only open BETWEEN sMins and eMins (e.g. 1:00 PM - 3:00 PM lang)
      return checkMins < sMins || checkMins > eMins;
    } else {
      // maintenanceWindow: Closed BETWEEN sMins and eMins
      return checkMins >= sMins && checkMins <= eMins;
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
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  /// Returns a copy of [StoreSettings] with updated fields.
  StoreSettings copyWith({
    bool? isClosed,
    String? closureMessage,
    DateTime? scheduledCloseAt,
    DateTime? scheduledOpenAt,
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
    DateTime? updatedAt,
  }) {
    return StoreSettings(
      isClosed: isClosed ?? this.isClosed,
      closureMessage: closureMessage ?? this.closureMessage,
      scheduledCloseAt: scheduledCloseAt ?? this.scheduledCloseAt,
      scheduledOpenAt: scheduledOpenAt ?? this.scheduledOpenAt,
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
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns active override matching a given date if any.
  ScheduleOverride? activeOverrideFor(DateTime date) {
    for (final override in overrides) {
      if (override.appliesToDate(date)) {
        return override;
      }
    }
    return null;
  }

  /// Evaluates manual, scheduled overrides, or operating hour constraints to determine if store is closed right now.
  bool get effectivelyClosed {
    if (isClosed) return true;

    final now = DateTime.now();

    // 1. Check Scheduled Overrides
    for (final override in overrides) {
      if (override.appliesToDate(now)) {
        if (override.isDateTimeClosed(now)) {
          return true;
        }
      }
    }

    // 2. Check Scheduled Outage
    final DateTime? sClose = scheduledCloseAt;
    final DateTime? sOpen = scheduledOpenAt;
    if (sClose != null && sOpen != null) {
      if (now.isAfter(sClose) && now.isBefore(sOpen)) {
        return true;
      }
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

  /// Human-readable explanation text for store closure reason or active schedule label.
  String get closureReason {
    if (isClosed) {
      final String rawMsg = closureMessage?.trim() ?? '';
      final String reasonText =
          rawMsg.isNotEmpty ? rawMsg : 'Will be back soon.';
      final DateTime time = updatedAt ?? scheduledCloseAt ?? DateTime.now();
      final String formattedTime = DateFormat('MMM d, h:mm a').format(time);
      return '$formattedTime — $reasonText';
    }

    final now = DateTime.now();

    for (final override in overrides) {
      if (override.appliesToDate(now)) {
        final reason = override.reason.isNotEmpty
            ? override.reason
            : 'Holiday / Special Schedule';
        if (override.type == OverrideType.fullClosure) {
          return 'Closed: $reason';
        } else if (override.type == OverrideType.customOpenHours) {
          if (override.isDateTimeClosed(now)) {
            return '$reason (Open ${override.formatTimeRange()} only).';
          } else {
            return 'Open: $reason (${override.formatTimeRange()})';
          }
        } else {
          if (override.isDateTimeClosed(now)) {
            return 'Closed for maintenance: $reason (${override.formatTimeRange()}).';
          }
        }
      }
    }

    final DateTime? sClose = scheduledCloseAt;
    final DateTime? sOpen = scheduledOpenAt;
    if (sClose != null && sOpen != null) {
      if (now.isAfter(sClose) && now.isBefore(sOpen)) {
        final reopens = DateFormat('MMM d, h:mm a').format(sOpen);
        return (closureMessage != null && closureMessage!.trim().isNotEmpty)
            ? closureMessage!
            : 'Scheduled closure active until $reopens.';
      }
    }

    if (operatingHoursEnabled) {
      if (closedDaysOfWeek.contains(now.weekday)) {
        return 'Store is closed today per operating schedule.';
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
        }
      }
    }

    return 'Store is currently open.';
  }

  /// Active status label for store status badges.
  String get activeStatusLabel {
    if (isClosed) {
      return closureMessage?.trim().isNotEmpty == true
          ? closureMessage!
          : 'Emergency Maintenance Active';
    }
    final active = activeOverrideFor(DateTime.now());
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

  /// Status badge label describing store status.
  String get statusLabel {
    if (isClosed) return 'MAINTENANCE';
    final now = DateTime.now();

    final active = activeOverrideFor(now);
    if (active != null) {
      if (active.isDateTimeClosed(now)) {
        return active.type == OverrideType.fullClosure
            ? 'HOLIDAY'
            : 'SPECIAL SCHEDULE';
      } else {
        return 'SPECIAL HOURS';
      }
    }

    final DateTime? sClose = scheduledCloseAt;
    final DateTime? sOpen = scheduledOpenAt;
    if (sClose != null && sOpen != null) {
      if (now.isAfter(sClose) && now.isBefore(sOpen)) {
        return 'SCHEDULED';
      }
    }
    if (operatingHoursEnabled && effectivelyClosed) {
      return 'OUT OF HOURS';
    }
    return 'OPEN';
  }

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
