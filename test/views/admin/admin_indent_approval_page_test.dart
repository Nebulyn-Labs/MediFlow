import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      Completer<Map<String, dynamic>>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockAIService implements AIService {
  @override
  Future<Map<String, dynamic>> forecastDemand(
    String medicineName,
    List<DailyUsageLog> logs,
    int daysToForecast, {
    String? facilityId,
  }) async {
    return {'prediction': 100};
  }

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

  Widget pump(FirebaseService firebase, {AIService? aiService}) {
    return ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(firebase),
        aiServiceProvider.overrideWithValue(aiService ?? _HangingAIService()),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const AdminIndentApprovalPage(),
      ),
    );
  }

  // Issue #323: post-await setState in _analyzeRequest must be guarded.
  testWidgets(
      'disposing mid AI analyze does not throw setState-after-dispose (#323)',
      (WidgetTester tester) async {
    final streamFirebase = _StreamFirebaseService(
      requests: [request],
      inventoryItems: [inventoryItem],
    );

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Analyze with AI'), findsOneWidget);

    await tester.tap(find.text('Analyze with AI'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('allows selecting individual requests and select all (#407)',
      (WidgetTester tester) async {
    final req1 = MedRequest(
      id: 'req-1',
      facilityId: facility.id,
      medicineName: 'Paracetamol',
      type: RequestType.regularIndent,
      quantity: 50,
      requestDate: DateTime(2026, 1, 1),
      status: RequestStatus.pending,
    );
    final req2 = MedRequest(
      id: 'req-2',
      facilityId: facility.id,
      medicineName: 'Amoxicillin',
      type: RequestType.regularIndent,
      quantity: 100,
      requestDate: DateTime(2026, 1, 1),
      status: RequestStatus.pending,
    );

    final streamFirebase = _StreamFirebaseService(requests: [req1, req2]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Select All (0/2)'), findsOneWidget);

    // Select first request
    await tester.tap(find.byKey(const Key('checkbox_req-1')));
    await tester.pump();
    expect(find.text('Select All (1/2)'), findsOneWidget);

    // Tap Select All
    await tester.tap(find.byKey(const Key('bulk_select_all_checkbox')));
    await tester.pump();
    expect(find.text('Select All (2/2)'), findsOneWidget);

    // Deselect Select All
    await tester.tap(find.byKey(const Key('bulk_select_all_checkbox')));
    await tester.pump();
    expect(find.text('Select All (0/2)'), findsOneWidget);
  });

  testWidgets(
      'bulk approve displays confirmation and approves selected requests (#407)',
      (WidgetTester tester) async {
    final req1 = MedRequest(
      id: 'req-1',
      facilityId: facility.id,
      medicineName: 'Paracetamol',
      type: RequestType.regularIndent,
      quantity: 50,
      requestDate: DateTime(2026, 1, 1),
      status: RequestStatus.pending,
    );
    final req2 = MedRequest(
      id: 'req-2',
      facilityId: facility.id,
      medicineName: 'Amoxicillin',
      type: RequestType.regularIndent,
      quantity: 100,
      requestDate: DateTime(2026, 1, 1),
      status: RequestStatus.pending,
    );

    final streamFirebase = _StreamFirebaseService(requests: [req1, req2]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Select All
    await tester.tap(find.byKey(const Key('bulk_select_all_checkbox')));
    await tester.pump();

    // Tap Bulk Approve
    await tester.tap(find.byKey(const Key('bulk_approve_button')));
    await tester.pumpAndSettle();

    // Confirmation dialog should be shown
    expect(find.text('Confirm Bulk Approval'), findsOneWidget);
    expect(find.text('Are you sure you want to approve 2 selected request(s)?'),
        findsOneWidget);

    // Confirm approval
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();

    expect(streamFirebase.updatedStatuses['req-1'], RequestStatus.approved);
    expect(streamFirebase.updatedStatuses['req-2'], RequestStatus.approved);
    expect(find.text('Successfully approved 2 request(s)!'), findsOneWidget);
  });

  testWidgets(
      'canceling bulk confirmation dialog does not update requests (#407)',
      (WidgetTester tester) async {
    final req1 = MedRequest(
      id: 'req-1',
      facilityId: facility.id,
      medicineName: 'Paracetamol',
      type: RequestType.regularIndent,
      quantity: 50,
      requestDate: DateTime(2026, 1, 1),
      status: RequestStatus.pending,
    );

    final streamFirebase = _StreamFirebaseService(requests: [req1]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('checkbox_req-1')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('bulk_decline_button')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Bulk Decline'), findsOneWidget);

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(streamFirebase.updatedStatuses.containsKey('req-1'), false);
  });

  testWidgets('bulk decline updates selected requests (#407)',
      (WidgetTester tester) async {
    final req1 = MedRequest(
      id: 'req-1',
      facilityId: facility.id,
      medicineName: 'Paracetamol',
      type: RequestType.regularIndent,
      quantity: 50,
      requestDate: DateTime(2026, 1, 1),
      status: RequestStatus.pending,
    );

    final streamFirebase = _StreamFirebaseService(requests: [req1]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('checkbox_req-1')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('bulk_decline_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(streamFirebase.updatedStatuses['req-1'], RequestStatus.rejected);
    expect(find.text('Successfully declined 1 request(s)!'), findsOneWidget);
  });

  testWidgets('bulk analyze triggers AI forecast for selected requests (#407)',
      (WidgetTester tester) async {
    final req1 = MedRequest(
      id: 'req-1',
      facilityId: facility.id,
      medicineName: 'Paracetamol',
      type: RequestType.regularIndent,
      quantity: 50,
      requestDate: DateTime(2026, 1, 1),
      status: RequestStatus.pending,
    );

    final streamFirebase = _StreamFirebaseService(
      requests: [req1],
      inventoryItems: [inventoryItem],
    );

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase, aiService: _MockAIService()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('checkbox_req-1')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('bulk_analyze_button')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Bulk AI Analysis'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Analyze'));
    await tester.pumpAndSettle();

    expect(
      find.text('Bulk AI analysis completed for 1 request(s)!'),
      findsOneWidget,
    );
  });

  testWidgets(
      'single approve shows confirmation dialog before approving request (#249)',
      (WidgetTester tester) async {
    final streamFirebase = _StreamFirebaseService(requests: [request]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase));
    await tester.pumpAndSettle();

    // Tap single Approve button
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Approval'), findsOneWidget);
    expect(
      find.text(
          'Are you sure you want to approve the request for Paracetamol?'),
      findsOneWidget,
    );

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(streamFirebase.updatedStatuses.containsKey('req-1'), false);

    // Tap Approve again and confirm
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Approve')));
    await tester.pumpAndSettle();

    expect(streamFirebase.updatedStatuses['req-1'], RequestStatus.approved);
  });

  testWidgets(
      'single decline shows confirmation dialog before declining request (#249)',
      (WidgetTester tester) async {
    final streamFirebase = _StreamFirebaseService(requests: [request]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase));
    await tester.pumpAndSettle();

    // Tap single Decline button
    await tester.tap(find.widgetWithText(TextButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Decline'), findsOneWidget);
    expect(
      find.text(
          'Are you sure you want to decline the request for Paracetamol?'),
      findsOneWidget,
    );

    // Confirm decline
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Decline')));
    await tester.pumpAndSettle();

    expect(streamFirebase.updatedStatuses['req-1'], RequestStatus.rejected);
  });

  testWidgets('Export CSV exports pending indent requests (#85)',
      (WidgetTester tester) async {
    final streamFirebase = _StreamFirebaseService(requests: [request]);

    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'save' ? '/tmp/indent_requests.csv' : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(streamFirebase));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('export_indent_csv_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('export_indent_csv_button')));
    await tester.pumpAndSettle();

    expect(find.text('Indent requests CSV exported ✓'), findsOneWidget);
  });
}

/// Fake firebase service that drives a streamed list of pending requests
/// and the inventory/log lookups the AI analyze flow needs.
class _StreamFirebaseService implements FirebaseService {
  _StreamFirebaseService(
      {required this.requests, this.inventoryItems = const []});

  final List<MedRequest> requests;
  final List<InventoryItem> inventoryItems;
  final Map<String, RequestStatus> updatedStatuses = {};

  @override
  Future<List<InventoryItem>> getInventoryOnce(String facilityId) async =>
      inventoryItems;

  @override
  Future<List<DailyUsageLog>> getRecentLogs(String facilityId,
          {int days = 30}) async =>
      const [];

  @override
  Future<void> updateRequestStatus(String id, RequestStatus status) async {
    updatedStatuses[id] = status;
  }

  @override
  Stream<List<MedRequest>> streamRequests(String? facilityId) {
    // `Stream.value` emits the list asynchronously on first listen, which is
    // what StreamBuilder needs to settle out of `ConnectionState.waiting`.
    return Stream.value(requests);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
