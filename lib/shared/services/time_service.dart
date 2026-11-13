import 'package:flutter/foundation.dart';

/// Centralized Time Simulation & Fast-Forward Control Service.
///
/// Enables capstone testing and demonstration of time-dependent features
/// such as perishable batch expirations, store operating hours, order timeouts,
/// shift durations, and automated daily/monthly metrics.
class TimeService extends ChangeNotifier {
  static final TimeService instance = TimeService._internal();

  factory TimeService() => instance;

  TimeService._internal();

  Duration _offset = Duration.zero;

  /// Current simulated DateTime adding active fast-forward offset to real-world time.
  static DateTime get now => DateTime.now().add(instance._offset);

  /// Active time simulation offset from real-world time.
  Duration get offset => _offset;

  /// Returns true if time is currently being fast-forwarded or simulated.
  bool get isSimulated => _offset != Duration.zero;

  /// Human-readable representation of active fast-forward offset (e.g., "+30m", "+2h", "+1d").
  String get formattedOffset {
    if (!isSimulated) return 'Real-Time';
    final totalMins = _offset.inMinutes;
    if (totalMins.abs() < 60) {
      return '${totalMins >= 0 ? '+' : ''}${totalMins}m';
    }
    final totalHours = _offset.inHours;
    if (totalHours.abs() < 24) {
      final remainingMins = totalMins.abs() % 60;
      final minStr = remainingCountStr(remainingMins);
      return '${totalHours >= 0 ? '+' : ''}${totalHours}h$minStr';
    }
    final totalDays = _offset.inDays;
    final remainingHours = totalHours.abs() % 24;
    final hourStr = remainingHours > 0 ? '${remainingHours}h' : '';
    return '${totalDays >= 0 ? '+' : ''}${totalDays}d$hourStr';
  }

  String remainingCountStr(int mins) => mins > 0 ? '${mins}m' : '';

  /// Fast-forwards simulated time by specified minutes.
  void addMinutes(int mins) {
    _offset += Duration(minutes: mins);
    notifyListeners();
  }

  /// Fast-forwards simulated time by specified hours.
  void addHours(int hours) {
    _offset += Duration(hours: hours);
    notifyListeners();
  }

  /// Fast-forwards simulated time by specified days.
  void addDays(int days) {
    _offset += Duration(days: days);
    notifyListeners();
  }

  /// Explicitly sets the time simulation offset.
  void setOffset(Duration newOffset) {
    _offset = newOffset;
    notifyListeners();
  }

  /// Resets simulated time back to real-world clock (zero offset).
  void reset() {
    _offset = Duration.zero;
    notifyListeners();
  }
}
