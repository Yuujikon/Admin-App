import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/format.dart';
import '../utils/totp.dart';

/// User role authorization levels.
enum UserRole { admin, inventoryManager, cashier, none }

/// Authentication provider managing Firebase Auth state, user roles, phone numbers, and TOTP 2FA.
class AppAuthProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  /// Returns currently signed in Firebase user.
  User? get currentUser => _auth.currentUser;

  UserRole _role = UserRole.none;

  /// Active user role.
  UserRole get role => _role;

  String? _phoneNumber;

  /// User contact phone number.
  String? get phoneNumber => _phoneNumber;

  String? _totpSecret;

  /// Active 2FA secret key.
  String get totpSecret => _totpSecret ?? 'JBSWY3DPEHPK3PXP';

  bool _isTotpLinked = false;

  /// True if TOTP authenticator app link is confirmed.
  bool get isTotpLinked => _isTotpLinked;

  bool _totpEnabled = true;

  /// True if 2FA verification is enforced for login.
  bool get totpEnabled => _totpEnabled;

  bool _initialized = false;

  /// True when initial auth and role state fetching is complete.
  bool get initialized => _initialized;

  bool _adminVerified = false;

  /// True if staff user has successfully completed TOTP/PIN verification for active session.
  bool get adminVerified => _adminVerified;

  StreamSubscription<DocumentSnapshot>? _userSub;

  /// Initializes authentication state listeners.
  AppAuthProvider() {
    _auth.authStateChanges().listen((user) {
      _userSub?.cancel();
      if (user != null) {
        _listenToUserDoc(user.uid);
      } else {
        _role = UserRole.none;
        _phoneNumber = null;
        _totpSecret = null;
        _isTotpLinked = false;
        _totpEnabled = true;
        _adminVerified = false;
        _initialized = true;
        notifyListeners();
      }
    });
  }

  /// Establishes real-time listener on user metadata document in Firestore (`users/{uid}`).
  void _listenToUserDoc(String uid) {
    _userSub = _db.collection('users').doc(uid).snapshots().listen((doc) async {
      if (doc.exists) {
        final data = doc.data()!;
        final roleStr = data['role'] ?? 'none';
        final isDisabled = data['isDisabled'] == true;
        _phoneNumber = data['phoneNumber'];
        _totpSecret = data['totpSecret'];
        _isTotpLinked = data['totpLinked'] == true;
        _totpEnabled = data['totpEnabled'] ?? true;

        if (_totpSecret == null || _totpSecret!.isEmpty) {
          _totpSecret = TotpUtils.generateSecret();
          await _db.collection('users').doc(uid).set({
            'totpSecret': _totpSecret,
          }, SetOptions(merge: true));
        }

        if (isDisabled) {
          _role = UserRole.none;
        } else {
          _role = UserRole.values.firstWhere(
            (e) => e.name == roleStr,
            orElse: () => UserRole.none,
          );
        }

        // Special case: make sure the main admin is always an admin
        if (currentUser?.email == 'markjeo.hinampas@gmail.com') {
          _role = UserRole.admin;
          if (roleStr != 'admin' || isDisabled) {
            await _db.collection('users').doc(uid).set(
                {'role': 'admin', 'isDisabled': false},
                SetOptions(merge: true));
          }
        }
      } else {
        _totpSecret = TotpUtils.generateSecret();
        if (currentUser?.email == 'markjeo.hinampas@gmail.com') {
          _role = UserRole.admin;
          await _db.collection('users').doc(uid).set({
            'email': currentUser?.email,
            'role': 'admin',
            'isDisabled': false,
            'totpSecret': _totpSecret,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          _role = UserRole.none;
          await _db.collection('users').doc(uid).set({
            'email': currentUser?.email,
            'role': 'none',
            'isCustomer': false,
            'isDisabled': false,
            'totpSecret': _totpSecret,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
      _initialized = true;
      notifyListeners();
    }, onError: (e) {
      debugPrint('Error listening to user role: $e');
      _role = UserRole.none;
      _initialized = true;
      notifyListeners();
    });
  }

  /// Triggers a manual refresh of the user document permissions.
  Future<void> refreshRole() async {
    final user = currentUser;
    if (user != null) {
      _userSub?.cancel();
      _listenToUserDoc(user.uid);
    }
  }

  /// Updates current user phone number in Firestore.
  Future<void> updatePhoneNumber(String phone) async {
    if (currentUser == null) return;

    final sanitized = formatPhoneNumber(phone);

    await _db.collection('users').doc(currentUser!.uid).update({
      'phoneNumber': sanitized,
    });
    _phoneNumber = sanitized;
    notifyListeners();
  }

  /// Generates a new TOTP secret key for 2FA authenticator apps.
  Future<void> regenerateTotpSecret() async {
    if (currentUser == null) return;
    _totpSecret = TotpUtils.generateSecret();
    _isTotpLinked = false;
    await _db.collection('users').doc(currentUser!.uid).set({
      'totpSecret': _totpSecret,
      'totpLinked': false,
    }, SetOptions(merge: true));
    notifyListeners();
  }

  /// Updates TOTP 2FA enforcement setting.
  Future<void> setTotpEnabled(bool enabled) async {
    _totpEnabled = enabled;
    notifyListeners();
    if (currentUser != null) {
      await _db.collection('users').doc(currentUser!.uid).set({
        'totpEnabled': enabled,
      }, SetOptions(merge: true));
    }
  }

  /// Marks TOTP link setup as completed.
  Future<void> markTotpLinked() async {
    _isTotpLinked = true;
    notifyListeners();
    if (currentUser != null) {
      await _db.collection('users').doc(currentUser!.uid).set({
        'totpLinked': true,
      }, SetOptions(merge: true));
    }
  }

  /// Sets session 2FA/PIN verification status flag.
  void setAdminVerified(bool val) {
    _adminVerified = val;
    notifyListeners();
  }

  /// Formats TOTP URI string for QR code generation in Google Authenticator.
  Uri get totpUri {
    final email = currentUser?.email ?? 'User';
    return Uri.parse(
      'otpauth://totp/GDC%20Sari-Sari:${Uri.encodeComponent(email)}?secret=$totpSecret&issuer=GDC%20Sari-Sari',
    );
  }

  /// Verifies a 6-digit TOTP code generated by Google Authenticator app.
  bool verifyTotp(String code) {
    return TotpUtils.verifyTotpCode(totpSecret, code);
  }

  /// Authenticates user credentials with Firebase Auth.
  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Signs out current user and resets auth session flags.
  Future<void> logout() async {
    _userSub?.cancel();
    await _auth.signOut();
    _role = UserRole.none;
    _adminVerified = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }
}
