import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Companion utility for seeding and maintaining primary Admin account roles.
class AdminSeeder {
  static const String primaryAdminEmail = 'markjeo.hinampas@gmail.com';

  /// Ensures the primary store owner account is guaranteed the 'admin' role in Firestore.
  static Future<void> seedPrimaryAdmin(User user) async {
    if (user.email != primaryAdminEmail) return;

    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists || doc.data()?['role'] != 'admin' || doc.data()?['isDisabled'] == true) {
        await docRef.set({
          'email': user.email,
          'role': 'admin',
          'isDisabled': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('AdminSeeder: Primary Admin profile verified for ${user.email} ✅');
      }
    } catch (e) {
      debugPrint('AdminSeeder Error: $e');
    }
  }
}
