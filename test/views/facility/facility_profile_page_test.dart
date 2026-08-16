import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/facility/facility_profile_page.dart';

class TestFirebaseService implements FirebaseService {
  Facility? facilityToReturn;
  Object? errorToThrow;
  int getFacilityCallCount = 0;

  TestFirebaseService({this.facilityToReturn, this.errorToThrow});

  @override
  Future<Facility?> getFacility(String id) async {
    getFacilityCallCount++;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return facilityToReturn;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final testFacility = Facility(
    id: 'fac-101',
    name: 'Central Hospital',
    email: 'central@hospital.org',
    type: FacilityType.urban,
    region: 'North District',
    latitude: 12.3456,
    longitude: 78.9101,
    createdAt: DateTime(2026, 1, 1),
  );

  Widget createWidgetUnderTest(TestFirebaseService fakeService) {
    return ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(fakeService),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: FacilityProfilePage(facilityId: 'fac-101'),
        ),
      ),
    );
  }

  group('FacilityProfilePage Error Handling & Retry Tests', () {
    testWidgets('renders facility profile when load succeeds', (tester) async {
      final service = TestFirebaseService(facilityToReturn: testFacility);

      await tester.pumpWidget(createWidgetUnderTest(service));
      await tester.pumpAndSettle();

      expect(find.text('Profile & Settings'), findsOneWidget);
      expect(find.text('Central Hospital'), findsOneWidget);
      expect(find.text('North District'), findsOneWidget);
      expect(find.text('central@hospital.org'), findsOneWidget);
      expect(find.text('Facility not found'), findsNothing);
      expect(find.text('Failed to load facility'), findsNothing);
    });

    testWidgets(
        'renders "Facility not found" when facility is null without error',
        (tester) async {
      final service = TestFirebaseService(facilityToReturn: null);

      await tester.pumpWidget(createWidgetUnderTest(service));
      await tester.pumpAndSettle();

      expect(find.text('Facility not found'), findsOneWidget);
      expect(find.text('Failed to load facility'), findsNothing);
    });

    testWidgets(
        'renders visually distinct error state with message when exception is thrown',
        (tester) async {
      final service =
          TestFirebaseService(errorToThrow: Exception('Connection timeout'));

      await tester.pumpWidget(createWidgetUnderTest(service));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load facility'), findsOneWidget);
      expect(find.text('Exception: Connection timeout'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Facility not found'), findsNothing);
    });

    testWidgets(
        'tapping Retry button re-runs load and displays profile on success',
        (tester) async {
      final service =
          TestFirebaseService(errorToThrow: Exception('Network error'));

      await tester.pumpWidget(createWidgetUnderTest(service));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load facility'), findsOneWidget);
      expect(service.getFacilityCallCount, 1);

      // Fix error state before retrying
      service.errorToThrow = null;
      service.facilityToReturn = testFacility;

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(service.getFacilityCallCount, 2);
      expect(find.text('Failed to load facility'), findsNothing);
      expect(find.text('Central Hospital'), findsOneWidget);
    });
  });
}
