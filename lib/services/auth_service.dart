import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;

  Future<bool> verifyPin(String pin) async {
    final prefs  = await SharedPreferences.getInstance();
    final stored = prefs.getString('admin_pin') ?? '1234';
    return pin == stored;
  }

  Future<void> changePin(String newPin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_pin', newPin);
  }

  Future<void> loginToFirebase(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  bool get isFirebaseAuthenticated => _auth.currentUser != null;
  String? get currentUserEmail => _auth.currentUser?.email;

  Future<String?> getAdminEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('admin_email');
  }

  Future<void> setAdminEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_email', email);
  }
}
