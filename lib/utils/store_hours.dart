import '../models/store_settings.dart';
import '../shared/services/time_service.dart';

/// Utility class for checking store open/closed status and pickup schedule slots.
class StoreHours {
  /// Dynamically checks if the store is currently (or on a target date) within active operating/pickup hours.
  static bool isOpen([StoreSettings? settings, DateTime? date]) {
    final checkTime = date ?? TimeService.now;
    if (settings != null) {
      return !settings.isEffectivelyClosedAt(checkTime);
    }
    final h = checkTime.hour;
    return h >= 8 && h < 21; // Default fallback: 8:00 AM - 9:00 PM
  }

  /// Dynamically generates available pickup slots based on store settings, schedule overrides, and date.
  static List<Map<String, dynamic>> availableSlots(
      [StoreSettings? settings, DateTime? targetDate]) {
    final date = targetDate ?? TimeService.now;
    final now = TimeService.now;
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    if (settings != null && settings.isClosed) {
      return []; // No slots available during emergency maintenance
    }

    final matchingOverrides = settings != null
        ? settings.overridesForDate(date)
        : const <ScheduleOverride>[];

    // If any full-day closure applies on targetDate, no slots are available.
    if (matchingOverrides.any((o) => o.type == OverrideType.fullClosure)) {
      return [];
    }

    final customHoursOverrides = matchingOverrides
        .where((o) => o.type == OverrideType.customOpenHours)
        .toList();
    final maintenanceOverrides = matchingOverrides
        .where((o) => o.type == OverrideType.maintenanceWindow)
        .toList();

    final ScheduleOverride? customHoursOverride =
        customHoursOverrides.isNotEmpty ? customHoursOverrides.first : null;

    // If no custom open hours override exists, respect regular closed days of week.
    if (customHoursOverride == null &&
        settings != null &&
        settings.operatingHoursEnabled &&
        settings.closedDaysOfWeek.contains(date.weekday)) {
      return [];
    }

    int openHour = 8;
    int closeHour = 20;

    if (customHoursOverride != null) {
      if (customHoursOverride.startMinutes != null) {
        openHour = customHoursOverride.startMinutes! ~/ 60;
      }
      if (customHoursOverride.endMinutes != null) {
        closeHour = (customHoursOverride.endMinutes! / 60.0).ceil();
      }
    } else if (settings != null && settings.operatingHoursEnabled) {
      if (settings.dailyOpenTime != null) {
        final parts = settings.dailyOpenTime!.split(':');
        if (parts.isNotEmpty) openHour = int.tryParse(parts[0]) ?? openHour;
      }
      if (settings.dailyCloseTime != null) {
        final parts = settings.dailyCloseTime!.split(':');
        if (parts.isNotEmpty) closeHour = int.tryParse(parts[0]) ?? closeHour;
      }
    }

    final slots = <Map<String, dynamic>>[];
    for (int hour = openHour; hour < closeHour; hour++) {
      // If targetDate is today, skip past hours
      if (isToday && now.hour >= hour) {
        continue;
      }

      // Skip any slot overlapping an active maintenance window override
      final slotStartMins = hour * 60;
      final slotEndMins = (hour + 1) * 60;
      bool blockedByMaintenance = false;
      for (final m in maintenanceOverrides) {
        final sMins = m.startMinutes ?? 0;
        final eMins = m.endMinutes ?? 1439;
        if (slotStartMins < eMins && slotEndMins > sMins) {
          blockedByMaintenance = true;
          break;
        }
      }
      if (blockedByMaintenance) continue;

      final displayStart = _formatHour(hour);
      final displayEnd = _formatHour(hour + 1);
      final label = '$displayStart – $displayEnd';
      slots.add({
        'value': displayStart,
        'label': label,
        'hour': hour,
      });
    }
    return slots;
  }

  static String _formatHour(int hour) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:00 $period';
  }
}
