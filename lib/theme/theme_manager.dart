import 'package:flutter/material.dart';

class ThemeManager with ChangeNotifier {
  // 1. Default Theme (Light)
  ThemeMode _themeMode = ThemeMode.light;

  // 2. Getter (Main.dart isay use karega)
  ThemeMode get themeMode => _themeMode;

  // 3. Helper Getter (Profile Screen k Switch k liye)
  // Agar theme Dark hai to True wapis karega, warna False
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // 4. Toggle Function (Switch change honay par call hoga)
  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners(); // Puri app ko signal bhejo ke refresh ho jaye
  }
}

// Global Instance (Isay puri app mein access karenge)
final ThemeManager themeManager = ThemeManager();