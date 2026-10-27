import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/auth_service.dart';
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

  String _status = 'none';

  /// Active user approval status ('pending', 'approved', 'denied', 'none').
  String get status => _status;

  /// True if account is waiting for admin approval.
  bool get isPending => _status == 'pending';

  /// True if account access was denied or revoked.
  bool get isDenied => _status == 'denied';

  /// True if account is approved by admin.
  bool get isApproved => _status == 'approved';

  String? _userFullName;

  /// Active user full name.
  String? get userFullName => _userFullName;

  String? _requestedRole;

  /// Requested employee role during registration.
  String? get requestedRole => _requestedRole;

  /// True if user's email address has been verified.
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  String? _phoneNumber;

  /// User contact phone number.
  String? get phoneNumber => _phoneNumber;

  String? _userPin;

  /// Active 4-digit security PIN for employee account.
  String? get userPin => _userPin;

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
        _status = 'none';
        _userFullName = null;
        _requestedRole = null;
        _phoneNumber = null;
        _userPin = null;
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
        final statusVal = data['status'] as String?;

        _userFullName = data['name'] as String?;
        _requestedRole = data['requestedRole'] as String?;
        _phoneNumber = data['phoneNumber'];
        _userPin = data['pin'] as String?;
        _totpSecret = data['totpSecret'];
        _isTotpLinked = data['totpLinked'] == true;
        _totpEnabled = data['totpEnabled'] ?? true;

        if (_totpSecret == null || _totpSecret!.isEmpty || data['isCustomer'] == null) {
          _totpSecret = _totpSecret ?? TotpUtils.generateSecret();
          await _db.collection('users').doc(uid).set({
            'totpSecret': _totpSecret,
            'isCustomer': false,
            if (data['status'] == null) 'status': roleStr == 'none' ? 'pending' : 'approved',
          }, SetOptions(merge: true));
        }

        if (isDisabled || statusVal == 'denied') {
          _role = UserRole.none;
          _status = 'denied';
        } else if (statusVal == 'pending' || roleStr == 'none') {
          _role = UserRole.none;
          _status = 'pending';
        } else {
          _status = 'approved';
          _role = UserRole.values.firstWhere(
            (e) => e.name == roleStr,
            orElse: () => UserRole.none,
          );
        }
      } else {
        _totpSecret = TotpUtils.generateSecret();
        if (currentUser?.email == 'markjeo.hinampas@gmail.com') {
          _role = UserRole.admin;
          _status = 'approved';
          await _db.collection('users').doc(uid).set({
            'email': currentUser?.email,
            'role': 'admin',
            'status': 'approved',
            'isCustomer': false,
            'isDisabled': false,
            'totpSecret': _totpSecret,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          _role = UserRole.none;
          _status = 'pending';
          await _db.collection('users').doc(uid).set({
            'email': currentUser?.email,
            'role': 'none',
            'status': 'pending',
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
      _status = 'none';
      _initialized = true;
      notifyListeners();
    });
  }

  /// Registers a new employee credentials with Firebase Auth, sends verification email,
  /// and creates initial Firestore pending user document.
  Future<void> registerEmployee({
    required String name,
    required String email,
    required String password,
    required String requestedRole,
  }) async {
    final userCred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );

    final user = userCred.user;
    if (user != null) {
      await user.sendEmailVerification().catchError((e) {
        debugPrint('Error sending verification email: $e');
      });

      _totpSecret = TotpUtils.generateSecret();
      await _db.collection('users').doc(user.uid).set({
        'name': name.trim(),
        'email': email.trim(),
        'role': 'none',
        'requestedRole': requestedRole,
        'status': 'pending',
        'isDisabled': false,
        'isCustomer': false,
        'authMethod': 'email',
        'totpSecret': _totpSecret,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Resends account verification email link to the active user.
  Future<void> resendEmailVerification() async {
    final user = currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  /// Signs in or registers user via Google Auth.
  /// Returns true if user document exists (returning user), false if first-time user who needs profile setup.
  Future<bool> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in was cancelled.');
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCred =
        await _auth.signInWithCredential(credential);
    final user = userCred.user;

    if (user != null) {
      final doc = await _db.collection('users').doc(user.uid).get();
      return doc.exists;
    }
    return false;
  }

  /// Completes registration details for a first-time Google Sign-In user.
  Future<void> completeGoogleRegistration({
    required String name,
    required String requestedRole,
  }) async {
    final user = currentUser;
    if (user == null) return;

    _totpSecret = TotpUtils.generateSecret();
    await _db.collection('users').doc(user.uid).set({
      'name': name.trim(),
      'email': user.email,
      'role': 'none',
      'requestedRole': requestedRole,
      'status': 'pending',
      'isDisabled': false,
      'isCustomer': false,
      'authMethod': 'google',
      'totpSecret': _totpSecret,
      'createdAt': FieldValue.serverTimestamp(),
    });
    notifyListeners();
  }

  /// Triggers a manual refresh of the user document permissions.
  Future<void> refreshRole() async {
    final user = currentUser;
    if (user != null) {
      await user.reload();
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

  /// Updates current user 4-digit security PIN in Firestore and local storage.
  Future<void> updateUserPin(String newPin) async {
    final user = currentUser;
    if (user == null) return;

    final trimmed = newPin.trim();
    await _db.collection('users').doc(user.uid).set({
      'pin': trimmed,
    }, SetOptions(merge: true));

    await AuthService().changePin(trimmed);
    _userPin = trimmed;
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
    _status = 'none';
    _adminVerified = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }
}
