import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/services/ai_service.dart';
import 'package:med_supply_prototype/services/routing_service.dart';
import 'package:med_supply_prototype/services/optimization_service.dart';
import 'package:med_supply_prototype/views/admin/route_optimization_map.dart';

// -----------------------------------------------------------------------------
// FAKES
// -----------------------------------------------------------------------------

class FakeFirebaseService implements FirebaseService {
  final List<Facility> facilities;
  final List<InventoryItem> inventory;
  final List<MedRequest> requests;
  int getFacilitiesCallCount = 0;

  FakeFirebaseService({
    required this.facilities,
    required this.inventory,
    required this.requests,
  });

  @override
  Future<List<Facility>> getFacilities() async {
    getFacilitiesCallCount++;
    return facilities;
  }

  late final Stream<List<InventoryItem>> _inventoryStream =
      Stream.value(inventory);
  late final Stream<List<MedRequest>> _requestsStream = Stream.value(requests);

  @override
  Stream<List<InventoryItem>> streamAllMedicines() {
    return _inventoryStream;
  }

  @override
  Stream<List<MedRequest>> streamRequests(String? facilityId) {
    if (facilityId != null) {
      return Stream.value(
          requests.where((r) => r.facilityId == facilityId).toList());
    }
    return _requestsStream;
  }

