import 'package:cloud_firestore/cloud_firestore.dart';

class StoreSettings {
  final bool isClosed;
  final String? closureMessage;
  final DateTime? scheduledCloseAt;
  final DateTime? scheduledOpenAt;

  final String? announcement;

  // Expiration windows in hours
  final int perishableWindowHours;
  final int mixedWindowHours;
  final int standardWindowHours;

  const StoreSettings({
    required this.isClosed,
    this.closureMessage,
    this.scheduledCloseAt,
    this.scheduledOpenAt,
    this.perishableWindowHours = 2,
    this.mixedWindowHours = 24,
    this.standardWindowHours = 72,
    this.announcement,
  });

  factory StoreSettings.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return StoreSettings(
      isClosed: d['isClosed'] ?? false,
      closureMessage: d['closureMessage'],
      scheduledCloseAt: (d['scheduledCloseAt'] as Timestamp?)?.toDate(),
      scheduledOpenAt: (d['scheduledOpenAt'] as Timestamp?)?.toDate(),
      perishableWindowHours: d['perishableWindowHours'] ?? 2,
      mixedWindowHours: d['mixedWindowHours'] ?? 24,
      standardWindowHours: d['standardWindowHours'] ?? 72,
      announcement: d['announcement'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'isClosed': isClosed,
    'closureMessage': closureMessage,
    'scheduledCloseAt': scheduledCloseAt != null ? Timestamp.fromDate(scheduledCloseAt!) : null,
    'scheduledOpenAt': scheduledOpenAt != null ? Timestamp.fromDate(scheduledOpenAt!) : null,
    'perishableWindowHours': perishableWindowHours,
    'mixedWindowHours': mixedWindowHours,
    'standardWindowHours': standardWindowHours,
    'announcement': announcement,
  };

  bool get effectivelyClosed {
    if (isClosed) return true;
    final now = DateTime.now();
    if (scheduledCloseAt != null && scheduledOpenAt != null) {
      return now.isAfter(scheduledCloseAt!) && now.isBefore(scheduledOpenAt!);
    }
    return false;
  }
}
