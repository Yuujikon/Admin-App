import '../models/store_settings.dart';

class StoreHours {
  /// Dynamically checks if the store is currently within active operating/pickup hours.
  static bool isOpen([StoreSettings? settings]) {
    if (settings != null) {
      return !settings.effectivelyClosed;
    }
    final h = DateTime.now().hour;
    return h >= 8 && h < 21; // Default fallback: 8:00 AM - 9:00 PM
  }

  /// Dynamically generates available pickup slots based on store settings and schedule.
  static List<Map<String, dynamic>> availableSlots([StoreSettings? settings]) {
    final now = DateTime.now();

    if (settings != null && settings.effectivelyClosed) {
      return []; // No slots available when store is closed
    }

    int openHour = 8;
    int closeHour = 20;

    if (settings != null && settings.operatingHoursEnabled) {
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
      if (now.hour < hour) {
        final displayStart = _formatHour(hour);
        final displayEnd = _formatHour(hour + 1);
        final label = '$displayStart – $displayEnd';
        slots.add({
          'value': displayStart,
          'label': label,
          'hour': hour,
        });
      }
    }
    return slots;
  }

  static String _formatHour(int hour) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:00 $period';
  }
}