  @override
  Future<String?> seedDemoData() async {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FailingFirebaseService implements FirebaseService {
  final Exception exception;
  int callCount = 0;

  FailingFirebaseService(this.exception);

  @override
  Future<List<Facility>> getFacilities() async {
    callCount++;
    throw exception;
  }

  @override
  Stream<List<InventoryItem>> streamAllMedicines() {
    return Stream.value([]);
  }

  @override
  Stream<List<MedRequest>> streamRequests(String? facilityId) {
    return Stream.value([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RetryableFirebaseService implements FirebaseService {
  final List<Facility> facilities;
  final int failUntilAttempt;
  int callCount = 0;

  RetryableFirebaseService({
    required this.facilities,
    this.failUntilAttempt = 2,
  });

  @override
  Future<List<Facility>> getFacilities() async {
    callCount++;
    if (callCount <= failUntilAttempt) {
      throw Exception('Network unavailable');
    }
    return facilities;
  }

  @override
  Stream<List<InventoryItem>> streamAllMedicines() {
    return Stream.value([]);
  }

  @override
  Stream<List<MedRequest>> streamRequests(String? facilityId) {
    return Stream.value([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOptimizationService implements OptimizationService {
  final List<TransferRecommendation> recommendations;

  FakeOptimizationService(this.recommendations);

  @override
  List<TransferRecommendation> calculateOptimalTransfers({
    required List<Facility> facilities,
    required Map<String, List<InventoryItem>> inventories,
    required List<MedRequest> requests,
  }) {
    return recommendations;
  }

  @override
  List<MultiStopRoute> calculateMultiStopRoutes({
    required List<Facility> facilities,
    required Map<String, List<InventoryItem>> inventories,
    required List<MedRequest> requests,
    RoutingStrategy? routingStrategy,
  }) {
    if (recommendations.isEmpty) return [];
    
    // Convert recommendation to a simple multi-stop route
    final rec = recommendations.first;
    return [
      MultiStopRoute(
        stops: [rec.donor, rec.recipient],
        transfers: [rec],
      )
    ];
  }
}

class FakeRoutingService implements RoutingService {
  @override
  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    return [start, end];
  }

  @override
  Future<List<LatLng>> getMultiStopRoute(List<LatLng> stops) async {
    return stops;
  }
}

class FakeAIService implements AIService {
  @override
  Future<String> generateRedistributionPlan(
      List<MedRequest> requests, List<Facility> facilities) async {
    return 'Mock AI Summary: Transfer optimized.';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Dummy HttpOverrides to prevent network requests for Map tiles
class DummyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = DummyHttpOverrides();
  });

  group('RouteOptimizationMap Widget Tests', () {
    late Facility donor;
    late Facility recipient;
    late InventoryItem inventory;
    late MedRequest request;
    late TransferRecommendation recommendation;

    setUp(() {
      donor = Facility(
        id: 'd1',
        name: 'Donor PHC',
        email: 'donor@test.com',
        type: 'urban',
        region: 'North',
        latitude: 28.61,
        longitude: 77.21,
        createdAt: DateTime.now(),
      );

      recipient = Facility(
        id: 'r1',
        name: 'Recipient CHC',
        email: 'recip@test.com',
        type: 'rural',
        region: 'North',
        latitude: 28.71,
        longitude: 77.31,
        createdAt: DateTime.now(),
      );

      inventory = InventoryItem(
        id: 'inv1',
        medicineName: 'ORS',
        batchId: 'B1',
        arrivalDate: DateTime.now(),
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        initialQuantity: 1000,
        remainingQuantity: 800, // Surplus
        unit: 'sachets',
        lastUpdated: DateTime.now(),
        facilityId: donor.id,
      );

      request = MedRequest(
        id: 'req1',
        facilityId: recipient.id,
        medicineName: 'ORS',
        type: RequestType.regularIndent,
        quantity: 500,
        requestDate: DateTime.now(),
        status: RequestStatus.pending,
      );

      recommendation = TransferRecommendation(
        donor: donor,
        recipient: recipient,
        medicine: 'ORS',
        quantity: 500,
        score: 180,
        reasoning: 'Proximity + Rural Priority',
      );
    });

    Widget createWidgetUnderTest(List<TransferRecommendation> recs,
        {FirebaseService? firebaseService}) {
      return ProviderScope(
        overrides: [
          firebaseServiceProvider.overrideWithValue(
            firebaseService ??
                FakeFirebaseService(
                  facilities: [donor, recipient],
                  inventory: [inventory],
                  requests: [request],
                ),
          ),
          optimizationServiceProvider
              .overrideWithValue(FakeOptimizationService(recs)),
          routingServiceProvider.overrideWithValue(FakeRoutingService()),
          aiServiceProvider.overrideWithValue(FakeAIService()),
        ],
        child: const MaterialApp(
          home: RouteOptimizationMap(),
        ),
      );
    }

    testWidgets('initial loading state and empty map state',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      
      // Build our app and trigger a frame.
      await tester.pumpWidget(createWidgetUnderTest([]));

      // Initially, it should show a loading indicator (though it might resolve instantly with fakes).
      // We can't easily catch the loading state because getFacilities completes immediately in Fake,
      // but let's verify what it renders after loading.
      await tester.pumpAndSettle();

      expect(find.text('Transfer Manifest'), findsOneWidget);
      expect(find.text('Generate Optimal Routes'), findsOneWidget);
      expect(find.text('Click Generate to start analysis'), findsOneWidget);

      // PolylineLayer should not have any polyline since showRoutes is false initially
      expect(find.byType(PolylineLayer), findsNothing);
    });

    testWidgets('generates routes, displays recommendations and AI summary',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      
      await tester.pumpWidget(createWidgetUnderTest([recommendation]));
      await tester.pumpAndSettle();

      // Tap the Generate button
      await tester.tap(find.text('Generate Optimal Routes'));

      // Allow async operations (calculateOptimalTransfers, getRoute, AI) to complete
      await tester.pumpAndSettle();

      // Verify button changed to "Re-optimize Routes"
      expect(find.text('Re-optimize Routes'), findsOneWidget);

      // Verify AI summary appears
      expect(find.text('Mock AI Summary: Transfer optimized.'), findsOneWidget);

      // Verify recommendation details appear in the transfer card
      expect(find.text('Donor PHC'), findsWidgets);
      expect(find.text('Recipient CHC'), findsWidgets);
      expect(find.text('ORS'), findsOneWidget);
      expect(find.text('500 Units requested'), findsOneWidget);
      expect(find.text('Proximity + Rural Priority'), findsOneWidget);

      // Verify Clear Map button appears
      expect(find.text('Clear Map'), findsOneWidget);

      // Map should have routes rendered now
      expect(find.byType(PolylineLayer), findsOneWidget);
    });

    testWidgets('Clear Map behavior hides routes and summary',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      
      await tester.pumpWidget(createWidgetUnderTest([recommendation]));
      await tester.pumpAndSettle();

      // Generate routes first
      await tester.tap(find.text('Generate Optimal Routes'));
      await tester.pumpAndSettle();

      expect(find.text('Clear Map'), findsOneWidget);

      // Tap Clear Map
      await tester.tap(find.text('Clear Map'));
      await tester.pumpAndSettle();

      // Verify it went back to empty state
      expect(find.text('Click Generate to start analysis'), findsOneWidget);
      expect(find.text('Generate Optimal Routes'), findsOneWidget);
      expect(find.text('Clear Map'), findsNothing);
      expect(find.text('Mock AI Summary: Transfer optimized.'), findsNothing);
      expect(find.byType(PolylineLayer), findsNothing);
    });

    testWidgets('failed initialization shows error message and retry button',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final failingService = FailingFirebaseService(
        Exception('Firebase connection failed'),
      );

      await tester.pumpWidget(
        createWidgetUnderTest([], firebaseService: failingService),
      );
      await tester.pumpAndSettle();

      // Error message should be displayed
      expect(
        find.text(
            'Unable to load facilities. Please check your connection and try again.'),
        findsOneWidget,
      );

      // Retry button should be visible
      expect(find.text('Retry'), findsOneWidget);

      // Error icon should be visible
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      // Loading spinner should NOT be visible
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Main content should NOT be visible
      expect(find.text('Transfer Manifest'), findsNothing);
      expect(find.text('Generate Optimal Routes'), findsNothing);
    });

    testWidgets('loading indicator always dismissed after failure',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final failingService = FailingFirebaseService(
        Exception('Timeout'),
      );

      await tester.pumpWidget(
        createWidgetUnderTest([], firebaseService: failingService),
      );
      await tester.pumpAndSettle();

      // Loading should be dismissed
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Error state should be shown
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text(
            'Unable to load facilities. Please check your connection and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('retry successfully reloads data after failure',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final retryableService = RetryableFirebaseService(
        facilities: [donor, recipient],
        failUntilAttempt: 1,
      );

      await tester.pumpWidget(
        createWidgetUnderTest([], firebaseService: retryableService),
      );
      await tester.pumpAndSettle();

      // Should show error state initially
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text(
            'Unable to load facilities. Please check your connection and try again.'),
        findsOneWidget,
      );

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Should now show the main content
      expect(find.text('Transfer Manifest'), findsOneWidget);
      expect(find.text('Generate Optimal Routes'), findsOneWidget);

      // Error should be gone
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('retry after multiple failures eventually succeeds',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final retryableService = RetryableFirebaseService(
        facilities: [donor, recipient],
        failUntilAttempt: 2,
      );

      await tester.pumpWidget(
        createWidgetUnderTest([], firebaseService: retryableService),
      );
      await tester.pumpAndSettle();

      // First attempt fails
      expect(find.text('Retry'), findsOneWidget);

      // First retry still fails
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      // Second retry succeeds
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Should now show the main content
      expect(find.text('Transfer Manifest'), findsOneWidget);
      expect(find.text('Generate Optimal Routes'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('empty facility list renders successfully',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emptyService = FakeFirebaseService(
        facilities: [],
        inventory: [],
        requests: [],
      );

      await tester.pumpWidget(
        createWidgetUnderTest([], firebaseService: emptyService),
      );
      await tester.pumpAndSettle();

      // Should render the main content with no error
      expect(find.text('Transfer Manifest'), findsOneWidget);
      expect(find.text('Generate Optimal Routes'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('successful initialization does not show error state',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createWidgetUnderTest([]));
      await tester.pumpAndSettle();

      // No error state
      expect(find.text('Retry'), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

      // Main content visible
      expect(find.text('Transfer Manifest'), findsOneWidget);
      expect(find.text('Generate Optimal Routes'), findsOneWidget);
    });

    testWidgets('network unavailable shows user-friendly error',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final networkErrorService = FailingFirebaseService(
        SocketException('Network is unreachable'),
      );

      await tester.pumpWidget(
        createWidgetUnderTest([], firebaseService: networkErrorService),
      );
      await tester.pumpAndSettle();

      // Should show friendly error, not raw exception
      expect(
        find.text(
            'Unable to load facilities. Please check your connection and try again.'),
        findsOneWidget,
      );
      // Raw exception should NOT be visible
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('Network is unreachable'), findsNothing);
    });

    testWidgets('retry button clears previous error before reloading',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final retryableService = RetryableFirebaseService(
        facilities: [donor, recipient],
        failUntilAttempt: 1,
      );

      await tester.pumpWidget(
        createWidgetUnderTest([], firebaseService: retryableService),
      );
      await tester.pumpAndSettle();

      // Error visible
      expect(find.text('Retry'), findsOneWidget);

      // Tap retry - error should clear and loading should show briefly
      await tester.tap(find.text('Retry'));

      // Pump once to trigger the setState for loading
      await tester.pump();

      // Error message should be gone immediately after retry
      expect(
        find.text(
            'Unable to load facilities. Please check your connection and try again.'),
        findsNothing,
      );

      // Let it complete
      await tester.pumpAndSettle();

      // Should show success
      expect(find.text('Transfer Manifest'), findsOneWidget);
    });
  });
}
