import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';
import 'package:med_supply_prototype/theme/theme_provider.dart';
import 'package:med_supply_prototype/views/shared/sidebar_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget createTestApp({required Widget child, required ProviderContainer container}) {
    final router = GoRouter(
      initialLocation: '/admin/overview',
      routes: [
        GoRoute(
          path: '/admin/overview',
          builder: (context, state) => SidebarLayout(
            role: 'admin',
            child: const Text('Admin Overview Content'),
          ),
        ),
      ],
    );

    return UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final themeMode = ref.watch(themeModeProvider);
          return MaterialApp.router(
            theme: ThemeData(
              brightness: Brightness.light,
              extensions: const [MediFlowTheme.light],
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [MediFlowTheme.dark],
            ),
            themeMode: themeMode,
            routerConfig: router,
          );
        },
      ),
    );
  }

  testWidgets('Theme toggle button is present in sidebar and switches theme mode on tap',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        themeModeProvider.overrideWith(() => ThemeModeNotifier(initialMode: ThemeMode.dark)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      createTestApp(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('theme_toggle_button'));
    expect(toggleFinder, findsOneWidget);

    // Initial mode is dark
    expect(container.read(themeModeProvider), ThemeMode.dark);

    // Tap to switch to light mode
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.light);

    // Tap again to switch back to dark mode
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
