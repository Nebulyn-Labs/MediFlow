import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:med_supply_prototype/views/shared/confirm_logout_dialog.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

void main() {
  late MockFirebaseAuth mockAuth;

  setUp(() {
    mockAuth = MockFirebaseAuth();
  });

  Widget buildTestWidget({required WidgetBuilder builder}) {
    final router = GoRouter(
      initialLocation: '/test',
      routes: [
        GoRoute(
          path: '/test',
          builder: (context, state) => Scaffold(body: builder(context)),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('Home Screen')),
        ),
      ],
    );

    return MaterialApp.router(
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
      ),
      routerConfig: router,
    );
  }

  testWidgets('confirmLogout returns false when Cancel is pressed',
      (WidgetTester tester) async {
    bool? result;

    await tester.pumpWidget(
      buildTestWidget(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await confirmLogout(context);
          },
          child: const Text('Logout Button'),
        ),
      ),
    );

    await tester.tap(find.text('Logout Button'));
    await tester.pumpAndSettle();

    expect(find.text('Log out'), findsNWidgets(2)); // Title & Button
    expect(find.text('Are you sure you want to log out?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('confirmLogout returns true when Log out is pressed',
      (WidgetTester tester) async {
    bool? result;

    await tester.pumpWidget(
      buildTestWidget(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await confirmLogout(context);
          },
          child: const Text('Logout Button'),
        ),
      ),
    );

    await tester.tap(find.text('Logout Button'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('signOutWithConfirmation does not sign out if cancelled',
      (WidgetTester tester) async {
    when(() => mockAuth.signOut()).thenAnswer((_) async {});

    await tester.pumpWidget(
      buildTestWidget(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            await signOutWithConfirmation(context, auth: mockAuth);
          },
          child: const Text('Logout Button'),
        ),
      ),
    );

    await tester.tap(find.text('Logout Button'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockAuth.signOut());
    expect(find.text('Home Screen'), findsNothing);
  });

  testWidgets(
      'signOutWithConfirmation calls signOut and navigates to / when confirmed',
      (WidgetTester tester) async {
    when(() => mockAuth.signOut()).thenAnswer((_) async {});

    await tester.pumpWidget(
      buildTestWidget(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            await signOutWithConfirmation(context, auth: mockAuth);
          },
          child: const Text('Logout Button'),
        ),
      ),
    );

    await tester.tap(find.text('Logout Button'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Log out'));
    await tester.pumpAndSettle();

    verify(() => mockAuth.signOut()).called(1);
    expect(find.text('Home Screen'), findsOneWidget);
  });

  testWidgets('signOutWithConfirmation shows snackbar if signOut throws error',
      (WidgetTester tester) async {
    when(() => mockAuth.signOut()).thenThrow(Exception('Auth Error'));

    await tester.pumpWidget(
      buildTestWidget(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            await signOutWithConfirmation(context, auth: mockAuth);
          },
          child: const Text('Logout Button'),
        ),
      ),
    );

    await tester.tap(find.text('Logout Button'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Log out'));
    await tester.pumpAndSettle();

    verify(() => mockAuth.signOut()).called(1);
    expect(find.text('Sign out failed: Exception: Auth Error'), findsOneWidget);
    expect(find.text('Home Screen'), findsNothing);
  });
}
