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

class _FakeFirebaseService implements FirebaseService {
  _FakeFirebaseService({this.inventory = const []});

  final List<InventoryItem> inventory;

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
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpDailyLoggingPage(
  WidgetTester tester,
  _FakeFirebaseService firebase,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(firebase),
        connectivityStatusProvider.overrideWith((ref) => Stream.value(true)),
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
}

void main() {
  group('FormField initialValue compliance (#405)', () {
    testWidgets(
        'DailyLoggingPage medicine dropdown uses initialValue instead of deprecated value',
        (WidgetTester tester) async {
      final firebase = _FakeFirebaseService(
        inventory: [_item('Paracetamol'), _item('ORS')],
      );
      await _pumpDailyLoggingPage(tester, firebase);

      // The medicine picker on the real page is a DropdownButtonFormField whose
      // default is the first medicine. Building it with `initialValue` (rather
      // than the deprecated `value`) is what #405 is about.
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(dropdown.initialValue, 'Paracetamol');
    });

    testWidgets('TextFormField initializes correctly with initialValue',
        (WidgetTester tester) async {
      String enteredText = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextFormField(
              initialValue: 'Default Quantity',
              onChanged: (val) => enteredText = val,
            ),
          ),
        ),
      );

      // Verify default initial value displays correctly
      expect(find.text('Default Quantity'), findsOneWidget);

      // Enter new text
      await tester.enterText(find.byType(TextFormField), '100');
      expect(enteredText, equals('100'));
    });
  });
}
