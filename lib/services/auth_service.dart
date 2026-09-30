import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Authentication service for handling admin PIN verification and Firebase Auth.
class AuthService {
  final _auth = FirebaseAuth.instance;

  /// Verifies if the provided [pin] matches the stored admin PIN in local storage.
  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('admin_pin') ?? '1234';
    return pin == stored;
  }

  /// Updates the stored admin PIN in local preferences to [newPin].
  Future<void> changePin(String newPin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_pin', newPin);
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
