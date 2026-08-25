import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to dark theme mode when no preference is saved', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('loads saved light preference from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        themePreferenceKey: 'light',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Trigger read to initialize notifier
      container.read(themeModeProvider);
      // Wait for async _loadFromPreferences
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('toggleTheme alternates between dark and light', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.dark);

      await container.read(themeModeProvider.notifier).toggleTheme();
      expect(container.read(themeModeProvider), ThemeMode.light);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(themePreferenceKey), 'light');

      await container.read(themeModeProvider.notifier).toggleTheme();
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(prefs.getString(themePreferenceKey), 'dark');
    });

    test('setThemeMode updates state and persists choice', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);

      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(themePreferenceKey), 'light');

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.system);
      expect(container.read(themeModeProvider), ThemeMode.system);
      expect(prefs.getString(themePreferenceKey), 'system');
    });
  });

  group('isDarkModeProvider', () {
    test('reflects active theme mode', () {
      final container = ProviderContainer(
        overrides: [
          themeModeProvider.overrideWith(
              () => ThemeModeNotifier(initialMode: ThemeMode.dark)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isDarkModeProvider), isTrue);

      container.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
      expect(container.read(isDarkModeProvider), isFalse);
    });
  });
}
