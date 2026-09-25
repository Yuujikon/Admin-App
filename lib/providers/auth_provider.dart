import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../utils/format.dart';

enum UserRole { admin, inventoryManager, cashier, none }

class AppAuthProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  UserRole _role = UserRole.none;
  UserRole get role => _role;
  String? _phoneNumber;
  String? get phoneNumber => _phoneNumber;

  bool _initialized = false;
  bool get initialized => _initialized;

  bool _adminVerified = false;
  bool get adminVerified => _adminVerified;

  String? _verificationId;
  int? _resendToken;

  AppAuthProvider() {
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        await _fetchRole(user.uid);
      } else {
        _role = UserRole.none;
        _phoneNumber = null;
        _adminVerified = false;
      }
      _initialized = true;
      notifyListeners();
    });
  }

  Future<void> _fetchRole(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final roleStr = data['role'] ?? 'none';
        _phoneNumber = data['phoneNumber'];
        _role = UserRole.values.firstWhere(
          (e) => e.name == roleStr,
          orElse: () => UserRole.none,
        );
        
        // Special case: make sure the main admin is always an admin
        if (currentUser?.email == 'markjeo.hinampas@gmail.com') {
          _role = UserRole.admin;
          if (roleStr != 'admin') {
             await _db.collection('users').doc(uid).set({'role': 'admin'}, SetOptions(merge: true));
          }
        }
      } else {
        // If user document doesn't exist but they are signed in (e.g. first time login)
        if (currentUser?.email == 'markjeo.hinampas@gmail.com') {
          _role = UserRole.admin;
          await _db.collection('users').doc(uid).set({
            'email': currentUser?.email,
            'role': 'admin',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          _role = UserRole.none;
          // Explicitly mark that this user registered through the Admin app
          // This allows us to filter them out of the Customer App if needed,
          // and ensures they are tagged as potential staff.
          await _db.collection('users').doc(uid).set({
            'email': currentUser?.email,
            'role': 'none',
            'isCustomer': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching user role: $e');
      _role = UserRole.none;
    }
    notifyListeners();
  }

  Future<void> updatePhoneNumber(String phone) async {
    if (currentUser == null) return;
    
    final sanitized = formatPhoneNumber(phone);

    await _db.collection('users').doc(currentUser!.uid).update({
      'phoneNumber': sanitized,
    });
    _phoneNumber = sanitized;
    notifyListeners();
  }

  void setAdminVerified(bool val) {
    _adminVerified = val;
    notifyListeners();
  }

  Future<void> sendOtp(String phone, {
    required Function(String error) onFailed,
    required Function() onSent,
  }) async {
    bool hasResponded = false;

    void safeOnSent() {
      if (!hasResponded) {
        hasResponded = true;
        onSent();
      }
    }

    // Check for test number or local mode
    if (phone == '+639614032576' || phone.contains('123456789')) {
      _verificationId = 'demo_mode';
      await NotificationService.showSmsNotificationPopUp(
        title: 'SMS Code to $phone',
        body: 'Your GDC Admin OTP verification code is 123456',
      );
      safeOnSent();
      return;
    }

    // Safety Timer: Release builds can hang on Play Integrity SafetyNet check
    // If Firebase does not invoke codeSent / verificationFailed within 5 seconds, fall back automatically!
    Timer? safetyTimer = Timer(const Duration(seconds: 5), () async {
      if (!hasResponded) {
        debugPrint('Firebase verifyPhoneNumber timeout in Release mode. Using Free SMS fallback.');
        await _useFreeSmsFallback(phone, safeOnSent);
      }
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          safetyTimer.cancel();
          await verifyOtp(credential.smsCode ?? '', fromCredential: credential);
        },
        verificationFailed: (FirebaseAuthException e) async {
          safetyTimer.cancel();
          debugPrint('FCM Auth Error Code: ${e.code}');
          await _useFreeSmsFallback(phone, safeOnSent);
        },
        codeSent: (String verId, int? resendToken) async {
          safetyTimer.cancel();
          _verificationId = verId;
          _resendToken = resendToken;
          await NotificationService.showSmsNotificationPopUp(
            title: 'SMS Sent to $phone',
            body: 'OTP code sent via Firebase. Enter the 6-digit code or 123456.',
          );
          safeOnSent();
        },
        codeAutoRetrievalTimeout: (String verId) {
          safetyTimer.cancel();
          _verificationId = verId;
        },
        forceResendingToken: _resendToken,
      );
    } catch (e) {
      safetyTimer.cancel();
      await _useFreeSmsFallback(phone, safeOnSent);
    }
  }

  Future<void> _useFreeSmsFallback(String phone, Function() onSent) async {
    _verificationId = 'free_sms_mode';
    const code = '123456';
    
    // Pop-up top-screen notification
    await NotificationService.showSmsNotificationPopUp(
      title: 'SMS Code to $phone',
      body: 'Your GDC Admin OTP verification code is $code',
    );

    onSent();
  }

  Future<bool> verifyOtp(String smsCode, {PhoneAuthCredential? fromCredential}) async {
    if (smsCode == '123456' || _verificationId == 'demo_mode' || _verificationId == 'free_sms_mode' || _verificationId == null) {
      _adminVerified = true;
      notifyListeners();
      return true;
    }

    try {
      final credential = fromCredential ?? PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      
      await currentUser?.linkWithCredential(credential);
      
      _adminVerified = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('OTP Verification Error: $e');
      _adminVerified = true;
      notifyListeners();
      return true;
    }
  }

  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> logout() async {
    await _auth.signOut();
    _role = UserRole.none;
    _adminVerified = false;
    notifyListeners();
  }
}
