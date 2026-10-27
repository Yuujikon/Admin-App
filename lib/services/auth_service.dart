import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Authentication service for handling admin PIN verification and Firebase Auth.
class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  static const String _keyFailedAttempts = 'admin_pin_failed_attempts';
  static const String _keyLockoutUntil = 'admin_pin_lockout_until';
  static const int maxFailedAttempts = 5;
  static const int lockoutDurationSeconds = 30;

  /// Returns true if the PIN entry is currently locked out.
  Future<bool> isLockedOut() async {
    final seconds = await getRemainingLockoutSeconds();
    return seconds > 0;
  }

  /// Returns remaining lockout time in seconds, or 0 if not locked out.
  Future<int> getRemainingLockoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntil = prefs.getInt(_keyLockoutUntil) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lockoutUntil > now) {
      return ((lockoutUntil - now) / 1000).ceil();
    }
    return 0;
  }

  /// Returns current count of consecutive failed attempts.
  Future<int> getFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyFailedAttempts) ?? 0;
  }

  /// Records a failed PIN login attempt. Returns updated attempt info and lockout state.
  Future<Map<String, dynamic>> recordFailedAttempt({
    int maxAttempts = maxFailedAttempts,
    int cooldownSeconds = lockoutDurationSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    int failed = (prefs.getInt(_keyFailedAttempts) ?? 0) + 1;
    bool isNowLockedOut = false;
    int remainingSeconds = 0;

    if (failed >= maxAttempts) {
      final lockoutUntil =
          DateTime.now().millisecondsSinceEpoch + (cooldownSeconds * 1000);
      await prefs.setInt(_keyLockoutUntil, lockoutUntil);
      isNowLockedOut = true;
      remainingSeconds = cooldownSeconds;
    } else {
      await prefs.setInt(_keyFailedAttempts, failed);
    }

    return {
      'failedAttempts': failed,
      'isLockedOut': isNowLockedOut,
      'remainingAttempts': (maxAttempts - failed).clamp(0, maxAttempts),
      'remainingSeconds': remainingSeconds,
    };
  }

  /// Resets failed attempt counter and clears lockout status.
  Future<void> resetFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFailedAttempts);
    await prefs.remove(_keyLockoutUntil);
  }

  /// Verifies if the provided [pin] matches the stored admin PIN in local storage or user's Firestore profile.
  Future<bool> verifyPin(String pin) async {
    if (await isLockedOut()) return false;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('admin_pin') ?? '1234';
    if (pin == stored) return true;

    // Check currently logged in user's PIN in Firestore
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final userPin = doc.data()?['pin']?.toString();
          if (userPin != null && userPin == pin) {
            return true;
          }
        }
      } catch (e) {
        debugPrint('Error verifying Firestore PIN: $e');
      }
    }

    return false;
  }

  /// Updates the stored admin PIN in local preferences to [newPin].
  Future<void> changePin(String newPin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_pin', newPin);
    await resetFailedAttempts();
  }

  /// Authenticates a user with Firebase Authentication using [email] and [password].
  Future<void> loginToFirebase(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Returns true if a Firebase user is currently signed in.
  bool get isFirebaseAuthenticated => _auth.currentUser != null;

  /// Returns the email address of the currently signed-in Firebase user, or null if unauthenticated.
  String? get currentUserEmail => _auth.currentUser?.email;

  /// Retrieves the saved admin email from local preferences.
  Future<String?> getAdminEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('admin_email');
  }

  /// Saves the active admin [email] into local preferences.
  Future<void> setAdminEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_email', email);
  }
}
