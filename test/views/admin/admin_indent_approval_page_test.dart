import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/models/daily_usage_log.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/services/ai_service.dart';
import 'package:med_supply_prototype/views/admin/admin_indent_approval_page.dart';

class _HangingAIService implements AIService {
  @override
  Future<Map<String, dynamic>> forecastDemand(
    String medicineName,
    List<DailyUsageLog> logs,
    int daysToForecast, {
    String? facilityId,
  }) =>
      // Never resolves on its own. #323 only needs the forecast to stay
      // pending while the page is disposed, so a permanent pending future
      // is enough; the test asserts no exception fires in that window.
      Completer<Map<String, dynamic>>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Facility facility;
  late InventoryItem inventoryItem;
  late MedRequest request;

  setUp(() {
    facility = Facility(
      id: 'fac-1',
      name: 'Test PHC',
      email: 't@test.com',
      type: 'urban',
      region: 'North',
      latitude: 28.6,
      longitude: 77.2,
      createdAt: DateTime(2026, 1, 1),
    );
    inventoryItem = InventoryItem(
      id: 'inv-1',
      medicineName: 'Paracetamol',
      batchId: 'B1',
      arrivalDate: DateTime(2026, 1, 1),
      expiryDate: DateTime(2027, 1, 1),
      initialQuantity: 1000,
      remainingQuantity: 200,
      unit: 'units',
      lastUpdated: DateTime(2026, 1, 1),
      facilityId: facility.id,
    );
    request = MedRequest(
      id: 'req-1',
      facilityId: facility.id,
      medicineName: 'Paracetamol',
      type: RequestType.regularIndent,
      quantity: 50,
      requestDate: DateTime(2026, 1, 1),
      status: RequestStatus.pending,
    );
  });

  Widget pump(FirebaseService firebase) {
    return ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(firebase),
        aiServiceProvider.overrideWithValue(_HangingAIService()),
      ],
      child: const MaterialApp(home: AdminIndentApprovalPage()),
    );
  }

  // Issue #323: post-await setState in _analyzeRequest must be guarded.
  testWidgets(
      'disposing mid AI analyze does not throw setState-after-dispose (#323)',
      (WidgetTester tester) async {
    // Drive a streamed list of pending requests so the page renders the
    // "Analyze with AI" button.
    final streamFirebase = _StreamFirebaseService(
      requests: [request],
      inventoryItems: [inventoryItem],
    );

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase));
    // Let the stream subscription deliver its first event.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Analyze with AI'), findsOneWidget);

    // Tap "Analyze with AI" — the AI call never resolves under the fake.
    await tester.tap(find.text('Analyze with AI'));
    await tester.pump();

    // Navigate away before the forecast returns. The pre-fix code would
    // throw a setState-after-dispose assertion; the post-fix code returns
    // early on `!mounted`.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });
}

/// Fake firebase service that drives a streamed list of pending requests
/// and the inventory/log lookups the AI analyze flow needs.
class _StreamFirebaseService implements FirebaseService {
  _StreamFirebaseService(
      {required this.requests, this.inventoryItems = const []});

  final List<MedRequest> requests;
  final List<InventoryItem> inventoryItems;

  @override
  Future<List<InventoryItem>> getInventoryOnce(String facilityId) async =>
      inventoryItems;

  @override
  Future<List<DailyUsageLog>> getRecentLogs(String facilityId,
          {int days = 30}) async =>
      const [];

  @override
  Future<void> updateRequestStatus(String id, RequestStatus status) async {}

  @override
  Stream<List<MedRequest>> streamRequests(String? facilityId) {
    // `Stream.value` emits the list asynchronously on first listen, which is
    // what StreamBuilder needs to settle out of `ConnectionState.waiting`.
    return Stream.value(requests);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
