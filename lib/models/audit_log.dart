import 'package:cloud_firestore/cloud_firestore.dart';

class AuditLog {
  final String id;
  final Timestamp timestamp;
  final String actorId;
  final String actorEmail;
  final String? actorName;
  final String actorRole;
  final String module;
  final String action;
  final String targetId;
  final String targetName;
  final String summary;
  final Map<String, dynamic>? beforeData;
  final Map<String, dynamic>? afterData;

  AuditLog({
    required this.id,
    required this.timestamp,
    required this.actorId,
    required this.actorEmail,
    this.actorName,
    required this.actorRole,
    required this.module,
    required this.action,
    required this.targetId,
    required this.targetName,
    required this.summary,
    this.beforeData,
    this.afterData,
  });

  factory AuditLog.fromMap(Map<String, dynamic> data, String documentId) {
    return AuditLog(
      id: documentId,
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      actorId: data['actorId'] ?? '',
      actorEmail: data['actorEmail'] ?? '',
      actorName: data['actorName'] as String?,
      actorRole: data['actorRole'] ?? '',
      module: data['module'] ?? '',
      action: data['action'] ?? '',
      targetId: data['targetId'] ?? '',
      targetName: data['targetName'] ?? '',
      summary: data['summary'] ?? '',
      beforeData: data['beforeData'] as Map<String, dynamic>?,
      afterData: data['afterData'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': FieldValue.serverTimestamp(),
      'actorId': actorId,
      'actorEmail': actorEmail,
      if (actorName != null) 'actorName': actorName,
      'actorRole': actorRole,
      'module': module,
      'action': action,
      'targetId': targetId,
      'targetName': targetName,
      'summary': summary,
      if (beforeData != null) 'beforeData': beforeData,
      if (afterData != null) 'afterData': afterData,
    };
  }
}
