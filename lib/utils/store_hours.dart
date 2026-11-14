import '../models/store_settings.dart';
import '../shared/services/time_service.dart';

/// Utility class for checking store open/closed status and pickup schedule slots.
class StoreHours {
  /// Dynamically checks if the store is currently (or on a target date) within active operating/pickup hours.
  static bool isOpen([StoreSettings? settings, DateTime? date]) {
    final checkTime = date ?? TimeService.now;
    if (settings != null) {
      if (settings.isClosed) return false;

      // Check date-range schedule overrides first
      for (final override in settings.overrides) {
        if (override.appliesToDate(checkTime)) {
          return !override.isDateTimeClosed(checkTime);
        }
      }

      return !settings.effectivelyClosed;
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

    // Check if there is a ScheduleOverride active for targetDate
    ScheduleOverride? override;
    if (settings != null) {
      for (final o in settings.overrides) {
        if (o.appliesToDate(date)) {
          override = o;
          break;
        }
      }
    }

    if (override != null) {
      if (override.type == OverrideType.fullClosure) {
        return []; // Closed all day
      }
    } else if (settings != null && settings.effectivelyClosed && isToday) {
      return [];
    }

    int openHour = 8;
    int closeHour = 20;

    if (override != null && override.type == OverrideType.customOpenHours) {
      if (override.startMinutes != null) {
        openHour = override.startMinutes! ~/ 60;
      }
      if (override.endMinutes != null) {
        closeHour = (override.endMinutes! / 60.0).ceil();
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

      // If maintenance window override applies, skip maintenance hours
      if (override != null && override.type == OverrideType.maintenanceWindow) {
        final slotStartMins = hour * 60;
        final slotEndMins = (hour + 1) * 60;
        final sMins = override.startMinutes ?? 0;
        final eMins = override.endMinutes ?? 1439;
        if (slotStartMins >= sMins && slotEndMins <= eMins) {
          continue; // Skip maintenance slot
        }
      }

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
