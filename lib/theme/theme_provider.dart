import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String themePreferenceKey = 'mediflow_theme_mode';

/// Manages application theme mode with local persistence via [SharedPreferences].
class ThemeModeNotifier extends Notifier<ThemeMode> {
  final ThemeMode _initialMode;
  ThemeModeNotifier({ThemeMode initialMode = ThemeMode.dark})
      : _initialMode = initialMode;

  @override
  ThemeMode build() {
    _loadFromPreferences();
    return _initialMode;
  }

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(themePreferenceKey);
      if (savedMode != null) {
        switch (savedMode) {
          case 'light':
            state = ThemeMode.light;
            break;
          case 'dark':
            state = ThemeMode.dark;
            break;
          case 'system':
            state = ThemeMode.system;
            break;
        }
      }
    } catch (e) {
      debugPrint('Error loading theme preference: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (mode) {
        case ThemeMode.light:
          await prefs.setString(themePreferenceKey, 'light');
          break;
        case ThemeMode.dark:
          await prefs.setString(themePreferenceKey, 'dark');
          break;
        case ThemeMode.system:
          await prefs.setString(themePreferenceKey, 'system');
          break;
      }
    } catch (e) {
      debugPrint('Error saving theme preference: $e');
    }
  }

  Future<void> toggleTheme() async {
    if (state == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(() {
  return ThemeModeNotifier();
});

/// Convenient helper provider that returns true if dark mode is selected.
final isDarkModeProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  return mode != ThemeMode.light;
});
