import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:med_supply_prototype/main.dart' show authRedirect;
import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/auth/login_screen.dart';

// -------- Mocks --------

class MockUserCredential extends Mock implements UserCredential {}

class MockFacility extends Mock implements Facility {}

class MockFirebaseService extends Mock implements FirebaseService {}

// -------- Helpers --------

/// Creates a GoRouter configured for auth-route testing.
/// Set [withRedirect] to false to skip the auth redirect guard,
/// useful for isolating LoginScreen routing behaviour.
GoRouter createTestRouter({
  required FirebaseService Function() mockServiceProvider,
  bool withRedirect = true,
}) {
  return GoRouter(
    initialLocation: '/',
    redirect: withRedirect ? authRedirect : null,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/login/:role',
        builder: (context, state) {
          final role = state.pathParameters['role']!;
          return ProviderScope(
            overrides: [
              firebaseServiceProvider.overrideWithValue(mockServiceProvider()),
            ],
            child: LoginScreen(role: role),
          );
        },
      ),
      ShellRoute(
        builder: (_, __, child) => Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => Scaffold(body: child),
          ),
        ),
        routes: [
          GoRoute(
            path: '/facility/:id/overview',
            builder: (_, __) => const Scaffold(body: Text('Facility Overview')),
          ),
          GoRoute(
            path: '/admin/overview',
            builder: (_, __) => const Scaffold(body: Text('Admin Overview')),
          ),
        ],
      ),
    ],
  );
}

// -------- Tests --------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoRouter Redirect Guard', () {
    testWidgets(
        'unauthenticated users are redirected to / from protected routes',
        (tester) async {
      final router = createTestRouter(
        mockServiceProvider: () => MockFirebaseService(),
        withRedirect: true,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );

      // FirebaseAuth.instance.currentUser is null without Firebase init,
      // so navigating to a protected route must redirect to '/'.
      router.go('/facility/any/overview');
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets(
        'unauthenticated users are redirected to / from /admin/overview',
        (tester) async {
      final router = createTestRouter(
        mockServiceProvider: () => MockFirebaseService(),
        withRedirect: true,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );

      router.go('/admin/overview');
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('LoginScreen Post-Login Routing', () {
    testWidgets('facility login navigates to /facility/:id/overview',
        (tester) async {
      const email = 'rampur@mediflow.com';
      const password = 'password123';
      final facilityId =
          email.toLowerCase().replaceAll('@', '_').replaceAll('.', '_');

      final mockService = MockFirebaseService();
      final mockCredential = MockUserCredential();

      when(() => mockService.login(email, password))
          .thenAnswer((_) async => mockCredential);

      final mockFacility = MockFacility();
      when(() => mockFacility.id).thenReturn(facilityId);
      when(() => mockService.getFacility(facilityId))
          .thenAnswer((_) async => mockFacility);

      final router = createTestRouter(
        mockServiceProvider: () => mockService,
        withRedirect: false,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );

      router.go('/login/facility');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), email);
      await tester.enterText(find.byType(TextField).at(1), password);
      await tester.pump();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('Facility Overview'), findsOneWidget);
    });

    testWidgets('admin login navigates to /admin/overview', (tester) async {
      const email = 'admin@mediflow.com';
      const password = 'password123';

      final mockService = MockFirebaseService();
      final mockCredential = MockUserCredential();

      when(() => mockService.login(email, password))
          .thenAnswer((_) async => mockCredential);

      final router = createTestRouter(
        mockServiceProvider: () => mockService,
        withRedirect: false,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );

      router.go('/login/admin');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), email);
      await tester.enterText(find.byType(TextField).at(1), password);
      await tester.pump();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('Admin Overview'), findsOneWidget);
    });

    testWidgets('login failure shows error and does not navigate',
        (tester) async {
      const email = 'bad@mediflow.com';
      const password = 'wrongpass';

      final mockService = MockFirebaseService();

      when(() => mockService.login(any(), any())).thenThrow(
        FirebaseAuthException(
          code: 'user-not-found',
          message: 'No user found',
        ),
      );

      final router = createTestRouter(
        mockServiceProvider: () => mockService,
        withRedirect: false,
      );

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );

      router.go('/login/facility');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), email);
      await tester.enterText(find.byType(TextField).at(1), password);
      await tester.pump();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // Should still be on the login screen â€” no navigation occurred.
      expect(find.byType(TextField), findsAtLeast(2));
      expect(find.text('Login failed: No user found'), findsOneWidget);
    });
  });
}
