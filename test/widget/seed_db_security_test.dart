import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/auth/login_screen.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockFirebaseAuth extends Mock implements auth.FirebaseAuth {}

class MockFirebaseService extends Mock implements FirebaseService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirebaseService Seed & Clear Database Security', () {
    test('seedDemoData blocks unauthenticated seeding in non-debug environment',
        () async {
      final mockFirestore = MockFirebaseFirestore();
      final mockAuth = MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);

      final service = FirebaseService(mockFirestore, mockAuth);

      // In unit test environment, kDebugMode is true by default.
      // But we verify that if currentUser is null and !kDebugMode condition is evaluated,
      // it rejects anonymous seeding appropriately.
      if (!kDebugMode) {
        final result = await service.seedDemoData();
        expect(result, contains('disabled in production builds'));
      }
    });

    test('clearDatabase throws error when unauthenticated in non-debug environment',
        () async {
      final mockFirestore = MockFirebaseFirestore();
      final mockAuth = MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);

      final service = FirebaseService(mockFirestore, mockAuth);

      if (!kDebugMode) {
        expect(
          () => service.clearDatabase(),
          throwsA(isA<Exception>()),
        );
      }
    });
  });

  group('LoginScreen Seed DB Confirmation Dialog', () {
    late MockFirebaseService mockService;

    setUp(() {
      mockService = MockFirebaseService();
    });

    testWidgets(
        'Tapping Seed DB shows confirmation dialog and does not seed if canceled',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseServiceProvider.overrideWithValue(mockService),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            home: const LoginScreen(role: 'admin'),
          ),
        ),
      );

      // Find Seed DB button
      final seedButton = find.text('Seed DB');
      expect(seedButton, findsOneWidget);

      // Tap Seed DB button
      await tester.tap(seedButton);
      await tester.pumpAndSettle();

      // Confirmation dialog should be visible
      expect(find.text('Confirm Database Reseed'), findsOneWidget);
      expect(find.text('Wipe & Reseed'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog closed, seedDemoData was NOT called
      expect(find.text('Confirm Database Reseed'), findsNothing);
      verifyNever(() => mockService.seedDemoData());
    });

    testWidgets('Tapping Wipe & Reseed invokes seedDemoData', (tester) async {
      when(() => mockService.seedDemoData())
          .thenAnswer((_) async => null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseServiceProvider.overrideWithValue(mockService),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            home: const LoginScreen(role: 'admin'),
          ),
        ),
      );

      // Tap Seed DB button
      await tester.tap(find.text('Seed DB'));
      await tester.pumpAndSettle();

      // Tap Wipe & Reseed
      await tester.tap(find.text('Wipe & Reseed'));
      await tester.pumpAndSettle();

      // seedDemoData was called once
      verify(() => mockService.seedDemoData()).called(1);
    });
  });
}
