import 'package:cloud_firestore/cloud_firestore.dart';

class StoreSettings {
  final bool isClosed;
  final String? closureMessage;
  final DateTime? scheduledCloseAt;
  final DateTime? scheduledOpenAt;

  const StoreSettings({
    required this.isClosed,
    this.closureMessage,
    this.scheduledCloseAt,
    this.scheduledOpenAt,
  });

  factory StoreSettings.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return StoreSettings(
      isClosed: d['isClosed'] ?? false,
      closureMessage: d['closureMessage'],
      scheduledCloseAt: (d['scheduledCloseAt'] as Timestamp?)?.toDate(),
      scheduledOpenAt: (d['scheduledOpenAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'isClosed': isClosed,
    'closureMessage': closureMessage,
    'scheduledCloseAt': scheduledCloseAt != null ? Timestamp.fromDate(scheduledCloseAt!) : null,
    'scheduledOpenAt': scheduledOpenAt != null ? Timestamp.fromDate(scheduledOpenAt!) : null,
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
