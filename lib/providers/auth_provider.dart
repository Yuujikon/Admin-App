import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/audit_log_service.dart';
import '../services/auth_service.dart';
import '../utils/admin_seeder.dart';
import '../utils/email_validator.dart';
import '../utils/format.dart';
import '../utils/totp.dart';

/// User role authorization levels.
enum UserRole { admin, trustedPartner, none }

/// Outcome of a Google Sign-In attempt.
enum GoogleSignInResult { returning, needsProfile, cancelled }

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

  /// True if user's email address has been verified via Firebase Auth.
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  bool _isEmailOtpVerified = false;

  /// True if user verified their email address via 6-digit Email OTP during registration.
  bool get isEmailOtpVerified => _isEmailOtpVerified;

  bool _needsProfileCompletion = false;

  /// True if a first-time Google Sign-In user must complete their staff profile before submission.
  bool get needsProfileCompletion => _needsProfileCompletion;

  bool _isLoadingProfile = false;

  /// True while fetching the signed-in user's Firestore profile document.
  bool get isLoadingProfile => _isLoadingProfile;

  bool _isRegisteringInProgress = false;

  String? _phoneNumber;

  /// User contact phone number.
  String? get phoneNumber => _phoneNumber;

  String? _userPin;

  /// Active 6-digit security PIN for employee account.
  String? get userPin => _userPin;

  List<String> _recoveryCodes = [];

  /// Active 8-character backup recovery codes for emergency admin PIN reset.
  List<String> get recoveryCodes => List.unmodifiable(_recoveryCodes);

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

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot>? _userSub;

  /// Initializes authentication state listeners.
  AppAuthProvider() {
    _authSub = _auth.authStateChanges().listen((user) {
      if (_isRegisteringInProgress) {
        if (user != null) {
          _isLoadingProfile = true;
          notifyListeners();
        }
        return;
      }

      _userSub?.cancel();
      _userSub = null;
      if (user != null) {
        _isLoadingProfile = true;
        notifyListeners();
        _listenToUserDoc(user.uid);
      } else {
        _resetLocalState();
        _initialized = true;
        notifyListeners();
      }
    });
  }

  void _resetLocalState() {
    _role = UserRole.none;
    _status = 'none';
    _userFullName = null;
    _requestedRole = null;
    _phoneNumber = null;
    _userPin = null;
    _recoveryCodes = [];
    _totpSecret = null;
    _isTotpLinked = false;
    _totpEnabled = true;
    _adminVerified = false;
    _isEmailOtpVerified = false;
    _needsProfileCompletion = false;
    _isLoadingProfile = false;
  }

  bool _isPrimaryAdminEmail(String? email) {
    return email?.trim().toLowerCase() ==
        AdminSeeder.primaryAdminEmail.toLowerCase();
  }

  /// Establishes real-time listener on user metadata document in Firestore (`users/{uid}`).
  void _listenToUserDoc(String uid) {
    _userSub?.cancel();
    _userSub = _db.collection('users').doc(uid).snapshots().listen((doc) async {
      if (doc.exists) {
        final data = doc.data()!;
        final roleStr = data['role'] ?? 'none';
        final isDisabled = data['isDisabled'] == true;
        final statusVal = data['status'] as String?;

        _needsProfileCompletion = false;
        _userFullName = data['name'] as String?;
        _requestedRole = data['requestedRole'] as String?;
        _phoneNumber = data['phoneNumber'] as String?;
        _userPin = data['pin'] as String?;
        _totpSecret = data['totpSecret'] as String?;
        _isTotpLinked = data['totpLinked'] == true;
        _totpEnabled = data['totpEnabled'] ?? true;
        _isEmailOtpVerified = data['emailOtpVerified'] == true;

        final rawCodes = data['recoveryCodes'];
        if (rawCodes is List) {
          _recoveryCodes = List<String>.from(rawCodes.map((e) => e.toString()));
        } else {
          _recoveryCodes = [];
        }

        if (_totpSecret == null ||
            _totpSecret!.isEmpty ||
            data['isCustomer'] == null) {
          _totpSecret = (_totpSecret == null || _totpSecret!.isEmpty)
              ? TotpUtils.generateSecret()
              : _totpSecret;
          await _db.collection('users').doc(uid).set({
            'totpSecret': _totpSecret,
            'isCustomer': false,
            if (data['status'] == null)
              'status': roleStr == 'none' ? 'pending' : 'approved',
          }, SetOptions(merge: true));
        }

        if (roleStr == 'admin' && _recoveryCodes.isEmpty) {
          _recoveryCodes = generateRecoveryCodes();
          await _db.collection('users').doc(uid).set({
            'recoveryCodes': _recoveryCodes,
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
          if (roleStr == 'admin') {
            _role = UserRole.admin;
          } else if (roleStr == 'trustedPartner' ||
              roleStr == 'cashier' ||
              roleStr == 'inventoryManager') {
            _role = UserRole.trustedPartner;
          } else {
            _role = UserRole.none;
          }
        }
      } else {
        final user = _auth.currentUser;
        if (_isPrimaryAdminEmail(user?.email)) {
          _totpSecret = TotpUtils.generateSecret();
          _role = UserRole.admin;
          _status = 'approved';
          _needsProfileCompletion = false;
          await _db.collection('users').doc(uid).set({
            'name': user?.displayName ?? 'Store Admin',
            'email': user?.email?.trim().toLowerCase(),
            'role': 'admin',
            'status': 'approved',
            'isCustomer': false,
            'isDisabled': false,
            'totpSecret': _totpSecret,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          final isGoogleUser =
              user?.providerData.any((p) => p.providerId == 'google.com') ??
                  false;
          if (isGoogleUser) {
            // Require first-time Google sign-in users to finish profile setup before creating doc.
            _role = UserRole.none;
            _status = 'none';
            _needsProfileCompletion = true;
          } else {
            _totpSecret = TotpUtils.generateSecret();
            _role = UserRole.none;
            _status = 'pending';
            _needsProfileCompletion = false;
            await _db.collection('users').doc(uid).set({
              'name': user?.displayName ?? '',
              'email': user?.email?.trim().toLowerCase(),
              'role': 'none',
              'requestedRole': 'trustedPartner',
              'status': 'pending',
              'isCustomer': false,
              'isDisabled': false,
              'totpSecret': _totpSecret,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }
      _isLoadingProfile = false;
      _initialized = true;
      notifyListeners();
    }, onError: (e) {
      debugPrint('Error listening to user role: $e');
      _role = UserRole.none;
      _status = 'none';
      _isLoadingProfile = false;
      _initialized = true;
      notifyListeners();
    });
  }

  /// Registers a new employee with Firebase Auth, sends verification email (when needed),
  /// and creates the initial Firestore user document without racing the auth listener.
  Future<void> registerEmployee({
    required String name,
    required String email,
    required String password,
    required String requestedRole,
    String? phoneNumber,
    bool verifiedViaEmailOtp = false,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedName = name.trim();
    final trimmedPass = password.trim();

    final emailErr = EmailValidator.validate(normalizedEmail);
    if (emailErr != null) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: emailErr,
      );
    }

    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      final phoneErr = validatePhoneNumber(phoneNumber);
      if (phoneErr != null) {
        throw FirebaseAuthException(
          code: 'invalid-phone-number',
          message: phoneErr,
        );
      }
    }

    _isRegisteringInProgress = true;
    try {
      final userCred = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: trimmedPass,
      );

      final user = userCred.user;
      if (user != null) {
        await user.updateDisplayName(trimmedName).catchError((e) {
          debugPrint('Error updating display name: $e');
        });

        final isPrimaryAdmin = _isPrimaryAdminEmail(normalizedEmail);

        if (!verifiedViaEmailOtp && !isPrimaryAdmin) {
          await user.sendEmailVerification().catchError((e) {
            debugPrint('Error sending verification email: $e');
          });
        }

        final sanitizedPhone =
            phoneNumber != null && phoneNumber.trim().isNotEmpty
                ? formatPhoneNumber(phoneNumber.trim())
                : null;

        _totpSecret = TotpUtils.generateSecret();
        _phoneNumber = sanitizedPhone;
        _isEmailOtpVerified = verifiedViaEmailOtp;

        await _db.collection('users').doc(user.uid).set({
          'name': trimmedName,
          'email': normalizedEmail,
          if (sanitizedPhone != null) 'phoneNumber': sanitizedPhone,
          'role': isPrimaryAdmin ? 'admin' : 'none',
          'requestedRole': isPrimaryAdmin ? 'admin' : requestedRole,
          'status': isPrimaryAdmin ? 'approved' : 'pending',
          'isDisabled': false,
          'isCustomer': false,
          'authMethod': 'email',
          'emailOtpVerified': verifiedViaEmailOtp,
          'totpSecret': _totpSecret,
          'createdAt': FieldValue.serverTimestamp(),
        });

        try {
          await AuditLogService().logAction(
            module: 'Auth',
            action: 'REGISTER',
            targetId: user.uid,
            targetName: normalizedEmail,
            summary:
                'New staff registration submitted for $trimmedName ($normalizedEmail)',
          );
        } catch (e) {
          debugPrint('Audit log error on register: $e');
        }
      }
    } finally {
      _isRegisteringInProgress = false;
      final user = _auth.currentUser;
      if (user != null) {
        _isLoadingProfile = true;
        _listenToUserDoc(user.uid);
      } else {
        _isLoadingProfile = false;
      }
    }
  }

  /// Lightweight check of Firebase Auth `emailVerified` status without
  /// tearing down or re-subscribing to Firestore.
  Future<bool> checkEmailVerificationStatus() async {
    final user = currentUser;
    if (user == null) return false;
    final wasVerified = user.emailVerified;
    try {
      await user.reload();
    } catch (e) {
      debugPrint('Error reloading user verification status: $e');
    }
    final isNowVerified = _auth.currentUser?.emailVerified ?? false;
    if (isNowVerified != wasVerified) {
      notifyListeners();
    }
    return isNowVerified;
  }

  /// Resends account verification email link to the active user.
  Future<void> resendEmailVerification() async {
    final user = currentUser;
    if (user != null) {
      await user.reload();
      if (!(_auth.currentUser?.emailVerified ?? false)) {
        await _auth.currentUser?.sendEmailVerification();
      }
      notifyListeners();
    }
  }

  /// Signs in or registers user via Google Auth.
  ///
  /// Returns [GoogleSignInResult.cancelled] if the user dismissed the Google picker,
  /// [GoogleSignInResult.returning] if the user already has a profile document,
  /// or [GoogleSignInResult.needsProfile] for first-time staff registrants.
  Future<GoogleSignInResult> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      return GoogleSignInResult.cancelled;
    }

    _isRegisteringInProgress = true;
    try {
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCred =
          await _auth.signInWithCredential(credential);
      final user = userCred.user;

      if (user == null) {
        return GoogleSignInResult.cancelled;
      }

      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) {
        _needsProfileCompletion = false;
        _isRegisteringInProgress = false;
        _isLoadingProfile = true;
        notifyListeners();
        _listenToUserDoc(user.uid);

        final email = user.email?.trim().toLowerCase() ?? 'Unknown';
        await AuthService().setAdminEmail(email);
        try {
          await AuditLogService().logAction(
            module: 'Auth',
            action: 'LOGIN',
            targetId: user.uid,
            targetName: email,
            summary: 'User $email signed in with Google',
          );
        } catch (e) {
          debugPrint('Audit log error on Google login: $e');
        }
        return GoogleSignInResult.returning;
      }

      if (_isPrimaryAdminEmail(user.email)) {
        _totpSecret = TotpUtils.generateSecret();
        await _db.collection('users').doc(user.uid).set({
          'name': user.displayName ?? 'Store Admin',
          'email': user.email?.trim().toLowerCase(),
          'role': 'admin',
          'requestedRole': 'admin',
          'status': 'approved',
          'isCustomer': false,
          'isDisabled': false,
          'authMethod': 'google',
          'totpSecret': _totpSecret,
          'createdAt': FieldValue.serverTimestamp(),
        });
        _needsProfileCompletion = false;
        _isRegisteringInProgress = false;
        _isLoadingProfile = true;
        notifyListeners();
        _listenToUserDoc(user.uid);
        return GoogleSignInResult.returning;
      }

      // First-time Google staff registrant: hold on profile completion screen.
      _role = UserRole.none;
      _status = 'none';
      _needsProfileCompletion = true;
      _isLoadingProfile = false;
      _initialized = true;
      _isRegisteringInProgress = false;
      notifyListeners();
      return GoogleSignInResult.needsProfile;
    } catch (e) {
      _isRegisteringInProgress = false;
      _isLoadingProfile = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Completes registration details for a first-time Google Sign-In user.
  Future<void> completeGoogleRegistration({
    required String name,
    String? phoneNumber,
    String requestedRole = 'trustedPartner',
  }) async {
    final user = currentUser;
    if (user == null) return;

    final trimmedName = name.trim();
    final sanitizedPhone = phoneNumber != null && phoneNumber.trim().isNotEmpty
        ? formatPhoneNumber(phoneNumber.trim())
        : null;

    await user.updateDisplayName(trimmedName).catchError((e) {
      debugPrint('Error updating Google user displayName: $e');
    });

    _totpSecret = TotpUtils.generateSecret();
    _phoneNumber = sanitizedPhone;

    await _db.collection('users').doc(user.uid).set({
      'name': trimmedName,
      'email': user.email?.trim().toLowerCase(),
      if (sanitizedPhone != null) 'phoneNumber': sanitizedPhone,
      'role': 'none',
      'requestedRole': requestedRole,
      'status': 'pending',
      'isDisabled': false,
      'isCustomer': false,
      'authMethod': 'google',
      'totpSecret': _totpSecret,
      'createdAt': FieldValue.serverTimestamp(),
    });

    try {
      await AuditLogService().logAction(
        module: 'Auth',
        action: 'REGISTER',
        targetId: user.uid,
        targetName: user.email ?? 'Unknown',
        summary:
            'New Google staff registration submitted for $trimmedName (${user.email})',
      );
    } catch (e) {
      debugPrint('Audit log error on Google register: $e');
    }

    _needsProfileCompletion = false;
    _isLoadingProfile = true;
    notifyListeners();
    _listenToUserDoc(user.uid);
  }

  /// Triggers a manual refresh of the user document permissions and auth state.
  Future<void> refreshRole() async {
    final user = currentUser;
    if (user != null) {
      try {
        await user.reload();
      } catch (e) {
        debugPrint('Error reloading user in refreshRole: $e');
      }
      _userSub?.cancel();
      _userSub = null;
      _listenToUserDoc(user.uid);
      notifyListeners();
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

  /// Updates current user 6-digit security PIN in Firestore and local storage.
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

  /// Generates [count] formatted 8-character uppercase backup recovery codes (e.g. XXXX-XXXX).
  static List<String> generateRecoveryCodes({int count = 5}) {
    final random = Random.secure();
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Excludes ambiguous characters (0, 1, O, I)
    final List<String> codes = [];
    for (int i = 0; i < count; i++) {
      final code =
          List.generate(8, (index) => chars[random.nextInt(chars.length)])
              .join();
      codes.add('${code.substring(0, 4)}-${code.substring(4)}');
    }
    return codes;
  }

  /// Generates new backup recovery codes for active admin and updates Firestore.
  Future<List<String>> regenerateRecoveryCodes() async {
    final user = currentUser;
    if (user == null) return [];

    final newCodes = generateRecoveryCodes();
    _recoveryCodes = newCodes;
    await _db.collection('users').doc(user.uid).set({
      'recoveryCodes': newCodes,
    }, SetOptions(merge: true));
    notifyListeners();
    return newCodes;
  }

  /// Verifies an emergency backup recovery code for admin account.
  /// If valid, consumes/removes the code from Firestore, clears the existing 6-digit PIN,
  /// and returns true.
  Future<bool> verifyAndConsumeRecoveryCode(String codeInput) async {
    final user = currentUser;
    if (user == null) return false;

    final sanitized =
        codeInput.replaceAll('-', '').replaceAll(' ', '').toUpperCase();
    if (sanitized.isEmpty) return false;

    int matchIndex = _recoveryCodes.indexWhere(
      (c) =>
          c.replaceAll('-', '').replaceAll(' ', '').toUpperCase() == sanitized,
    );

    if (matchIndex == -1) {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final rawCodes = doc.data()?['recoveryCodes'];
        if (rawCodes is List) {
          final firestoreCodes =
              List<String>.from(rawCodes.map((e) => e.toString()));
          matchIndex = firestoreCodes.indexWhere(
            (c) =>
                c.replaceAll('-', '').replaceAll(' ', '').toUpperCase() ==
                sanitized,
          );
          if (matchIndex != -1) {
            _recoveryCodes = firestoreCodes;
          }
        }
      }
    }

    if (matchIndex == -1) return false;

    _recoveryCodes.removeAt(matchIndex);
    _userPin = null;

    await _db.collection('users').doc(user.uid).update({
      'recoveryCodes': _recoveryCodes,
      'pin': FieldValue.delete(),
    });

    await AuthService().clearPin();
    notifyListeners();
    return true;
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

  /// Authenticates user credentials with Firebase Auth and records a login audit event.
  Future<void> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedPass = password.trim();
    final cred = await _auth.signInWithEmailAndPassword(
      email: normalizedEmail,
      password: trimmedPass,
    );
    final user = cred.user;
    if (user != null) {
      await AuthService().setAdminEmail(normalizedEmail);
      try {
        await AuditLogService().logAction(
          module: 'Auth',
          action: 'LOGIN',
          targetId: user.uid,
          targetName: normalizedEmail,
          summary: 'User $normalizedEmail logged in',
        );
      } catch (e) {
        debugPrint('Audit log error on login: $e');
      }
    }
  }

  /// Signs out current user (including Google Sign-In cache) and resets auth session flags.
  Future<void> logout() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await AuditLogService().logAction(
          module: 'Auth',
          action: 'LOGOUT',
          targetId: user.uid,
          targetName: user.email ?? 'Unknown',
          summary: 'User ${user.email} logged out',
        );
      } catch (e) {
        debugPrint('Audit log error on logout: $e');
      }
    }
    _userSub?.cancel();
    _userSub = null;
    await _auth.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await AuthService().clearPin();
    _resetLocalState();
    _initialized = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }
}
