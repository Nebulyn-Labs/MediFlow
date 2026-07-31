import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key used to persist the selected theme mode.
const String kThemeModePrefsKey = 'theme_mode';

/// Holds the theme mode selected by the user and persists it to local
/// storage so the choice survives app restarts.
final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

/// Seed value loaded from local storage before [runApp].
final initialThemeModeProvider = Provider<ThemeMode>(
  (ref) => ThemeMode.dark,
);

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialThemeModeProvider);

  /// Toggles between dark and light theme and persists the choice.
  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _persist(state);
  }

  /// Sets the theme mode explicitly and persists the choice.
  void setMode(ThemeMode mode) {
    if (state == mode) return;
    state = mode;
    _persist(mode);
  }

  Future<void> _persist(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kThemeModePrefsKey, mode.name);
    } catch (e) {
      debugPrint('Failed to persist theme mode: $e');
    }
  }
}
