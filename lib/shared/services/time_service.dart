import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Centralized Time Simulation & Fast-Forward Control Service.
///
/// Enables capstone testing and demonstration of time-dependent features
/// such as perishable batch expirations, store operating hours, order timeouts,
/// shift durations, and automated daily/monthly metrics.
///
/// Real-time synchronization is maintained with Cloud Firestore under `system_config/time_simulation`
/// so time skips on the Admin App immediately affect all connected Customer Apps and Admin instances.
class TimeService extends ChangeNotifier {
  static final TimeService instance = TimeService._internal();

  factory TimeService() => instance;

  TimeService._internal() {
    _initRealtimeSync();
  }

  Duration _offset = Duration.zero;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _syncSubscription;

  /// Current simulated DateTime adding active fast-forward offset to real-world time.
  static DateTime get now => DateTime.now().add(instance._offset);

  /// Active time simulation offset from real-world time.
  Duration get offset => _offset;

  /// Returns true if time is currently being fast-forwarded or simulated.
  bool get isSimulated => _offset != Duration.zero;

  /// Initializes real-time listener to Firestore system config to sync time travel with Customer app.
  void _initRealtimeSync() {
    try {
      _syncSubscription = FirebaseFirestore.instance
          .collection('system_config')
          .doc('time_simulation')
          .snapshots()
          .listen((doc) {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final mins = (data['offsetMinutes'] as num? ?? 0).toInt();
          if (_offset.inMinutes != mins) {
            _offset = Duration(minutes: mins);
            notifyListeners();
          }
        }
      }, onError: (e) {
        debugPrint('TimeService Sync Error: $e');
      });
    } catch (e) {
      debugPrint('TimeService Init Error: $e');
    }
  }

  /// Pushes updated offset in minutes to Firestore so all Customer apps update in real time.
  Future<void> _pushOffsetToFirestore(int minutes) async {
    try {
      await FirebaseFirestore.instance
          .collection('system_config')
          .doc('time_simulation')
          .set({
        'offsetMinutes': minutes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to sync time simulation offset to Firestore: $e');
    }
  }

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

  /// Fast-forwards simulated time by specified minutes and syncs with Customer App.
  void addMinutes(int mins) {
    _offset += Duration(minutes: mins);
    notifyListeners();
    _pushOffsetToFirestore(_offset.inMinutes);
  }

  /// Fast-forwards simulated time by specified hours and syncs with Customer App.
  void addHours(int hours) {
    _offset += Duration(hours: hours);
    notifyListeners();
    _pushOffsetToFirestore(_offset.inMinutes);
  }

  /// Fast-forwards simulated time by specified days and syncs with Customer App.
  void addDays(int days) {
    _offset += Duration(days: days);
    notifyListeners();
    _pushOffsetToFirestore(_offset.inMinutes);
  }

  /// Explicitly sets the time simulation offset and syncs with Customer App.
  void setOffset(Duration newOffset) {
    _offset = newOffset;
    notifyListeners();
    _pushOffsetToFirestore(_offset.inMinutes);
  }

  /// Resets simulated time back to real-world clock (zero offset) and syncs with Customer App.
  void reset() {
    _offset = Duration.zero;
    notifyListeners();
    _pushOffsetToFirestore(0);
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
