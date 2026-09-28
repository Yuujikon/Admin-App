import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/format.dart';
import '../utils/totp.dart';

enum UserRole { admin, inventoryManager, cashier, none }

class AppAuthProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  UserRole _role = UserRole.none;
  UserRole get role => _role;
  String? _phoneNumber;
  String? get phoneNumber => _phoneNumber;

  String? _totpSecret;
  String get totpSecret => _totpSecret ?? 'JBSWY3DPEHPK3PXP';

  bool _isTotpLinked = false;
  bool get isTotpLinked => _isTotpLinked;

  bool _totpEnabled = true;
  bool get totpEnabled => _totpEnabled;

  bool _initialized = false;
  bool get initialized => _initialized;

  bool _adminVerified = false;
  bool get adminVerified => _adminVerified;

  StreamSubscription<DocumentSnapshot>? _userSub;

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
            await _db.collection('users').doc(uid).set({'role': 'admin', 'isDisabled': false}, SetOptions(merge: true));
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

  Future<void> refreshRole() async {
    final user = currentUser;
    if (user != null) {
      _userSub?.cancel();
      _listenToUserDoc(user.uid);
    }
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

  Future<void> setTotpEnabled(bool enabled) async {
    _totpEnabled = enabled;
    notifyListeners();
    if (currentUser != null) {
      await _db.collection('users').doc(currentUser!.uid).set({
        'totpEnabled': enabled,
      }, SetOptions(merge: true));
    }
  }

  Future<void> markTotpLinked() async {
    _isTotpLinked = true;
    notifyListeners();
    if (currentUser != null) {
      await _db.collection('users').doc(currentUser!.uid).set({
        'totpLinked': true,
      }, SetOptions(merge: true));
    }
  }

  void setAdminVerified(bool val) {
    _adminVerified = val;
    notifyListeners();
  }

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

  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

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
