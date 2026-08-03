import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
          // Create the user document even for non-admins so the Admin can see and promote them
          await _db.collection('users').doc(uid).set({
            'email': currentUser?.email,
            'role': 'none',
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
    await _db.collection('users').doc(currentUser!.uid).update({
      'phoneNumber': phone,
    });
    _phoneNumber = phone;
    notifyListeners();
  }

  void setAdminVerified(bool val) {
    _adminVerified = val;
    notifyListeners();
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
