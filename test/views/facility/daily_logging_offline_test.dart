import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/daily_usage_log.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/services/connectivity_service.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/facility/daily_logging_page.dart';
import 'package:med_supply_prototype/views/shared/connectivity_indicator.dart';

const String _facilityId = 'facility-1';

InventoryItem _item(String name) {
  final now = DateTime(2026, 1, 1);
  return InventoryItem(
    id: 'inv-$name',
    medicineName: name,
    batchId: 'batch-$name',
    arrivalDate: now,
    expiryDate: now.add(const Duration(days: 365)),
    initialQuantity: 1000,
    remainingQuantity: 800,
    unit: 'units',
    lastUpdated: now,
  );
}

class FakeFirebaseService implements FirebaseService {
  FakeFirebaseService({this.inventory = const []});

  final List<InventoryItem> inventory;
  int logUsageCallCount = 0;

  @override
  Future<List<InventoryItem>> getInventoryOnce(String facilityId) async =>
      inventory;

  @override
  Future<PaginatedLogsResult> getPaginatedLogs(
    String facilityId, {
    int pageSize = 15,
    DocumentSnapshot? startAfter,
  }) async =>
      PaginatedLogsResult(logs: const [], lastDocument: null, hasMore: false);

  @override
  Future<void> logUsage({
    required String facilityId,
    required DateTime date,
    required String medicineName,
    required int quantity,
    required int patients,
  }) async {
    logUsageCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<FakeFirebaseService> _pumpPage(
  WidgetTester tester, {
  required Stream<bool> status,
}) async {
  final firebase = FakeFirebaseService(
    inventory: [_item('Paracetamol'), _item('ORS')],
  );

  // A desktop-sized surface so the whole Manual form, including the submit
  // button, is on screen and tappable.
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(firebase),
        connectivityStatusProvider.overrideWith((ref) => status),
      ],
      child: const MaterialApp(
        home: DailyLoggingPage(facilityId: _facilityId),
      ),
    ),
  );
  // Let the connectivity status and the faked Firestore reads resolve. The
  // skeleton loaders animate forever, so pumpAndSettle is not an option here.
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 300));

  return firebase;
}

/// Pushes [value] onto the status stream and pumps until the screen has caught
/// up: one frame to deliver the event, one to rebuild and settle the banner
/// animation.
Future<void> _emit(
  WidgetTester tester,
  StreamController<bool> controller,
  bool value,
) async {
  controller.add(value);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Reads the enabled state of the button carrying [label].
bool _isButtonEnabled(WidgetTester tester, String label) {
  final button = tester.widget<ButtonStyleButton>(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    ),
  );
  return button.onPressed != null;
}

void main() {
  group('Daily Logging - connectivity indicator', () {
    testWidgets('shows an online indicator and no banner while connected',
        (tester) async {
      await _pumpPage(tester, status: Stream.value(true));

      expect(find.byType(ConnectivityIndicator), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.textContaining('You are offline'), findsNothing);
    });

    testWidgets('shows an offline indicator and banner while disconnected',
        (tester) async {
      await _pumpPage(tester, status: Stream.value(false));

      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining('You are offline'), findsOneWidget);
    });

    testWidgets('updates automatically as connectivity changes',
        (tester) async {
      final controller = StreamController<bool>.broadcast();
      // Not awaited: closing inside tearDown would wait on a microtask that
      // the (already finished) fake async zone will never pump.
      addTearDown(() {
        controller.close();
      });

      await _pumpPage(tester, status: controller.stream);
      expect(find.text('Online'), findsOneWidget);

      await _emit(tester, controller, false);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining('You are offline'), findsOneWidget);

      await _emit(tester, controller, true);
      expect(find.text('Online'), findsOneWidget);
      expect(find.textContaining('You are offline'), findsNothing);
    });
  });

  group('Daily Logging - offline degradation', () {
    testWidgets('existing functionality is untouched while online',
        (tester) async {
      await _pumpPage(tester, status: Stream.value(true));

      expect(find.text('Save Log'), findsOneWidget);
      expect(_isButtonEnabled(tester, 'Save Log'), isTrue);

      final exportButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.file_download_outlined));
      expect(exportButton.onPressed, isNotNull);
    });

    testWidgets('disables saving and exporting while offline', (tester) async {
      await _pumpPage(tester, status: Stream.value(false));

      expect(find.text('Save Log (offline)'), findsOneWidget);
      expect(_isButtonEnabled(tester, 'Save Log (offline)'), isFalse);

      final exportButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.file_download_outlined));
      expect(exportButton.onPressed, isNull);
    });

    testWidgets('a filled-in form is not written while offline',
        (tester) async {
      final controller = StreamController<bool>.broadcast();
      // Not awaited: closing inside tearDown would wait on a microtask that
      // the (already finished) fake async zone will never pump.
      addTearDown(() {
        controller.close();
      });

      final firebase = await _pumpPage(tester, status: controller.stream);

      // Fill the form while still online.
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Units Distributed'), '10');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Patients Served'), '4');

      // Connectivity drops after the form was filled but before submitting.
      await _emit(tester, controller, false);

      await tester.tap(find.text('Save Log (offline)'));
      await tester.pump();

      expect(firebase.logUsageCallCount, 0);

      // The input survives the outage, so the user can submit on reconnect.
      await _emit(tester, controller, true);
      await tester.tap(find.text('Save Log'));
      await tester.pump();

      expect(firebase.logUsageCallCount, 1);
    });

    testWidgets('restores normal behaviour once reconnected', (tester) async {
      final controller = StreamController<bool>.broadcast();
      // Not awaited: closing inside tearDown would wait on a microtask that
      // the (already finished) fake async zone will never pump.
      addTearDown(() {
        controller.close();
      });

      await _pumpPage(tester, status: controller.stream);

      await _emit(tester, controller, false);
      expect(_isButtonEnabled(tester, 'Save Log (offline)'), isFalse);

      await _emit(tester, controller, true);

      expect(find.text('Save Log'), findsOneWidget);
      expect(_isButtonEnabled(tester, 'Save Log'), isTrue);
    });
  });

  group('Daily Logging - mounted guards (#323)', () {
    // The simulated QR scan takes two seconds. If the user navigates away
    // before it finishes, the post-await setState would throw without the
    // mounted guard added by #323.
    testWidgets(
        'disposing mid simulated QR scan does not throw setState-after-dispose',
        (tester) async {
      await _pumpPage(tester, status: Stream.value(true));

      // Switch to the Scan tab. The simulate button is rendered there.
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      // The tab shows the "Simulate Scan" button until the first scan lands,
      // then "Scan Another". Tap whichever is visible.
      final simulate = find.text('Simulate Scan');
      final another = find.text('Scan Another');
      final button = simulate.evaluate().isNotEmpty ? simulate : another;
      expect(button, findsOneWidget);
      await tester.tap(button);
      // The 2-second delay is in flight; do not pump it yet.
      await tester.pump();

      // Navigate away before the simulated scan finishes.
      await tester.pumpWidget(const SizedBox.shrink());
      // Drain the queue well past the 2-second timer so any post-dispose
      // setState would have fired.
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
    });
  });
}
