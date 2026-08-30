import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/daily_usage_log.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/facility/active_indents_page.dart';

class _FakeFirebaseService implements FirebaseService {
  _FakeFirebaseService({required this.requests});

  final List<MedRequest> requests;
  int streamRequestsCallCount = 0;
  String? lastStreamedFacilityId;

  @override
  Future<List<InventoryItem>> getInventoryOnce(String facilityId) async => [];

  @override
  Stream<List<MedRequest>> streamRequests(String? facilityId) {
    streamRequestsCallCount++;
    lastStreamedFacilityId = facilityId;
    return Stream.value(requests);
  }

  @override
  Future<PaginatedLogsResult> getPaginatedLogs(
    String facilityId, {
    int pageSize = 15,
    DocumentSnapshot? startAfter,
  }) async =>
      PaginatedLogsResult(logs: const [], lastDocument: null, hasMore: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeFirebaseService> _pumpPage(
  WidgetTester tester, {
  required String facilityId,
  List<MedRequest> requests = const [],
  _FakeFirebaseService? firebase,
}) async {
  final service = firebase ?? _FakeFirebaseService(requests: requests);

  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        home: ActiveIndentsPage(facilityId: facilityId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 300));
  return service;
}

void main() {
  testWidgets('Active Indents opens one requests stream and keeps it (#322)',
      (tester) async {
    final firebase = await _pumpPage(tester, facilityId: 'fac-1');

    expect(firebase.streamRequestsCallCount, 1);
    expect(firebase.lastStreamedFacilityId, 'fac-1');

    await tester.tap(find.text('30 days'));
    await tester.pump();
    await tester.tap(find.text('90 days').last);
    await tester.pump();

    expect(firebase.streamRequestsCallCount, 1);
  });

  testWidgets(
      'Active Indents switches the requests stream with facility (#322)',
      (tester) async {
    final firebase = _FakeFirebaseService(requests: const []);
    await _pumpPage(tester, facilityId: 'fac-1', firebase: firebase);

    expect(firebase.streamRequestsCallCount, 1);
    expect(firebase.lastStreamedFacilityId, 'fac-1');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseServiceProvider.overrideWithValue(firebase),
        ],
        child: const MaterialApp(
          home: ActiveIndentsPage(facilityId: 'fac-2'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(firebase.streamRequestsCallCount, 2);
    expect(firebase.lastStreamedFacilityId, 'fac-2');
  });
}
