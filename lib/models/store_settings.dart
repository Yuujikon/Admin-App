import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class StoreSettings {
  final bool isClosed;
  final String? closureMessage;
  final DateTime? scheduledCloseAt;
  final DateTime? scheduledOpenAt;

  // Operating Hours Settings
  final bool operatingHoursEnabled;
  final String? dailyOpenTime;  // e.g. "08:00"
  final String? dailyCloseTime; // e.g. "21:00"
  final List<int> closedDaysOfWeek; // 1 = Mon ... 7 = Sun

  // Expiration windows in hours
  final int perishableWindowHours;
  final int mixedWindowHours;
  final int standardWindowHours;

  // Global Thresholds & Master Data
  final int globalLowStockThreshold;
  final List<String> masterCategories;
  final String? announcement;

  const StoreSettings({
    required this.isClosed,
    this.closureMessage,
    this.scheduledCloseAt,
    this.scheduledOpenAt,
    this.operatingHoursEnabled = false,
    this.dailyOpenTime = "08:00",
    this.dailyCloseTime = "21:00",
    this.closedDaysOfWeek = const [],
    this.perishableWindowHours = 2,
    this.mixedWindowHours = 24,
    this.standardWindowHours = 72,
    this.globalLowStockThreshold = 5,
    this.masterCategories = const [
      'Fresh', 'Grains', 'Snacks', 'Beverages', 
      'Canned Goods', 'Personal Care', 'Condiments', 'Others'
    ],
    this.announcement,
  });

  factory StoreSettings.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return StoreSettings(
      isClosed: d['isClosed'] ?? false,
      closureMessage: d['closureMessage'],
      scheduledCloseAt: (d['scheduledCloseAt'] as Timestamp?)?.toDate(),
      scheduledOpenAt: (d['scheduledOpenAt'] as Timestamp?)?.toDate(),
      operatingHoursEnabled: d['operatingHoursEnabled'] ?? false,
      dailyOpenTime: d['dailyOpenTime'] ?? "08:00",
      dailyCloseTime: d['dailyCloseTime'] ?? "21:00",
      closedDaysOfWeek: List<int>.from(d['closedDaysOfWeek'] ?? []),
      perishableWindowHours: d['perishableWindowHours'] ?? 2,
      mixedWindowHours: d['mixedWindowHours'] ?? 24,
      standardWindowHours: d['standardWindowHours'] ?? 72,
      globalLowStockThreshold: (d['globalLowStockThreshold'] as num? ?? 5).toInt(),
      masterCategories: List<String>.from(d['masterCategories'] ?? [
        'Fresh', 'Grains', 'Snacks', 'Beverages', 
        'Canned Goods', 'Personal Care', 'Condiments', 'Others'
      ]),
      announcement: d['announcement'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'isClosed': isClosed,
    'closureMessage': closureMessage,
    'scheduledCloseAt': scheduledCloseAt != null ? Timestamp.fromDate(scheduledCloseAt!) : null,
    'scheduledOpenAt': scheduledOpenAt != null ? Timestamp.fromDate(scheduledOpenAt!) : null,
    'operatingHoursEnabled': operatingHoursEnabled,
    'dailyOpenTime': dailyOpenTime,
    'dailyCloseTime': dailyCloseTime,
    'closedDaysOfWeek': closedDaysOfWeek,
    'perishableWindowHours': perishableWindowHours,
    'mixedWindowHours': mixedWindowHours,
    'standardWindowHours': standardWindowHours,
    'globalLowStockThreshold': globalLowStockThreshold,
    'masterCategories': masterCategories,
    'announcement': announcement,
  };

  StoreSettings copyWith({
    bool? isClosed,
    String? closureMessage,
    DateTime? scheduledCloseAt,
    DateTime? scheduledOpenAt,
    bool? operatingHoursEnabled,
    String? dailyOpenTime,
    String? dailyCloseTime,
    List<int>? closedDaysOfWeek,
    int? perishableWindowHours,
    int? mixedWindowHours,
    int? standardWindowHours,
    int? globalLowStockThreshold,
    List<String>? masterCategories,
    String? announcement,
  }) {
    return StoreSettings(
      isClosed: isClosed ?? this.isClosed,
      closureMessage: closureMessage ?? this.closureMessage,
      scheduledCloseAt: scheduledCloseAt ?? this.scheduledCloseAt,
      scheduledOpenAt: scheduledOpenAt ?? this.scheduledOpenAt,
      operatingHoursEnabled: operatingHoursEnabled ?? this.operatingHoursEnabled,
      dailyOpenTime: dailyOpenTime ?? this.dailyOpenTime,
      dailyCloseTime: dailyCloseTime ?? this.dailyCloseTime,
      closedDaysOfWeek: closedDaysOfWeek ?? this.closedDaysOfWeek,
      perishableWindowHours: perishableWindowHours ?? this.perishableWindowHours,
      mixedWindowHours: mixedWindowHours ?? this.mixedWindowHours,
      standardWindowHours: standardWindowHours ?? this.standardWindowHours,
      globalLowStockThreshold: globalLowStockThreshold ?? this.globalLowStockThreshold,
      masterCategories: masterCategories ?? this.masterCategories,
      announcement: announcement ?? this.announcement,
    );
  }

  bool get effectivelyClosed {
    if (isClosed) return true;
    
    final now = DateTime.now();

    // 1. Check Scheduled Outage
    if (scheduledCloseAt != null && scheduledOpenAt != null) {
      if (now.isAfter(scheduledCloseAt!) && now.isBefore(scheduledOpenAt!)) {
        return true;
      }
    }

    // 2. Check Daily Operating Hours & Days if enabled
    if (operatingHoursEnabled) {
      if (closedDaysOfWeek.contains(now.weekday)) {
        return true;
      }
      if (dailyOpenTime != null && dailyCloseTime != null) {
        final openMins = _parseMinutes(dailyOpenTime!);
        final closeMins = _parseMinutes(dailyCloseTime!);
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

  String get closureReason {
    if (isClosed) {
      return (closureMessage != null && closureMessage!.trim().isNotEmpty)
          ? closureMessage!
          : 'Store is manually closed.';
    }

    final now = DateTime.now();

    if (scheduledCloseAt != null && scheduledOpenAt != null) {
      if (now.isAfter(scheduledCloseAt!) && now.isBefore(scheduledOpenAt!)) {
        final reopens = DateFormat('MMM d, h:mm a').format(scheduledOpenAt!);
        return (closureMessage != null && closureMessage!.trim().isNotEmpty)
            ? closureMessage!
            : 'Scheduled closure active until $reopens.';
      }
    }

    if (operatingHoursEnabled) {
      if (closedDaysOfWeek.contains(now.weekday)) {
        return 'Store is closed today per operating schedule.';
      }
      if (dailyOpenTime != null && dailyCloseTime != null) {
        final openMins = _parseMinutes(dailyOpenTime!);
        final closeMins = _parseMinutes(dailyCloseTime!);
        final curMins = now.hour * 60 + now.minute;

        if (openMins != null && closeMins != null) {
          bool outside = false;
          if (openMins < closeMins) {
            outside = curMins < openMins || curMins >= closeMins;
          } else if (openMins > closeMins) {
            outside = curMins < openMins && curMins >= closeMins;
          }
          if (outside) {
            return 'Outside daily operating hours (${_formatTimeStr(dailyOpenTime!)} – ${_formatTimeStr(dailyCloseTime!)}).';
          }
        }
      }
    }

    return 'Store is currently open.';
  }

  String get statusLabel {
    if (isClosed) return 'CLOSED';
    final now = DateTime.now();
    if (scheduledCloseAt != null && scheduledOpenAt != null) {
      if (now.isAfter(scheduledCloseAt!) && now.isBefore(scheduledOpenAt!)) {
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

