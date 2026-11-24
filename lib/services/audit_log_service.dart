import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/audit_log.dart';

class AuditLogService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> logAction({
    required String module,
    required String action,
    required String targetId,
    required String targetName,
    required String summary,
    Map<String, dynamic>? beforeData,
    Map<String, dynamic>? afterData,
    WriteBatch? batch,
    Transaction? transaction,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('Cannot log action: No user signed in.');
        return;
      }

      String role = 'unknown';
      String? name;
      try {
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          role = userDoc.data()?['role'] ?? 'none';
          name = userDoc.data()?['name'];
        }
      } catch (e) {
        debugPrint('Failed to fetch user role for audit log: $e');
      }

      final logRef = _firestore.collection('audit_logs').doc();
      final auditLog = AuditLog(
        id: logRef.id,
        timestamp:
            Timestamp.now(), // Will be overwritten by serverTimestamp in toMap
        actorId: user.uid,
        actorEmail: user.email ?? 'Unknown',
        actorName: name,
        actorRole: role,
        module: module,
        action: action,
        targetId: targetId,
        targetName: targetName,
        summary: summary,
        beforeData: beforeData,
        afterData: afterData,
      );

      if (batch != null) {
        batch.set(logRef, auditLog.toMap());
      } else if (transaction != null) {
        transaction.set(logRef, auditLog.toMap());
      } else {
        await logRef.set(auditLog.toMap());
      }
    } catch (e) {
      debugPrint('Error logging action: $e');
    }
  }

  Stream<List<AuditLog>> getAuditLogs({int limit = 50}) {
    return _firestore
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => AuditLog.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<List<AuditLog>> fetchAuditLogs(
      {int limit = 50, DocumentSnapshot? startAfter}) async {
    Query query = _firestore
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) =>
            AuditLog.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }
}
