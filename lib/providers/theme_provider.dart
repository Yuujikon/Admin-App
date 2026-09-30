import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for managing application theme mode preferences (Light vs Dark mode).
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  /// Currently active theme mode.
  ThemeMode get themeMode => _themeMode;

  /// True if current theme mode is set to dark mode.
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Initializes [ThemeProvider] and loads saved theme preference from local storage.
  ThemeProvider() {
    _loadTheme();
  }

  /// Internal helper to load theme setting from [SharedPreferences].
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode');
    if (isDark != null) {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      notifyListeners();
    }
  }

  /// Toggles theme mode between Light and Dark and persists preference to disk.
  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
  }
}
