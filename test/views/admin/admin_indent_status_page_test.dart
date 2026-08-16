import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/admin/admin_indent_status_page.dart';

void main() {
  late MedRequest pendingReq;
  late MedRequest approvedReq;
  late MedRequest rejectedReq;
  late MedRequest fulfilledReq;
  late MedRequest needsReviewReq;

  setUp(() {
    pendingReq = MedRequest(
      id: 'req-pending',
      facilityId: 'fac-1',
      medicineName: 'Paracetamol',
      type: RequestType.regularIndent,
      quantity: 50,
      requestDate: DateTime(2026, 1, 1),
      status: RequestStatus.pending,
    );
    approvedReq = MedRequest(
      id: 'req-approved',
      facilityId: 'fac-1',
      medicineName: 'Amoxicillin',
      type: RequestType.regularIndent,
      quantity: 100,
      requestDate: DateTime(2026, 1, 2),
      status: RequestStatus.approved,
    );
    rejectedReq = MedRequest(
      id: 'req-rejected',
      facilityId: 'fac-1',
      medicineName: 'Ibuprofen',
      type: RequestType.regularIndent,
      quantity: 30,
      requestDate: DateTime(2026, 1, 3),
      status: RequestStatus.rejected,
    );
    fulfilledReq = MedRequest(
      id: 'req-fulfilled',
      facilityId: 'fac-1',
      medicineName: 'Cetirizine',
      type: RequestType.regularIndent,
      quantity: 20,
      requestDate: DateTime(2026, 1, 4),
      status: RequestStatus.fulfilled,
    );
    needsReviewReq = MedRequest(
      id: 'req-needs-review',
      facilityId: 'fac-1',
      medicineName: 'Metformin',
      type: RequestType.regularIndent,
      quantity: 40,
      requestDate: DateTime(2026, 1, 5),
      status: RequestStatus.needsManualReview,
    );
  });

  Widget pump(FirebaseService firebase) {
    return ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(firebase),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const AdminIndentStatusPage(),
      ),
    );
  }

  testWidgets(
      'offers only valid transitions for pending request and prompts confirmation (#249)',
      (WidgetTester tester) async {
    final firebase = _FakeFirebaseService([pendingReq]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(firebase));
    await tester.pumpAndSettle();

    // Open popup menu for pending request
    await tester.tap(find.byType(PopupMenuButton<RequestStatus>));
    await tester.pumpAndSettle();

    // Menu options offered for pending: APPROVED and REJECTED
    expect(find.text('APPROVED'), findsOneWidget);
    expect(find.text('REJECTED'), findsOneWidget);
    expect(find.text('FULFILLED'), findsNothing);

    // Tap APPROVED
    await tester.tap(find.text('APPROVED'));
    await tester.pumpAndSettle();

    // Confirmation dialog should appear
    expect(find.text('Confirm Status Change'), findsOneWidget);
    expect(
      find.text(
          'Are you sure you want to change the status of Paracetamol request to APPROVED?'),
      findsOneWidget,
    );

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(firebase.updatedStatuses.containsKey('req-pending'), false);

    // Open popup menu again and confirm approval
    await tester.tap(find.byType(PopupMenuButton<RequestStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPROVED'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'APPROVED'));
    await tester.pumpAndSettle();

    expect(firebase.updatedStatuses['req-pending'], RequestStatus.approved);
  });

  testWidgets('offers only valid transitions for approved request (#249)',
      (WidgetTester tester) async {
    final firebase = _FakeFirebaseService([approvedReq]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(firebase));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<RequestStatus>));
    await tester.pumpAndSettle();

      expect(find.text('DISPATCHED'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);
    expect(find.text('PENDING'), findsNothing);
  });

  testWidgets('offers only valid transitions for rejected request (#249)',
      (WidgetTester tester) async {
    final firebase = _FakeFirebaseService([rejectedReq]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(firebase));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<RequestStatus>));
    await tester.pumpAndSettle();

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('APPROVED'), findsNothing);
    expect(find.text('FULFILLED'), findsNothing);
  });

  testWidgets(
      'offers pending/rejected transitions and a "NEEDS REVIEW" badge for '
      'needsManualReview request (#314)', (WidgetTester tester) async {
    final firebase = _FakeFirebaseService([needsReviewReq]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(firebase));
    await tester.pumpAndSettle();

    // A request onIndentApproved couldn't process automatically must be
    // visibly flagged, not rendered as an ordinary pending row (#314).
    expect(find.text('NEEDS REVIEW'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<RequestStatus>));
    await tester.pumpAndSettle();

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('REJECTED'), findsOneWidget);
    expect(find.text('APPROVED'), findsNothing);
    expect(find.text('FULFILLED'), findsNothing);

    await tester.tap(find.text('PENDING'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'PENDING'));
    await tester.pumpAndSettle();

    expect(firebase.updatedStatuses['req-needs-review'], RequestStatus.pending);
  });

  testWidgets('disables popup menu for fulfilled request (#249)',
      (WidgetTester tester) async {
    final firebase = _FakeFirebaseService([fulfilledReq]);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(firebase));
    await tester.pumpAndSettle();

    final popupMenu = tester.widget<PopupMenuButton<RequestStatus>>(
      find.byType(PopupMenuButton<RequestStatus>),
    );
    expect(popupMenu.enabled, false);
  });
}

class _FakeFirebaseService implements FirebaseService {
  _FakeFirebaseService(this.requests);

  final List<MedRequest> requests;
  final Map<String, RequestStatus> updatedStatuses = {};

  @override
  Stream<List<MedRequest>> streamRequests(String? facilityId) {
    return Stream.value(requests);
  }

  @override
  Future<void> updateRequestStatus(String id, RequestStatus status) async {
    updatedStatuses[id] = status;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
