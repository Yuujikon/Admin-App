class StoreHours {
  // Current active store hours for pickup
  static const int openHour  = 9;  // 9:00 AM
  static const int closeHour = 22; // 10:00 PM

  /// Checks if the store is currently within active pickup hours.
  static bool isOpen() {
    final h = DateTime.now().hour;
    return h >= openHour && h < closeHour;
  }

  static List<Map<String, dynamic>> availableSlots() {
    final now = DateTime.now().hour;
    return [
      {'value': '11:00 AM', 'label': '11:00 AM – 12:00 PM', 'hour': 11},
      {'value': '12:00 PM', 'label': '12:00 PM – 1:00 PM',  'hour': 12},
      {'value': '1:00 PM',  'label': '1:00 PM – 2:00 PM',   'hour': 13},
      {'value': '2:00 PM',  'label': '2:00 PM – 3:00 PM',   'hour': 14},
      {'value': '3:00 PM',  'label': '3:00 PM (Last slot)',  'hour': 15},
    ].where((s) => now < (s['hour'] as int)).toList();
  }
}